"""HTTP contract tests for the business-gap endpoints — no database.

Pins router wiring, auth levels, and status codes (200/201/204/422/409)
for the §49 additions from the business-gap batch:

- ``POST /expenses/{id}/request-info``   (admin)  → 200
- ``POST /expenses/{id}/resubmit``       (member) → 200
- ``GET  /organizations/{id}/budgets``   (member) → 200 (Page envelope)
- ``PATCH /organizations/{id}/budgets/{budget_id}`` (admin) → 200
- ``GET /projects/{id}/members``         (member) → 200
- ``POST /projects/{id}/members``        (admin)  → 201
- ``DELETE /projects/{id}/members/{employee_id}`` (admin) → 204

Services are monkeypatched, so only the HTTP layer is under test here;
service logic lives in the matching unit-test files.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.v1 import deps as deps_module
from app.api.v1.deps import CurrentUser
from app.budgets import service as budget_service_module
from app.budgets.schemas import BudgetResponse
from app.common import permissions as permissions_module
from app.core.exceptions import ConflictError, NotFoundError
from app.db.connection import get_connection
from app.expenses import service as expense_service_module
from app.expenses.schemas import ExpenseResponse
from app.main import create_app
from app.projects import service as project_service_module
from app.projects.schemas import ProjectMemberListItem

AUTH_ADMIN = CurrentUser(employee_id=1, organization_id=10, is_admin=True)
AUTH_MEMBER = CurrentUser(employee_id=2, organization_id=10, is_admin=False)


def _now() -> str:
    return "2026-10-18T00:00:00"


def _expense_dict(status: str = "info_requested") -> dict[str, Any]:
    return {
        "expense_id": 7,
        "employee_id": 2,
        "project_id": 100,
        "organization_id": 10,
        "expense_type_id": 3,
        "amount": "1200.50",
        "status": status,
        "rejection_reason": None,
        "expense_date": "2026-10-01",
        "submission_date": _now(),
        "updated_at": _now(),
        "info_message": "Attach itemized receipt",
        "info_requested_at": _now(),
        "receipts": [],
    }


def _budget_dict(budget_id: int = 50) -> dict[str, Any]:
    return {
        "budget_id": budget_id,
        "amount": "60000.00",
        "employee_id": 1,
        "organization_id": 10,
        "start_date": "2026-10-01",
        "end_date": "2026-10-31",
        "created_at": _now(),
        "updated_at": _now(),
        "spent": "12400.00",
    }


def _member_dict(employee_id: int = 5) -> dict[str, Any]:
    return {
        "project_member_id": 900,
        "project_id": 100,
        "employee_id": employee_id,
        "employee_name": f"User {employee_id}",
        "employee_email": f"user{employee_id}@example.com",
        "role_id": 11,
        "role_name": "employee",
    }


def _project_dict() -> dict[str, Any]:
    return {
        "project_id": 100,
        "budget_id": 50,
        "name": "Website Revamp",
        "description": None,
        "is_active": True,
        "start_date": None,
        "end_date": None,
        "created_at": _now(),
        "updated_at": _now(),
        "budget_amount": "60000.00",
        "member_count": 1,
    }


@pytest.fixture
def admin_client(monkeypatch: pytest.MonkeyPatch) -> AsyncClient:
    return _make_client(monkeypatch, AUTH_ADMIN)


@pytest.fixture
def member_client(monkeypatch: pytest.MonkeyPatch) -> AsyncClient:
    return _make_client(monkeypatch, AUTH_MEMBER)


def _make_client(monkeypatch: pytest.MonkeyPatch, user: CurrentUser) -> AsyncClient:
    app = create_app()

    async def _dummy_conn() -> AsyncIterator[Any]:
        yield object()

    app.dependency_overrides[get_connection] = _dummy_conn
    app.dependency_overrides[deps_module.get_current_user] = lambda: user

    # The route guards ask the database what the caller may do. These
    # tests are about the HTTP contract, not about access, so the
    # lookup is stubbed to grant everything.
    class _AllGranted:
        def __contains__(self, item: object) -> bool:
            return True

    async def _all_granted(
        _conn: Any,
        *,
        employee_id: int,  # noqa: ARG001
        organization_id: int,  # noqa: ARG001
    ) -> _AllGranted:
        return _AllGranted()

    monkeypatch.setattr(permissions_module, "granted_permissions", _all_granted)
    app.dependency_overrides[deps_module.require_membership] = lambda: user
    app.dependency_overrides[deps_module.require_admin] = lambda: user

    # Patch the shared service instances (routers hold references to them).
    expense_svc = expense_service_module.service

    async def _request_info(_conn: Any, **_kwargs: Any) -> ExpenseResponse:
        return ExpenseResponse.model_validate(_expense_dict())

    async def _resubmit(_conn: Any, **_kwargs: Any) -> ExpenseResponse:
        return ExpenseResponse.model_validate(_expense_dict("pending"))

    monkeypatch.setattr(expense_svc, "request_info", _request_info)
    monkeypatch.setattr(expense_svc, "resubmit", _resubmit)

    budget_svc = budget_service_module.service

    async def _list_budgets(_conn: Any, **_kwargs: Any) -> list[BudgetResponse]:
        return [BudgetResponse.model_validate(_budget_dict())]

    async def _update_budget(_conn: Any, **kwargs: Any) -> BudgetResponse:
        row = _budget_dict(kwargs["budget_id"])
        payload = kwargs["payload"]
        if payload.amount is not None:
            row["amount"] = str(payload.amount)
        return BudgetResponse.model_validate(row)

    monkeypatch.setattr(budget_svc, "list_budgets", _list_budgets)
    monkeypatch.setattr(budget_svc, "update_budget", _update_budget)

    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


@pytest.fixture
def members_stub(monkeypatch: pytest.MonkeyPatch) -> dict[str, list[dict[str, Any]]]:
    """State shared by the patched project member service methods."""
    store: dict[str, list[dict[str, Any]]] = {"members": [_member_dict(5)]}

    svc = project_service_module.service

    async def _list(_conn: Any, **_kwargs: Any) -> list[ProjectMemberListItem]:
        return [ProjectMemberListItem.model_validate(r) for r in store["members"]]

    async def _add(_conn: Any, **kwargs: Any) -> ProjectMemberListItem:
        payload = kwargs["payload"]
        if payload.employee_id in [m["employee_id"] for m in store["members"]]:
            raise ConflictError("Employee is already a member of this project.")
        row = _member_dict(payload.employee_id)
        store["members"].append(row)
        return ProjectMemberListItem.model_validate(row)

    async def _remove(_conn: Any, **kwargs: Any) -> None:
        before = len(store["members"])
        store["members"] = [
            m for m in store["members"] if m["employee_id"] != kwargs["target_employee_id"]
        ]
        if len(store["members"]) == before:
            raise NotFoundError("Employee is not a member of this project.")

    monkeypatch.setattr(svc, "list_members", _list)
    monkeypatch.setattr(svc, "add_member", _add)
    monkeypatch.setattr(svc, "remove_member", _remove)
    return store


# -- expenses: request-info / resubmit --------------------------------------


async def test_request_info_contract(admin_client: AsyncClient) -> None:
    async with admin_client as client:
        response = await client.post(
            "/api/v1/expenses/7/request-info", json={"comments": "Attach itemized receipt"}
        )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "info_requested"
    assert body["info_message"] == "Attach itemized receipt"


async def test_resubmit_contract(admin_client: AsyncClient) -> None:
    async with admin_client as client:
        response = await client.post("/api/v1/expenses/7/resubmit")
    assert response.status_code == 200
    assert response.json()["status"] == "pending"


# -- budgets ----------------------------------------------------------------


async def test_budgets_list_and_patch_contract(admin_client: AsyncClient) -> None:
    async with admin_client as client:
        listed = await client.get(
            "/api/v1/organizations/10/budgets",
            params={"month": "2026-10"},
        )
        assert listed.status_code == 200
        page = listed.json()
        assert page["items"][0]["spent"] == "12400.00"

        patched = await client.patch(
            "/api/v1/organizations/10/budgets/50",
            json={"amount": "75000.00"},
        )
        assert patched.status_code == 200
        assert patched.json()["amount"] == "75000.00"


async def test_budget_patch_invalid_body_422(admin_client: AsyncClient) -> None:
    async with admin_client as client:
        response = await client.patch(
            "/api/v1/organizations/10/budgets/50",
            json={"amount": "-5"},
        )
    assert response.status_code == 422


# -- project members ----------------------------------------------------------


async def test_members_list_contract(
    admin_client: AsyncClient, members_stub: dict[str, list[dict[str, Any]]]
) -> None:
    async with admin_client as client:
        response = await client.get("/api/v1/projects/100/members")
    assert response.status_code == 200
    assert response.json()["items"][0]["employee_id"] == 5
    assert len(members_stub["members"]) == 1


async def test_member_add_and_remove_contract(
    admin_client: AsyncClient, members_stub: dict[str, list[dict[str, Any]]]
) -> None:
    async with admin_client as client:
        added = await client.post("/api/v1/projects/100/members", json={"employee_id": 6})
        assert added.status_code == 201
        assert added.json()["employee_id"] == 6

        duplicate = await client.post("/api/v1/projects/100/members", json={"employee_id": 6})
        assert duplicate.status_code == 409

        removed = await client.delete("/api/v1/projects/100/members/6")
        assert removed.status_code == 204

        gone = await client.delete("/api/v1/projects/100/members/6")
        assert gone.status_code == 404
    assert [m["employee_id"] for m in members_stub["members"]] == [5]
