from __future__ import annotations
from app.db.types import Conn, Row

_TYPE_COLUMNS = "type_id, name, created_at"

class ExpenseTypeRepository:
    async def create_type(self, conn: Conn, *, name: str) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO expense_types (name) VALUES (%s) RETURNING " + _TYPE_COLUMNS,
                (name,),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_types(self, conn: Conn) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute("SELECT " + _TYPE_COLUMNS + " FROM expense_types ORDER BY name ASC")
            return list(await cur.fetchall())