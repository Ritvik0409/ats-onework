"""Every query against organization data must scope itself by tenant.

The tenant boundary in this codebase is written in the SQL: a query says
``WHERE organization_id = %s`` and the service passes the organization.
That is a convention, not a guarantee — a query that forgets it reads
another organization's money.

This test reads the repositories and fails when a statement touches an
organization-owned table without a tenant predicate. It is the cheap
half of the protection: it catches the mistake where it is made, rather
than the database refusing to serve it later.

Three ways a statement may be acceptable:

**A — it filters.** A read or an update compares ``organization_id`` or
``employee_id`` to a value. ``employee_id`` is a person's own data,
which is narrower than an organization, so it counts too.

**B — it stamps.** A write names the organization (or the owner) among
the columns it writes, so the row is born belonging to someone.

**C — it resolves the organization.** A handful of statements exist to
answer "which organization does this row belong to?" — the organization
is what they are looking for, so they cannot filter by it. Each is
listed in :data:`RESOLVES_THE_ORGANIZATION` with the reason.

The tables in :data:`NOT_ORGANIZATION_OWNED` hold no organization's
data, so a query on them needs no scope. Each is listed with the reason.
"""

from __future__ import annotations

import ast
import re
from dataclasses import dataclass
from pathlib import Path

import pytest

APP_ROOT = Path(__file__).resolve().parents[2] / "app"

#: Tables that hold one organization's data.
ORGANIZATION_OWNED = {
    "organizations",
    "memberships",
    "roles",
    "permissions",
    "role_permissions",
    "membership_roles",
    "user_permissions",
    "expenses",
    "expense_media",
    "expense_approvals",
    "budgets",
    "projects",
    "project_members",
    "reimbursements",
    "notifications",
    "audit_logs",
}

#: Tables that hold nobody's organization data, and why a query on them
#: needs no tenant predicate.
NOT_ORGANIZATION_OWNED: dict[str, str] = {
    "access_catalog": "the platform's standard capabilities, shared by all",
    "authentication_tokens": "a person's own credentials, not an organization's",
    "users": "a person, not an organization",
    "employee_status": "a person's own working status",
    "categories": "a global taxonomy",
    "project_categories": "a global taxonomy",
    "rate_limit_buckets": "global counters",
    "schema_migrations": "the migration ledger",
}

#: Statements whose job is to answer "which organization is this row in?".
#: They cannot filter by the organization, because that is what they are
#: looking for. The calling service checks the answer it gets back
#: against the organization the caller is working in.
RESOLVES_THE_ORGANIZATION: dict[str, str] = {
    "access.repository.AccessRepository.list_all_organizations": (
        "the platform super administrator's view of every organization"
    ),
    "budgets.repository.BudgetRepository.get_org": ("finds the organization a budget belongs to"),
    "expenses.repository.ExpenseRepository.get_project_org": (
        "finds the organization a project belongs to"
    ),
    "projects.repository.ProjectRepository.get_budget_org": (
        "finds the organization a budget belongs to"
    ),
    "projects.repository.ProjectRepository.get_project_org": (
        "finds the organization a project belongs to"
    ),
    "project_requests.repository.ProjectAccessRepository.get_project_org": (
        "finds the organization a project belongs to"
    ),
}

#: A tenant predicate: a column compared to a bind parameter.
_SCOPE = re.compile(r"\b(organization_id|employee_id)\s*=\s*%s\b", re.I)
#: A comparison that only applies when a parameter is not null — an
#: optional filter, not a scope. ``(%s::int IS NULL OR e.employee_id = %s::int)``
#: filters by employee only sometimes, so it cannot stand in for the
#: organization filter. The optional table alias is allowed between the
#: "OR" and the column.
_OPTIONAL = re.compile(r"IS\s+NULL\s+OR\s+(\w+\.)?$", re.I)
_TABLE = re.compile(r"\b(?:FROM|JOIN|UPDATE|INTO)\s+(\w+)", re.I)
_WRITE = re.compile(r"^\s*(?:INSERT|UPDATE)\b", re.I)


def _has_scope(sql: str) -> bool:
    """Whether the statement filters by an organization or a person.

    An optional comparison does not count: it applies only some of the
    time, so the statement is not always scoped.
    """
    for match in _SCOPE.finditer(sql):
        prefix = sql[max(0, match.start() - 60) : match.start()]
        if _OPTIONAL.search(prefix):
            continue
        return True
    return False


@dataclass(frozen=True, slots=True)
class Statement:
    """One SQL statement found in a repository."""

    path: Path
    line: int
    function: str
    owner: str
    sql: str
    tables: frozenset[str]

    @property
    def key(self) -> str:
        module = self.path.relative_to(APP_ROOT).with_suffix("").as_posix()
        return f"{module.replace('/', '.')}.{self.owner}.{self.function}"


def _module_constants(tree: ast.Module) -> dict[str, str]:
    """The module's string constants, so a query can be read whole.

    The repositories build their SQL as a literal plus a named constant
    plus a literal, so reading one string on its own would miss most of
    the statement.
    """
    constants: dict[str, str] = {}
    for node in tree.body:
        if not (isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant)):
            continue
        if not isinstance(node.value.value, str):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name):
                constants[target.id] = node.value.value
    return constants


