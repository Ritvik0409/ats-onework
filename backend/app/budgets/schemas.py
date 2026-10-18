"""Budget DTOs (§49 #21). ``spent`` is computed, never stored."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class BudgetCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    amount: Decimal = Field(gt=0, max_digits=15, decimal_places=2)
    start_date: date
    end_date: date


class BudgetUpdate(BaseModel):
    """PATCH /organizations/{org}/budgets/{id} — partial; validation runs
    against the merged (current + new) values in the service."""

    model_config = ConfigDict(str_strip_whitespace=True)

    amount: Decimal | None = Field(default=None, gt=0, max_digits=15, decimal_places=2)
    start_date: date | None = None
    end_date: date | None = None

    @model_validator(mode="after")
    def _amount_required_if_present(self) -> BudgetUpdate:
        if self.amount is not None and self.amount <= 0:
            raise ValueError("Amount must be greater than zero.")
        return self


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
    spent: Decimal = Decimal("0")


class BudgetListItem(BudgetResponse):
    """Cursor-list row — same shape, distinct name per §11."""
