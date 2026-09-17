"""Notification orchestration — service layer (arch. doc §7, §38).

Services (expenses, approvals, reimbursements) call ``NotificationService``
from inside their workflow transaction so the notification row commits or
rolls back atomically with the business state change. Delivery to external
channels (push/email) is scheduled by routers via ``BackgroundTasks`` —
never awaited inline.
"""

from __future__ import annotations

from app.db.types import Conn, Row
from app.notifications.repository import NotificationRepository
from app.notifications.schemas import (
    NotificationCreate,
    NotificationListItem,
    NotificationResponse,
)

_repository = NotificationRepository()


class NotificationService:
    def __init__(self, repository: NotificationRepository | None = None) -> None:
        self._repository = repository or _repository

    async def create(self, conn: Conn, payload: NotificationCreate) -> NotificationResponse:
        row: Row = await self._repository.insert(conn, payload)
        return NotificationResponse.model_validate(row)

    async def list_for_employee(
        self,
        conn: Conn,
        *,
        employee_id: int,
        unread_only: bool = False,
        limit: int = 20,
        before_id: int | None = None,
    ) -> list[NotificationListItem]:
        rows = await self._repository.list_for_employee(
            conn,
            employee_id=employee_id,
            unread_only=unread_only,
            limit=limit,
            before_id=before_id,
        )
        return [NotificationListItem.model_validate(row) for row in rows]


service = NotificationService()
