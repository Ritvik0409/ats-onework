"""Budget and project listing correctness — real PostgreSQL required.

The list queries are the part of the API a client trusts most: what a
monthly report shows, and whether paging through a member list ever
terminates.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from decimal import Decimal

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app

pytestmark = pytest.mark.integration


@pytest.fixture
async def clean_db(db_connection) -> AsyncIterator[object]:
    from tests.conftest import truncate_all

    await truncate_all(db_connection)
    yield db_connection
    await truncate_all(db_connection)


@pytest.fixture
async def client(test_database: str) -> AsyncIterator[AsyncClient]:
    from app.core.config import get_settings
    from app.db.pool import close_pool, create_pool

    settings = get_settings()
    settings.database_url = test_database
    pool = create_pool(settings)
    await pool.open()
    try:
        app = create_app()
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            yield http
    finally:
        await close_pool()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _project(client: AsyncClient, headers: dict[str, str], org_id: int, name: str) -> int:
    budget = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "100000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=headers,
    )
    assert budget.status_code == 201, budget.text
    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget.json()["budget_id"], "name": name},
        headers=headers,
    )
    assert project.status_code == 201, project.text
    return project.json()["project_id"]


async def _expense_type(client: AsyncClient, headers: dict[str, str], org_id: int) -> int:
    created = await client.post(
        f"/api/v1/organizations/{org_id}/expense-types",
        json={"name": "Travel", "requires_receipt": False},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    return created.json()["expense_type_id"]


async def test_month_filter_does_not_include_the_next_month(
    clean_db,  # noqa: ARG001
    admin_token: str,
    client: AsyncClient,
) -> None:
    """October must not list a budget that starts on 1 November."""
    headers = _auth(admin_token)
    org_id = 1
    october = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "1000.00", "start_date": "2026-10-01", "end_date": "2026-10-31"},
        headers=headers,
    )
    november = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "2000.00", "start_date": "2026-11-01", "end_date": "2026-11-30"},
        headers=headers,
    )
    assert october.status_code == 201, october.text
    assert november.status_code == 201, november.text

    listed = await client.get(
        f"/api/v1/organizations/{org_id}/budgets", params={"month": "2026-10"}, headers=headers
    )
    assert listed.status_code == 200, listed.text
    ids = [item["budget_id"] for item in listed.json()["items"]]
    assert october.json()["budget_id"] in ids
    assert november.json()["budget_id"] not in ids

    listed_november = await client.get(
        f"/api/v1/organizations/{org_id}/budgets", params={"month": "2026-11"}, headers=headers
    )
    ids_november = [item["budget_id"] for item in listed_november.json()["items"]]
    assert november.json()["budget_id"] in ids_november
    assert october.json()["budget_id"] not in ids_november


async def test_spent_only_counts_expenses_inside_the_budget_period(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """A March expense must not show up as spend against an October budget."""
    headers = _auth(admin_token)
    org_id = 1
    october = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "100000.00", "start_date": "2026-10-01", "end_date": "2026-10-31"},
        headers=headers,
    )
    assert october.status_code == 201, october.text
    budget_id = october.json()["budget_id"]

    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget_id, "name": "October Project"},
        headers=headers,
    )
    assert project.status_code == 201, project.text
    project_id = project.json()["project_id"]
    type_id = await _expense_type(client, headers, org_id)

    for expense_date, amount in (("2026-10-15", "100.00"), ("2026-03-01", "500.00")):
        submitted = await client.post(
            "/api/v1/expenses",
            data={
                "project_id": str(project_id),
                "expense_type_id": str(type_id),
                "amount": amount,
                "expense_date": expense_date,
            },
            headers=_auth(member_token),
        )
        assert submitted.status_code == 201, submitted.text
        approved = await client.post(
            f"/api/v1/expenses/{submitted.json()['expense_id']}/approve",
            json={},
            headers=headers,
        )
        assert approved.status_code == 200, approved.text

    listed = await client.get(
        f"/api/v1/organizations/{org_id}/budgets", params={"month": "2026-10"}, headers=headers
    )
    assert listed.status_code == 200, listed.text
    budget = next(item for item in listed.json()["items"] if item["budget_id"] == budget_id)
    # Only the October expense counts.
    assert Decimal(str(budget["spent"])) == Decimal("100.00")


async def test_project_member_pagination_advances(
    clean_db,  # noqa: ARG001
    admin_token: str,
    client: AsyncClient,
) -> None:
    """Following the member cursor must not return the same page forever."""
    headers = _auth(admin_token)
    org_id = 1
    project_id = await _project(client, headers, org_id, "Paging Project")

    role = await client.post(
        f"/api/v1/organizations/{org_id}/roles",
        json={"name": "employee", "description": "Default member role"},
        headers=headers,
    )
    assert role.status_code == 201, role.text
    role_id = role.json()["role_id"]

    # Add enough people to the organization to need more than one page.
    employee_ids: list[int] = []
    for index in range(3):
        registered = await client.post(
            "/api/v1/auth/register",
            json={
                "name": f"Paging {index}",
                "email": f"paging-{index}@example.com",
                "password": "StrongPass1!",
            },
        )
        assert registered.status_code == 201, registered.text
        employee_ids.append(registered.json()["employee_id"])
        added = await client.post(
            f"/api/v1/organizations/{org_id}/members",
            json={"employee_id": registered.json()["employee_id"], "is_admin": False},
            headers=headers,
        )
        assert added.status_code == 201, added.text

    for employee_id in employee_ids:
        added = await client.post(
            f"/api/v1/projects/{project_id}/members",
            json={"employee_id": employee_id, "role_id": role_id},
            headers=headers,
        )
        assert added.status_code == 201, added.text

    first = await client.get(
        f"/api/v1/projects/{project_id}/members", params={"limit": 1}, headers=headers
    )
    assert first.status_code == 200, first.text
    body = first.json()
    assert len(body["items"]) == 1
    assert body["next_cursor"] is not None

    second = await client.get(
        f"/api/v1/projects/{project_id}/members",
        params={"limit": 1, "cursor": body["next_cursor"]},
        headers=headers,
    )
    assert second.status_code == 200, second.text
    second_ids = [item["project_member_id"] for item in second.json()["items"]]
    first_ids = [item["project_member_id"] for item in body["items"]]
    assert second_ids != first_ids, "the second page repeated the first"

    # And the whole list is reachable by paging.
    seen: set[int] = set()
    cursor: str | None = None
    for _ in range(10):
        params = {"limit": 1}
        if cursor is not None:
            params["cursor"] = cursor
        page = await client.get(
            f"/api/v1/projects/{project_id}/members", params=params, headers=headers
        )
        assert page.status_code == 200, page.text
        items = page.json()["items"]
        if not items:
            break
        seen.update(item["project_member_id"] for item in items)
        cursor = page.json()["next_cursor"]
        if cursor is None:
            break
    assert len(seen) == 3
