"""Expense DTOs — explicit request/response models (arch. doc §11, §49 #27-32).

No internal fields leak: ``password_hash``/``token_hash`` never appear here.
DB rows (``dict_row``) are mapped via ``model_validate`` — never returned raw.
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from app.core.constants import ApprovalAction, ExpenseStatus


class ExpenseCreate(BaseModel):
    """Body for ``POST /expenses`` (multipart form fields, §49 #27)."""

    model_config = ConfigDict(str_strip_whitespace=True)

    project_id: int = Field(gt=0)
    expense_type_id: int = Field(gt=0)
    amount: Decimal = Field(gt=0, max_digits=15, decimal_places=2)
    expense_date: date


class ApprovalActionRequest(BaseModel):
    """Body for approve/reject/request-info (§49 #31-33). Required on reject and request-info."""

    model_config = ConfigDict(str_strip_whitespace=True)

    comments: str | None = Field(default=None, max_length=2000)


class MediaResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    media_id: int
    expense_id: int
    receipt_url: str
    description: str | None = None
    uploaded_at: datetime


class ExpenseResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    expense_id: int
    employee_id: int
    project_id: int
    organization_id: int
    expense_type_id: int
    amount: Decimal
    status: ExpenseStatus
    rejection_reason: str | None = None
    expense_date: date
    submission_date: datetime
    updated_at: datetime
    info_message: str | None = None
    info_requested_at: datetime | None = None
    receipts: list[MediaResponse] = Field(default_factory=list)


class ExpenseListItem(BaseModel):
    """Cursor-list row — same scalar shape as response minus receipts (§11)."""

    model_config = ConfigDict(from_attributes=True)

    expense_id: int
    project_id: int
    expense_type_id: int
    amount: Decimal
    status: ExpenseStatus
    expense_date: date
    submission_date: datetime
    info_message: str | None = None


class ExpenseApprovalResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    approval_id: int
    expense_id: int
    actioned_by: int
    action: ApprovalAction
    comments: str | None = None
    actioned_at: datetime
