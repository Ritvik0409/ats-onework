"""Budget DTOs (§49 #21)."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class BudgetCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    amount: Decimal = Field(gt=0, max_digits=15, decimal_places=2)
    start_date: date
    end_date: date


class BudgetResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    budget_id: int
    amount: Decimal
    employee_id: int
    organization_id: int
    start_date: date
    end_date: date
    created_at: datetime
    updated_at: datetime
