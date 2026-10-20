"""Database-level tenant integrity — real PostgreSQL required.

The application layer scopes every query to one organization, but the
database is what makes a mistake impossible rather than merely
unlikely. These tests write directly through SQL, bypassing the service
layer, and check that the database refuses.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from psycopg import AsyncConnection

from tests.conftest import truncate_all

pytestmark = pytest.mark.integration


@pytest.fixture
async def clean_db(db_connection: AsyncConnection[dict]) -> AsyncIterator[AsyncConnection[dict]]:
    await truncate_all(db_connection)
    yield db_connection
    await truncate_all(db_connection)


async def _org(conn: AsyncConnection[dict], slug: str) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO organizations (name, slug, description) VALUES (%s, %s, %s)"
            " RETURNING organization_id",
            (slug, slug, "fixture"),
        )
        row = await cur.fetchone()
        assert row is not None
    await conn.commit()
    return int(row["organization_id"])


async def _user(conn: AsyncConnection[dict], email: str) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s)"
            " RETURNING employee_id",
            ("U", email, "argon2$not-a-real-hash"),
        )
        row = await cur.fetchone()
        assert row is not None
    await conn.commit()
    return int(row["employee_id"])


async def _membership(conn: AsyncConnection[dict], employee_id: int, org_id: int) -> None:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO memberships (employee_id, organization_id, is_admin) VALUES (%s, %s, %s)",
            (employee_id, org_id, True),
        )
    await conn.commit()


async def _budget(conn: AsyncConnection[dict], org_id: int, employee_id: int) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO budgets (amount, employee_id, organization_id, start_date, end_date)"
            " VALUES (%s, %s, %s, %s, %s) RETURNING budget_id",
            ("10000.00", employee_id, org_id, "2026-01-01", "2026-12-31"),
        )
        row = await cur.fetchone()
        assert row is not None
    await conn.commit()
    return int(row["budget_id"])


async def _expense(
    conn: AsyncConnection[dict],
    *,
    employee_id: int,
    project_id: int,
    org_id: int,
    type_id: int,
    status: str = "pending",
) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO expenses"
            " (employee_id, project_id, organization_id, expense_type_id, amount,"
            "  expense_date, status)"
            " VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING expense_id",
            (employee_id, project_id, org_id, type_id, "100.00", "2026-10-20", status),
        )
        row = await cur.fetchone()
        assert row is not None
    await conn.commit()
    return int(row["expense_id"])


async def _expense_type(conn: AsyncConnection[dict], org_id: int) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO expense_types (name, organization_id) VALUES (%s, %s)"
            " RETURNING expense_type_id",
            ("Travel", org_id),
        )
        row = await cur.fetchone()
        assert row is not None
    await conn.commit()
    return int(row["expense_type_id"])


async def _project(conn: AsyncConnection[dict], org_id: int, budget_id: int) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO projects (budget_id, organization_id, name) VALUES (%s, %s, %s)"
            " RETURNING project_id",
            (budget_id, org_id, "P"),
        )
        row = await cur.fetchone()
        assert row is not None
    await conn.commit()
    return int(row["project_id"])


async def test_reimbursement_cannot_reference_another_organizations_expense(
    clean_db: AsyncConnection[dict],
) -> None:
    """The rule the service layer enforced, now enforced by the database."""
    org_a = await _org(clean_db, "org-a")
    org_b = await _org(clean_db, "org-b")
    user_a = await _user(clean_db, "a@example.com")
    user_b = await _user(clean_db, "b@example.com")
    await _membership(clean_db, user_a, org_a)
    budget_a = await _budget(clean_db, org_a, user_a)
    await _membership(clean_db, user_b, org_b)
    await _budget(clean_db, org_b, user_b)
    type_a = await _expense_type(clean_db, org_a)
    project_a = await _project(clean_db, org_a, budget_a)
    expense_a = await _expense(
        clean_db,
        employee_id=user_a,
        project_id=project_a,
        org_id=org_a,
        type_id=type_a,
        status="approved",
    )

    async with clean_db.cursor() as cur:
        with pytest.raises(Exception) as exc:
            await cur.execute(
                "INSERT INTO reimbursements"
                " (expense_id, employee_id, organization_id, total_amount)"
                " VALUES (%s, %s, %s, %s)",
                (expense_a, user_b, org_b, "100.00"),
            )
    assert "fk_reimbursements_expense_org" in str(exc.value)
    await clean_db.rollback()


async def test_expense_status_transition_is_enforced_by_the_database(
    clean_db: AsyncConnection[dict],
) -> None:
    """An approved expense may only move on to 'reimbursed'."""
    org_a = await _org(clean_db, "org-a")
    user_a = await _user(clean_db, "a@example.com")
    await _membership(clean_db, user_a, org_a)
    budget_a = await _budget(clean_db, org_a, user_a)
    type_a = await _expense_type(clean_db, org_a)
    project_a = await _project(clean_db, org_a, budget_a)
    expense_a = await _expense(
        clean_db,
        employee_id=user_a,
        project_id=project_a,
        org_id=org_a,
        type_id=type_a,
        status="approved",
    )

    # approved -> pending is not a legal transition.
    async with clean_db.cursor() as cur:
        with pytest.raises(Exception) as exc:
            await cur.execute(
                "UPDATE expenses SET status = 'pending' WHERE expense_id = %s",
                (expense_a,),
            )
    assert "invalid expense status transition" in str(exc.value)
    await clean_db.rollback()

    # approved -> reimbursed is.
    async with clean_db.cursor() as cur:
        await cur.execute(
            "UPDATE expenses SET status = 'reimbursed' WHERE expense_id = %s",
            (expense_a,),
        )
    await clean_db.commit()


async def test_project_organization_must_match_its_budget(
    clean_db: AsyncConnection[dict],
) -> None:
    org_a = await _org(clean_db, "org-a")
    org_b = await _org(clean_db, "org-b")
    user_a = await _user(clean_db, "a@example.com")
    await _membership(clean_db, user_a, org_a)
    budget_a = await _budget(clean_db, org_a, user_a)

    async with clean_db.cursor() as cur:
        with pytest.raises(Exception) as exc:
            await cur.execute(
                "INSERT INTO projects (budget_id, organization_id, name) VALUES (%s, %s, %s)",
                (budget_a, org_b, "Cross-tenant"),
            )
    assert "organization must match its budget" in str(exc.value)
    await clean_db.rollback()
