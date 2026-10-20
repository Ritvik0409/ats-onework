"""Project-access-request persistence — raw SQL only (§5).

The request row is org-scoped via its denormalized ``organization_id``
(migration 0002); the project's org is still re-derived through its
budget so a stale/missing row cannot escape tenant checks.
"""

from __future__ import annotations

from app.db.types import Conn, Row
from app.project_requests.schemas import ProjectAccessStatus

_PAR_COLUMNS = (
    "access_request_id, project_id, employee_id, organization_id, status, "
    "decided_by, decision_comment, requested_at, decided_at, updated_at"
)

# Joined variant for UI queues — requester identity + target project name.
# Every source column MUST carry the ``par.`` prefix: the bare names are
# ambiguous the moment the projects/users tables join in.
_PAR_JOINED_COLUMNS = (
    "par.access_request_id, par.project_id, par.employee_id, par.organization_id,"
    " par.status, par.decided_by, par.decision_comment, par.requested_at,"
    " par.decided_at, par.updated_at,"
    " u.name AS employee_name, u.email AS employee_email, p.name AS project_name"
)

_JOINS = (
    " FROM project_access_requests par"
    " JOIN users u ON u.employee_id = par.employee_id"
    " JOIN projects p ON p.project_id = par.project_id"
)


class ProjectAccessRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

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

    async def get_request_org(self, conn: Conn, request_id: int) -> int | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT organization_id FROM project_access_requests WHERE access_request_id = %s",
                (request_id,),
            )
            row = await cur.fetchone()
            return None if row is None else int(row["organization_id"])

    async def create(
        self, conn: Conn, *, employee_id: int, project_id: int, organization_id: int
    ) -> Row:
        """Insert a pending request (partial unique rejects duplicates)."""
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO project_access_requests (project_id, employee_id, organization_id)"
                " VALUES (%s, %s, %s) RETURNING " + _PAR_COLUMNS,
                (project_id, employee_id, organization_id),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def get_by_id_for_update(self, conn: Conn, request_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _PAR_COLUMNS + " FROM project_access_requests"
                " WHERE access_request_id = %s AND organization_id = %s FOR UPDATE",
                (request_id, org_id),
            )
            return await cur.fetchone()

    async def find_pending(self, conn: Conn, project_id: int, employee_id: int) -> Row | None:
        """A duplicate pending request (partial unique `uq_par_pending`)."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _PAR_COLUMNS + " FROM project_access_requests"
                " WHERE project_id = %s AND employee_id = %s AND status = 'pending'",
                (project_id, employee_id),
            )
            return await cur.fetchone()

    async def list_by_project(
        self,
        conn: Conn,
        organization_id: int,
        *,
        project_id: int | None = None,
        status: ProjectAccessStatus | None = None,
        limit: int,
        before_id: int | None,
    ) -> list[Row]:
        """Admin queue — whole org by default, optionally one project.
        Joined context (requester name/email, project name) feeds the UI
        without extra round-trips."""
        clauses = [
            "par.organization_id = %s",
            "(%s::int IS NULL OR par.access_request_id < %s::int)",
        ]
        params: list[object] = [organization_id, before_id, before_id]
        if project_id is not None:
            clauses.append("par.project_id = %s")
            params.append(project_id)
        if status is not None:
            clauses.append("par.status = %s")
            params.append(status.value)
        params.append(limit)
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _PAR_JOINED_COLUMNS
                + _JOINS
                + " WHERE "
                + " AND ".join(clauses)
                + " ORDER BY par.access_request_id DESC LIMIT %s::int",
                tuple(params),
            )
            return list(await cur.fetchall())

    async def list_by_employee(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        limit: int,
        before_id: int | None,
    ) -> list[Row]:
        """Own requests only (GET /access-requests/mine)."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _PAR_JOINED_COLUMNS
                + _JOINS
                + " WHERE par.employee_id = %s::int AND par.organization_id = %s::int"
                " AND (%s::int IS NULL OR par.access_request_id < %s::int)"
                " ORDER BY par.access_request_id DESC LIMIT %s::int",
                (employee_id, organization_id, before_id, before_id, limit),
            )
            return list(await cur.fetchall())

    async def is_project_member(self, conn: Conn, project_id: int, employee_id: int) -> bool:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT 1 FROM project_members WHERE project_id = %s AND employee_id = %s",
                (project_id, employee_id),
            )
            return await cur.fetchone() is not None

    async def insert_member(
        self,
        conn: Conn,
        *,
        project_id: int,
        organization_id: int,
        employee_id: int,
        role_id: int,
    ) -> Row | None:
        """Grant membership (0001 `project_members`); returns None on conflict."""
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO project_members"
                " (project_id, organization_id, employee_id, role_id)"
                " VALUES (%s, %s, %s, %s)"
                " ON CONFLICT (project_id, employee_id) DO NOTHING"
                " RETURNING project_member_id, project_id, employee_id, role_id",
                (project_id, organization_id, employee_id, role_id),
            )
            return await cur.fetchone()

    async def get_default_role_id(self, conn: Conn, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT role_id FROM roles WHERE organization_id = %s AND name = 'employee'",
                (organization_id,),
            )
            return await cur.fetchone()

    async def update_status(
        self,
        conn: Conn,
        *,
        request_id: int,
        status: ProjectAccessStatus,
        decided_by: int,
        decision_comment: str | None,
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE project_access_requests SET status = %s, decided_by = %s,"
                " decision_comment = %s, decided_at = CURRENT_TIMESTAMP"
                " WHERE access_request_id = %s RETURNING " + _PAR_COLUMNS,
                (status.value, decided_by, decision_comment, request_id),
            )
            return await cur.fetchone()
