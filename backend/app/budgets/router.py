"""Budget endpoints — HTTP only (§49 #21). Nested under organizations."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.api.v1.deps import CurrentUser
from app.budgets.schemas import BudgetCreate, BudgetResponse, BudgetUpdate
from app.budgets.service import service as budget_service
from app.common.pagination import Page
from app.common.permissions import RequirePathPermission
from app.db.connection import get_connection
from app.db.types import Conn

router = APIRouter(prefix="/organizations", tags=["budgets"])


def _parse_cursor(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    try:
        value = int(cursor)
    except (TypeError, ValueError) as exc:
        from app.core.exceptions import ValidationError

        raise ValidationError("Invalid pagination cursor.") from exc
    return value if value > 0 else None


@router.get("/{organization_id}/budgets", response_model=Page[BudgetResponse])
async def list_budgets(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(RequirePathPermission("budget.read"))],
    conn: Annotated[Conn, Depends(get_connection)],
    month: Annotated[str | None, Query(description="Optional YYYY-MM overlap filter")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[BudgetResponse]:
    items = await budget_service.list_budgets(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        month=month,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].budget_id) if items else None
    return Page[BudgetResponse](items=items, next_cursor=next_cursor)


@router.post(
    "/{organization_id}/budgets", response_model=BudgetResponse, status_code=status.HTTP_201_CREATED
)
async def create_budget(
    organization_id: int,
    payload: BudgetCreate,
    user: Annotated[CurrentUser, Depends(RequirePathPermission("budget.manage"))],
    conn: Annotated[Conn, Depends(get_connection)],
) -> BudgetResponse:
    return await budget_service.create_budget(
        conn, actor_id=user.employee_id, organization_id=organization_id, payload=payload
    )


@router.patch("/{organization_id}/budgets/{budget_id}", response_model=BudgetResponse)
async def update_budget(
    organization_id: int,
    budget_id: int,
    payload: BudgetUpdate,
    user: Annotated[CurrentUser, Depends(RequirePathPermission("budget.manage"))],
    conn: Annotated[Conn, Depends(get_connection)],
) -> BudgetResponse:
    return await budget_service.update_budget(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        budget_id=budget_id,
        payload=payload,
    )
