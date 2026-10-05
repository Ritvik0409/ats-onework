from __future__ import annotations
from app.db.types import Conn, Row

_STATUS_COLUMNS = "status_id, email, is_active, updated_by, updated_at"

class EmployeeStatusRepository:
    async def upsert_status(self, conn: Conn, *, email: str, is_active: bool, updated_by: str | None) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO employee_status (email, is_active, updated_by) "
                "VALUES (%s, %s, %s) "
                "ON CONFLICT (email) DO UPDATE SET is_active = EXCLUDED.is_active, updated_by = EXCLUDED.updated_by, updated_at = NOW() "
                "RETURNING " + _STATUS_COLUMNS,
                (email, is_active, updated_by),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_statuses(self, conn: Conn) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute("SELECT " + _STATUS_COLUMNS + " FROM employee_status")
            return list(await cur.fetchall())