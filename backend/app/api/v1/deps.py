"""Shared API dependencies (arch. doc §10, §25, ADR-001 §51).

``get_current_user`` decodes the bearer JWT into the tenant-aware auth context.
Token claims are never trusted beyond validation — membership-based checks
(`require_membership`, permission wiring) are added in Phase 3/4 alongside
the organizations module.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.exceptions import AuthenticationError, AuthorizationError
from app.core.security.jwt import decode_access_token

_bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True, slots=True)
class CurrentUser:
    """Tenant-aware auth context carried through the request (§8)."""

    employee_id: int
    organization_id: int
    is_admin: bool


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
) -> CurrentUser:
    if credentials is None:
        raise AuthenticationError("Missing bearer token.")
    payload = decode_access_token(credentials.credentials)
    return CurrentUser(
        employee_id=payload["sub"],
        organization_id=payload["org"],
        is_admin=bool(payload.get("admin", False)),
    )


async def require_admin(
    user: Annotated[CurrentUser, Depends(get_current_user)],
) -> CurrentUser:
    if not user.is_admin:
        raise AuthorizationError("Administrator privileges required.")
    return user
