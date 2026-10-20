"""Who can see what — the capability model in action (real PostgreSQL).

An employee holds ``expense.read_own`` and not ``expense.read_all``:
they see their own expenses and nothing else. A manager holds both and
sees the whole organization. The scope is decided by the capability, in
the database — not by the client asking nicely.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app

pytestmark = pytest.mark.integration

JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00"


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


async def _setup(client: AsyncClient, admin_headers: dict[str, str]) -> tuple[int, int]:
    """A project and an expense type to submit against."""
    org_id = 1
    budget = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "10000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=admin_headers,
    )
    assert budget.status_code == 201, budget.text
    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget.json()["budget_id"], "name": "Scope Project"},
        headers=admin_headers,
    )
    assert project.status_code == 201, project.text
    etype = await client.post(
        f"/api/v1/organizations/{org_id}/expense-types",
        json={"name": "Travel", "requires_receipt": False},
        headers=admin_headers,
    )
    assert etype.status_code == 201, etype.text
    return project.json()["project_id"], etype.json()["expense_type_id"]


async def test_an_employee_sees_only_their_own_expenses(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """The member submits one; the admin submits another. Each sees one."""
    admin_headers = _auth(admin_token)
    project_id, type_id = await _setup(client, admin_headers)

    for token in (member_token, admin_token):
        submitted = await client.post(
            "/api/v1/expenses",
            data={
                "project_id": str(project_id),
                "expense_type_id": str(type_id),
                "amount": "250.00",
                "expense_date": "2026-10-20",
            },
            headers=_auth(token),
        )
        assert submitted.status_code == 201, submitted.text

    member_view = await client.get("/api/v1/expenses", headers=_auth(member_token))
    assert member_view.status_code == 200, member_view.text
    member_items = member_view.json()["items"]
    assert len(member_items) == 1, "an employee must not see their colleagues' expenses"
    assert member_items[0]["employee_name"] == "a member"

    admin_view = await client.get("/api/v1/expenses", headers=_auth(admin_token))
    assert admin_view.status_code == 200, admin_view.text
    # The administrator holds expense.read_all, so they see both.
    assert len(admin_view.json()["items"]) == 2


async def test_an_employee_cannot_read_a_colleagues_expense(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """A colleague's expense is a 404, not a 403 — it must not even be
    possible to find out that the id exists."""
    admin_headers = _auth(admin_token)
    project_id, type_id = await _setup(client, admin_headers)

    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        headers=_auth(admin_token),
    )
    assert submitted.status_code == 201, submitted.text
    expense_id = submitted.json()["expense_id"]

    read = await client.get(f"/api/v1/expenses/{expense_id}", headers=_auth(member_token))
    assert read.status_code == 404, read.text


async def test_an_employee_cannot_use_an_organizational_endpoint(
    clean_db,  # noqa: ARG001
    member_token: str,
    client: AsyncClient,
) -> None:
    """The member directory is a management surface."""
    denied = await client.get("/api/v1/users", headers=_auth(member_token))
    assert denied.status_code == 403, denied.text


async def test_an_employee_cannot_approve_an_expense(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """Holding expense.read_own does not open the review queue."""
    admin_headers = _auth(admin_token)
    project_id, type_id = await _setup(client, admin_headers)
    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        headers=_auth(admin_token),
    )
    assert submitted.status_code == 201, submitted.text

    queue = await client.get("/api/v1/approvals/pending", headers=_auth(member_token))
    assert queue.status_code == 403, queue.text


async def test_withdrawing_a_grant_takes_effect_immediately(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """The guard reads the database on every request, so a grant that is
    taken away applies at once — not when the token expires."""
    admin_headers = _auth(admin_token)
    org_id = seeded_orgs["a"]["organization_id"]
    member_id = seeded_orgs["a"]["users"]["member"]["employee_id"]

    before = await client.get("/api/v1/users", headers=_auth(member_token))
    assert before.status_code == 403, before.text

    # Give the member the capability directly.
    granted = await client.put(
        f"/api/v1/organizations/{org_id}/access/members/{member_id}/permissions",
        json={"permissions": ["user.read"]},
        headers=admin_headers,
    )
    assert granted.status_code == 200, granted.text

    after = await client.get("/api/v1/users", headers=_auth(member_token))
    assert after.status_code == 200, after.text

    # And take it away again.
    revoked = await client.put(
        f"/api/v1/organizations/{org_id}/access/members/{member_id}/permissions",
        json={"permissions": []},
        headers=admin_headers,
    )
    assert revoked.status_code == 200, revoked.text

    final = await client.get("/api/v1/users", headers=_auth(member_token))
    assert final.status_code == 403, final.text


async def test_the_member_can_see_what_they_can_do(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    """The access endpoint reports a member's effective capabilities."""
    admin_headers = _auth(admin_token)
    org_id = seeded_orgs["a"]["organization_id"]
    member_id = seeded_orgs["a"]["users"]["member"]["employee_id"]

    access = await client.get(
        f"/api/v1/organizations/{org_id}/access/members/{member_id}",
        headers=admin_headers,
    )
    assert access.status_code == 200, access.text
    body = access.json()
    assert body["roles"] == ["employee"]
    assert "expense.read_own" in body["effective_permissions"]
    assert "expense.read_all" not in body["effective_permissions"]
    assert "expense.approve" not in body["effective_permissions"]
