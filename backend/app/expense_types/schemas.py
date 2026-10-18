"""Expense-type DTOs (§49 #25-26)."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class ExpenseTypeCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=100)
    description: str | None = None
    requires_receipt: bool = False
    default_limit: Decimal | None = Field(default=None, gt=0, max_digits=15, decimal_places=2)


class ExpenseTypeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    expense_type_id: int
    name: str
    organization_id: int
    description: str | None = None
    is_active: bool
    requires_receipt: bool
    default_limit: Decimal | None = None
    created_at: datetime
    updated_at: datetime
