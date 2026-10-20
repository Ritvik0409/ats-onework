"""Access endpoints — capabilities, roles and grants (§10, §35).

Two surfaces:

* ``/organizations/{organization_id}/access/...`` — an organization's
  own administrator configuring that organization's access.
* ``/system/...`` — the platform super administrator, who manages the
  capability catalogue and may configure any organization.

Both are HTTP concerns only; the rules live in the service.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.access.schemas import (
    CatalogEntryCreate,
    CatalogEntryResponse,
    CatalogEntryUpdate,
    InstallResult,
    MemberAccessResponse,
    MemberPermissionsUpdate,
    MemberRolesUpdate,
    OrganizationSummary,
    PermissionCreate,
    PermissionResponse,
    RoleCreate,
    RolePermissionsUpdate,
    RoleResponse,
    SuperuserResponse,
    SuperuserUpdate,
)
from app.access.service import service as access_service
from app.api.v1.deps import CurrentUser, get_current_user, require_superuser
from app.db.connection import get_connection
from app.db.types import Conn

org_router = APIRouter(prefix="/organizations", tags=["access"])
system_router = APIRouter(prefix="/system", tags=["system"])


@org_router.get(
    "/{organization_id}/access/permissions",
    response_model=list[PermissionResponse],
)
async def list_permissions(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[PermissionResponse]:
    """The capabilities this organization holds."""
    return await access_service.list_permissions(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        is_superuser=user.is_superuser,
    )


@org_router.post(
    "/{organization_id}/access/permissions",
    response_model=PermissionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_permission(
    organization_id: int,
    payload: PermissionCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> PermissionResponse:
    """Give this organization a capability of its own."""
    return await access_service.create_permission(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        payload=payload,
        is_superuser=user.is_superuser,
    )


@org_router.get(
    "/{organization_id}/access/roles",
    response_model=list[RoleResponse],
)
async def list_roles(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[RoleResponse]:
    """This organization's roles, each with the capabilities it grants."""
    return await access_service.list_roles(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        is_superuser=user.is_superuser,
    )


@org_router.post(
    "/{organization_id}/access/roles",
    response_model=RoleResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_role(
    organization_id: int,
    payload: RoleCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> RoleResponse:
    """Create a role and give it its grants."""
    return await access_service.create_role(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        payload=payload,
        is_superuser=user.is_superuser,
    )


@org_router.get(
    "/{organization_id}/access/roles/{role_id}/permissions",
    response_model=list[str],
)
async def get_role_permissions(
    organization_id: int,
    role_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[str]:
    """The capability names a role grants."""
    return await access_service.get_role_grants(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        role_id=role_id,
        is_superuser=user.is_superuser,
    )


@org_router.put(
    "/{organization_id}/access/roles/{role_id}/permissions",
    response_model=list[str],
)
async def set_role_permissions(
    organization_id: int,
    role_id: int,
    payload: RolePermissionsUpdate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[str]:
    """Replace a role's grants."""
    return await access_service.set_role_grants(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        role_id=role_id,
        payload=payload,
        is_superuser=user.is_superuser,
    )


@org_router.get(
    "/{organization_id}/access/members/{employee_id}",
    response_model=MemberAccessResponse,
)
async def get_member_access(
    organization_id: int,
    employee_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> MemberAccessResponse:
    """Everything one member can do in this organization."""
    return await access_service.get_member_access(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        target_id=employee_id,
        is_superuser=user.is_superuser,
    )


@org_router.put(
    "/{organization_id}/access/members/{employee_id}/roles",
    response_model=MemberAccessResponse,
)
async def set_member_roles(
    organization_id: int,
    employee_id: int,
    payload: MemberRolesUpdate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> MemberAccessResponse:
    """Replace the roles a member holds."""
    return await access_service.set_member_roles(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        target_id=employee_id,
        payload=payload,
        is_superuser=user.is_superuser,
    )


@org_router.put(
    "/{organization_id}/access/members/{employee_id}/permissions",
    response_model=MemberAccessResponse,
)
async def set_member_permissions(
    organization_id: int,
    employee_id: int,
    payload: MemberPermissionsUpdate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> MemberAccessResponse:
    """Replace the capabilities granted to a member directly."""
    return await access_service.set_member_permissions(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        target_id=employee_id,
        payload=payload,
        is_superuser=user.is_superuser,
    )


# -- the platform catalogue (super administrator) ---------------------------


@system_router.get("/catalog", response_model=list[CatalogEntryResponse])
async def list_catalog(
    _user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[CatalogEntryResponse]:
    """The platform's standard capabilities and roles."""
    return await access_service.list_catalog(conn)


@system_router.post(
    "/catalog",
    response_model=CatalogEntryResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_catalog_entry(
    payload: CatalogEntryCreate,
    user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> CatalogEntryResponse:
    """Add a capability or a standard role to the platform catalogue."""
    return await access_service.create_catalog_entry(
        conn, actor_id=user.employee_id, payload=payload
    )


@system_router.put("/catalog/{kind}/{name}", response_model=CatalogEntryResponse)
async def update_catalog_entry(
    kind: str,
    name: str,
    payload: CatalogEntryUpdate,
    user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> CatalogEntryResponse:
    """Change a catalogue entry's description or grants."""
    return await access_service.update_catalog_entry(
        conn, actor_id=user.employee_id, kind=kind, name=name, payload=payload
    )


@system_router.delete("/catalog/{kind}/{name}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_catalog_entry(
    kind: str,
    name: str,
    user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> None:
    """Remove a catalogue entry.

    Organizations that already installed it keep their own copy, so
    removing a standard capability never revokes access anyone already
    has.
    """
    await access_service.delete_catalog_entry(conn, actor_id=user.employee_id, kind=kind, name=name)


@system_router.post(
    "/organizations/{organization_id}/install",
    response_model=InstallResult,
)
async def install_catalog(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> InstallResult:
    """Install the current catalogue into an organization.

    Idempotent: capabilities and roles that already exist are left
    exactly as the organization has configured them.
    """
    return await access_service.install_catalog(
        conn, actor_id=user.employee_id, organization_id=organization_id
    )


@system_router.get("/organizations", response_model=list[OrganizationSummary])
async def list_organizations(
    _user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[OrganizationSummary]:
    """Every organization on the platform."""
    return await access_service.list_organizations(conn)


@system_router.get("/users/superusers", response_model=list[SuperuserResponse])
async def list_superusers(
    _user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[SuperuserResponse]:
    """The platform super administrators."""
    return await access_service.list_superusers(conn)


@system_router.put("/users/{employee_id}/superuser", response_model=SuperuserResponse)
async def set_superuser(
    employee_id: int,
    payload: SuperuserUpdate,
    user: Annotated[CurrentUser, Depends(require_superuser)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> SuperuserResponse:
    """Grant or revoke platform super administrator rights."""
    return await access_service.set_superuser(
        conn,
        actor_id=user.employee_id,
        employee_id=employee_id,
        is_superuser=payload.is_superuser,
    )
