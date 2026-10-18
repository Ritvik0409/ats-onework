"""Budget endpoints — HTTP only (§49 #21). Nested under organizations."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.budgets.schemas import BudgetCreate, BudgetResponse
from app.budgets.service import service as budget_service
from app.db.connection import get_connection
from app.db.types import Conn

router = APIRouter(prefix="/organizations", tags=["budgets"])


@router.post(
    "/{organization_id}/budgets", response_model=BudgetResponse, status_code=status.HTTP_201_CREATED
)
async def create_budget(
    organization_id: int,
    payload: BudgetCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> BudgetResponse:
    return await budget_service.create_budget(
        conn, actor_id=user.employee_id, organization_id=organization_id, payload=payload
    )
