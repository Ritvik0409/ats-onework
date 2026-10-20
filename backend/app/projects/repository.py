"""Project persistence — raw SQL only (§5). Tenant scope resolves via budgets."""

from __future__ import annotations

from datetime import date

from app.db.types import Conn, Row

# Every project read also surfaces the budget amount and the member count —
# both belong to the project's business meaning and the Flutter app shows them.
# The member ids come along too: without them a client cannot tell which
# projects the signed-in employee actually has access to.
_PROJECT_SELECT = (
    "p.project_id, p.budget_id, p.name, p.description, p.is_active,"
    " p.start_date, p.end_date, p.created_at, p.updated_at,"
    " b.amount AS budget_amount,"
    " (SELECT COUNT(*) FROM project_members pm WHERE pm.project_id = p.project_id)"
    " AS member_count,"
    " COALESCE((SELECT ARRAY_AGG(pm.employee_id ORDER BY pm.employee_id)"
    "           FROM project_members pm WHERE pm.project_id = p.project_id),"
    "          ARRAY[]::int[]) AS assigned_employee_ids"
)

# Same fields re-read after INSERT/UPDATE: the joined aggregate columns
# (budget_amount, member_count) cannot appear in those statements'
# RETURNING clauses — ``budgets.amount`` is not the target table and
# plain RETURNING only sees the mutated row — so write-backs return their
# own fields and the caller re-fetches with the joined SELECT.
_PROJECT_RETURNING = (
    "project_id, budget_id, organization_id, name, description, is_active,"
    " start_date, end_date, created_at, updated_at"
)


_MEMBER_SELECT = (
    "pm.project_member_id, pm.project_id, pm.employee_id, pm.role_id,"
    " r.name AS role_name, u.name AS employee_name, u.email AS employee_email"
)


# Member fields WITHOUT the joined names — write statements (INSERT /
# DELETE ... RETURNING) can only reference the target table, so they
# return these and ``insert_member`` re-reads the joined SELECT.
_MEMBER_RETURNING = "project_member_id, project_id, employee_id, role_id"


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
        organization_id: int,
        name: str,
        description: str | None,
        start_date: date | None,
        end_date: date | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO projects"
                " (budget_id, organization_id, name, description, start_date, end_date)"
                " VALUES (%s, %s, %s, %s, %s, %s) RETURNING " + _PROJECT_RETURNING,
                (budget_id, organization_id, name, description, start_date, end_date),
            )
            row = await cur.fetchone()
            assert row is not None
            # Re-read with the joined SELECT so the response carries
            # budget_amount + member_count like every other project read.
            inserted = await self.get_by_id(conn, row["project_id"], organization_id)
            assert inserted is not None
            return inserted

    async def get_by_id(self, conn: Conn, project_id: int, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _PROJECT_SELECT
                + " FROM projects p JOIN budgets b ON b.budget_id = p.budget_id"
                + " WHERE p.project_id = %s"
                + " AND p.organization_id = %s",
                (project_id, organization_id),
            )
            return await cur.fetchone()

    async def list_by_org(
        self, conn: Conn, organization_id: int, *, limit: int, before_id: int | None
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _PROJECT_SELECT
                + " FROM projects p JOIN budgets b ON b.budget_id = p.budget_id"
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
        organization_id: int,
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
            return await self.get_by_id(conn, project_id, organization_id)
        params.append(project_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE projects SET "
                + ", ".join(assignments)
                + " WHERE project_id = %s"
                + " AND organization_id = %s"
                + " RETURNING "
                + _PROJECT_RETURNING,
                tuple([*params, organization_id]),
            )
            row = await cur.fetchone()
            assert row is not None
            updated = await self.get_by_id(conn, row["project_id"], organization_id)
            assert updated is not None
            return updated

    # -- project members ---------------------------------------------------

    async def list_members(
        self,
        conn: Conn,
        project_id: int,
        *,
        organization_id: int,
        before_id: int | None,
        limit: int,
    ) -> list[Row]:
        """Members newest-first, keyset-paginated.

        The cursor is the last row's id and the next page selects rows
        *below* it, so the ordering must be descending to match. Pairing
        a descending cursor with an ascending order returned the same
        page forever.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _MEMBER_SELECT
                + " FROM project_members pm JOIN users u ON u.employee_id = pm.employee_id"
                + " JOIN roles r ON r.role_id = pm.role_id"
                + " WHERE pm.project_id = %s"
                + " AND pm.organization_id = %s"
                + " AND (%s::int IS NULL OR pm.project_member_id < %s::int)"
                + " ORDER BY pm.project_member_id DESC LIMIT %s::int",
                (project_id, organization_id, before_id, before_id, limit),
            )
            return list(await cur.fetchall())

    async def is_project_member(self, conn: Conn, project_id: int, employee_id: int) -> bool:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT 1 FROM project_members WHERE project_id = %s AND employee_id = %s",
                (project_id, employee_id),
            )
            return (await cur.fetchone()) is not None

    async def get_member(self, conn: Conn, member_id: int, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _MEMBER_SELECT
                + " FROM project_members pm JOIN users u ON u.employee_id = pm.employee_id"
                + " JOIN roles r ON r.role_id = pm.role_id"
                + " WHERE pm.project_member_id = %s"
                + " AND pm.organization_id = %s",
                (member_id, organization_id),
            )
            return await cur.fetchone()

    async def insert_member(
        self,
        conn: Conn,
        *,
        project_id: int,
        organization_id: int,
        employee_id: int,
        role_id: int,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO project_members"
                " (project_id, organization_id, employee_id, role_id)"
                " VALUES (%s, %s, %s, %s) RETURNING " + _MEMBER_RETURNING,
                (project_id, organization_id, employee_id, role_id),
            )
            row = await cur.fetchone()
            assert row is not None
            # Re-read with the joined SELECT so the response carries
            # role_name / employee identity like every other member read.
            inserted = await self.get_member(conn, row["project_member_id"], organization_id)
            assert inserted is not None
            return inserted

    async def delete_member(self, conn: Conn, project_id: int, employee_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM project_members WHERE project_id = %s AND employee_id = %s"
                " RETURNING " + _MEMBER_RETURNING,
                (project_id, employee_id),
            )
            return await cur.fetchone()

    async def get_default_role_id(self, conn: Conn, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT role_id FROM roles WHERE organization_id = %s AND name = 'employee'",
                (organization_id,),
            )
            return await cur.fetchone()

    async def get_role(self, conn: Conn, role_id: int, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT role_id, organization_id, name FROM roles"
                " WHERE role_id = %s AND organization_id = %s",
                (role_id, organization_id),
            )
            return await cur.fetchone()

    async def get_employee_membership(
        self, conn: Conn, employee_id: int, organization_id: int
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, organization_id),
            )
            return await cur.fetchone()
