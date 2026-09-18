"""HTTP contract tests for §49 #3-20 — no database required.

The app is exercised over ASGI with ``get_connection`` overridden to a dummy,
auth dependencies overridden to a fixed admin context, and service methods
monkeypatched, so these tests pin router wiring, auth levels, and status
codes (201/200/204/401/403/404/422) plus the shared error envelope —
without touching PostgreSQL.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.v1 import deps as deps_module
from app.api.v1.deps import CurrentUser
from app.auth import router as auth_router_module
from app.auth.schemas import TokenPair, UserResponse
from app.common.pagination import Page
from app.core.exceptions import NotFoundError
from app.db.connection import get_connection
from app.main import create_app
from app.organizations import router as org_router_module
from app.organizations.schemas import (
    MembershipResponse,
    OrganizationResponse,
    RoleResponse,
)
from app.users import router as users_router_module
from app.users.schemas import EmployeeStatusResponse, UserListItem

AUTH_USER = CurrentUser(employee_id=1, organization_id=10, is_admin=True)


def _now() -> str:
    return "2026-09-18T00:00:00"


def _user_dict() -> dict[str, Any]:
    return {
        "employee_id": 1,
        "name": "Asha Admin",
        "email": "admin@acme.test",
        "account_status": "active",
        "is_superuser": False,
        "last_login_at": None,
        "created_at": _now(),
        "updated_at": _now(),
    }


def _pair_dict() -> dict[str, Any]:
    return {
        "access_token": "access",
        "refresh_token": "refresh",
        "token_type": "bearer",
        "expires_in": 1800,
        "organizations": [
            {"organization_id": 10, "name": "Acme", "slug": "acme", "is_admin": True}
        ],
    }


def _org_dict() -> dict[str, Any]:
    return {
        "organization_id": 10,
        "name": "Acme",
        "slug": "acme",
        "description": None,
        "is_system": False,
        "is_active": True,
        "created_at": _now(),
        "updated_at": _now(),
    }


def _list_item() -> dict[str, Any]:
    return {
        "employee_id": 1,
        "name": "Asha Admin",
        "email": "admin@acme.test",
        "account_status": "active",
    }


def _status_dict() -> dict[str, Any]:
    return {
        "status_id": 1,
        "employee_id": 1,
        "status": "active",
        "started_at": _now(),
        "ended_at": None,
        "updated_by": 1,
    }


def _membership_dict() -> dict[str, Any]:
    return {
        "membership_id": 1,
        "employee_id": 2,
        "organization_id": 10,
        "is_admin": False,
        "joined_at": _now(),
        "updated_at": _now(),
    }


def _role_dict() -> dict[str, Any]:
    return {
        "role_id": 1,
        "name": "manager",
        "organization_id": 10,
        "description": None,
        "is_active": True,
        "created_at": _now(),
        "updated_at": _now(),
    }


@pytest.fixture
def app_with_overrides(monkeypatch: pytest.MonkeyPatch) -> Any:
    app = create_app()

    async def _dummy_conn() -> AsyncIterator[Any]:
        yield object()

    app.dependency_overrides[get_connection] = _dummy_conn
    app.dependency_overrides[deps_module.get_current_user] = lambda: AUTH_USER
    app.dependency_overrides[deps_module.require_membership] = lambda: AUTH_USER
    app.dependency_overrides[deps_module.require_admin] = lambda: AUTH_USER

    async def _register(_conn: Any, _payload: Any) -> UserResponse:
        return UserResponse.model_validate(_user_dict())

    async def _login(_conn: Any, _payload: Any) -> TokenPair:
        return TokenPair.model_validate(_pair_dict())

    async def _refresh(_conn: Any, _payload: Any) -> TokenPair:
        return TokenPair.model_validate(_pair_dict())

    async def _logout(_conn: Any, **_kwargs: Any) -> None:
        return None

    async def _switch(_conn: Any, **_kwargs: Any) -> TokenPair:
        return TokenPair.model_validate(_pair_dict())

    auth_svc = auth_router_module.auth_service
    monkeypatch.setattr(auth_svc, "register", _register)
    monkeypatch.setattr(auth_svc, "login", _login)
    monkeypatch.setattr(auth_svc, "refresh", _refresh)
    monkeypatch.setattr(auth_svc, "logout", _logout)
    monkeypatch.setattr(auth_svc, "switch_organization", _switch)

    async def _get_me(_conn: Any, _employee_id: int) -> UserResponse:
        return UserResponse.model_validate(_user_dict())

    async def _list_users(_conn: Any, **_kwargs: Any) -> Page[UserListItem]:
        return Page(items=[UserListItem.model_validate(_list_item())])

    async def _update_user(_conn: Any, **_kwargs: Any) -> UserResponse:
        return UserResponse.model_validate(_user_dict())

    async def _list_statuses(_conn: Any, _employee_id: int) -> list[EmployeeStatusResponse]:
        return [EmployeeStatusResponse.model_validate(_status_dict())]

    async def _create_status(_conn: Any, **_kwargs: Any) -> EmployeeStatusResponse:
        payload = _kwargs["payload"]
        row = _status_dict() | {"status": payload.status.value}
        return EmployeeStatusResponse.model_validate(row)

    user_svc = users_router_module.user_service
    monkeypatch.setattr(user_svc, "get_me", _get_me)
    monkeypatch.setattr(user_svc, "list_users", _list_users)
    monkeypatch.setattr(user_svc, "update_user", _update_user)
    monkeypatch.setattr(user_svc, "list_statuses", _list_statuses)
    monkeypatch.setattr(user_svc, "create_status", _create_status)

    async def _org_response(_conn: Any, **_kwargs: Any) -> OrganizationResponse:
        return OrganizationResponse.model_validate(_org_dict())

    async def _list_own(_conn: Any, _employee_id: int) -> list[OrganizationResponse]:
        return [OrganizationResponse.model_validate(_org_dict())]

    async def _add_member(_conn: Any, **_kwargs: Any) -> MembershipResponse:
        return MembershipResponse.model_validate(_membership_dict())

    async def _remove_member(_conn: Any, **_kwargs: Any) -> None:
        return None

    async def _list_roles(_conn: Any, **_kwargs: Any) -> list[RoleResponse]:
        return [RoleResponse.model_validate(_role_dict())]

    async def _create_role(_conn: Any, **_kwargs: Any) -> RoleResponse:
        return RoleResponse.model_validate(_role_dict())

    org_svc = org_router_module.organization_service
    monkeypatch.setattr(org_svc, "create_organization", _org_response)
    monkeypatch.setattr(org_svc, "list_own", _list_own)
    monkeypatch.setattr(org_svc, "get_organization", _org_response)
    monkeypatch.setattr(org_svc, "update_organization", _org_response)
    monkeypatch.setattr(org_svc, "add_member", _add_member)
    monkeypatch.setattr(org_svc, "remove_member", _remove_member)
    monkeypatch.setattr(org_svc, "list_roles", _list_roles)
    monkeypatch.setattr(org_svc, "create_role", _create_role)
    return app


def _make_client(app: Any) -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def test_auth_contract_status_codes(app_with_overrides: Any) -> None:
    async with _make_client(app_with_overrides) as client:
        register = await client.post(
            "/api/v1/auth/register",
            json={"name": "A", "email": "a@example.com", "password": "StrongPass1!"},
        )
        assert register.status_code == 201, register.text
        assert "password_hash" not in register.json()

        login = await client.post(
            "/api/v1/auth/login",
            json={"email": "a@example.com", "password": "StrongPass1!"},
        )
        assert login.status_code == 200, login.text
        assert login.json()["token_type"] == "bearer"

        refresh = await client.post("/api/v1/auth/refresh", json={"refresh_token": "r"})
        assert refresh.status_code == 200, refresh.text

        logout = await client.post("/api/v1/auth/logout", json={"refresh_token": "r"})
        assert logout.status_code == 204, logout.text

        switch = await client.post("/api/v1/auth/switch-organization", json={"organization_id": 10})
        assert switch.status_code == 200, switch.text


async def test_auth_register_422_on_short_password(app_with_overrides: Any) -> None:
    async with _make_client(app_with_overrides) as client:
        response = await client.post(
            "/api/v1/auth/register",
            json={"name": "A", "email": "a@example.com", "password": "short"},
        )
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "validation_error"


async def test_users_contract_status_codes(app_with_overrides: Any) -> None:
    async with _make_client(app_with_overrides) as client:
        assert (await client.get("/api/v1/users/me")).status_code == 200
        assert (await client.get("/api/v1/users")).status_code == 200
        patch = await client.patch("/api/v1/users/1", json={"name": "New"})
        assert patch.status_code == 200, patch.text
        assert (await client.get("/api/v1/users/1/statuses")).status_code == 200
        create = await client.post("/api/v1/users/1/statuses", json={"status": "on_leave"})
        assert create.status_code == 201, create.text
        assert create.json()["status"] == "on_leave"


async def test_organizations_contract_status_codes(app_with_overrides: Any) -> None:
    async with _make_client(app_with_overrides) as client:
        create = await client.post("/api/v1/organizations", json={"name": "Acme Corp"})
        assert create.status_code == 201, create.text
        assert create.json()["slug"] == "acme"

        assert (await client.get("/api/v1/organizations")).status_code == 200
        assert (await client.get("/api/v1/organizations/10")).status_code == 200
        assert (
            await client.patch("/api/v1/organizations/10", json={"name": "Acme 2"})
        ).status_code == 200

        add = await client.post("/api/v1/organizations/10/members", json={"employee_id": 2})
        assert add.status_code == 201, add.text
        remove = await client.delete("/api/v1/organizations/10/members/2")
        assert remove.status_code == 204, remove.text

        assert (await client.get("/api/v1/organizations/10/roles")).status_code == 200
        role = await client.post("/api/v1/organizations/10/roles", json={"name": "manager"})
        assert role.status_code == 201, role.text


async def test_unauthenticated_users_me_401() -> None:
    app = create_app()

    async def _dummy_conn() -> AsyncIterator[Any]:
        yield object()

    app.dependency_overrides[get_connection] = _dummy_conn
    async with _make_client(app) as client:
        response = await client.get("/api/v1/users/me")
        assert response.status_code == 401
        assert "error" in response.json()


async def test_service_not_found_maps_to_envelope(
    app_with_overrides: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def _missing(_conn: Any, **_kwargs: Any) -> Any:
        raise NotFoundError("Organization not found.")

    monkeypatch.setattr(org_router_module.organization_service, "get_organization", _missing)
    async with _make_client(app_with_overrides) as client:
        response = await client.get("/api/v1/organizations/999")
        assert response.status_code == 404
        assert response.json() == {
            "error": {"code": "not_found", "message": "Organization not found."}
        }
