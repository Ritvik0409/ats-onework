"""Notification persistence — raw SQL only (arch. doc §5, §32).

The repository inserts into ``notifications`` / reads back rows; it owns no
business rules and is never called from routers — only from services.
Every statement is parameterized; rows come back as dicts (``dict_row``).
"""

from __future__ import annotations

from app.db.types import Conn, Row
from app.notifications.schemas import NotificationCreate, NotificationListItem


class NotificationRepository:
    async def insert(self, conn: Conn, payload: NotificationCreate) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO notifications
                    (employee_id, title, message, type, reference_id)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING notification_id, employee_id, title, message,
                          type, reference_id, is_read, created_at
                """,
                (
                    payload.employee_id,
                    payload.title,
                    payload.message,
                    payload.type,
                    payload.reference_id,
                ),
            )
            row = await cur.fetchone()
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row

    async def list_for_employee(
        self,
        conn: Conn,
        *,
        employee_id: int,
        unread_only: bool = False,
        limit: int = 20,
        before_id: int | None = None,
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT notification_id, employee_id, title, message,
                       type, reference_id, is_read, created_at
                FROM notifications
                WHERE employee_id = %s
                  AND (%s OR NOT is_read)
                  AND (%s::int IS NULL OR notification_id < %s::int)
                ORDER BY notification_id DESC
                LIMIT %s::int
                """,
                (employee_id, not unread_only, before_id, before_id, limit),
            )
            return list(await cur.fetchall())

    async def mark_read(self, conn: Conn, *, employee_id: int, notification_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                UPDATE notifications
                SET is_read = TRUE
                WHERE notification_id = %s AND employee_id = %s AND NOT is_read
                RETURNING notification_id, employee_id, title, message,
                          type, reference_id, is_read, created_at
                """,
                (notification_id, employee_id),
            )
            return await cur.fetchone()

    async def mark_all_read(self, conn: Conn, *, employee_id: int) -> int:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                UPDATE notifications
                SET is_read = TRUE
                WHERE employee_id = %s AND NOT is_read
                """,
                (employee_id,),
            )
            return cur.rowcount

    async def to_list_items(self, rows: list[Row]) -> list[NotificationListItem]:
        return [NotificationListItem.model_validate(row) for row in rows]
