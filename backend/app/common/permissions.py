"""Reusable authorization dependency factory (arch. doc §10).

Usage::

    @router.post("")
    async def create_thing(
        user: CurrentUser = Depends(RequirePermission("expenses.create")),
    ): ...

The evaluation is database-backed: a permission is granted when it is
attached to one of the caller's roles, or granted to the caller directly.
Permission rows are organization-scoped unless they are marked
``is_global``.

Admins bypass the check — an administrator membership is the
organization's top authority, and the seeded role catalog does not
duplicate it.

.. note::

   No route depends on this class yet: the API authorizes on membership
   (``require_membership`` / ``require_admin``) alone. It is the
   extension point for role-scoped authorization, and it is deliberately
   not wired into routes until the permission catalog is seeded, so that
   adding it cannot silently strip capabilities from existing users.

Never scatter ad-hoc permission checks across routers.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends

from app.api.v1.deps import CurrentUser, require_membership
from app.core.exceptions import AuthorizationError
from app.db.connection import get_connection
from app.db.types import Conn

# Granted through a role attached to the caller's membership.
_ROLE_GRANT_SQL = """
SELECT EXISTS (
    SELECT 1
    FROM memberships m
    JOIN membership_roles mr ON mr.membership_id = m.membership_id
    JOIN role_permissions rp ON rp.role_id = mr.role_id
    JOIN permissions p ON p.permission_id = rp.permission_id
    WHERE m.employee_id = %s
      AND m.organization_id = %s
      AND p.api_name = %s
)
"""

# Granted directly to the caller.
_DIRECT_GRANT_SQL = """
SELECT EXISTS (
    SELECT 1
    FROM user_permissions up
    JOIN permissions p ON p.permission_id = up.permission_id
    WHERE up.employee_id = %s
      AND p.api_name = %s
      AND (p.is_global OR p.organization_id = %s)
)
"""


async def has_permission(
    conn: Conn,
    *,
    employee_id: int,
    organization_id: int,
    api_name: str,
) -> bool:
    """Whether the caller holds ``api_name`` in the given organization."""
    async with conn.cursor() as cur:
        await cur.execute(
            _ROLE_GRANT_SQL,
            (employee_id, organization_id, api_name),
        )
        role_row = await cur.fetchone()
        await cur.execute(
            _DIRECT_GRANT_SQL,
            (employee_id, api_name, organization_id),
        )
        direct_row = await cur.fetchone()
    return bool(role_row["exists"]) or bool(direct_row["exists"])


class RequirePermission:
    """Route dependency that demands a named permission.

    Admins are always allowed; everyone else needs the permission to be
    present in the role catalog.
    """

    def __init__(self, api_name: str) -> None:
        self.api_name = api_name

    async def __call__(
        self,
        user: Annotated[CurrentUser, Depends(require_membership)],
        conn: Annotated[Conn, Depends(get_connection)],
    ) -> CurrentUser:
        if user.is_admin:
            return user
        granted = await has_permission(
            conn,
            employee_id=user.employee_id,
            organization_id=user.organization_id,
            api_name=self.api_name,
        )
        if not granted:
            raise AuthorizationError(f"Missing permission: {self.api_name}")
        return user
