"""Shared API dependencies (arch. doc §10, §25, ADR-001 §51).

``get_current_user`` decodes the bearer JWT into the tenant-aware auth context.
Token ``org``/``admin`` claims are never trusted beyond validation —
``require_membership`` re-reads the membership row and rebuilds the auth
context from the database. Full role/permission evaluation lands with the
organizations module's AuthorizationService (§35); until then an active admin
membership grants all permissions.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.exceptions import AuthenticationError, AuthorizationError
from app.core.security.jwt import decode_access_token
from app.db.connection import get_connection
from app.db.types import Conn

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


async def require_membership(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> CurrentUser:
    """Rebuild the auth context from the membership row — the DB is the source
    of truth for ``organization_id``/``is_admin``, not the token (§9)."""
    async with conn.cursor() as cur:
        await cur.execute(
            """
            SELECT is_admin
            FROM memberships
            WHERE employee_id = %s AND organization_id = %s
            """,
            (user.employee_id, user.organization_id),
        )
        row = await cur.fetchone()
    if row is None:
        raise AuthorizationError("No active membership in this organization.")
    return CurrentUser(
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        is_admin=bool(row["is_admin"]),
    )


async def require_admin(
    user: Annotated[CurrentUser, Depends(require_membership)],
) -> CurrentUser:
    if not user.is_admin:
        raise AuthorizationError("Administrator privileges required.")
    return user
