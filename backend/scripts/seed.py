"""Deterministic development/test seed data.

Creates two organizations (Org A + Org B) with admin and employee users —
the exact layout the mandatory multi-tenant isolation tests require (§27).

Idempotent: safe to re-run; existing rows are left untouched. Natural unique
keys (organization slug, user email, membership pair, role name+org,
expense type name+org) drive the idempotency.

The seeded accounts share one password, taken from ``SEED_PASSWORD``. When
that is not configured the script generates a random password and prints it
once — there is no built-in default credential, so pointing this at a real
database can never create accounts with a published password (§19).

Usage (from ``backend/``)::

    uv run python scripts/seed.py
    uv run python scripts/seed.py --dsn postgresql://...@localhost:5432/ats
"""

from __future__ import annotations

import argparse
import secrets
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg
from psycopg.rows import dict_row
from pwdlib import PasswordHash

ORGS = [
    {"slug": "acme-corp", "name": "Acme Corp", "description": "Seed organization A"},
    {"slug": "globex-inc", "name": "Globex Inc", "description": "Seed organization B"},
]

USERS = [
    # (email, name, org_slug, is_admin, role)
    # Domain is a plausible-but-never-to-be-registered .dev — it must pass the
    # API's own email validation (RFC 2606 names like .test are rejected) so
    # seeded users can actually log in through /auth/login.
    #
    # One account per persona, so every dashboard in the app can be opened:
    # the role decides the capabilities, and the capabilities decide what
    # the portal shows.
    ("admin@acme-corp.dev", "Asha Admin", "acme-corp", True, "admin"),
    ("manager@acme-corp.dev", "Maya Manager", "acme-corp", False, "manager"),
    ("director@acme-corp.dev", "Dev Director", "acme-corp", False, "director"),
    ("finance@acme-corp.dev", "Fay Finance", "acme-corp", False, "finance"),
    ("employee@acme-corp.dev", "Evan Employee", "acme-corp", False, "employee"),
    ("admin@globex-inc.dev", "Gita Admin", "globex-inc", True, "admin"),
    (
        "manager@globex-inc.dev",
        "Max Manager",
        "globex-inc",
        False,
        "manager",
    ),
    ("employee@globex-inc.dev", "Guru Employee", "globex-inc", False, "employee"),
]

# The demo claims behind the dashboards: (owner role, type, amount, status,
# months ago, rejection reason). The spread over months is what gives the
# trend charts something to plot.
DEMO_EXPENSES = [
    ("employee", "Travel", 4800.00, "reimbursed", 7, None),
    ("employee", "Meals", 1250.50, "approved", 6, None),
    ("employee", "Travel", 3200.00, "rejected", 5, "Missing the itemised receipt"),
    ("employee", "Meals", 980.00, "pending", 4, None),
    ("employee", "Travel", 7650.00, "approved", 3, None),
    ("employee", "Meals", 1420.75, "reimbursed", 2, None),
    ("employee", "Travel", 5900.00, "info_requested", 1, None),
    ("employee", "Meals", 640.00, "pending", 0, None),
    ("manager", "Travel", 12500.00, "reimbursed", 6, None),
    ("manager", "Meals", 2100.00, "approved", 3, None),
    ("manager", "Travel", 8300.00, "pending", 1, None),
    ("admin", "Travel", 21000.00, "reimbursed", 4, None),
]

# The payout pipeline: how many reimbursements sit in each stage.
DEMO_REIMBURSEMENTS = [
    ("paid", 6),
    ("processing", 2),
    ("pending", 3),
    ("failed", 1),
]

# The standard roles (employee, manager, finance, director, hr, admin) are
# not listed here: they come from the access catalogue, which is the single
# place the platform's access model is defined.
EXPENSE_TYPES = [
    {"name": "Travel", "requires_receipt": True, "default_limit": "5000.00"},
    {"name": "Meals", "requires_receipt": True, "default_limit": "1500.00"},
]

_hasher = PasswordHash.recommended()


def resolve_password() -> str:
    """The password every seeded account gets.

    ``SEED_PASSWORD`` wins. Without it a random password is generated and
    printed once — the seeder never falls back to a published constant.
    """
    from app.core.config import get_settings

    configured = get_settings().seed_password
    if configured:
        return configured
    generated = secrets.token_urlsafe(12)
    print(f"[seed] SEED_PASSWORD is not set — generated password: {generated}")
    return generated


def fetch_one(cur, query: str, params: tuple) -> dict | None:
    cur.execute(query, params)
    return cur.fetchone()


def seed_organizations(cur) -> None:
    for org in ORGS:
        row = fetch_one(
            cur,
            "SELECT organization_id FROM organizations WHERE slug = %s",
            (org["slug"],),
        )
        if row is None:
            cur.execute(
                """
                INSERT INTO organizations (name, slug, description)
                VALUES (%s, %s, %s)
                RETURNING organization_id
                """,
                (org["name"], org["slug"], org["description"]),
            )
            org["organization_id"] = cur.fetchone()["organization_id"]
        else:
            org["organization_id"] = row["organization_id"]


