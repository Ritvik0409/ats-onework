"""Audit-log reads — raw SQL only (§5).

Audit rows carry the organization they belong to (migration 0005), so the
tenant scope comes straight from the column. Deriving it from the actor's
membership instead would expose the actions of someone who belongs to
several organizations to each of them.
"""

from __future__ import annotations

from app.db.types import Conn, Row

_LOG_COLUMNS = (
    "log_id, actor_id, organization_id, action, table_name, record_id, "
    "old_values, new_values, created_at"
)


class AuditLogRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

    async def list_for_org(
        self,
        conn: Conn,
        organization_id: int,
        *,
        table_name: str | None,
        actor_id: int | None,
        limit: int,
        before_id: int | None,
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _LOG_COLUMNS + " FROM audit_logs l"
                " WHERE l.organization_id = %s"
                " AND (%s::text IS NULL OR l.table_name = %s::text)"
                " AND (%s::int IS NULL OR l.actor_id = %s::int)"
                " AND (%s::int IS NULL OR l.log_id < %s::int)"
                " ORDER BY l.log_id DESC LIMIT %s::int",
                (
                    organization_id,
                    table_name,
                    table_name,
                    actor_id,
                    actor_id,
                    before_id,
                    before_id,
                    limit,
                ),
            )
            return list(await cur.fetchall())
