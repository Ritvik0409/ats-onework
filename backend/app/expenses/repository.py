from __future__ import annotations
from app.db.types import Conn, Row

_EXPENSE_COLUMNS = "expense_id, employee_id, employee_name, email, type, amount, date, description, status, receipt_base64, project_name, uploader_role, created_at, updated_at"

class ExpenseRepository:
    async def create_expense(self, conn: Conn, *, employee_id: str, employee_name: str, email: str, type: str, amount: float, date: str, description: str, status: str, receipt_base64: str | None, project_name: str | None, uploader_role: str) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO expenses (employee_id, employee_name, email, type, amount, date, description, status, receipt_base64, project_name, uploader_role)"
                " VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING " + _EXPENSE_COLUMNS,
                (employee_id, employee_name, email, type, amount, date, description, status, receipt_base64, project_name, uploader_role),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_expenses(self, conn: Conn) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute("SELECT " + _EXPENSE_COLUMNS + " FROM expenses ORDER BY created_at DESC")
            return list(await cur.fetchall())

    async def update_expense_status(self, conn: Conn, expense_id: str, *, status: str, rejection_reason: str | None, processed_by: str | None, transaction_id: str | None, payment_receipt_url: str | None) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE expenses SET status = %s, rejection_reason = %s, processed_by = %s, transaction_id = %s, payment_receipt_url = %s WHERE expense_id = %s RETURNING " + _EXPENSE_COLUMNS,
                (status, rejection_reason, processed_by, transaction_id, payment_receipt_url, expense_id),
            )
            return await cur.fetchone()