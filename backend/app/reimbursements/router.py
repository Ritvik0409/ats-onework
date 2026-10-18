"""Reimbursement endpoints — HTTP only (§49 #33-35)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.common.pagination import Page
from app.core.constants import ReimbursementStatus
from app.db.connection import get_connection
from app.db.types import Conn
from app.reimbursements.schemas import (
    ReimbursementCreate,
    ReimbursementListItem,
    ReimbursementResponse,
    ReimbursementTransitionRequest,
)
from app.reimbursements.service import service as reimbursement_service

router = APIRouter(prefix="/reimbursements", tags=["reimbursements"])
expense_router = APIRouter(prefix="/expenses", tags=["reimbursements"])


def _parse_cursor(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    try:
        value = int(cursor)
    except (TypeError, ValueError) as exc:
        from app.core.exceptions import ValidationError

        raise ValidationError("Invalid pagination cursor.") from exc
    return value if value > 0 else None


@expense_router.post(
    "/{expense_id}/reimbursement",
    response_model=ReimbursementResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_reimbursement(
    expense_id: int,
    payload: ReimbursementCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ReimbursementResponse:
    return await reimbursement_service.create_for_expense(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        expense_id=expense_id,
        payload=payload,
    )


@router.get("", response_model=Page[ReimbursementListItem])
async def list_reimbursements(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
    status_filter: Annotated[ReimbursementStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ReimbursementListItem]:
    items = await reimbursement_service.list(
        conn,
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        status=status_filter,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].reimbursement_id) if items else None
    return Page[ReimbursementListItem](items=items, next_cursor=next_cursor)


@router.post("/{reimbursement_id}/transition", response_model=ReimbursementResponse)
async def transition_reimbursement(
    reimbursement_id: int,
    payload: ReimbursementTransitionRequest,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ReimbursementResponse:
    return await reimbursement_service.transition(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        reimbursement_id=reimbursement_id,
        payload=payload,
    )
