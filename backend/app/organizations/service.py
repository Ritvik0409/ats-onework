"""Organization business rules — orgs, memberships, org-scoped roles
(arch. doc §8-9, §35-37; contracts §49 #13-20).

Authorization model for path-scoped routes: the service — not the generic
``require_admin`` dependency — enforces membership against the **path**
organization, because the token's ``org`` claim may point elsewhere:

- caller has no membership in the path org → ``NotFoundError`` (404 —
  cross-tenant IDs stay undiscoverable, §49 conventions);
- caller is a member but not an admin on an admin-only operation →
  ``AuthorizationError`` (403).

Membership changes and role creation are multi-write workflows (row +
audit) sharing the request-scoped connection (§7). Removing the last admin
is rejected with 409 so an org can never be orphaned.
"""

from __future__ import annotations

from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin, require_path_member
from app.common.utils import slugify
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.db.types import Conn, Row
from app.organizations.repository import OrganizationRepository
from app.organizations.schemas import (
    MembershipCreate,
    MembershipResponse,
    OrganizationCreate,
    OrganizationResponse,
    OrganizationUpdate,
    RoleCreate,
    RoleResponse,
)

_repository = OrganizationRepository()


class OrganizationService:
    """Owns orgs + memberships (§35 MembershipService duties live here
    until the module needs splitting — one class, no premature abstraction)."""

    def __init__(self, repository: OrganizationRepository | None = None) -> None:
        self._repository = repository or _repository

    # -- organizations -----------------------------------------------------

    async def create_organization(
        self, conn: Conn, *, actor_id: int, payload: OrganizationCreate
    ) -> OrganizationResponse:
        """Create the org and stamp the creator as its first admin — one
        request-scoped transaction, so neither row survives without the other."""
        slug = payload.slug or slugify(payload.name)
        if not slug:
            raise ValidationError("Organization name must contain at least one letter or digit.")
        org = await self._repository.create_organization(
            conn, name=payload.name, slug=slug, description=payload.description
        )
        await self._repository.add_membership(
            conn,
            employee_id=actor_id,
            organization_id=org["organization_id"],
            is_admin=True,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            action="organization.create",
            table_name="organizations",
            record_id=str(org["organization_id"]),
            new_values={"name": org["name"], "slug": org["slug"]},
        )
        return OrganizationResponse.model_validate(org)

    async def list_own(self, conn: Conn, employee_id: int) -> list[OrganizationResponse]:
        rows = await self._repository.list_organizations_for_employee(conn, employee_id)
        return [OrganizationResponse.model_validate(row) for row in rows]

    async def get_organization(
        self, conn: Conn, *, employee_id: int, organization_id: int
    ) -> OrganizationResponse:
        await self._require_member(conn, employee_id, organization_id)
        org = await self._repository.get_organization(conn, organization_id)
        if org is None:  # pragma: no cover — membership implies the org exists
            raise NotFoundError("Organization not found.")
        return OrganizationResponse.model_validate(org)

    async def update_organization(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        payload: OrganizationUpdate,
    ) -> OrganizationResponse:
        await self._require_admin(conn, employee_id, organization_id)
        current = await self._repository.get_organization(conn, organization_id)
        if current is None:  # pragma: no cover — admin implies the org exists
            raise NotFoundError("Organization not found.")
        if not payload.model_dump(exclude_unset=True):
            # No-op PATCH — return current state without writing a
            # misleading audit row claiming something changed.
            return OrganizationResponse.model_validate(current)
        row = await self._repository.update_organization(
            conn,
            organization_id,
            name=payload.name,
            slug=payload.slug,
            description=payload.description,
            is_active=payload.is_active,
        )
        if row is None:  # pragma: no cover — guarded above; race safety
            raise NotFoundError("Organization not found.")
        await audit_service.log(
            conn,
            actor_id=employee_id,
            action="organization.update",
            table_name="organizations",
            record_id=str(organization_id),
            old_values={
                "name": current["name"],
                "slug": current["slug"],
                "is_active": current["is_active"],
            },
            new_values={
                "name": row["name"],
                "slug": row["slug"],
                "is_active": row["is_active"],
            },
        )
        return OrganizationResponse.model_validate(row)

    # -- memberships ---------------------------------------------------------

    async def add_member(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        payload: MembershipCreate,
    ) -> MembershipResponse:
        await self._require_admin(conn, actor_id, organization_id)
        if not await self._repository.user_exists(conn, payload.employee_id):
            raise NotFoundError("User not found.")
        if (
            await self._repository.get_membership(conn, payload.employee_id, organization_id)
            is not None
        ):
            raise ConflictError("This user is already a member of the organization.")
        row = await self._repository.add_membership(
            conn,
            employee_id=payload.employee_id,
            organization_id=organization_id,
            is_admin=payload.is_admin,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            action="organization.member.add",
            table_name="memberships",
            record_id=str(row["membership_id"]),
            new_values={
                "employee_id": payload.employee_id,
                "organization_id": organization_id,
                "is_admin": payload.is_admin,
            },
        )
        return MembershipResponse.model_validate(row)

    async def remove_member(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        employee_id: int,
    ) -> None:
        await self._require_admin(conn, actor_id, organization_id)
        target = await self._repository.get_membership(conn, employee_id, organization_id)
        if target is None:
            raise NotFoundError("Membership not found.")
        # Lock the admin rows BEFORE counting: two concurrent removals would
        # otherwise both observe N=2, both delete, and orphan the org. The
        # FOR UPDATE lock serializes them inside the request transaction (§7).
        admin_rows = await self._repository.lock_admin_memberships(conn, organization_id)
        if bool(target["is_admin"]) and len(admin_rows) <= 1:
            raise ConflictError("Cannot remove the last administrator of the organization.")
        await self._repository.remove_membership(
            conn, employee_id=employee_id, organization_id=organization_id
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            action="organization.member.remove",
            table_name="memberships",
            record_id=str(target["membership_id"]),
            old_values={
                "employee_id": employee_id,
                "organization_id": organization_id,
            },
        )

    # -- roles (org-scoped) ----------------------------------------------------

    async def list_roles(
        self, conn: Conn, *, employee_id: int, organization_id: int
    ) -> list[RoleResponse]:
        await self._require_member(conn, employee_id, organization_id)
        rows = await self._repository.list_roles(conn, organization_id)
        return [RoleResponse.model_validate(row) for row in rows]

    async def create_role(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        payload: RoleCreate,
    ) -> RoleResponse:
        await self._require_admin(conn, actor_id, organization_id)
        row = await self._repository.create_role(
            conn,
            organization_id=organization_id,
            name=payload.name,
            description=payload.description,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            action="organization.role.create",
            table_name="roles",
            record_id=str(row["role_id"]),
            new_values={
                "name": payload.name,
                "organization_id": organization_id,
            },
        )
        return RoleResponse.model_validate(row)

    # -- guards ------------------------------------------------------------------

    async def _require_member(self, conn: Conn, employee_id: int, organization_id: int) -> Row:
        # Canonical path-org gate lives in app.common.tenant — the 404 here
        # is what keeps cross-tenant IDs undiscoverable (§49).
        return require_path_member(
            await self._repository.get_membership(conn, employee_id, organization_id)
        )

    async def _require_admin(self, conn: Conn, employee_id: int, organization_id: int) -> Row:
        return require_path_admin(
            await self._repository.get_membership(conn, employee_id, organization_id)
        )


service = OrganizationService()
