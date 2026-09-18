"""Auth DTOs — request/response shapes for §49 #3-7.

``UserResponse`` is re-exported from the users module so the two can never
drift (§11). ``TokenPair`` carries the stateless access token plus the
opaque refresh token and the caller's organization list (ADR-001 §51) —
the client picks its active organization from that list and calls
``switch-organization`` to move between them.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.users.schemas import UserResponse

__all__ = [
    "LoginRequest",
    "OrganizationSummary",
    "OrganizationSwitchRequest",
    "RefreshRequest",
    "TokenPair",
    "UserCreate",
    "UserResponse",
]


class UserCreate(BaseModel):
    """Registration body — §49 #3."""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=100)
    email: EmailStr = Field(max_length=254)
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(BaseModel):
    """Login body — §49 #4."""

    model_config = ConfigDict(str_strip_whitespace=True)

    email: EmailStr = Field(max_length=254)
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    """Refresh/logout body — the opaque client-visible token (§49 #5-6)."""

    refresh_token: str = Field(min_length=1)


class OrganizationSwitchRequest(BaseModel):
    """Switch active organization — §49 #7."""

    organization_id: int = Field(gt=0)


class OrganizationSummary(BaseModel):
    """One membership row embedded in ``TokenPair`` (ADR-001 §51)."""

    model_config = ConfigDict(from_attributes=True)

    organization_id: int
    name: str
    slug: str
    is_admin: bool


class TokenPair(BaseModel):
    """Access + refresh pair returned by login/refresh/switch (§49 #4-5/#7)."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(gt=0, description="Access-token lifetime in seconds")
    organizations: list[OrganizationSummary] = Field(default_factory=list)