def seed_users_and_memberships(cur, password: str) -> dict[str, int]:
    """Create users and memberships; stamps admin employee_id on their org.

    Returns the employee id of every seeded account, keyed by email, so
    the demo data can be attached to the right people.
    """
    employee_ids: dict[str, int] = {}
    for email, name, org_slug, is_admin, _role in USERS:
        user = fetch_one(
            cur,
            "SELECT employee_id FROM users WHERE email = %s",
            (email,),
        )
        if user is None:
            cur.execute(
                """
                INSERT INTO users (name, email, password_hash)
                VALUES (%s, %s, %s)
                RETURNING employee_id
                """,
                (name, email, _hasher.hash(password)),
            )
            employee_id = cur.fetchone()["employee_id"]
        else:
            employee_id = user["employee_id"]
        employee_ids[email] = employee_id

        org = next(o for o in ORGS if o["slug"] == org_slug)
        existing = fetch_one(
            cur,
            "SELECT 1 FROM memberships WHERE employee_id = %s AND organization_id = %s",
            (employee_id, org["organization_id"]),
        )
        if existing is None:
            cur.execute(
                """
                INSERT INTO memberships (employee_id, organization_id, is_admin)
                VALUES (%s, %s, %s)
                """,
                (employee_id, org["organization_id"], is_admin),
            )
        if is_admin:
            org["admin_employee_id"] = employee_id
    return employee_ids


def seed_access(cur) -> None:
    """Install the standard capabilities and roles into every organization.

    The seeder creates organizations with raw SQL, so it does not go
    through the application's "create organization" path and cannot rely
    on that path to install the access model. The same install functions
    the application uses are called here instead, so both routes end up
    with the same standard capabilities and roles.
    """
    for org in ORGS:
        cur.execute("SELECT ats_install_permissions(%s)", (org["organization_id"],))
        cur.execute("SELECT ats_install_roles(%s)", (org["organization_id"],))


def seed_membership_roles(cur) -> None:
    """Give every membership the role its account was seeded with.

    An administrator holds the ``admin`` role, everyone else the persona
    they were created for — manager, director, finance, employee. Without
    a role a membership holds no capability at all, so this is what makes
    a seeded account able to do anything, and what makes the portal show
    the right tabs for it.
    """
    for email, _name, org_slug, _is_admin, role_name in USERS:
        org = next(o for o in ORGS if o["slug"] == org_slug)
        cur.execute(
            """
            INSERT INTO membership_roles (membership_id, role_id, organization_id)
            SELECT m.membership_id, r.role_id, m.organization_id
              FROM memberships m
              JOIN users u ON u.employee_id = m.employee_id
              JOIN roles r
                ON r.organization_id = m.organization_id AND r.name = %s
             WHERE m.organization_id = %s AND u.email = %s
            ON CONFLICT DO NOTHING
            """,
            (role_name, org["organization_id"], email),
        )


