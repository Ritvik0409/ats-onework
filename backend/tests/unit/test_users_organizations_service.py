"""Users + organizations service behavior with in-memory doubles — no database.

Todo-required coverage: response field-exposure audit (no sensitive fields),
active-status conflict → 409, cross-org access → 404, duplicate slug → 409
(surfaced as ``ConflictError`` at the service boundary; the psycopg
``UniqueViolation`` → 409 mapping lives in the shared exception handler),
and the last-admin removal guard → 409.
"""

from __future__ import annotations

from typing import Any

import pytest

from app.core.constants import AccountStatus, EmployeeStatus
from app.core.exceptions import (
    AuthorizationError,
    ConflictError,
    NotFoundError,
    ValidationError,
)
from app.core.security import tokens as opaque_tokens
from app.organizations import service as org_service_module
from app.organizations.schemas import (
    MembershipCreate,
    OrganizationCreate,
    OrganizationUpdate,
    RoleCreate,
)
from app.organizations.service import OrganizationService
from app.users import service as user_service_module
from app.users.schemas import EmployeeStatusCreate, UserUpdate
from app.users.service import UserService


class _AuditStub:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    async def log(self, _conn: Any, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        return {"log_id": len(self.calls)}


def _now() -> Any:
    return opaque_tokens.utc_now_naive()


def _user_row(employee_id: int, **overrides: Any) -> dict[str, Any]:
    row = {
        "employee_id": employee_id,
        "name": f"User {employee_id}",
        "email": f"user{employee_id}@example.com",
        "account_status": AccountStatus.ACTIVE.value,
        "is_superuser": False,
        "last_login_at": None,
        "created_at": _now(),
        "updated_at": _now(),
        # Sensitive column present at the DB layer — must never surface.
        "password_hash": "argon2$should-never-leak",
    }
    row.update(overrides)
    return row


class _UserRepositoryStub:
    def __init__(self) -> None:
        self.users: dict[int, dict[str, Any]] = {}
        self.statuses: list[dict[str, Any]] = []
        self._next_status = 1

    async def get_by_id(self, _conn: Any, employee_id: int) -> dict[str, Any] | None:
        return self.users.get(employee_id)

    async def list_users(
        self,
        _conn: Any,
        *,
        limit: int,
        after_id: int | None,
        search: str | None = None,
        account_status: AccountStatus | None = None,
    ) -> list[dict[str, Any]]:
        rows = sorted(self.users.values(), key=lambda r: r["employee_id"])
        out = []
        for row in rows:
            if after_id is not None and row["employee_id"] <= after_id:
                continue
            if search and search.lower() not in (row["name"] + row["email"]).lower():
                continue
            if account_status and row["account_status"] != account_status.value:
                continue
            out.append(row)
        return out[: limit + 1]

    async def update_user(
        self, _conn: Any, employee_id: int, **fields: Any
    ) -> dict[str, Any] | None:
        row = self.users.get(employee_id)
        if row is None:
            return None
        if fields.get("name") is not None:
            row["name"] = fields["name"]
        if fields.get("account_status") is not None:
            row["account_status"] = fields["account_status"].value
        if fields.get("is_superuser") is not None:
            row["is_superuser"] = fields["is_superuser"]
        return row

    async def list_statuses(self, _conn: Any, employee_id: int) -> list[dict[str, Any]]:
        return [s for s in self.statuses if s["employee_id"] == employee_id]

    async def get_active_status(self, _conn: Any, employee_id: int) -> dict[str, Any] | None:
        for row in self.statuses:
            if row["employee_id"] == employee_id and row["ended_at"] is None:
                return row
        return None

    async def create_status(
        self,
        _conn: Any,
        *,
        employee_id: int,
        status: EmployeeStatus,
        updated_by: int | None,
    ) -> dict[str, Any]:
        row = {
            "status_id": self._next_status,
            "employee_id": employee_id,
            "status": status.value,
            "started_at": _now(),
            "ended_at": None,
            "updated_by": updated_by,
        }
        self._next_status += 1
        self.statuses.append(row)
        return row


class _OrgRepositoryStub:
    def __init__(self) -> None:
        self.known_users: set[int] = set()
        self.orgs: dict[int, dict[str, Any]] = {}
        self.slugs: dict[str, int] = {}
        self.memberships: dict[tuple[int, int], dict[str, Any]] = {}
        self.roles: list[dict[str, Any]] = []
        self._next_org = 1
        self._next_membership = 1
        self._next_role = 1

    # -- orgs ----------------------------------------------------------

    async def create_organization(
        self, _conn: Any, *, name: str, slug: str, description: str | None
    ) -> dict[str, Any]:
        if slug in self.slugs:
            raise ConflictError("An organization with this slug already exists.")
        org_id = self._next_org
        self._next_org += 1
        row = {
            "organization_id": org_id,
            "name": name,
            "slug": slug,
            "description": description,
            "is_system": False,
            "is_active": True,
            "created_at": _now(),
            "updated_at": _now(),
        }
        self.orgs[org_id] = row
        self.slugs[slug] = org_id
        return row

    async def get_organization(self, _conn: Any, organization_id: int) -> dict[str, Any] | None:
        return self.orgs.get(organization_id)

    async def list_organizations_for_employee(
        self, _conn: Any, employee_id: int
    ) -> list[dict[str, Any]]:
        return [
            self.orgs[org_id] for (uid, org_id) in sorted(self.memberships) if uid == employee_id
        ]

    async def update_organization(
        self, _conn: Any, organization_id: int, **fields: Any
    ) -> dict[str, Any] | None:
        row = self.orgs.get(organization_id)
        if row is None:
            return None
        if fields.get("slug") is not None and fields["slug"] != row["slug"]:
            if fields["slug"] in self.slugs:
                raise ConflictError("An organization with this slug already exists.")
            del self.slugs[row["slug"]]
            self.slugs[fields["slug"]] = organization_id
            row["slug"] = fields["slug"]
        for key in ("name", "description", "is_active"):
            if fields.get(key) is not None:
                row[key] = fields[key]
        return row

    # -- memberships ------------------------------------------------------

    async def get_membership(
        self, _conn: Any, employee_id: int, organization_id: int
    ) -> dict[str, Any] | None:
        return self.memberships.get((employee_id, organization_id))

    async def add_membership(
        self, _conn: Any, *, employee_id: int, organization_id: int, is_admin: bool
    ) -> dict[str, Any]:
        row = {
            "membership_id": self._next_membership,
            "employee_id": employee_id,
            "organization_id": organization_id,
            "is_admin": is_admin,
            "joined_at": _now(),
            "updated_at": _now(),
        }
        self._next_membership += 1
        self.memberships[(employee_id, organization_id)] = row
        return row

    async def remove_membership(self, _conn: Any, *, employee_id: int, organization_id: int) -> int:
        return 1 if self.memberships.pop((employee_id, organization_id), None) else 0

    async def count_admins(self, _conn: Any, organization_id: int) -> int:
        return sum(
            1
            for (__uid, org_id), m in self.memberships.items()
            if org_id == organization_id and m["is_admin"]
        )

    async def lock_admin_memberships(
        self, _conn: Any, organization_id: int
    ) -> list[dict[str, Any]]:
        """Test double mirrors the FOR UPDATE lock by returning live rows —
        the service counts them, exactly like the real implementation."""
        return [
            m
            for (__uid, org_id), m in self.memberships.items()
            if org_id == organization_id and m["is_admin"]
        ]

    async def user_exists(self, _conn: Any, employee_id: int) -> bool:
        return employee_id in self.known_users

    # -- roles ---------------------------------------------------------------

    async def list_roles(self, _conn: Any, organization_id: int) -> list[dict[str, Any]]:
        return [r for r in self.roles if r["organization_id"] == organization_id]

    async def create_role(
        self, _conn: Any, *, organization_id: int, name: str, description: str | None
    ) -> dict[str, Any]:
        if any(r["organization_id"] == organization_id and r["name"] == name for r in self.roles):
            raise ConflictError("A role with this name already exists in this organization.")
        row = {
            "role_id": self._next_role,
            "name": name,
            "organization_id": organization_id,
            "description": description,
            "is_active": True,
            "created_at": _now(),
            "updated_at": _now(),
        }
        self._next_role += 1
        self.roles.append(row)
        return row


@pytest.fixture
def user_repo() -> _UserRepositoryStub:
    repo = _UserRepositoryStub()
    repo.users[1] = _user_row(1)
    repo.users[2] = _user_row(2, account_status=AccountStatus.SUSPENDED.value)
    return repo


@pytest.fixture
def user_svc(user_repo: _UserRepositoryStub, monkeypatch: pytest.MonkeyPatch) -> UserService:
    monkeypatch.setattr(user_service_module, "audit_service", _AuditStub())
    return UserService(repository=user_repo)  # type: ignore[arg-type]


@pytest.fixture
def org_repo() -> _OrgRepositoryStub:
    repo = _OrgRepositoryStub()
    repo.known_users = {1, 2, 3}
    return repo


@pytest.fixture
def org_svc(org_repo: _OrgRepositoryStub, monkeypatch: pytest.MonkeyPatch) -> OrganizationService:
    monkeypatch.setattr(org_service_module, "audit_service", _AuditStub())
    return OrganizationService(repository=org_repo)  # type: ignore[arg-type]


# -- users ---------------------------------------------------------------------


async def test_get_me_hides_sensitive_fields(user_svc: UserService) -> None:
    response = await user_svc.get_me(object(), 1)
    dumped = response.model_dump()
    assert dumped["email"] == "user1@example.com"
    assert "password_hash" not in dumped
    assert "token_hash" not in dumped


async def test_get_me_unknown_user_404(user_svc: UserService) -> None:
    with pytest.raises(NotFoundError):
        await user_svc.get_me(object(), 999)


async def test_list_users_keyset_pagination(user_svc: UserService) -> None:
    first = await user_svc.list_users(object(), limit=1, cursor=None)
    assert [u.employee_id for u in first.items] == [1]
    assert first.next_cursor is not None
    second = await user_svc.list_users(object(), limit=1, cursor=first.next_cursor)
    assert [u.employee_id for u in second.items] == [2]
    assert second.next_cursor is None


async def test_list_users_invalid_cursor_422(user_svc: UserService) -> None:
    with pytest.raises(ValidationError):
        await user_svc.list_users(object(), limit=10, cursor="bogus")


async def test_list_users_null_cursor_422(user_svc: UserService) -> None:
    """A crafted cursor with a null keyset must be a 422, never a 500."""
    from app.common.pagination import encode_cursor

    with pytest.raises(ValidationError):
        await user_svc.list_users(object(), limit=10, cursor=encode_cursor(after_id=None))


async def test_update_user_unknown_404(user_svc: UserService) -> None:
    with pytest.raises(NotFoundError):
        await user_svc.update_user(
            object(), actor_id=1, employee_id=999, payload=UserUpdate(name="X")
        )


async def test_update_user_noop_writes_no_audit(
    user_repo: _UserRepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An empty PATCH returns current state without a misleading audit row."""
    from app.users import service as user_service_module
    from app.users.service import UserService

    audit = _AuditStub()
    monkeypatch.setattr(user_service_module, "audit_service", audit)
    svc = UserService(repository=user_repo)  # type: ignore[arg-type]
    before = dict(user_repo.users[1])
    response = await svc.update_user(object(), actor_id=1, employee_id=1, payload=UserUpdate())
    assert response.name == before["name"]
    assert audit.calls == []


async def test_create_status_conflict_409(user_svc: UserService) -> None:
    created = await user_svc.create_status(
        object(),
        actor_id=1,
        employee_id=1,
        payload=EmployeeStatusCreate(status=EmployeeStatus.ACTIVE),
    )
    assert created.status == EmployeeStatus.ACTIVE
    with pytest.raises(ConflictError):
        await user_svc.create_status(
            object(),
            actor_id=1,
            employee_id=1,
            payload=EmployeeStatusCreate(status=EmployeeStatus.ON_LEAVE),
        )


async def test_create_status_unknown_user_404(user_svc: UserService) -> None:
    with pytest.raises(NotFoundError):
        await user_svc.create_status(
            object(),
            actor_id=1,
            employee_id=999,
            payload=EmployeeStatusCreate(status=EmployeeStatus.ACTIVE),
        )


# -- organizations ---------------------------------------------------------------


async def test_create_org_stamps_creator_admin(
    org_svc: OrganizationService, org_repo: _OrgRepositoryStub
) -> None:
    org = await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Acme Corp")
    )
    assert org.slug == "acme-corp"  # derived via slugify
    membership = await org_repo.get_membership(object(), 1, org.organization_id)
    assert membership is not None and membership["is_admin"] is True


async def test_create_org_duplicate_slug_409(org_svc: OrganizationService) -> None:
    await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Acme", slug="acme")
    )
    with pytest.raises(ConflictError):
        await org_svc.create_organization(
            object(), actor_id=2, payload=OrganizationCreate(name="Other", slug="acme")
        )


async def test_create_org_symbol_only_name_422(org_svc: OrganizationService) -> None:
    """A name that slugifies to nothing must be a 422, not an empty slug row."""
    with pytest.raises(ValidationError):
        await org_svc.create_organization(
            object(), actor_id=1, payload=OrganizationCreate(name="!!!")
        )


async def test_cross_org_access_404(
    org_svc: OrganizationService, org_repo: _OrgRepositoryStub
) -> None:
    org = await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Private")
    )
    with pytest.raises(NotFoundError):
        await org_svc.get_organization(object(), employee_id=2, organization_id=org.organization_id)
    with pytest.raises(NotFoundError):
        await org_svc.list_roles(object(), employee_id=2, organization_id=org.organization_id)
    assert org_repo.orgs[org.organization_id]["name"] == "Private"


async def test_non_admin_update_403(
    org_svc: OrganizationService, org_repo: _OrgRepositoryStub
) -> None:
    org = await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Gated")
    )
    await org_repo.add_membership(
        object(), employee_id=2, organization_id=org.organization_id, is_admin=False
    )
    with pytest.raises(AuthorizationError) as exc:
        await org_svc.update_organization(
            object(),
            employee_id=2,
            organization_id=org.organization_id,
            payload=OrganizationUpdate(name="Hijacked"),
        )
    assert exc.value.status_code == 403


async def test_update_org_noop_writes_no_audit(
    org_repo: _OrgRepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An empty PATCH returns current state without a misleading audit row."""
    from app.organizations import service as org_service_module
    from app.organizations.service import OrganizationService

    audit = _AuditStub()
    monkeypatch.setattr(org_service_module, "audit_service", audit)
    svc = OrganizationService(repository=org_repo)  # type: ignore[arg-type]
    org = await svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Steady")
    )
    audit.calls.clear()
    same = await svc.update_organization(
        object(),
        employee_id=1,
        organization_id=org.organization_id,
        payload=OrganizationUpdate(),
    )
    assert same.name == "Steady"
    assert audit.calls == []


async def test_add_member_duplicate_409_and_unknown_user_404(
    org_svc: OrganizationService,
) -> None:
    org = await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Team")
    )
    await org_svc.add_member(
        object(),
        actor_id=1,
        organization_id=org.organization_id,
        payload=MembershipCreate(employee_id=2),
    )
    with pytest.raises(ConflictError):
        await org_svc.add_member(
            object(),
            actor_id=1,
            organization_id=org.organization_id,
            payload=MembershipCreate(employee_id=2),
        )
    with pytest.raises(NotFoundError):
        await org_svc.add_member(
            object(),
            actor_id=1,
            organization_id=org.organization_id,
            payload=MembershipCreate(employee_id=4242),
        )


