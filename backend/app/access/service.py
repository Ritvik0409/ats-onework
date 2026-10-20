"""Access business rules — capabilities, roles and grants (§10, §35).

The access model has three layers, and this module is where they are
put together:

* a **capability** belongs to an organization (``permissions``);
* a **role** belongs to an organization and grants capabilities
  (``roles`` + ``role_permissions``);
* a **membership** holds roles (``membership_roles``) and may hold
  extra capabilities of its own (``user_permissions``).

The platform's standard capabilities and roles live in
``access_catalog`` and are installed into an organization when it is
created. After that the organization configures its own access, which
is what these endpoints are for.

Every operation is scoped to one organization. A caller who is not a
member of the organization is reported as *not found* rather than
*forbidden*, so these endpoints cannot be used to probe another
tenant's roster (arch. doc §8, §49). A platform super administrator
may manage any organization's access, which is the one exception —
they are not a member of the organization they administer.
"""

from __future__ import annotations

from app.access.repository import AccessRepository
from app.access.schemas import (
    CatalogEntryCreate,
    CatalogEntryResponse,
    CatalogEntryUpdate,
    InstallResult,
    MemberAccessResponse,
    MemberPermissionsUpdate,
    MemberRolesUpdate,
    PermissionCreate,
    PermissionResponse,
    RoleCreate,
    RolePermissionsUpdate,
    RoleResponse,
)
from app.common.audit import service as audit_service
from app.common.permissions import granted_permissions
from app.common.tenant import require_path_admin, require_path_member
from app.core.exceptions import ConflictError, NotFoundError
from app.db.types import Conn, Row

_repository = AccessRepository()


