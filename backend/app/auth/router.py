"""Auth endpoints — HTTP concerns only (arch. doc §3, §49 #3-7).

Every handler parses its request model, calls ``AuthService``, and returns
the response model with the contract status code. No business logic, no SQL.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.auth.schemas import (
    LoginRequest,
    OrganizationSwitchRequest,
    RefreshRequest,
    TokenPair,
    UserCreate,
    UserResponse,
)
from app.auth.service import service as auth_service
from app.db.connection import get_connection
from app.db.types import Conn

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    payload: UserCreate, conn: Annotated[Conn, Depends(get_connection)]
) -> UserResponse:
    return await auth_service.register(conn, payload)


@router.post("/login", response_model=TokenPair)
async def login(payload: LoginRequest, conn: Annotated[Conn, Depends(get_connection)]) -> TokenPair:
    return await auth_service.login(conn, payload)


@router.post("/refresh", response_model=TokenPair)
async def refresh(
    payload: RefreshRequest, conn: Annotated[Conn, Depends(get_connection)]
) -> TokenPair:
    return await auth_service.refresh(conn, payload)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    payload: RefreshRequest,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> Response:
    await auth_service.logout(conn, employee_id=user.employee_id, payload=payload)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/switch-organization", response_model=TokenPair)
async def switch_organization(
    payload: OrganizationSwitchRequest,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> TokenPair:
    return await auth_service.switch_organization(
        conn, employee_id=user.employee_id, payload=payload
    )
