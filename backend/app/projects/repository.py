from __future__ import annotations
from app.db.types import Conn, Row

_PROJECT_COLUMNS = "project_id, name, budget, is_active, created_at, updated_at"

class ProjectRepository:
    async def create_project(self, conn: Conn, *, name: str, budget: float, is_active: bool) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO projects (name, budget, is_active) VALUES (%s, %s, %s) RETURNING " + _PROJECT_COLUMNS,
                (name, budget, is_active),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_projects(self, conn: Conn) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute("SELECT " + _PROJECT_COLUMNS + " FROM projects ORDER BY name ASC")
            return list(await cur.fetchall())

    async def update_project(self, conn: Conn, project_id: str, *, budget: float | None, is_active: bool | None) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE projects SET budget = COALESCE(%s, budget), is_active = COALESCE(%s, is_active) WHERE project_id = %s RETURNING " + _PROJECT_COLUMNS,
                (budget, is_active, project_id),
            )
            return await cur.fetchone()