"""User endpoints — HTTP concerns only (§49 #8-12).

Auth levels: ``/me`` needs any authenticated user; every other route needs
an admin membership (``require_admin`` → 403 for members, 401 without a
token via ``get_current_user``).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.api.v1.deps import CurrentUser, get_current_user, require_admin
from app.common.pagination import Page
from app.core.constants import AccountStatus
from app.db.connection import get_connection
from app.db.types import Conn
from app.users.schemas import (
    EmployeeStatusCreate,
    EmployeeStatusResponse,
    UserListItem,
    UserResponse,
    UserUpdate,
)
from app.users.service import service as user_service

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserResponse)
async def get_me(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> UserResponse:
    return await user_service.get_me(conn, user.employee_id)


@router.get("", response_model=Page[UserListItem])
async def list_users(
    _admin: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
    search: Annotated[str | None, Query(max_length=100)] = None,
    account_status: Annotated[AccountStatus | None, Query()] = None,
) -> Page[UserListItem]:
    return await user_service.list_users(
        conn, limit=limit, cursor=cursor, search=search, account_status=account_status
    )


@router.patch("/{employee_id}", response_model=UserResponse)
async def update_user(
    employee_id: int,
    payload: UserUpdate,
    admin: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> UserResponse:
    return await user_service.update_user(
        conn, actor_id=admin.employee_id, employee_id=employee_id, payload=payload
    )


@router.get("/{employee_id}/statuses", response_model=list[EmployeeStatusResponse])
async def list_statuses(
    employee_id: int,
    _admin: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[EmployeeStatusResponse]:
    return await user_service.list_statuses(conn, employee_id)


@router.post(
    "/{employee_id}/statuses",
    response_model=EmployeeStatusResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_status(
    employee_id: int,
    payload: EmployeeStatusCreate,
    admin: Annotated[CurrentUser, Depends(require_admin)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> EmployeeStatusResponse:
    return await user_service.create_status(
        conn, actor_id=admin.employee_id, employee_id=employee_id, payload=payload
    )
