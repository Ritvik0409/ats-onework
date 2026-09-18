"""User persistence — raw SQL only (arch. doc §5, §32).

Reads and writes the ``users`` table plus the ``employee_status`` temporal
log. Like every repository, this module owns no business rules: the
single-active status invariant is enforced by the partial unique index
``idx_employee_status_single_active`` with a service-level 409 pre-check
for a friendly error (§49 #12).
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
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _USER_COLUMNS + " FROM users WHERE employee_id = %s",
                (employee_id,),
            )
            return await cur.fetchone()

    async def list_users(
        self,
        conn: Conn,
        *,
        limit: int,
        after_id: int | None,
        search: str | None = None,
        account_status: AccountStatus | None = None,
    ) -> list[Row]:
        """Keyset list ordered by ``employee_id`` — ``limit + 1`` rows are
        fetched so the service can decide ``next_cursor`` (§21).

        ``search`` is matched literally: LIKE wildcards (``%``, ``_``) in
        user input are escaped so a search for ``"100%"`` does not match
        every row.
        """
        status_value = account_status.value if account_status else None
        escaped = _escape_like(search) if search is not None else None
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT employee_id, name, email, account_status, is_superuser,
                       last_login_at, created_at, updated_at
                FROM users
                WHERE (%s::int IS NULL OR employee_id > %s::int)
                  AND (%s::text IS NULL OR
                       name ILIKE '%%' || %s::text || '%%' ESCAPE '\\' OR
                       email ILIKE '%%' || %s::text || '%%' ESCAPE '\\')
                  AND (%s::text IS NULL OR account_status = %s::text)
                ORDER BY employee_id ASC
                LIMIT %s::int
                """,
                (
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
        name: str | None = None,
        account_status: AccountStatus | None = None,
        is_superuser: bool | None = None,
    ) -> Row | None:
        assignments: list[str] = []
        params: list[object] = []
        if name is not None:
            assignments.append("name = %s")
            params.append(name)
        if account_status is not None:
            assignments.append("account_status = %s")
            params.append(account_status.value)
        if is_superuser is not None:
            assignments.append("is_superuser = %s")
            params.append(is_superuser)
        if not assignments:
            return await self.get_by_id(conn, employee_id)
        params.append(employee_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE users SET "
                + ", ".join(assignments)
                + " WHERE employee_id = %s RETURNING "
                + _USER_COLUMNS,
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
