"""Budget persistence — raw SQL only (§5)."""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from app.db.types import Conn, Row

_BUDGET_COLUMNS = (
    "budget_id, amount, employee_id, organization_id, start_date, end_date, created_at, updated_at"
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
                " VALUES (%s, %s, %s, %s, %s) RETURNING " + _BUDGET_COLUMNS,
                (str(amount), employee_id, organization_id, start_date, end_date),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def get_by_id(self, conn: Conn, budget_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _BUDGET_COLUMNS + " FROM budgets WHERE budget_id = %s",
                (budget_id,),
            )
            return await cur.fetchone()
