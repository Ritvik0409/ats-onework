"""Reusable authorization dependency factory (arch. doc §10).

Usage::

    @router.post("")
    async def create_thing(
        user: CurrentUser = Depends(RequirePermission("expenses.create")),
    ): ...

Full role/permission evaluation (``roles``/``permissions`` tables) lands with
the organizations module's AuthorizationService (§35); until then an active
admin membership grants all permissions — checked against the DB-backed auth
context. Never scatter ad-hoc permission checks across routers.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends

from app.api.v1.deps import CurrentUser, require_membership
from app.core.exceptions import AuthorizationError


class RequirePermission:
    def __init__(self, api_name: str) -> None:
        self.api_name = api_name

    async def __call__(
        self,
        user: Annotated[CurrentUser, Depends(require_membership)],
    ) -> CurrentUser:
        # TODO(Phase 4.3): evaluate via AuthorizationService — membership roles
        # and role/user permissions; admins bypass.
        if not user.is_admin:
            raise AuthorizationError(f"Missing permission: {self.api_name}")
        return user