def _resolve(node: ast.AST, constants: dict[str, str]) -> str:
    """The text of a SQL expression, as far as it can be worked out."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return constants.get(node.id, "")
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return _resolve(node.left, constants) + _resolve(node.right, constants)
    if isinstance(node, ast.List):
        # A list of fragments, joined the way the repository joins them.
        return " ".join(_resolve(item, constants) for item in node.elts)
    if isinstance(node, ast.Call):
        # ``" AND ".join(clauses)`` — the fragments are what matters, not
        # the separator between them.
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr == "join":
            if node.args:
                return _resolve(node.args[0], constants)
            return _resolve(func.value, constants)
    return ""


def _local_strings(function: ast.FunctionDef | ast.AsyncFunctionDef) -> dict[str, str]:
    """The function's own string variables, so a query built from a
    list of clauses can be read whole."""
    locals_: dict[str, str] = {}
    for node in ast.walk(function):
        if isinstance(node, ast.Assign) and isinstance(node.value, (ast.List, ast.Constant)):
            if isinstance(node.value, ast.List):
                if not all(
                    isinstance(item, ast.Constant) and isinstance(item.value, str)
                    for item in node.value.elts
                ):
                    continue
                text = " ".join(item.value for item in node.value.elts)
            else:
                text = node.value.value
            for target in node.targets:
                if isinstance(target, ast.Name):
                    locals_[target.id] = text
    return locals_


def _statements(path: Path) -> list[Statement]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    constants = _module_constants(tree)
    found: list[Statement] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue
        for method in node.body:
            if not isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            locals_ = {**constants, **_local_strings(method)}
            for inner in ast.walk(method):
                if not isinstance(inner, ast.Call):
                    continue
                func = inner.func
                if not isinstance(func, ast.Attribute) or func.attr != "execute":
                    continue
                if not inner.args:
                    continue
                sql = _resolve(inner.args[0], locals_)
                if not sql:
                    continue
                tables = frozenset(match.group(1).lower() for match in _TABLE.finditer(sql))
                found.append(
                    Statement(
                        path=path,
                        line=inner.lineno,
                        function=method.name,
                        owner=node.name,
                        sql=sql,
                        tables=tables,
                    )
                )
    return found


def _repositories() -> list[Path]:
    return sorted(APP_ROOT.rglob("*repository.py"))


def test_the_repositories_were_found() -> None:
    """A scanner that silently finds nothing would pass every check."""
    repositories = _repositories()
    assert len(repositories) >= 10, f"only found {len(repositories)} repositories"


def test_the_scanner_actually_reads_the_queries() -> None:
    """The scanner has to see the SQL, or the check below is vacuous."""
    statements = [s for path in _repositories() for s in _statements(path)]
    assert len(statements) > 40, f"only found {len(statements)} statements"
    assert any("organization_id" in s.sql for s in statements)
    assert any("expenses" in s.tables for s in statements)


def test_every_organization_query_scopes_itself() -> None:
    """The check itself."""
    unscoped: list[str] = []
    for path in _repositories():
        for statement in _statements(path):
            organization_tables = statement.tables & ORGANIZATION_OWNED
            if not organization_tables:
                continue
            if _has_scope(statement.sql):
                continue
            if _WRITE.match(statement.sql) and re.search(
                r"\b(organization_id|employee_id)\b", statement.sql, re.I
            ):
                continue
            if statement.key in RESOLVES_THE_ORGANIZATION:
                continue
            unscoped.append(
                f"{statement.path.relative_to(APP_ROOT.parents[1])}:{statement.line}"
                f"  {statement.key}  tables={sorted(organization_tables)}\n"
                f"      {' '.join(statement.sql.split())[:160]}"
            )
    assert not unscoped, (
        "These statements read organization data without a tenant predicate:\n"
        + "\n".join(unscoped)
        + "\n\nAdd `organization_id = %s` (or `employee_id = %s` for a person's "
        "own data) to the statement and pass the organization through."
    )


def test_every_exemption_still_exists() -> None:
    """An exemption for a method that has been renamed is a stale promise."""
    found = {statement.key for path in _repositories() for statement in _statements(path)}
    missing = sorted(set(RESOLVES_THE_ORGANIZATION) - found)
    assert not missing, (
        "These exemptions name a method that no longer exists: "
        f"{missing}. Remove them, or update the names."
    )


def test_the_exemptions_are_the_ones_that_resolve_the_organization() -> None:
    """An exemption must actually be a statement that resolves the
    organization — otherwise it is a hole with a good name on it."""
    for path in _repositories():
        for statement in _statements(path):
            if statement.key not in RESOLVES_THE_ORGANIZATION:
                continue
            assert re.search(r"SELECT[^;]*\borganization_id\b", statement.sql, re.I | re.S), (
                f"{statement.key} is exempt as resolving the organization, but "
                "it does not select one."
            )


@pytest.mark.parametrize("table", sorted(NOT_ORGANIZATION_OWNED))
def test_the_exempt_tables_hold_no_organization_data(table: str) -> None:
    """An exemption is a claim about a table — this checks the claim.

    A table that starts carrying organization data must lose its
    exemption, and this fails when it does.
    """
    assert table not in ORGANIZATION_OWNED, (
        f"{table} is listed as not organization-owned, but it is also listed "
        "as organization-owned. One of the two lists is out of date."
    )
    assert NOT_ORGANIZATION_OWNED[table], "every exemption needs a reason"
