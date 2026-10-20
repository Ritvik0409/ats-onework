"""Expense endpoints — HTTP concerns only (§49 #27-32).

``POST /expenses`` accepts multipart form fields + receipt files (§15);
files go through the ``ObjectStorage`` abstraction — only the URL lands
in ``expense_media.receipt_url``. Admin decisions live under
``POST /expenses/{id}/approve|reject``; the pending queue is
``GET /approvals/pending`` (separate prefix, same module).
"""

from __future__ import annotations

import io
import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, Query, UploadFile, status
from pydantic import ValidationError as PydanticValidationError

from app.api.v1.deps import CurrentUser, require_admin, require_membership
from app.common.object_storage import get_object_storage
from app.common.pagination import Page
from app.core.constants import ExpenseStatus
from app.core.exceptions import ValidationError
from app.db.connection import get_connection
from app.db.types import Conn
from app.expenses.schemas import (
    ApprovalActionRequest,
    ExpenseCreate,
    ExpenseListItem,
    ExpenseResponse,
    ExpenseResubmit,
)
from app.expenses.service import service as expense_service
from app.expenses.uploads import verify_upload
from app.notifications.dispatch import enqueue_notification_dispatch
from app.notifications.schemas import NotificationResponse

router = APIRouter(prefix="/expenses", tags=["expenses"])
approvals_router = APIRouter(prefix="/approvals", tags=["approvals"])

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


def _page(items: list[ExpenseListItem]) -> Page[ExpenseListItem]:
    next_cursor = str(items[-1].expense_id) if items else None
    return Page[ExpenseListItem](items=items, next_cursor=next_cursor)


@router.post("", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
async def submit_expense(
    background: BackgroundTasks,
    user: Annotated[CurrentUser, Depends(require_membership)],
    conn: Annotated[Conn, Depends(get_connection)],
    project_id: Annotated[int, Form(gt=0)],
    expense_type_id: Annotated[int, Form(gt=0)],
    amount: Annotated[str, Form()],
    expense_date: Annotated[date, Form()],
    description: Annotated[str | None, Form(max_length=1000)] = None,
    files: Annotated[list[UploadFile] | None, File()] = None,
) -> ExpenseResponse:
    # The payload is validated by the same schema the API documents, so an
    # amount of "NaN" or "Infinity" is a 422 instead of a 500 and an
    # over-long description cannot reach the database.
    try:
        payload = ExpenseCreate.model_validate(
            {
                "project_id": project_id,
                "expense_type_id": expense_type_id,
                "amount": amount,
                "expense_date": expense_date,
                "description": description,
            }
        )
    except PydanticValidationError as exc:
        raise ValidationError("Invalid expense payload.", details=exc.errors()) from exc
    stored: list[tuple[str, str | None]] = []
    storage = get_object_storage()
    for upload in files or []:
        content = await upload.read()
        if len(content) > _MAX_FILE_BYTES:
            raise ValidationError(f"File {upload.filename} exceeds 5MB.")
        # The stored extension comes from the file's own bytes, never from
        # the client-supplied name or Content-Type header.
        verified = verify_upload(upload.filename, content)
        key = f"receipts/{user.organization_id}/{uuid.uuid4().hex}{verified.extension}"
        url = await storage.upload(
            key=key,
            data=io.BytesIO(content),
            content_type=verified.content_type,
        )
        stored.append((url, upload.filename))
    created_notifications: list[NotificationResponse] = []
    try:
        response = await expense_service.submit(
            conn,
            employee_id=user.employee_id,
            organization_id=user.organization_id,
            project_id=payload.project_id,
            expense_type_id=payload.expense_type_id,
            amount=payload.amount,
            expense_date=payload.expense_date,
            description=payload.description,
            receipts=stored,
            created_notifications=created_notifications,
        )
    except Exception:
        # The expense row was never written, so the files that were already
        # uploaded would be orphans. Remove them instead of leaking them.
        for url, _ in stored:
            await storage.delete(key=url)
        raise
    # External delivery happens after the transaction has committed.
    for notification in created_notifications:
        enqueue_notification_dispatch(background, notification)
    return response


@router.get("", response_model=Page[ExpenseListItem])
async def list_expenses(
    user: Annotated[CurrentUser, Depends(require_membership)],
    conn: Annotated[Conn, Depends(get_connection)],
    status_filter: Annotated[ExpenseStatus | None, Query(alias="status")] = None,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ExpenseListItem]:
    items = await expense_service.list(
        conn,
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        status=status_filter,
        from_date=from_date,
        to_date=to_date,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    return _page(items)


@router.get("/{expense_id}", response_model=ExpenseResponse)
async def get_expense(
    expense_id: int,
    user: Annotated[CurrentUser, Depends(require_membership)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ExpenseResponse:
    return await expense_service.get(
        conn,
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        expense_id=expense_id,
    )


@approvals_router.get("/pending", response_model=Page[ExpenseListItem])
async def list_pending(
    user: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ExpenseListItem]:
    items = await expense_service.list_pending(
        conn,
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    return _page(items)


@router.post("/{expense_id}/approve", response_model=ExpenseResponse)
async def approve_expense(
    expense_id: int,
    payload: ApprovalActionRequest,
    user: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ExpenseResponse:
    return await expense_service.approve(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        expense_id=expense_id,
        payload=payload,
    )


@router.post("/{expense_id}/reject", response_model=ExpenseResponse)
async def reject_expense(
    expense_id: int,
    payload: ApprovalActionRequest,
    user: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ExpenseResponse:
    return await expense_service.reject(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        expense_id=expense_id,
        payload=payload,
    )


@router.post("/{expense_id}/request-info", response_model=ExpenseResponse)
async def request_expense_info(
    expense_id: int,
    payload: ApprovalActionRequest,
    user: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ExpenseResponse:
    """Admin asks the employee for details — status becomes info_requested."""
    return await expense_service.request_info(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        expense_id=expense_id,
        payload=payload,
    )


@router.post("/{expense_id}/resubmit", response_model=ExpenseResponse)
async def resubmit_expense(
    expense_id: int,
    user: Annotated[CurrentUser, Depends(require_membership)],
    conn: Annotated[Conn, Depends(get_connection)],
    payload: ExpenseResubmit | None = None,
) -> ExpenseResponse:
    """The submitting employee returns an info_requested expense to pending.

    The optional body carries the answer to the manager's question.
    """
    return await expense_service.resubmit(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        expense_id=expense_id,
        response=payload.response if payload is not None else None,
    )
