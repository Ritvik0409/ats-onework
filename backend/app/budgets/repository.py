"""Budget persistence — raw SQL only (§5).

``spent`` is derived each read (never denormalized): the sum of
approved + reimbursed expenses across every project that references the
budget. Rejected and still-pending expenses deliberately do not count
against the budget.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from app.db.types import Conn, Row

_BUDGET_COLUMNS = (
    "budget_id, amount, employee_id, organization_id, start_date, end_date, created_at, updated_at"
)

# Aggregates included in every read the API returns.
_SPENT_EXPR = (
    "COALESCE((SELECT SUM(e.amount) FROM expenses e"
    " JOIN projects p ON p.project_id = e.project_id"
    " WHERE p.budget_id = b.budget_id"
    " AND e.status IN ('approved', 'reimbursed')), 0) AS spent"
)

_BUDGET_SELECT = (
    f"b.budget_id, b.amount, b.employee_id, b.organization_id,"
    f" b.start_date, b.end_date, b.created_at, b.updated_at, {_SPENT_EXPR}"
)

# Same select spelled against INSERT ... RETURNING / UPDATE ... RETURNING
# (no aliases exist there, so the target table is referenced by name —
# the spent subquery still correlates against ``budgets.budget_id``).
_BUDGET_SELECT_NAMED = (
    "budgets.budget_id, budgets.amount, budgets.employee_id, budgets.organization_id,"
    " budgets.start_date, budgets.end_date, budgets.created_at, budgets.updated_at,"
    " COALESCE((SELECT SUM(e.amount) FROM expenses e"
    " JOIN projects p ON p.project_id = e.project_id"
    " WHERE p.budget_id = budgets.budget_id"
    " AND e.status IN ('approved', 'reimbursed')), 0) AS spent"
)


class BudgetRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

    async def create(
        self,
        conn: Conn,
        *,
        amount: Decimal,
        employee_id: int,
        organization_id: int,
        start_date: date,
        end_date: date,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO budgets (amount, employee_id, organization_id, start_date, end_date)"
                " VALUES (%s, %s, %s, %s, %s) RETURNING " + _BUDGET_SELECT_NAMED,
                (str(amount), employee_id, organization_id, start_date, end_date),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def get_by_id(self, conn: Conn, budget_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _BUDGET_SELECT + " FROM budgets b WHERE b.budget_id = %s",
                (budget_id,),
            )
            return await cur.fetchone()

    async def get_org(self, conn: Conn, budget_id: int) -> int | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT organization_id FROM budgets WHERE budget_id = %s", (budget_id,)
            )
            row = await cur.fetchone()
            return None if row is None else int(row["organization_id"])

    async def list_by_org(
        self,
        conn: Conn,
        organization_id: int,
        *,
        range_start: date | None,
        range_end: date | None,
        limit: int,
        before_id: int | None,
    ) -> list[Row]:
        """Budgets ordered newest-first; an optional (start, end) window
        keeps only budgets whose [start_date, end_date] overlap it."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _BUDGET_SELECT
                + " FROM budgets b"
                + " WHERE b.organization_id = %s"
                + " AND (%s::date IS NULL OR b.end_date >= %s::date)"
                + " AND (%s::date IS NULL OR b.start_date <= %s::date)"
                + " AND (%s::int IS NULL OR b.budget_id < %s::int)"
                + " ORDER BY b.budget_id DESC LIMIT %s::int",
                (
                    organization_id,
                    range_start,
                    range_start,
                    range_end,
                    range_end,
                    before_id,
                    before_id,
                    limit,
                ),
            )
            return list(await cur.fetchall())

    async def update(
        self,
        conn: Conn,
        budget_id: int,
        *,
        amount: Decimal | None = None,
        start_date: date | None = None,
        end_date: date | None = None,
    ) -> Row | None:
        assignments: list[str] = []
        params: list[object] = []
        if amount is not None:
            assignments.append("amount = %s")
            params.append(str(amount))
        if start_date is not None:
            assignments.append("start_date = %s")
            params.append(start_date)
        if end_date is not None:
            assignments.append("end_date = %s")
            params.append(end_date)
        if not assignments:
            return await self.get_by_id(conn, budget_id)
        params.append(budget_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE budgets SET "
                + ", ".join(assignments)
                + " WHERE budget_id = %s RETURNING "
                + _BUDGET_SELECT_NAMED,
                tuple(params),
            )
            return await cur.fetchone()
