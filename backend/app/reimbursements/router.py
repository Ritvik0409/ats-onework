"""Reimbursement endpoints — HTTP only (§49 #33-35)."""

from __future__ import annotations

import io
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, Query, UploadFile, status

from app.api.v1.deps import CurrentUser
from app.common.object_storage import get_object_storage
from app.common.pagination import Page
from app.common.permissions import RequireAnyPermission, RequirePermission
from app.core.constants import ReimbursementStatus
from app.core.exceptions import ValidationError
from app.db.connection import get_connection
from app.db.types import Conn
from app.expenses.uploads import verify_upload
from app.reimbursements.schemas import (
    ReimbursementCreate,
    ReimbursementListItem,
    ReimbursementResponse,
    ReimbursementTransitionRequest,
)
from app.reimbursements.service import service as reimbursement_service

router = APIRouter(prefix="/reimbursements", tags=["reimbursements"])
expense_router = APIRouter(prefix="/expenses", tags=["reimbursements"])

_MAX_FILE_BYTES = 5 * 1024 * 1024


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
    user: Annotated[CurrentUser, Depends(RequirePermission("reimbursement.create"))],
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
    user: Annotated[
        CurrentUser,
        Depends(RequireAnyPermission("reimbursement.read_own", "reimbursement.read_all")),
    ],
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


@router.post("/{reimbursement_id}/receipt", response_model=ReimbursementResponse)
async def attach_payment_receipt(
    reimbursement_id: int,
    user: Annotated[CurrentUser, Depends(RequirePermission("reimbursement.receipt"))],
    conn: Annotated[Conn, Depends(get_connection)],
    file: Annotated[UploadFile, File()],
) -> ReimbursementResponse:
    """Attach the receipt that proves a payout was made.

    The file's type is taken from its own bytes and the stored extension
    is chosen server-side, exactly as for an expense receipt.
    """
    content = await file.read()
    if len(content) > _MAX_FILE_BYTES:
        raise ValidationError(f"File {file.filename} exceeds 5MB.")
    verified = verify_upload(file.filename, content)
    storage = get_object_storage()
    key = f"payment-receipts/{user.organization_id}/{uuid.uuid4().hex}{verified.extension}"
    url = await storage.upload(
        key=key,
        data=io.BytesIO(content),
        content_type=verified.content_type,
    )
    try:
        return await reimbursement_service.attach_payment_receipt(
            conn,
            actor_id=user.employee_id,
            organization_id=user.organization_id,
            reimbursement_id=reimbursement_id,
            payment_receipt_url=url,
        )
    except Exception:
        # The reimbursement was not updated, so the uploaded file would
        # be an orphan.
        await storage.delete(key=url)
        raise


@router.post("/{reimbursement_id}/transition", response_model=ReimbursementResponse)
async def transition_reimbursement(
    reimbursement_id: int,
    payload: ReimbursementTransitionRequest,
    user: Annotated[CurrentUser, Depends(RequirePermission("reimbursement.transition"))],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ReimbursementResponse:
    return await reimbursement_service.transition(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        reimbursement_id=reimbursement_id,
        payload=payload,
    )