async def test_remove_last_admin_409(org_svc: OrganizationService) -> None:
    org = await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Solo")
    )
    with pytest.raises(ConflictError):
        await org_svc.remove_member(
            object(),
            actor_id=1,
            organization_id=org.organization_id,
            employee_id=1,
        )


async def test_remove_member_happy_path_after_second_admin(
    org_svc: OrganizationService, org_repo: _OrgRepositoryStub
) -> None:
    org = await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Duo")
    )
    await org_svc.add_member(
        object(),
        actor_id=1,
        organization_id=org.organization_id,
        payload=MembershipCreate(employee_id=2, is_admin=True),
    )
    await org_svc.remove_member(
        object(),
        actor_id=2,
        organization_id=org.organization_id,
        employee_id=1,
    )
    assert await org_repo.get_membership(object(), 1, org.organization_id) is None


async def test_roles_scoped_and_duplicate_409(org_svc: OrganizationService) -> None:
    org = await org_svc.create_organization(
        object(), actor_id=1, payload=OrganizationCreate(name="Roles")
    )
    role = await org_svc.create_role(
        object(),
        actor_id=1,
        organization_id=org.organization_id,
        payload=RoleCreate(name="manager"),
    )
    assert role.organization_id == org.organization_id
    with pytest.raises(ConflictError):
        await org_svc.create_role(
            object(),
            actor_id=1,
            organization_id=org.organization_id,
            payload=RoleCreate(name="manager"),
        )
