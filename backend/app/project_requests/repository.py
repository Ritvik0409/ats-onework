from __future__ import annotations
from app.db.types import Conn, Row

_REQ_COLUMNS = "request_id, email, name, status, created_at, updated_at"

class ProjectRequestRepository:
    async def create_request(self, conn: Conn, *, email: str, name: str, status: str) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO project_requests (email, name, status) VALUES (%s, %s, %s) RETURNING " + _REQ_COLUMNS,
                (email, name, status),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_requests(self, conn: Conn) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute("SELECT " + _REQ_COLUMNS + " FROM project_requests ORDER BY created_at DESC")
            return list(await cur.fetchall())

    async def update_status(self, conn: Conn, email: str, status: str) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE project_requests SET status = %s WHERE email = %s RETURNING " + _REQ_COLUMNS,
                (status, email),
            )
            return await cur.fetchone()