"""Shared API dependencies (arch. doc §10, §25, ADR-001 §51).

``get_current_user`` decodes the bearer JWT into the tenant-aware auth
context and re-reads the account's state, so suspending or locking an
account takes effect immediately instead of when the access token
happens to expire. Token ``org``/``admin`` claims are never trusted
beyond validation — ``require_membership`` re-reads the membership row
and rebuilds the auth context from the database.

Authorization is membership-based: an active admin membership grants all
permissions in the organization. The role/permission tables exist in the
schema but no endpoint grants capabilities from them yet, so the API
does not pretend to enforce them.

Scope note (§8, §49): these dependencies validate the **token's** org —
correct for collection routes, but resource routes (``/expenses/{id}``,
``/organizations/{id}``, …) must 404 cross-tenant probes instead of 403.
Services behind such paths enforce the **path** org via
``app.common.tenant.require_path_member`` / ``require_path_admin``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.constants import AccountStatus
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
    conn: Annotated[Conn, Depends(get_connection)],
) -> CurrentUser:
    """Decode the bearer token into the tenant-aware auth context.

    The account's state is re-read on every request so that suspending or
    locking an account takes effect immediately rather than when the
    access token happens to expire (§9).
    """
    if credentials is None:
        raise AuthenticationError("Missing bearer token.")
    payload = decode_access_token(credentials.credentials)
    async with conn.cursor() as cur:
        await cur.execute(
            "SELECT account_status FROM users WHERE employee_id = %s",
            (payload["sub"],),
        )
        row = await cur.fetchone()
    if row is None:
        raise AuthenticationError("Unknown account.")
    if row["account_status"] != AccountStatus.ACTIVE.value:
        raise AuthorizationError("This account is not active. Contact your administrator.")
    return CurrentUser(
        employee_id=payload["sub"],
        organization_id=payload["org"],
        is_admin=bool(payload.get("admin", False)),
    )


async def require_membership(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> CurrentUser:
    """Rebuild the auth context from the database — the DB is the source
    of truth for ``organization_id``/``is_admin``/``account_status``, not
    the token (§9).

    The account status is re-read on every request, so suspending or
    locking an account takes effect immediately instead of waiting for
    the access token to expire.
    """
    async with conn.cursor() as cur:
        await cur.execute(
            """
            SELECT m.is_admin, u.account_status
            FROM memberships m
            JOIN users u ON u.employee_id = m.employee_id
            WHERE m.employee_id = %s AND m.organization_id = %s
            """,
            (user.employee_id, user.organization_id),
        )
        row = await cur.fetchone()
    if row is None:
        raise AuthorizationError("No active membership in this organization.")
    if row["account_status"] != AccountStatus.ACTIVE.value:
        raise AuthorizationError("This account is not active. Contact your administrator.")
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
