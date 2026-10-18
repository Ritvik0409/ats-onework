"""Expense-type endpoints — HTTP only (§49 #25-26). Nested under organizations."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.db.connection import get_connection
from app.db.types import Conn
from app.expense_types.schemas import ExpenseTypeCreate, ExpenseTypeResponse
from app.expense_types.service import service as expense_type_service

router = APIRouter(prefix="/organizations", tags=["expense-types"])


@router.post(
    "/{organization_id}/expense-types",
    response_model=ExpenseTypeResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_expense_type(
    organization_id: int,
    payload: ExpenseTypeCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ExpenseTypeResponse:
    return await expense_type_service.create_type(
        conn, actor_id=user.employee_id, organization_id=organization_id, payload=payload
    )


@router.get("/{organization_id}/expense-types", response_model=list[ExpenseTypeResponse])
async def list_expense_types(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[ExpenseTypeResponse]:
    return await expense_type_service.list_types(
        conn, employee_id=user.employee_id, organization_id=organization_id
    )
