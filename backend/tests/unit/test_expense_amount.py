"""Expense payload validation — no database required.

The submit endpoint used to parse the amount by hand, which turned
``amount=NaN`` into an unhandled error (HTTP 500) and let
``amount=Infinity`` through to the database. It now goes through the
schema the API documents.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError as PydanticValidationError

from app.expenses.schemas import ExpenseCreate, ExpenseResubmit


def _payload(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "project_id": 1,
        "expense_type_id": 2,
        "amount": "250.00",
        "expense_date": "2026-10-20",
    }
    base.update(overrides)
    return base


@pytest.mark.parametrize("amount", ["NaN", "Infinity", "-Infinity", "inf", "-inf"])
def test_non_finite_amounts_are_rejected(amount: str) -> None:
    with pytest.raises(PydanticValidationError):
        ExpenseCreate.model_validate(_payload(amount=amount))


@pytest.mark.parametrize("amount", ["0", "-5", "-0.01"])
def test_non_positive_amounts_are_rejected(amount: str) -> None:
    with pytest.raises(PydanticValidationError):
        ExpenseCreate.model_validate(_payload(amount=amount))


def test_amount_with_too_many_decimal_places_is_rejected() -> None:
    with pytest.raises(PydanticValidationError):
        ExpenseCreate.model_validate(_payload(amount="12.345"))


def test_amount_beyond_the_column_precision_is_rejected() -> None:
    with pytest.raises(PydanticValidationError):
        ExpenseCreate.model_validate(_payload(amount="12345678901234567890.12"))


def test_valid_amount_is_accepted() -> None:
    expense = ExpenseCreate.model_validate(_payload(amount="250.50"))
    assert str(expense.amount) == "250.50"


def test_description_is_optional_but_bounded() -> None:
    assert ExpenseCreate.model_validate(_payload()).description is None
    assert (
        ExpenseCreate.model_validate(_payload(description="Taxi to client")).description
        == "Taxi to client"
    )
    with pytest.raises(PydanticValidationError):
        ExpenseCreate.model_validate(_payload(description="x" * 1001))


def test_resubmit_answer_is_bounded() -> None:
    assert ExpenseResubmit().response is None
    assert ExpenseResubmit(response="Here it is").response == "Here it is"
    with pytest.raises(PydanticValidationError):
        ExpenseResubmit(response="x" * 2001)
