from __future__ import annotations
from app.db.types import Conn, Row

_BUDGET_COLUMNS = "budget_id, month, amount, set_by_email, set_by_name, created_at, updated_at"

class BudgetRepository:
    async def get_by_month(self, conn: Conn, month: str) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _BUDGET_COLUMNS + " FROM budgets WHERE month = %s",
                (month,),
            )
            return await cur.fetchone()

    async def upsert_budget(self, conn: Conn, *, month: str, amount: float, set_by_email: str, set_by_name: str) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO budgets (month, amount, set_by_email, set_by_name) "
                "VALUES (%s, %s, %s, %s) "
                "ON CONFLICT (month) DO UPDATE SET amount = EXCLUDED.amount, set_by_email = EXCLUDED.set_by_email, set_by_name = EXCLUDED.set_by_name, updated_at = NOW() "
                "RETURNING " + _BUDGET_COLUMNS,
                (month, amount, set_by_email, set_by_name),
            )
            row = await cur.fetchone()
            assert row is not None
            return row