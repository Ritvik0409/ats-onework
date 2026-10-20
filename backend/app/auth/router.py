"""Auth endpoints — HTTP concerns only (arch. doc §3, §49 #3-7).

Every handler parses its request model, calls ``AuthService``, and returns
the response model with the contract status code. No business logic, no SQL.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.auth.schemas import (
    ChangePasswordRequest,
    LoginRequest,
    OrganizationSwitchRequest,
    RefreshRequest,
    TokenPair,
    UserCreate,
    UserResponse,
)
from app.auth.service import service as auth_service
from app.core import rate_limit
from app.db.connection import get_connection
from app.db.types import Conn

router = APIRouter(prefix="/auth", tags=["auth"])


def _client_address(request: Request) -> str:
    """The caller's address, for the rate limiter.

    The direct peer is used rather than a forwarded header: a header
    the caller can choose would let them sidestep the limit by making
    one up. Behind a proxy the address is the proxy's, so the limit
    applies to the proxy -- which is the honest thing for it to do.
    """
    client = request.client
    return client.host if client else "unknown"


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    payload: UserCreate,
    request: Request,
    conn: Annotated[Conn, Depends(get_connection)],
) -> UserResponse:
    await rate_limit.hit(
        conn,
        key=f"register:addr:{_client_address(request)}",
        limit=rate_limit.REGISTER_PER_ADDRESS,
    )
    return await auth_service.register(conn, payload)


@router.post("/login", response_model=TokenPair)
async def login(
    payload: LoginRequest,
    request: Request,
    conn: Annotated[Conn, Depends(get_connection)],
) -> TokenPair:
    address = _client_address(request)
    # The address is limited first, then the account: the first bounds
    # the CPU an unauthenticated caller can spend, the second bounds
    # the guessing.
    await rate_limit.hit(conn, key=f"login:addr:{address}", limit=rate_limit.LOGIN_PER_ADDRESS)
    await rate_limit.hit(
        conn,
        key=f"login:addr-accounts:{address}",
        limit=rate_limit.LOGIN_PER_ADDRESS_ACCOUNTS,
    )
    identifier = payload.email.strip().lower()
    await rate_limit.hit(
        conn, key=f"login:account:{identifier}", limit=rate_limit.LOGIN_PER_ACCOUNT
    )
    try:
        pair = await auth_service.login(conn, payload)
    except Exception:
        # A failed attempt counts towards the limit — that is the point
        # of the limit.
        raise
    # A successful sign-in clears the account's counter, so a person
    # who fat-fingered their password a few times is not left
    # throttled.
    await rate_limit.clear(conn, key=f"login:account:{identifier}")
    return pair


@router.post("/refresh", response_model=TokenPair)
async def refresh(
    payload: RefreshRequest,
    request: Request,
    conn: Annotated[Conn, Depends(get_connection)],
) -> TokenPair:
    await rate_limit.hit(
        conn,
        key=f"refresh:addr:{_client_address(request)}",
        limit=rate_limit.REFRESH_PER_ADDRESS,
    )
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


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    payload: ChangePasswordRequest,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> Response:
    """Change the signed-in user's own password.

    Every other session of theirs ends, so a password change is a way
    to recover from a compromise.
    """
    await auth_service.change_password(conn, employee_id=user.employee_id, payload=payload)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
