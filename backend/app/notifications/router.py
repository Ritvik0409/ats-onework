"""Notification read endpoints — HTTP only (§49 #36-38). Owner-scoped."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.api.v1.deps import CurrentUser
from app.common.pagination import Page
from app.common.permissions import RequirePermission
from app.db.connection import get_connection
from app.db.types import Conn
from app.notifications.schemas import NotificationListItem
from app.notifications.service import service as notification_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


def _parse_cursor(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    try:
        value = int(cursor)
    except (TypeError, ValueError) as exc:
        from app.core.exceptions import ValidationError

        raise ValidationError("Invalid pagination cursor.") from exc
    return value if value > 0 else None


@router.get("", response_model=Page[NotificationListItem])
async def list_notifications(
    user: Annotated[CurrentUser, Depends(RequirePermission("notification.read"))],
    conn: Annotated[Conn, Depends(get_connection)],
    unread_only: Annotated[bool, Query()] = False,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[NotificationListItem]:
    items = await notification_service.list_for_employee(
        conn,
        employee_id=user.employee_id,
        unread_only=unread_only,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].notification_id) if items else None
    return Page[NotificationListItem](items=items, next_cursor=next_cursor)


@router.post("/{notification_id}/read", status_code=status.HTTP_204_NO_CONTENT)
async def mark_read(
    notification_id: int,
    user: Annotated[CurrentUser, Depends(RequirePermission("notification.read"))],
    conn: Annotated[Conn, Depends(get_connection)],
) -> Response:
    await notification_service.mark_read(
        conn, employee_id=user.employee_id, notification_id=notification_id
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/read-all", status_code=status.HTTP_204_NO_CONTENT)
async def mark_all_read(
    user: Annotated[CurrentUser, Depends(RequirePermission("notification.read"))],
    conn: Annotated[Conn, Depends(get_connection)],
) -> Response:
    await notification_service.mark_all_read(conn, employee_id=user.employee_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
