"""Reimbursement DTOs (§49 #33-35)."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from app.core.constants import ReimbursementStatus


class ReimbursementCreate(BaseModel):
    """Body for ``POST /expenses/{id}/reimbursement`` — amount derives from the expense."""

    model_config = ConfigDict(str_strip_whitespace=True)

    payment_reference: str | None = Field(default=None, max_length=100)


class ReimbursementTransitionRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    target_status: ReimbursementStatus
    payment_reference: str | None = Field(default=None, max_length=100)


class ReimbursementResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    reimbursement_id: int
    expense_id: int
    employee_id: int
    organization_id: int
    total_amount: Decimal
    payment_reference: str | None = None
    status: ReimbursementStatus
    paid_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class ReimbursementListItem(ReimbursementResponse):
    """Cursor-list row — same shape, distinct name per §11."""
