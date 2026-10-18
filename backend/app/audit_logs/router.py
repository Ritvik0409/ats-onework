"""Audit-log read endpoint — HTTP only (§49 #39, admin only)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.api.v1.deps import CurrentUser, get_current_user
from app.audit_logs.schemas import AuditLogListItem
from app.audit_logs.service import service as audit_log_service
from app.common.pagination import Page
from app.db.connection import get_connection
from app.db.types import Conn

router = APIRouter(prefix="/audit-logs", tags=["audit-logs"])


def _parse_cursor(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    try:
        value = int(cursor)
    except (TypeError, ValueError) as exc:
        from app.core.exceptions import ValidationError

        raise ValidationError("Invalid pagination cursor.") from exc
    return value if value > 0 else None


@router.get("", response_model=Page[AuditLogListItem])
async def list_audit_logs(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
    table_name: Annotated[str | None, Query()] = None,
    actor_id: Annotated[int | None, Query(gt=0)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[AuditLogListItem]:
    items = await audit_log_service.list(
        conn,
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        table_name=table_name,
        actor_id=actor_id,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].log_id) if items else None
    return Page[AuditLogListItem](items=items, next_cursor=next_cursor)
