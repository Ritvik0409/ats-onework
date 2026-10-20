"""Access DTOs — capabilities, roles and grants (§10, §35)."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PermissionResponse(BaseModel):
    """A capability the organization holds."""

    model_config = ConfigDict(from_attributes=True)

    permission_id: int
    api_name: str
    organization_id: int
    is_global: bool
    description: str | None = None


class PermissionCreate(BaseModel):
    """Create a capability for the organization."""

    model_config = ConfigDict(str_strip_whitespace=True)

    api_name: str = Field(min_length=1, max_length=100, pattern=r"^[a-z0-9_]+$")
    description: str | None = Field(default=None, max_length=500)


class RoleResponse(BaseModel):
    """An organization's role, with the capabilities it grants."""

    model_config = ConfigDict(from_attributes=True)

    role_id: int
    name: str
    organization_id: int
    description: str | None = None
    is_active: bool
    created_at: datetime
    updated_at: datetime
    #: The capability names this role grants.
    permissions: list[str] = Field(default_factory=list)


class RoleCreate(BaseModel):
    """Create a role, optionally with its grants."""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    #: Capability names the role grants. Names the organization does not
    #: hold are ignored rather than rejected, so a role can be created
    #: before its capabilities are.
    permissions: list[str] = Field(default_factory=list)


class RolePermissionsUpdate(BaseModel):
    """Replace a role's grants."""

    model_config = ConfigDict(str_strip_whitespace=True)

    permissions: list[str] = Field(default_factory=list)


class MemberRolesUpdate(BaseModel):
    """Replace the roles a member holds."""

    model_config = ConfigDict(str_strip_whitespace=True)

    role_ids: list[int] = Field(default_factory=list)


class MemberPermissionsUpdate(BaseModel):
    """Replace the capabilities granted to a person directly."""

    model_config = ConfigDict(str_strip_whitespace=True)

    permissions: list[str] = Field(default_factory=list)


class MemberAccessResponse(BaseModel):
    """Everything one member can do in one organization."""

    employee_id: int
    organization_id: int
    is_admin: bool
    roles: list[str] = Field(default_factory=list)
    #: Capabilities granted directly, on top of the roles' grants.
    direct_permissions: list[str] = Field(default_factory=list)
    #: Every capability the member effectively holds.
    effective_permissions: list[str] = Field(default_factory=list)


class CatalogEntryResponse(BaseModel):
    """One row of the platform's access catalogue."""

    model_config = ConfigDict(from_attributes=True)

    catalog_id: int
    kind: str
    name: str
    description: str | None = None
    grants: list[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class CatalogEntryCreate(BaseModel):
    """Add a capability or a standard role to the platform catalogue."""

    model_config = ConfigDict(str_strip_whitespace=True)

    kind: str = Field(pattern=r"^(permission|role)$")
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    #: For a role: the capability names it grants.
    grants: list[str] = Field(default_factory=list)


class CatalogEntryUpdate(BaseModel):
    """Change a catalogue entry's description or grants."""

    model_config = ConfigDict(str_strip_whitespace=True)

    description: str | None = Field(default=None, max_length=500)
    grants: list[str] | None = None


class InstallResult(BaseModel):
    """What an installation added to an organization."""

    permissions_installed: int
    roles_installed: int


class SuperuserResponse(BaseModel):
    """A platform super administrator."""

    model_config = ConfigDict(from_attributes=True)

    employee_id: int
    name: str
    email: str
    account_status: str
    is_superuser: bool
    last_login_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class SuperuserUpdate(BaseModel):
    """Grant or revoke platform super administrator rights."""

    is_superuser: bool


class OrganizationSummary(BaseModel):
    """An organization, for the platform administration list."""

    model_config = ConfigDict(from_attributes=True)

    organization_id: int
    name: str
    slug: str
    description: str | None = None
    is_system: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime
    member_count: int = 0