class AccessService:
    def __init__(self, repository: AccessRepository | None = None) -> None:
        self._repository = repository or _repository

    # -- capabilities -------------------------------------------------------

    async def list_permissions(
        self, conn: Conn, *, employee_id: int, organization_id: int
    ) -> list[PermissionResponse]:
        await self._require_member(conn, employee_id, organization_id)
        rows = await self._repository.list_permissions(conn, organization_id)
        return [PermissionResponse.model_validate(row) for row in rows]

    async def create_permission(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        payload: PermissionCreate,
        is_superuser: bool = False,
    ) -> PermissionResponse:
        await self._require_admin(conn, actor_id, organization_id, is_superuser)
        existing = await self._repository.get_permission(conn, organization_id, payload.api_name)
        if existing is not None:
            raise ConflictError("This organization already has that capability.")
        row = await self._repository.create_permission(
            conn,
            organization_id=organization_id,
            api_name=payload.api_name,
            description=payload.description,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="access.permission.create",
            table_name="permissions",
            record_id=str(row["permission_id"]),
            new_values={
                "api_name": payload.api_name,
                "organization_id": organization_id,
            },
        )
        return PermissionResponse.model_validate(row)

    # -- roles --------------------------------------------------------------

    async def list_roles(
        self, conn: Conn, *, employee_id: int, organization_id: int
    ) -> list[RoleResponse]:
        await self._require_member(conn, employee_id, organization_id)
        rows = await self._repository.list_roles(conn, organization_id)
        return [
            RoleResponse(
                **RoleResponse.model_validate(row).model_dump(),
                permissions=await self._repository.list_role_grants(
                    conn, organization_id, row["role_id"]
                ),
            )
            for row in rows
        ]

    async def create_role(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        payload: RoleCreate,
        is_superuser: bool = False,
    ) -> RoleResponse:
        await self._require_admin(conn, actor_id, organization_id, is_superuser)
        existing = await self._repository.get_role_by_name(conn, organization_id, payload.name)
        if existing is not None:
            raise ConflictError("This organization already has a role with that name.")
        row = await self._repository.create_role(
            conn,
            organization_id=organization_id,
            name=payload.name,
            description=payload.description,
        )
        await self._repository.replace_role_grants(
            conn, organization_id, row["role_id"], payload.permissions
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="access.role.create",
            table_name="roles",
            record_id=str(row["role_id"]),
            new_values={
                "name": payload.name,
                "organization_id": organization_id,
                "permissions": payload.permissions,
            },
        )
        return RoleResponse(
            **RoleResponse.model_validate(row).model_dump(),
            permissions=await self._repository.list_role_grants(
                conn, organization_id, row["role_id"]
            ),
        )

    async def get_role_grants(
        self, conn: Conn, *, employee_id: int, organization_id: int, role_id: int
    ) -> list[str]:
        await self._require_member(conn, employee_id, organization_id)
        role = await self._repository.get_role(conn, organization_id, role_id)
        if role is None:
            raise NotFoundError("Role not found.")
        return await self._repository.list_role_grants(conn, organization_id, role_id)

    async def set_role_grants(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        role_id: int,
        payload: RolePermissionsUpdate,
        is_superuser: bool = False,
    ) -> list[str]:
        await self._require_admin(conn, actor_id, organization_id, is_superuser)
        role = await self._repository.get_role(conn, organization_id, role_id)
        if role is None:
            raise NotFoundError("Role not found.")
        before = await self._repository.list_role_grants(conn, organization_id, role_id)
        await self._repository.replace_role_grants(
            conn, organization_id, role_id, payload.permissions
        )
        after = await self._repository.list_role_grants(conn, organization_id, role_id)
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="access.role.grants.update",
            table_name="roles",
            record_id=str(role_id),
            old_values={"permissions": before},
            new_values={"permissions": after},
        )
        return after

    # -- member access ------------------------------------------------------

    async def get_member_access(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        target_id: int,
        is_superuser: bool = False,
    ) -> MemberAccessResponse:
        await self._require_admin(conn, actor_id, organization_id, is_superuser)
        membership = await self._membership(conn, target_id, organization_id)
        role_rows = await self._repository.list_member_roles(conn, organization_id, target_id)
        direct = await self._repository.list_user_grants(conn, organization_id, target_id)
        effective = await granted_permissions(
            conn, employee_id=target_id, organization_id=organization_id
        )
        return MemberAccessResponse(
            employee_id=target_id,
            organization_id=organization_id,
            is_admin=bool(membership["is_admin"]),
            roles=[row["name"] for row in role_rows],
            direct_permissions=direct,
            effective_permissions=sorted(effective),
        )

    async def set_member_roles(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        target_id: int,
        payload: MemberRolesUpdate,
        is_superuser: bool = False,
    ) -> MemberAccessResponse:
        await self._require_admin(conn, actor_id, organization_id, is_superuser)
        await self._membership(conn, target_id, organization_id)
        before = [
            row["name"]
            for row in await self._repository.list_member_roles(conn, organization_id, target_id)
        ]
        await self._repository.replace_member_roles(
            conn, organization_id, target_id, payload.role_ids
        )
        after = [
            row["name"]
            for row in await self._repository.list_member_roles(conn, organization_id, target_id)
        ]
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="access.member.roles.update",
            table_name="membership_roles",
            record_id=str(target_id),
            old_values={"roles": before},
            new_values={"roles": after},
        )
        return await self.get_member_access(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            target_id=target_id,
            is_superuser=is_superuser,
        )

    async def set_member_permissions(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        target_id: int,
        payload: MemberPermissionsUpdate,
        is_superuser: bool = False,
    ) -> MemberAccessResponse:
        await self._require_admin(conn, actor_id, organization_id, is_superuser)
        await self._membership(conn, target_id, organization_id)
        before = await self._repository.list_user_grants(conn, organization_id, target_id)
        await self._repository.replace_user_grants(
            conn, organization_id, target_id, payload.permissions
        )
        after = await self._repository.list_user_grants(conn, organization_id, target_id)
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="access.member.permissions.update",
            table_name="user_permissions",
            record_id=str(target_id),
            old_values={"permissions": before},
            new_values={"permissions": after},
        )
        return await self.get_member_access(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            target_id=target_id,
            is_superuser=is_superuser,
        )

    # -- the platform catalogue --------------------------------------------

    async def list_catalog(self, conn: Conn) -> list[CatalogEntryResponse]:
        rows = await self._repository.list_catalog(conn)
        return [CatalogEntryResponse.model_validate(row) for row in rows]

    async def create_catalog_entry(
        self, conn: Conn, *, actor_id: int, payload: CatalogEntryCreate
    ) -> CatalogEntryResponse:
        existing = await self._repository.get_catalog_entry(conn, payload.kind, payload.name)
        if existing is not None:
            raise ConflictError("The catalogue already has an entry with that name.")
        row = await self._repository.create_catalog_entry(
            conn,
            kind=payload.kind,
            name=payload.name,
            description=payload.description,
            grants=payload.grants,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=None,
            action="access.catalog.create",
            table_name="access_catalog",
            record_id=str(row["catalog_id"]),
            new_values={
                "kind": payload.kind,
                "name": payload.name,
                "grants": payload.grants,
            },
        )
        return CatalogEntryResponse.model_validate(row)

    async def update_catalog_entry(
        self,
        conn: Conn,
        *,
        actor_id: int,
        kind: str,
        name: str,
        payload: CatalogEntryUpdate,
    ) -> CatalogEntryResponse:
        row = await self._repository.update_catalog_entry(
            conn,
            kind=kind,
            name=name,
            description=payload.description,
            grants=payload.grants,
        )
        if row is None:
            raise NotFoundError("Catalogue entry not found.")
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=None,
            action="access.catalog.update",
            table_name="access_catalog",
            record_id=str(row["catalog_id"]),
            new_values={"kind": kind, "name": name, "grants": payload.grants},
        )
        return CatalogEntryResponse.model_validate(row)

    async def delete_catalog_entry(
        self, conn: Conn, *, actor_id: int, kind: str, name: str
    ) -> None:
        deleted = await self._repository.delete_catalog_entry(conn, kind, name)
        if deleted == 0:
            raise NotFoundError("Catalogue entry not found.")
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=None,
            action="access.catalog.delete",
            table_name="access_catalog",
            record_id=name,
            old_values={"kind": kind, "name": name},
        )

    async def install_catalog(
        self, conn: Conn, *, actor_id: int, organization_id: int
    ) -> InstallResult:
        """Install the current catalogue into an organization."""
        permissions, roles = await self._repository.install_catalog_for_org(conn, organization_id)
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="access.catalog.install",
            table_name="organizations",
            record_id=str(organization_id),
            new_values={
                "permissions_installed": permissions,
                "roles_installed": roles,
            },
        )
        return InstallResult(permissions_installed=permissions, roles_installed=roles)

    # -- helpers -------------------------------------------------------------

    async def _membership(self, conn: Conn, employee_id: int, organization_id: int) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, organization_id),
            )
            row = await cur.fetchone()
        if row is None:
            raise NotFoundError("Member not found.")
        return row

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_member(await self._membership(conn, employee_id, org_id))

    async def _require_admin(
        self, conn: Conn, employee_id: int, org_id: int, is_superuser: bool = False
    ) -> Row | None:
        """An organization's administrator, or a platform super administrator.

        A super administrator is not a member of the organization they
        administer, so their membership is not required.
        """
        if is_superuser:
            return None
        return require_path_admin(await self._membership(conn, employee_id, org_id))


service = AccessService()
