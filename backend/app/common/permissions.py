"""Reusable authorization dependencies — role and capability checks
(arch. doc §10, §35).

The API authorizes on two independent things:

* **membership** — "is this person in this organization, and is the
  account active". That is the ``require_membership`` dependency and
  the ``is_admin`` flag on the membership row.
* **capability** — "may this person do this thing here". A capability
  comes from the roles a membership holds, plus any capability granted
  to the person directly.

Both are stored in the database (``roles``, ``membership_roles``,
``role_permissions``, ``permissions``, ``user_permissions``) and are
read fresh on every request, so a grant that is withdrawn takes effect
immediately rather than when a token expires.

The organization owns a copy of every capability, so a grant can only
ever point at a capability of the same organization — enforced by
composite foreign keys in the schema.

Usage::

    @router.get("")
    async def list_things(
        user: CurrentUser = Depends(RequirePermission("thing.read")),
    ): ...

    # any one of several capabilities is enough
    user: CurrentUser = Depends(RequireAnyPermission("thing.read_own", "thing.read_all")),

Never scatter ad-hoc permission checks across routers.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Path

from app.api.v1.deps import CurrentUser, get_current_user, require_membership
from app.core.exceptions import AuthorizationError
from app.db.connection import get_connection
from app.db.types import Conn

# Every capability the caller holds in the organization, whether it comes
# from a role they hold or from a grant made to them directly.
#
# The two halves are unioned: a role grant walks
# membership -> membership_roles -> role_permissions -> permissions, and a
# direct grant walks user_permissions -> permissions.
_GRANTED_SQL = """
SELECT DISTINCT p.api_name
  FROM permissions p
 WHERE p.organization_id = %s
   AND (
        p.permission_id IN (
            SELECT rp.permission_id
              FROM memberships m
              JOIN membership_roles mr ON mr.membership_id = m.membership_id
              JOIN role_permissions rp ON rp.role_id = mr.role_id
             WHERE m.employee_id = %s AND m.organization_id = %s
        )
        OR p.permission_id IN (
            SELECT up.permission_id
              FROM user_permissions up
             WHERE up.employee_id = %s AND up.organization_id = %s
        )
   )
"""


async def granted_permissions(conn: Conn, *, employee_id: int, organization_id: int) -> set[str]:
    """The names of every capability the caller holds in the organization."""
    async with conn.cursor() as cur:
        await cur.execute(
            _GRANTED_SQL,
            (organization_id, employee_id, organization_id, employee_id, organization_id),
        )
        rows = await cur.fetchall()
    return {row["api_name"] for row in rows}


async def has_permission(
    conn: Conn,
    *,
    employee_id: int,
    organization_id: int,
    api_name: str,
) -> bool:
    """Whether the caller holds one named capability."""
    granted = await granted_permissions(
        conn, employee_id=employee_id, organization_id=organization_id
    )
    return api_name in granted


async def require_capability(
    conn: Conn,
    *,
    employee_id: int,
    organization_id: int,
    api_name: str,
) -> None:
    """Raise unless the caller holds a named capability.

    Used by the services whose organization is only known once the
    resource has been resolved — a project, for instance — so the check
    runs against the organization the operation actually acts on.
    """
    if not await has_permission(
        conn,
        employee_id=employee_id,
        organization_id=organization_id,
        api_name=api_name,
    ):
        raise AuthorizationError(f"Missing permission: {api_name}")


class RequirePermission:
    """Route dependency: the caller must hold this capability.

    The capability is evaluated in the caller's **active** organization
    — the one their token names. Use :class:`RequirePathPermission`
    where the route names the organization in its path.

    The check is against the database, so a grant that is withdrawn takes
    effect on the caller's next request.
    """

    def __init__(self, api_name: str) -> None:
        self.api_name = api_name

    async def __call__(
        self,
        user: Annotated[CurrentUser, Depends(require_membership)],
        conn: Annotated[Conn, Depends(get_connection)],
    ) -> CurrentUser:
        granted = await granted_permissions(
            conn,
            employee_id=user.employee_id,
            organization_id=user.organization_id,
        )
        if self.api_name not in granted:
            raise AuthorizationError(f"Missing permission: {self.api_name}")
        return user


class RequireAnyPermission:
    """Route dependency: the caller must hold at least one of these.

    Used where several capabilities each open the same door — reading
    your own expenses versus reading the whole organization's.
    """

    def __init__(self, *api_names: str) -> None:
        self.api_names = api_names

    async def __call__(
        self,
        user: Annotated[CurrentUser, Depends(require_membership)],
        conn: Annotated[Conn, Depends(get_connection)],
    ) -> CurrentUser:
        granted = await granted_permissions(
            conn,
            employee_id=user.employee_id,
            organization_id=user.organization_id,
        )
        if not any(name in granted for name in self.api_names):
            raise AuthorizationError("Missing permission: " + " or ".join(self.api_names))
        return user


class RequirePathPermission:
    """Route dependency for routes that name the organization in the path.

    The capability is evaluated in the **path** organization, not the
    caller's active one, so a caller cannot spend a capability they hold
    in one organization on another organization's resource.
    """

    def __init__(self, api_name: str) -> None:
        self.api_name = api_name

    async def __call__(
        self,
        organization_id: Annotated[int, Path()],
        user: Annotated[CurrentUser, Depends(get_current_user)],
        conn: Annotated[Conn, Depends(get_connection)],
    ) -> CurrentUser:
        granted = await granted_permissions(
            conn, employee_id=user.employee_id, organization_id=organization_id
        )
        if self.api_name not in granted:
            raise AuthorizationError(f"Missing permission: {self.api_name}")
        return user


class RequireAnyPathPermission:
    """Route dependency: the caller must hold one of these, in the path's
    organization."""

    def __init__(self, *api_names: str) -> None:
        self.api_names = api_names

    async def __call__(
        self,
        organization_id: Annotated[int, Path()],
        user: Annotated[CurrentUser, Depends(get_current_user)],
        conn: Annotated[Conn, Depends(get_connection)],
    ) -> CurrentUser:
        granted = await granted_permissions(
            conn, employee_id=user.employee_id, organization_id=organization_id
        )
        if not any(name in granted for name in self.api_names):
            raise AuthorizationError("Missing permission: " + " or ".join(self.api_names))
        return user
