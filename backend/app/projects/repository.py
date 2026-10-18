"""Project persistence — raw SQL only (§5). Tenant scope resolves via budgets."""

from __future__ import annotations

from datetime import date

from app.db.types import Conn, Row

_PROJECT_COLUMNS = (
    "project_id, budget_id, name, description, "
    "is_active, start_date, end_date, created_at, updated_at"
)


class ProjectRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

    async def get_budget_org(self, conn: Conn, budget_id: int) -> int | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT organization_id FROM budgets WHERE budget_id = %s",
                (budget_id,),
            )
            row = await cur.fetchone()
            return None if row is None else int(row["organization_id"])

    async def get_project_org(self, conn: Conn, project_id: int) -> int | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT b.organization_id AS organization_id"
                " FROM projects p JOIN budgets b ON b.budget_id = p.budget_id"
                " WHERE p.project_id = %s",
                (project_id,),
            )
            row = await cur.fetchone()
            return None if row is None else int(row["organization_id"])

    async def create(
        self,
        conn: Conn,
        *,
        budget_id: int,
        name: str,
        description: str | None,
        start_date: date | None,
        end_date: date | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO projects (budget_id, name, description, start_date, end_date)"
                " VALUES (%s, %s, %s, %s, %s) RETURNING " + _PROJECT_COLUMNS,
                (budget_id, name, description, start_date, end_date),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def get_by_id(self, conn: Conn, project_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _PROJECT_COLUMNS + " FROM projects WHERE project_id = %s",
                (project_id,),
            )
            return await cur.fetchone()

    async def list_by_org(
        self, conn: Conn, organization_id: int, *, limit: int, before_id: int | None
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT p.project_id, p.budget_id, p.name, p.description, p.is_active,"
                " p.start_date, p.end_date, p.created_at, p.updated_at"
                " FROM projects p JOIN budgets b ON b.budget_id = p.budget_id"
                " WHERE b.organization_id = %s"
                " AND (%s::int IS NULL OR p.project_id < %s::int)"
                " ORDER BY p.project_id DESC LIMIT %s::int",
                (organization_id, before_id, before_id, limit),
            )
            return list(await cur.fetchall())

    async def update(
        self,
        conn: Conn,
        project_id: int,
        *,
        name: str | None = None,
        description: str | None = None,
        is_active: bool | None = None,
        start_date: date | None = None,
        end_date: date | None = None,
    ) -> Row | None:
        assignments: list[str] = []
        params: list[object] = []
        if name is not None:
            assignments.append("name = %s")
            params.append(name)
        if description is not None:
            assignments.append("description = %s")
            params.append(description)
        if is_active is not None:
            assignments.append("is_active = %s")
            params.append(is_active)
        if start_date is not None:
            assignments.append("start_date = %s")
            params.append(start_date)
        if end_date is not None:
            assignments.append("end_date = %s")
            params.append(end_date)
        if not assignments:
            return await self.get_by_id(conn, project_id)
        params.append(project_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE projects SET "
                + ", ".join(assignments)
                + " WHERE project_id = %s RETURNING "
                + _PROJECT_COLUMNS,
                tuple(params),
            )
            return await cur.fetchone()
