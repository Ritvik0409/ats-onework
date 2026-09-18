"""AuthService behavior with an in-memory repository double — no database.

Covers every auth test the todo requires: happy path, wrong password → 401,
suspended/locked → 403, expired/unknown refresh → 401, rotation invalidating
the old token, and switch-to-non-member-org → 403.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

import pytest

from app.auth import service as auth_service_module
from app.auth.schemas import (
    LoginRequest,
    OrganizationSwitchRequest,
    RefreshRequest,
    UserCreate,
)
from app.auth.service import AuthService
from app.core.constants import AccountStatus, TokenPurpose
from app.core.exceptions import (
    AuthenticationError,
    AuthorizationError,
    ConflictError,
    NotFoundError,
)
from app.core.security import passwords as password_security
from app.core.security import tokens as opaque_tokens

STANTON_DEV_PASSWORD = "DevPassword123!"


class _AuditStub:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    async def log(self, _conn: Any, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        return {"log_id": len(self.calls)}


class _AuthRepositoryStub:
    """In-memory double of AuthRepository — mirrors its method contracts."""

    def __init__(self) -> None:
        self.users: dict[int, dict[str, Any]] = {}
        self.by_email: dict[str, int] = {}
        self.memberships: dict[tuple[int, int], dict[str, Any]] = {}
        self.orgs: dict[int, dict[str, Any]] = {}
        self.tokens: dict[str, dict[str, Any]] = {}
        self.last_login: dict[int, datetime] = {}
        self.password_updates: list[tuple[int, str]] = []
        self._next_user = 100
        self._next_token = 500
        self.deleted_hashes: list[str] = []

    # -- users ---------------------------------------------------------

    async def get_user_by_email(self, _conn: Any, email: str) -> dict[str, Any] | None:
        user_id = self.by_email.get(email.lower())
        return self.users.get(user_id) if user_id is not None else None

    async def get_user_by_id(self, _conn: Any, employee_id: int) -> dict[str, Any] | None:
        return self.users.get(employee_id)

    async def create_user(
        self, _conn: Any, *, name: str, email: str, password_hash: str
    ) -> dict[str, Any]:
        now = opaque_tokens.utc_now_naive()
        user_id = self._next_user
        self._next_user += 1
        row = {
            "employee_id": user_id,
            "name": name,
            "email": email.lower(),
            "password_hash": password_hash,
            "account_status": AccountStatus.ACTIVE.value,
            "is_superuser": False,
            "last_login_at": None,
            "created_at": now,
            "updated_at": now,
        }
        self.users[user_id] = row
        self.by_email[email.lower()] = user_id
        return {
            "employee_id": user_id,
            "name": name,
            "email": email.lower(),
            "account_status": AccountStatus.ACTIVE.value,
            "is_superuser": False,
            "last_login_at": None,
            "created_at": now,
            "updated_at": now,
        }

    async def update_password_hash(self, _conn: Any, employee_id: int, password_hash: str) -> None:
        self.password_updates.append((employee_id, password_hash))
        self.users[employee_id]["password_hash"] = password_hash

    async def update_last_login(self, _conn: Any, employee_id: int, at: datetime) -> None:
        self.last_login[employee_id] = at

    # -- memberships / orgs ----------------------------------------------

    async def list_memberships(self, _conn: Any, employee_id: int) -> list[dict[str, Any]]:
        rows = [
            {
                "organization_id": org_id,
                "is_admin": m["is_admin"],
                "name": self.orgs[org_id]["name"],
                "slug": self.orgs[org_id]["slug"],
            }
            for (uid, org_id), m in sorted(self.memberships.items())
            if uid == employee_id
        ]
        return rows

    async def get_membership(
        self, _conn: Any, employee_id: int, organization_id: int
    ) -> dict[str, Any] | None:
        return self.memberships.get((employee_id, organization_id))

    async def organization_exists(self, _conn: Any, organization_id: int) -> bool:
        return organization_id in self.orgs

    # -- tokens -----------------------------------------------------------

    async def insert_token(
        self,
        _conn: Any,
        *,
        employee_id: int,
        token_hash: str,
        purpose: TokenPurpose,
        expires_at: datetime,
    ) -> dict[str, Any]:
        token_id = self._next_token
        self._next_token += 1
        row = {
            "token_id": token_id,
            "employee_id": employee_id,
            "token_hash": token_hash,
            "purpose": purpose.value,
            "expires_at": expires_at,
            "created_at": opaque_tokens.utc_now_naive(),
        }
        self.tokens[token_hash] = row
        return row

    async def get_token(
        self, _conn: Any, token_hash: str, purpose: TokenPurpose
    ) -> dict[str, Any] | None:
        row = self.tokens.get(token_hash)
        return row if row is not None and row["purpose"] == purpose.value else None

    async def delete_token(self, _conn: Any, token_hash: str) -> int:
        self.deleted_hashes.append(token_hash)
        return 1 if self.tokens.pop(token_hash, None) is not None else 0

    async def delete_token_for_employee(
        self, _conn: Any, *, employee_id: int, token_hash: str
    ) -> int:
        row = self.tokens.get(token_hash)
        if row is not None and row["employee_id"] == employee_id:
            del self.tokens[token_hash]
            return 1
        return 0

    # -- seeding helpers ----------------------------------------------------

    def seed_user(
        self,
        email: str,
        password_hash: str,
        *,
        status: str = AccountStatus.ACTIVE.value,
    ) -> dict[str, Any]:
        now = opaque_tokens.utc_now_naive()
        user_id = self._next_user
        self._next_user += 1
        row = {
            "employee_id": user_id,
            "name": "Seed User",
            "email": email.lower(),
            "password_hash": password_hash,
            "account_status": status,
            "is_superuser": False,
            "last_login_at": None,
            "created_at": now,
            "updated_at": now,
        }
        self.users[user_id] = row
        self.by_email[email.lower()] = user_id
        return row

    def seed_org(self, organization_id: int, name: str = "Org", slug: str = "org") -> None:
        self.orgs[organization_id] = {"name": name, "slug": slug}

    def seed_membership(self, employee_id: int, organization_id: int, *, admin: bool) -> None:
        self.memberships[(employee_id, organization_id)] = {
            "membership_id": len(self.memberships) + 1,
            "employee_id": employee_id,
            "organization_id": organization_id,
            "is_admin": admin,
        }


@pytest.fixture
def stub() -> _AuthRepositoryStub:
    return _AuthRepositoryStub()


@pytest.fixture
def svc(stub: _AuthRepositoryStub, monkeypatch: pytest.MonkeyPatch) -> AuthService:
    audit = _AuditStub()
    monkeypatch.setattr(auth_service_module, "audit_service", audit)
    service = AuthService(repository=stub)  # type: ignore[arg-type]
    service._audit = audit  # type: ignore[attr-defined]
    return service


async def _seed_member(
    stub: _AuthRepositoryStub, *, org: int = 1, admin: bool = False
) -> dict[str, Any]:
    password_hash = await password_security.hash_password(STANTON_DEV_PASSWORD)
    user = stub.seed_user("member@example.com", password_hash)
    stub.seed_org(org, name=f"Org {org}", slug=f"org-{org}")
    stub.seed_membership(user["employee_id"], org, admin=admin)
    return user


async def test_register_happy_path(svc: AuthService, stub: _AuthRepositoryStub) -> None:
    response = await svc.register(
        object(), UserCreate(name="Asha", email="asha@example.com", password="StrongPass1!")
    )
    assert response.email == "asha@example.com"
    assert "password_hash" not in response.model_dump()
    assert stub.by_email["asha@example.com"] == response.employee_id


async def test_register_duplicate_email_409(svc: AuthService) -> None:
    await svc.register(
        object(), UserCreate(name="A", email="dup@example.com", password="StrongPass1!")
    )
    with pytest.raises(ConflictError):
        await svc.register(
            object(),
            UserCreate(name="B", email="DUP@example.com", password="StrongPass1!"),
        )


async def test_login_happy_path_sets_last_login(
    svc: AuthService, stub: _AuthRepositoryStub
) -> None:
    user = await _seed_member(stub, org=3, admin=True)
    pair = await svc.login(
        object(), LoginRequest(email=user["email"], password=STANTON_DEV_PASSWORD)
    )
    assert pair.organizations[0].organization_id == 3
    assert pair.organizations[0].is_admin is True
    assert stub.last_login[user["employee_id"]] is not None
    from app.core.security import jwt as jwt_security

    payload = jwt_security.decode_access_token(pair.access_token)
    assert (payload["sub"], payload["org"], payload["admin"]) == (
        user["employee_id"],
        3,
        True,
    )


async def test_login_wrong_password_401(svc: AuthService, stub: _AuthRepositoryStub) -> None:
    user = await _seed_member(stub)
    with pytest.raises(AuthenticationError) as exc:
        await svc.login(object(), LoginRequest(email=user["email"], password="WrongPass1!"))
    assert exc.value.status_code == 401


async def test_login_unknown_email_401(svc: AuthService) -> None:
    with pytest.raises(AuthenticationError) as exc:
        await svc.login(object(), LoginRequest(email="ghost@example.com", password="Whatever1!"))
    assert exc.value.status_code == 401


@pytest.mark.parametrize("status", ["suspended", "locked", "inactive"])
async def test_login_non_active_account_403(
    svc: AuthService, stub: _AuthRepositoryStub, status: str
) -> None:
    password_hash = await password_security.hash_password(STANTON_DEV_PASSWORD)
    user = stub.seed_user("blocked@example.com", password_hash, status=status)
    with pytest.raises(AuthorizationError) as exc:
        await svc.login(object(), LoginRequest(email=user["email"], password=STANTON_DEV_PASSWORD))
    assert exc.value.status_code == 403


async def test_refresh_rotation_invalidates_old(
    svc: AuthService, stub: _AuthRepositoryStub
) -> None:
    user = await _seed_member(stub)
    pair = await svc.login(
        object(), LoginRequest(email=user["email"], password=STANTON_DEV_PASSWORD)
    )
    rotated = await svc.refresh(object(), RefreshRequest(refresh_token=pair.refresh_token))
    assert rotated.refresh_token != pair.refresh_token
    with pytest.raises(AuthenticationError):
        await svc.refresh(object(), RefreshRequest(refresh_token=pair.refresh_token))


async def test_refresh_unknown_token_401(svc: AuthService) -> None:
    with pytest.raises(AuthenticationError) as exc:
        await svc.refresh(object(), RefreshRequest(refresh_token="no-such-token"))
    assert exc.value.status_code == 401


async def test_refresh_expired_token_401_and_cleaned(
    svc: AuthService, stub: _AuthRepositoryStub
) -> None:
    user = await _seed_member(stub)
    raw = opaque_tokens.generate_token()
    token_hash = opaque_tokens.hash_token(raw)
    await stub.insert_token(
        object(),
        employee_id=user["employee_id"],
        token_hash=token_hash,
        purpose=TokenPurpose.REFRESH,
        expires_at=opaque_tokens.utc_now_naive() - timedelta(seconds=1),
    )
    with pytest.raises(AuthenticationError) as exc:
        await svc.refresh(object(), RefreshRequest(refresh_token=raw))
    assert exc.value.status_code == 401
    assert token_hash not in stub.tokens


async def test_logout_revokes_owner_token_and_is_idempotent(
    svc: AuthService, stub: _AuthRepositoryStub
) -> None:
    user = await _seed_member(stub)
    pair = await svc.login(
        object(), LoginRequest(email=user["email"], password=STANTON_DEV_PASSWORD)
    )
    await svc.logout(
        object(),
        employee_id=user["employee_id"],
        payload=RefreshRequest(refresh_token=pair.refresh_token),
    )
    assert opaque_tokens.hash_token(pair.refresh_token) not in stub.tokens
    await svc.logout(  # unknown token → still silent (204 at the router)
        object(),
        employee_id=user["employee_id"],
        payload=RefreshRequest(refresh_token=pair.refresh_token),
    )


async def test_logout_cannot_revoke_other_users_token(
    svc: AuthService, stub: _AuthRepositoryStub
) -> None:
    first = await _seed_member(stub)
    stub.seed_user("second@example.com", "hash")
    second_id = stub.by_email["second@example.com"]
    pair = await svc.login(
        object(), LoginRequest(email=first["email"], password=STANTON_DEV_PASSWORD)
    )
    await svc.logout(
        object(),
        employee_id=second_id,
        payload=RefreshRequest(refresh_token=pair.refresh_token),
    )
    assert opaque_tokens.hash_token(pair.refresh_token) in stub.tokens


async def test_switch_organization_happy_path(svc: AuthService, stub: _AuthRepositoryStub) -> None:
    user = await _seed_member(stub, org=1, admin=False)
    stub.seed_org(2, name="Second", slug="second")
    stub.seed_membership(user["employee_id"], 2, admin=True)
    pair = await svc.switch_organization(
        object(),
        employee_id=user["employee_id"],
        payload=OrganizationSwitchRequest(organization_id=2),
    )
    from app.core.security import jwt as jwt_security

    payload = jwt_security.decode_access_token(pair.access_token)
    assert payload["org"] == 2
    assert payload["admin"] is True
    assert {o.organization_id for o in pair.organizations} == {1, 2}


async def test_switch_unknown_org_404(svc: AuthService, stub: _AuthRepositoryStub) -> None:
    user = await _seed_member(stub)
    with pytest.raises(NotFoundError):
        await svc.switch_organization(
            object(),
            employee_id=user["employee_id"],
            payload=OrganizationSwitchRequest(organization_id=999),
        )


async def test_switch_non_member_org_403(svc: AuthService, stub: _AuthRepositoryStub) -> None:
    user = await _seed_member(stub, org=1)
    stub.seed_org(2, name="Other", slug="other")
    with pytest.raises(AuthorizationError) as exc:
        await svc.switch_organization(
            object(),
            employee_id=user["employee_id"],
            payload=OrganizationSwitchRequest(organization_id=2),
        )
    assert exc.value.status_code == 403


async def test_login_multiple_memberships_defaults_to_first(
    svc: AuthService, stub: _AuthRepositoryStub
) -> None:
    user = await _seed_member(stub, org=5, admin=False)
    stub.seed_org(2, name="Earlier", slug="earlier")
    stub.seed_membership(user["employee_id"], 2, admin=True)
    pair = await svc.login(
        object(), LoginRequest(email=user["email"], password=STANTON_DEV_PASSWORD)
    )
    from app.core.security import jwt as jwt_security

    payload = jwt_security.decode_access_token(pair.access_token)
    assert payload["org"] == 2  # lowest organization_id wins until switch
