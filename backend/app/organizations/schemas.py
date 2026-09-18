"""Organization DTOs — orgs, memberships, roles (§49 #13-20, §11).

Tenant rule (§8): every nested read/write is scoped by ``organization_id`` —
cross-tenant access answers 404, never 403, so one org's IDs are
undiscoverable from another.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

_SLUG_PATTERN = r"^[a-z0-9]+(?:-[a-z0-9]+)*$"


class OrganizationCreate(BaseModel):
    """Create body — §49 #13. ``slug`` defaults from the name (§15 utils)."""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=100)
    slug: str | None = Field(default=None, min_length=1, max_length=100, pattern=_SLUG_PATTERN)
    description: str | None = None


class OrganizationUpdate(BaseModel):
    """Admin patch body — §49 #16."""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str | None = Field(default=None, min_length=1, max_length=100)
    slug: str | None = Field(default=None, min_length=1, max_length=100, pattern=_SLUG_PATTERN)
    description: str | None = None
    is_active: bool | None = None


class OrganizationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    organization_id: int
    name: str
    slug: str
    description: str | None = None
    is_system: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime


class MembershipCreate(BaseModel):
    """Add an existing user to the org — §49 #17."""

    employee_id: int = Field(gt=0)
    is_admin: bool = False


class MembershipResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    membership_id: int
    employee_id: int
    organization_id: int
    is_admin: bool
    joined_at: datetime
    updated_at: datetime


class RoleCreate(BaseModel):
    """Org-scoped role — §49 #20. ``UNIQUE(name, organization_id)`` → 409."""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=100)
    description: str | None = None


class RoleResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    role_id: int
    name: str
    organization_id: int
    description: str | None = None
    is_active: bool
    created_at: datetime
    updated_at: datetime
