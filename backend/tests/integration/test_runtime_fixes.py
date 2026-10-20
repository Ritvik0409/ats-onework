"""Runtime regression tests (2026-10-20 live-app session, §41).

Cases unit fakes cannot prove because they never send SQL to a real
planner — each corresponds to a 4xx/5xx the running app produced:

1. Budget create/update RETURNING clauses: the SELECT block is
   alias-prefixed (``b.budget_id``); a plain ``INSERT INTO budgets ...``
   RETURNING that shape dies with ``missing FROM-clause entry``.
2. Access-request queue: bare ``project_id`` in the joined SELECT is
   ambiguous once ``projects`` joins in.
3. Receipt upload: Flutter sends ``application/octet-stream`` with a
   ``receipt.jpg`` filename; the type check must fall back to the
   filename or every expense with a receipt is rejected.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app

pytestmark = pytest.mark.integration


@pytest.fixture
async def clean_db(db_connection):
    from tests.conftest import truncate_all

    await truncate_all(db_connection)
    yield db_connection
    await truncate_all(db_connection)


@pytest.fixture
async def client(test_database: str) -> AsyncIterator[AsyncClient]:
    """HTTP client whose app carries a real pool pointed at the throwaway DB.

    The shared ``test_client`` fixture deliberately skips lifespan (pool is
    process-global), so this fixture wires the pool itself from Settings —
    same pattern as the dev server, different DSN.
    """
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


async def test_budget_create_list_and_patch_round_trip(
    clean_db,  # noqa: ARG001 — truncate side effect, value unused
    admin_token: str,
    client: AsyncClient,
    seeded_orgs: dict,
) -> None:
    org_id = seeded_orgs["a"]["organization_id"]
    headers = _auth(admin_token)

    created = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "50000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert float(body["amount"]) == 50000.00
    assert float(body["spent"]) == 0.00

    listed = await client.get(f"/api/v1/organizations/{org_id}/budgets", headers=headers)
    assert listed.status_code == 200
    assert any(item["budget_id"] == body["budget_id"] for item in listed.json()["items"])

    patched = await client.patch(
        f"/api/v1/organizations/{org_id}/budgets/{body['budget_id']}",
        json={"amount": "60000.00"},
        headers=headers,
    )
    assert patched.status_code == 200, patched.text
    assert float(patched.json()["amount"]) == 60000.00


async def test_access_request_queue_join_and_create(
    clean_db,  # noqa: ARG001 — truncate side effect, value unused
    admin_token: str,
    member_token: str,
    client: AsyncClient,
    seeded_orgs: dict,
) -> None:
    org_id = seeded_orgs["a"]["organization_id"]
    admin_headers = _auth(admin_token)
    member_headers = _auth(member_token)

    budget = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "10000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=admin_headers,
    )
    assert budget.status_code == 201, budget.text
    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget.json()["budget_id"], "name": "Runtime Project"},
        headers=admin_headers,
    )
    assert project.status_code == 201, project.text
    project_id = project.json()["project_id"]

    # The exact request that returned a 500 before the fix: joined SELECT.
    queue = await client.get(
        "/api/v1/access-requests",
        params={"status": "pending"},
        headers=admin_headers,
    )
    assert queue.status_code == 200, queue.text
    assert queue.json()["items"] == []

    requested = await client.post(
        f"/api/v1/projects/{project_id}/access-requests", headers=member_headers
    )
    assert requested.status_code == 201, requested.text

    queue = await client.get(
        "/api/v1/access-requests", params={"status": "pending"}, headers=admin_headers
    )
    assert queue.status_code == 200, queue.text
    items = queue.json()["items"]
    assert len(items) == 1
    assert items[0]["project_name"] == "Runtime Project"
    assert items[0]["organization_id"] == org_id


async def test_project_member_add_and_remove(
    clean_db,  # noqa: ARG001 — truncate side effect, value unused
    admin_token: str,
    client: AsyncClient,
    seeded_orgs: dict,
) -> None:
    org_id = seeded_orgs["a"]["organization_id"]
    member_id = seeded_orgs["a"]["users"]["member"]["employee_id"]
    admin_headers = _auth(admin_token)

    admin_headers = _auth(admin_token)

    # Member rows default to the org's 'employee' role — create it first.
    role = await client.post(
        f"/api/v1/organizations/{org_id}/roles",
        json={"name": "employee"},
        headers=admin_headers,
    )
    assert role.status_code == 201, role.text
    budget = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "10000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=admin_headers,
    )
    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget.json()["budget_id"], "name": "Members Project"},
        headers=admin_headers,
    )
    project_id = project.json()["project_id"]

    # The exact request that returned a 500 before the fix: plain INSERT
    # cannot RETURNING joined user/role names.
    added = await client.post(
        f"/api/v1/projects/{project_id}/members",
        json={"employee_id": member_id},
        headers=admin_headers,
    )
    assert added.status_code == 201, added.text
    body = added.json()
    assert body["employee_id"] == member_id
    assert body["role_name"]  # joined from the roles table

    members = await client.get(f"/api/v1/projects/{project_id}/members", headers=admin_headers)
    assert members.status_code == 200
    assert any(item["employee_id"] == member_id for item in members.json()["items"])

    removed = await client.delete(
        f"/api/v1/projects/{project_id}/members/{member_id}", headers=admin_headers
    )
    assert removed.status_code in (200, 204), removed.text


async def test_receipt_upload_accepts_generic_type_with_jpg_name(
    clean_db,  # noqa: ARG001 — truncate side effect, value unused
    admin_token: str,
    member_token: str,
    client: AsyncClient,
    seeded_orgs: dict,
) -> None:
    org_id = seeded_orgs["a"]["organization_id"]
    admin_headers = _auth(admin_token)
    member_headers = _auth(member_token)

    budget = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "10000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=admin_headers,
    )
    assert budget.status_code == 201, budget.text
    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget.json()["budget_id"], "name": "Receipt Project"},
        headers=admin_headers,
    )
    etype = await client.post(
        f"/api/v1/organizations/{org_id}/expense-types",
        json={"name": "Travel", "requires_receipt": True, "default_limit": "5000.00"},
        headers=admin_headers,
    )
    assert project.status_code == 201 and etype.status_code == 201

    # Deliberately generic content type + real-jpeg bytes: the contract the
    # Flutter client actually exhibits (§49 #27). Must be accepted, not 422.
    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project.json()["project_id"]),
            "expense_type_id": str(etype.json()["expense_type_id"]),
            "amount": "250.00",
            "expense_date": "2026-10-20",
            "description": "Receipt upload regression",
        },
        files={
            "files": (
                "receipt.jpg",
                b"\xff\xd8\xff\xe0JPEGMAGIC",
                "application/octet-stream",
            )
        },
        headers=member_headers,
    )
    assert submitted.status_code == 201, submitted.text
    media = submitted.json().get("media") or submitted.json().get("receipts") or []
    assert len(media) == 1
    assert media[0]["receipt_url"]

    # A truly unknown extension stays rejected even with a generic type.
    bad = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project.json()["project_id"]),
            "expense_type_id": str(etype.json()["expense_type_id"]),
            "amount": "250.00",
            "expense_date": "2026-10-20",
            "description": "Bad extension still rejected",
        },
        files={"files": ("payload.exe", b"MZ", "application/octet-stream")},
        headers=member_headers,
    )
    assert bad.status_code == 422
