from __future__ import annotations
from app.db.types import Conn, Row

_REIMB_COLUMNS = "reimbursement_id, expense_id, amount, employee_email, status, created_at, updated_at"

class ReimbursementRepository:
    async def create(self, conn: Conn, *, expense_id: str, amount: float, employee_email: str) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO reimbursements (expense_id, amount, employee_email, status) VALUES (%s, %s, %s, 'Pending') RETURNING " + _REIMB_COLUMNS,
                (expense_id, amount, employee_email),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_all(self, conn: Conn) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute("SELECT " + _REIMB_COLUMNS + " FROM reimbursements ORDER BY created_at DESC")
            return list(await cur.fetchall())

    async def update(self, conn: Conn, reimbursement_id: str, status: str) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE reimbursements SET status = %s WHERE reimbursement_id = %s RETURNING " + _REIMB_COLUMNS,
                (status, reimbursement_id),
            )
            return await cur.fetchone()