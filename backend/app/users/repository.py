"""User persistence — raw SQL only (arch. doc §5, §32).

Reads and writes the ``users`` table plus the ``employee_status`` temporal
log. Like every repository, this module owns no business rules: the
single-active status invariant is enforced by the partial unique index
``idx_employee_status_single_active`` with a service-level 409 pre-check
for a friendly error (§49 #12).

Tenant note (§8): ``users`` rows are global — a person may belong to
several organizations — so every *admin* query here is scoped through
``memberships``. The two entry points that must stay global are
``get_by_id`` (used by ``GET /users/me``, the caller's own row) and the
``employee_status`` log, which has no organization column and is
therefore guarded by a membership check in the service.
"""

from __future__ import annotations

from app.core.constants import AccountStatus, EmployeeStatus
from app.db.types import Conn, Row

_USER_COLUMNS = (
    "employee_id, name, email, account_status, is_superuser, last_login_at, created_at, updated_at"
)

_STATUS_COLUMNS = "status_id, employee_id, status, started_at, ended_at, updated_by"


def _escape_like(value: str) -> str:
    """Escape LIKE/ILIKE wildcards so free-text search stays literal."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


class UserRepository:
    async def get_by_id(self, conn: Conn, employee_id: int) -> Row | None:
        """Global lookup by id — ``GET /users/me`` only.

        Admin endpoints must use :meth:`get_by_id_in_org` instead, or they
        would read and write users outside the caller's organization.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _USER_COLUMNS + " FROM users WHERE employee_id = %s",
                (employee_id,),
            )
            return await cur.fetchone()

    async def get_membership(
        self, conn: Conn, employee_id: int, organization_id: int
    ) -> Row | None:
        """Membership row for ``(employee, org)`` — the tenant gate (§8)."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, organization_id),
            )
            return await cur.fetchone()

    async def get_by_id_in_org(
        self, conn: Conn, employee_id: int, organization_id: int
    ) -> Row | None:
        """Scoped lookup — the user row only when they are a member of ``org``."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _USER_COLUMNS + " FROM users u"
                " WHERE u.employee_id = %s"
                " AND EXISTS (SELECT 1 FROM memberships m"
                "             WHERE m.employee_id = u.employee_id"
                "             AND m.organization_id = %s)",
                (employee_id, organization_id),
            )
            return await cur.fetchone()

    async def list_users(
        self,
        conn: Conn,
        *,
        organization_id: int,
        limit: int,
        after_id: int | None,
        search: str | None = None,
        account_status: AccountStatus | None = None,
    ) -> list[Row]:
        """Keyset list ordered by ``employee_id`` — ``limit + 1`` rows are
        fetched so the service can decide ``next_cursor`` (§21).

        Scoped to the members of ``organization_id``: an org admin only ever
        sees their own organization's directory (§8, §27).

        ``search`` is matched literally: LIKE wildcards (``%``, ``_``) in
        user input are escaped so a search for ``"100%"`` does not match
        every row.
        """
        status_value = account_status.value if account_status else None
        escaped = _escape_like(search) if search is not None else None
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT u.employee_id, u.name, u.email, u.account_status, u.is_superuser,
                       u.last_login_at, u.created_at, u.updated_at
                FROM users u
                WHERE EXISTS (SELECT 1 FROM memberships m
                              WHERE m.employee_id = u.employee_id
                                AND m.organization_id = %s)
                  AND (%s::int IS NULL OR u.employee_id > %s::int)
                  AND (%s::text IS NULL OR
                       u.name ILIKE '%%' || %s::text || '%%' ESCAPE '\\' OR
                       u.email ILIKE '%%' || %s::text || '%%' ESCAPE '\\')
                  AND (%s::text IS NULL OR u.account_status = %s::text)
                ORDER BY u.employee_id ASC
                LIMIT %s::int
                """,
                (
                    organization_id,
                    after_id,
                    after_id,
                    escaped,
                    escaped,
                    escaped,
                    status_value,
                    status_value,
                    limit + 1,
                ),
            )
            return list(await cur.fetchall())

    async def update_user(
        self,
        conn: Conn,
        employee_id: int,
        *,
        organization_id: int,
        name: str | None = None,
        account_status: AccountStatus | None = None,
    ) -> Row | None:
        """Patch a user **within the caller's organization**.

        The membership predicate is part of the UPDATE, not a separate
        check, so a concurrent membership removal cannot widen the write
        between the read and the write.
        """
        assignments: list[str] = []
        params: list[object] = []
        if name is not None:
            assignments.append("name = %s")
            params.append(name)
        if account_status is not None:
            assignments.append("account_status = %s")
            params.append(account_status.value)
        if not assignments:
            return await self.get_by_id_in_org(conn, employee_id, organization_id)
        params.extend((employee_id, organization_id))
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE users SET " + ", ".join(assignments) + " WHERE employee_id = %s"
                " AND EXISTS (SELECT 1 FROM memberships m"
                "             WHERE m.employee_id = users.employee_id"
                "             AND m.organization_id = %s) RETURNING " + _USER_COLUMNS,
                tuple(params),
            )
            return await cur.fetchone()

    async def list_statuses(self, conn: Conn, employee_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _STATUS_COLUMNS + " FROM employee_status WHERE employee_id = %s"
                " ORDER BY started_at DESC, status_id DESC",
                (employee_id,),
            )
            return list(await cur.fetchall())

    async def get_active_status(self, conn: Conn, employee_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _STATUS_COLUMNS + " FROM employee_status"
                " WHERE employee_id = %s AND ended_at IS NULL",
                (employee_id,),
            )
            return await cur.fetchone()

    async def close_status(
        self, conn: Conn, *, employee_id: int, updated_by: int | None
    ) -> Row | None:
        """End the employee's currently open status record.

        The request-scoped ``conn`` keeps close + re-open atomic with the
        caller's other writes. Returns None when nothing is open (e.g. a
        concurrent request already closed it); the caller then falls back
        to the DB's single-active partial unique for the final verdict.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE employee_status SET ended_at = CURRENT_TIMESTAMP,"
                " updated_by = %s WHERE employee_id = %s AND ended_at IS NULL"
                " RETURNING " + _STATUS_COLUMNS,
                (updated_by, employee_id),
            )
            return await cur.fetchone()

    async def create_status(
        self,
        conn: Conn,
        *,
        employee_id: int,
        status: EmployeeStatus,
        updated_by: int | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO employee_status (employee_id, status, updated_by)"
                " VALUES (%s, %s, %s) RETURNING " + _STATUS_COLUMNS,
                (employee_id, status.value, updated_by),
            )
            row = await cur.fetchone()
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row
