"""Deterministic development/test seed data.

Creates two organizations (Org A + Org B) with admin and employee users —
the exact layout the mandatory multi-tenant isolation tests require (§27).

Idempotent: safe to re-run; existing rows are left untouched. Natural unique
keys (organization slug, user email, membership pair, role name+org,
expense type name+org) drive the idempotency. No real credentials —
dev passwords only (arch. doc §19).

Usage (from ``backend/``)::

    uv run python scripts/seed.py
    uv run python scripts/seed.py --dsn postgresql://...@localhost:5432/ats
"""

from __future__ import annotations

import argparse
import os

import psycopg
from psycopg.rows import dict_row
from pwdlib import PasswordHash

DEFAULT_DSN = "postgresql://ats:ats_dev_password@localhost:5432/ats"

# Dev-only password — NEVER use in production (arch. doc §19).
DEV_PASSWORD = "DevPassword123!"

ORGS = [
    {"slug": "acme-corp", "name": "Acme Corp", "description": "Seed organization A"},
    {"slug": "globex-inc", "name": "Globex Inc", "description": "Seed organization B"},
]

USERS = [
    # (email, name, org_slug, is_admin)
    ("admin@acme.test", "Asha Admin", "acme-corp", True),
    ("employee@acme.test", "Evan Employee", "acme-corp", False),
    ("admin@globex.test", "Gita Admin", "globex-inc", True),
    ("employee@globex.test", "Guru Employee", "globex-inc", False),
]

ROLES = ["employee", "manager"]

EXPENSE_TYPES = [
    {"name": "Travel", "requires_receipt": True, "default_limit": 5000.00},
    {"name": "Meals", "requires_receipt": True, "default_limit": 1500.00},
]

_hasher = PasswordHash.recommended()


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


def seed_users_and_memberships(cur) -> None:
    """Create users and memberships; stamps admin employee_id on their org."""
    for email, name, org_slug, is_admin in USERS:
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
                (name, email, _hasher.hash(DEV_PASSWORD)),
            )
            employee_id = cur.fetchone()["employee_id"]
        else:
            employee_id = user["employee_id"]

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


def seed_roles(cur) -> None:
    for org in ORGS:
        for role in ROLES:
            cur.execute(
                """
                INSERT INTO roles (name, organization_id, description)
                VALUES (%s, %s, %s)
                ON CONFLICT (name, organization_id) DO NOTHING
                """,
                (role, org["organization_id"], f"Seed role {role}"),
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
            (org["organization_id"], 500000.00, "2026-01-01"),
        )
        if budget is None:
            cur.execute(
                """
                INSERT INTO budgets (amount, employee_id, organization_id, start_date, end_date)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING budget_id
                """,
                (
                    500000.00,
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
                INSERT INTO projects (budget_id, name, description, start_date, end_date)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (budget_id, "Atlas Migration", "Seed project", "2026-01-01", "2026-12-31"),
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dsn", default=None, help="PostgreSQL DSN")
    args = parser.parse_args()
    dsn = args.dsn or os.environ.get("DATABASE_URL") or DEFAULT_DSN

    with (
        psycopg.connect(dsn, row_factory=dict_row) as conn,
        conn.transaction(),
        conn.cursor() as cur,
    ):
        seed_organizations(cur)
        seed_users_and_memberships(cur)
        seed_roles(cur)
        seed_budgets_and_projects(cur)
        seed_expense_types(cur)

    print(
        "Seed complete: "
        f"{len(ORGS)} orgs, {len(USERS)} users, {len(ROLES) * len(ORGS)} roles, "
        "1 budget + 1 project + 2 expense types per org."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