def seed_budgets_and_projects(cur) -> None:
    """One FY2026 budget per org (owned by the org admin) + one seed project."""
    for org in ORGS:
        budget = fetch_one(
            cur,
            """
            SELECT budget_id FROM budgets
            WHERE organization_id = %s AND amount = %s AND start_date = %s
            """,
            (org["organization_id"], "500000.00", "2026-01-01"),
        )
        if budget is None:
            cur.execute(
                """
                INSERT INTO budgets (amount, employee_id, organization_id, start_date, end_date)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING budget_id
                """,
                (
                    "500000.00",
                    org["admin_employee_id"],
                    org["organization_id"],
                    "2026-01-01",
                    "2026-12-31",
                ),
            )
            budget_id = cur.fetchone()["budget_id"]
        else:
            budget_id = budget["budget_id"]

        project = fetch_one(
            cur,
            "SELECT project_id FROM projects WHERE budget_id = %s AND name = %s",
            (budget_id, "Atlas Migration"),
        )
        if project is None:
            cur.execute(
                """
                INSERT INTO projects
                    (budget_id, organization_id, name, description, start_date, end_date)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (
                    budget_id,
                    org["organization_id"],
                    "Atlas Migration",
                    "Seed project",
                    "2026-01-01",
                    "2026-12-31",
                ),
            )


def seed_expense_types(cur) -> None:
    for org in ORGS:
        for et in EXPENSE_TYPES:
            cur.execute(
                """
                INSERT INTO expense_types (organization_id, name, requires_receipt, default_limit)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (name, organization_id) DO NOTHING
                """,
                (
                    org["organization_id"],
                    et["name"],
                    et["requires_receipt"],
                    et["default_limit"],
                ),
            )


def seed_demo_expenses(cur, employee_ids: dict[str, int]) -> None:
    """A spread of claims so every dashboard has something to show.

    Without them the charts are empty and the trend lines are flat — the
    seeder's job is a local environment that can be looked at, not an
    empty ledger.
    """
    for org in ORGS:
        org_id = org["organization_id"]
        project = fetch_one(
            cur,
            "SELECT project_id FROM projects WHERE organization_id = %s LIMIT 1",
            (org_id,),
        )
        if project is None:
            continue
        project_id = project["project_id"]

        approver_id = org["admin_employee_id"]
        for owner_role, type_name, amount, status, months_ago, reason in DEMO_EXPENSES:
            email = f"{owner_role}@{org['slug']}.dev"
            owner_id = employee_ids.get(email)
            if owner_id is None:
                continue
            expense_type = fetch_one(
                cur,
                """
                SELECT expense_type_id FROM expense_types
                WHERE organization_id = %s AND name = %s
                """,
                (org_id, type_name),
            )
            if expense_type is None:
                continue
            expense_type_id = expense_type["expense_type_id"]

            # A claim of the same shape is created once; re-running the
            # seeder does not duplicate the ledger.
            if fetch_one(
                cur,
                """
                SELECT 1 FROM expenses
                WHERE organization_id = %s AND employee_id = %s
                  AND amount = %s AND expense_date = %s
                """,
                (org_id, owner_id, amount, _month_start(months_ago)),
            ):
                continue

            cur.execute(
                """
                INSERT INTO expenses
                    (employee_id, project_id, organization_id, expense_type_id,
                     amount, status, expense_date, submission_date, rejection_reason)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING expense_id
                """,
                (
                    owner_id,
                    project_id,
                    org_id,
                    expense_type_id,
                    amount,
                    status,
                    _month_start(months_ago),
                    _month_start(months_ago),
                    reason,
                ),
            )
            expense_id = cur.fetchone()["expense_id"]

            # The decisions the analytics average over.
            if status in ("approved", "reimbursed"):
                cur.execute(
                    """
                    INSERT INTO expense_approvals
                        (expense_id, organization_id, actioned_by, action, comments, actioned_at)
                    VALUES (%s, %s, %s, 'approved', %s, %s)
                    """,
                    (
                        expense_id,
                        org_id,
                        approver_id,
                        "Approved by the seeder",
                        _month_start(months_ago),
                    ),
                )
            elif status == "rejected":
                cur.execute(
                    """
                    INSERT INTO expense_approvals
                        (expense_id, organization_id, actioned_by, action, comments, actioned_at)
                    VALUES (%s, %s, %s, 'rejected', %s, %s)
                    """,
                    (
                        expense_id,
                        org_id,
                        approver_id,
                        reason or "Rejected by the seeder",
                        _month_start(months_ago),
                    ),
                )


def seed_demo_reimbursements(cur) -> None:
    """The payout pipeline: paid, processing, pending and failed."""
    for org in ORGS:
        org_id = org["organization_id"]
        approved = cur.execute(
            """
            SELECT expense_id, employee_id, amount FROM expenses
            WHERE organization_id = %s AND status IN ('approved', 'reimbursed')
            ORDER BY expense_id
            """,
            (org_id,),
        ).fetchall()
        if not approved:
            continue

        stages = [stage for stage, _count in DEMO_REIMBURSEMENTS for _ in range(_count)]
        for index, stage in enumerate(stages):
            if index >= len(approved):
                break
            row = approved[index]
            if fetch_one(
                cur,
                "SELECT 1 FROM reimbursements WHERE expense_id = %s",
                (row["expense_id"],),
            ):
                continue
            paid_at = _month_start(0) if stage == "paid" else None
            cur.execute(
                """
                INSERT INTO reimbursements
                    (expense_id, employee_id, organization_id, total_amount,
                     payment_reference, status, paid_at, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    row["expense_id"],
                    row["employee_id"],
                    org_id,
                    row["amount"],
                    f"SEED-{row['expense_id']}",
                    stage,
                    paid_at,
                    _month_start(0),
                ),
            )
            # Only a paid reimbursement settles the claim; the others are
            # still on their way.
            if stage == "paid":
                cur.execute(
                    "UPDATE expenses SET status = 'reimbursed' WHERE expense_id = %s",
                    (row["expense_id"],),
                )


def _month_start(months_ago: int) -> date:
    """The first day of the month ``months_ago`` months back."""
    today = date.today()
    index = today.year * 12 + today.month - 1 - months_ago
    return date(index // 12, index % 12 + 1, 15)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dsn", default=None, help="PostgreSQL DSN")
    args = parser.parse_args()
    from app.core.config import get_settings

    dsn = args.dsn or get_settings().effective_database_url
    password = resolve_password()

    with (
        psycopg.connect(
            dsn,
            row_factory=dict_row,
            options=f"-c TimeZone={get_settings().db_timezone}",
        ) as conn,
        conn.transaction(),
        conn.cursor() as cur,
    ):
        seed_organizations(cur)
        employee_ids = seed_users_and_memberships(cur, password)
        seed_access(cur)
        seed_membership_roles(cur)
        seed_budgets_and_projects(cur)
        seed_expense_types(cur)
        seed_demo_expenses(cur, employee_ids)
        seed_demo_reimbursements(cur)

    print(
        "Seed complete: "
        f"{len(ORGS)} orgs, {len(USERS)} users, "
        "the standard capabilities and roles per org, "
        "1 budget + 1 project + 2 expense types per org, "
        "plus demo claims and a payout pipeline."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
