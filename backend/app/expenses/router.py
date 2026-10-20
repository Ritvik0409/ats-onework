"""Expense endpoints — HTTP concerns only (§49 #27-32).

``POST /expenses`` accepts multipart form fields + receipt files (§15);
files go through the ``ObjectStorage`` abstraction — only the URL lands
in ``expense_media.receipt_url``. Admin decisions live under
``POST /expenses/{id}/approve|reject``; the pending queue is
``GET /approvals/pending`` (separate prefix, same module).
"""

from __future__ import annotations

import mimetypes
import uuid
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, Query, UploadFile, status

from app.api.v1.deps import CurrentUser, require_admin, require_membership
from app.common.object_storage import get_object_storage
from app.common.pagination import Page
from app.core.constants import ExpenseStatus
from app.core.exceptions import ValidationError
from app.db.connection import get_connection
from app.db.types import Conn
from app.expenses.schemas import (
    ApprovalActionRequest,
    ExpenseListItem,
    ExpenseResponse,
)
from app.expenses.service import service as expense_service

router = APIRouter(prefix="/expenses", tags=["expenses"])
approvals_router = APIRouter(prefix="/approvals", tags=["approvals"])

_ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp", "application/pdf"}
_MAX_FILE_BYTES = 5 * 1024 * 1024


def _resolve_content_type(filename: str | None, declared: str | None) -> str:
    """Pick a validated MIME type for an uploaded receipt.

    Trusting the declared Content-Type alone breaks real clients: Flutter's
    ``MultipartFile.fromBytes`` sends generic ``application/octet-stream``
    even for a named ``receipt.jpg``. So when the declared type is missing
    or generic, fall back to the filename extension. Neither route to an
    allowed type → 422.
    """
    ctype = (declared or "").split(";")[0].strip().lower()
    if ctype in _ALLOWED_CONTENT_TYPES:
        return ctype
    guessed, _ = mimetypes.guess_type(filename or "")
    if guessed and guessed in _ALLOWED_CONTENT_TYPES:
        return guessed
    raise ValidationError(
        f"File {filename or 'receipt'} has an unsupported type. Accepted: jpeg, png, webp, pdf."
    )


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
    files: Annotated[list[UploadFile] | None, File()] = None,
) -> ExpenseResponse:
    try:
        decimal_amount = Decimal(amount)
    except InvalidOperation as exc:
        from app.core.exceptions import ValidationError

        raise ValidationError("Amount must be a valid decimal.") from exc
    if decimal_amount <= 0:
        from app.core.exceptions import ValidationError

        raise ValidationError("Amount must be greater than zero.")
    stored: list[tuple[str, str | None]] = []
    storage = get_object_storage()
    for upload in files or []:
        content = await upload.read()
        if len(content) > _MAX_FILE_BYTES:
            from app.core.exceptions import ValidationError

            raise ValidationError(f"File {upload.filename} exceeds 5MB.")
        resolved_type = _resolve_content_type(upload.filename, upload.content_type)
        key = f"receipts/{user.organization_id}/{uuid.uuid4().hex}-{upload.filename or 'receipt'}"
        import io

        url = await storage.upload(
            key=key,
            data=io.BytesIO(content),
            content_type=resolved_type,
        )
        stored.append((url, upload.filename))
    background.add_task(lambda: None)
    return await expense_service.submit(
        conn,
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        project_id=project_id,
        expense_type_id=expense_type_id,
        amount=decimal_amount,
        expense_date=expense_date,
        receipts=stored,
    )


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
) -> ExpenseResponse:
    """The submitting employee returns an info_requested expense to pending."""
    return await expense_service.resubmit(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        expense_id=expense_id,
    )
