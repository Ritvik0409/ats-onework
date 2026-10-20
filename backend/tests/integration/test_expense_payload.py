"""Expense submission and review behaviour — real PostgreSQL required.

Covers the behaviours that only show up against a real database and a
real HTTP request: the payload rules, the receipt rules, and the
workflow guards.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app

pytestmark = pytest.mark.integration

JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00"
HTML_BYTES = b"<!DOCTYPE html><html><script>alert(1)</script></html>"


@pytest.fixture
async def clean_db(db_connection) -> AsyncIterator[object]:
    from tests.conftest import truncate_all

    await truncate_all(db_connection)
    yield db_connection
    await truncate_all(db_connection)


@pytest.fixture
async def client(test_database: str) -> AsyncIterator[AsyncClient]:
    """HTTP client whose app carries a real pool pointed at the throwaway DB."""
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


async def _setup(
    client: AsyncClient, admin_headers: dict[str, str], requires_receipt: bool = False
) -> tuple[int, int]:
    """Create a budget, a project and an expense type; return their ids."""
    org_id = 1
    budget = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "10000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=admin_headers,
    )
    assert budget.status_code == 201, budget.text
    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget.json()["budget_id"], "name": "Payload Project"},
        headers=admin_headers,
    )
    assert project.status_code == 201, project.text
    etype = await client.post(
        f"/api/v1/organizations/{org_id}/expense-types",
        json={"name": "Travel", "requires_receipt": requires_receipt, "default_limit": "5000.00"},
        headers=admin_headers,
    )
    assert etype.status_code == 201, etype.text
    return project.json()["project_id"], etype.json()["expense_type_id"]


async def test_non_finite_amount_is_a_422_not_a_500(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    project_id, type_id = await _setup(client, _auth(admin_token))
    for amount in ("NaN", "Infinity", "-Infinity"):
        response = await client.post(
            "/api/v1/expenses",
            data={
                "project_id": str(project_id),
                "expense_type_id": str(type_id),
                "amount": amount,
                "expense_date": "2026-10-20",
            },
            files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
            headers=_auth(member_token),
        )
        assert response.status_code == 422, f"{amount}: {response.text}"


async def test_html_named_as_a_receipt_is_rejected(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """A part that lies about its type must not reach the disk."""
    project_id, type_id = await _setup(client, _auth(admin_token))
    response = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", HTML_BYTES, "image/jpeg")},
        headers=_auth(member_token),
    )
    assert response.status_code == 422, response.text


async def test_stored_receipt_keeps_a_server_chosen_extension(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    project_id, type_id = await _setup(client, _auth(admin_token))
    response = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("evil.html", JPEG_BYTES, "image/jpeg")},
        headers=_auth(member_token),
    )
    assert response.status_code == 201, response.text
    receipt_url = response.json()["receipts"][0]["receipt_url"]
    assert receipt_url.endswith(".jpg")
    assert ".html" not in receipt_url


async def test_description_is_stored_and_returned(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """The text the employee types must survive the round trip."""
    project_id, type_id = await _setup(client, _auth(admin_token))
    response = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
            "description": "Taxi to the client office",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(member_token),
    )
    assert response.status_code == 201, response.text
    assert response.json()["description"] == "Taxi to the client office"

    listed = await client.get("/api/v1/expenses", headers=_auth(admin_token))
    assert listed.status_code == 200, listed.text
    assert listed.json()["items"][0]["description"] == "Taxi to the client office"


async def test_expense_list_carries_the_names_it_refers_to(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """A client cannot resolve the submitter or the category from ids alone."""
    project_id, type_id = await _setup(client, _auth(admin_token))
    await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(member_token),
    )
    listed = await client.get("/api/v1/expenses", headers=_auth(admin_token))
    assert listed.status_code == 200, listed.text
    item = listed.json()["items"][0]
    assert item["employee_name"] == "a member"
    assert item["employee_email"].endswith("@test.invalid")
    assert item["project_name"] == "Payload Project"
    assert item["expense_type_name"] == "Travel"
    assert item["employee_id"] > 0


async def test_expense_type_receipt_requirement_is_enforced(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    project_id, type_id = await _setup(client, _auth(admin_token), requires_receipt=True)
    response = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        headers=_auth(member_token),
    )
    assert response.status_code == 422, response.text


async def test_expense_type_limit_is_enforced(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    project_id, type_id = await _setup(client, _auth(admin_token))
    response = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "9000.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(member_token),
    )
    assert response.status_code == 422, response.text


async def test_long_rejection_comment_is_accepted(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """A 2000-character comment used to overflow the column and 500."""
    project_id, type_id = await _setup(client, _auth(admin_token))
    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(member_token),
    )
    assert submitted.status_code == 201, submitted.text
    expense_id = submitted.json()["expense_id"]

    comment = "Needs more detail. " * 104 + "x" * 24
    assert len(comment) == 2000
    rejected = await client.post(
        f"/api/v1/expenses/{expense_id}/reject",
        json={"comments": comment},
        headers=_auth(admin_token),
    )
    assert rejected.status_code == 200, rejected.text
    assert len(rejected.json()["rejection_reason"]) == 2000


async def test_rejection_comment_longer_than_the_limit_is_a_422(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """Beyond the limit the request is rejected cleanly, not with a 500."""
    project_id, type_id = await _setup(client, _auth(admin_token))
    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(member_token),
    )
    assert submitted.status_code == 201, submitted.text
    expense_id = submitted.json()["expense_id"]

    rejected = await client.post(
        f"/api/v1/expenses/{expense_id}/reject",
        json={"comments": "x" * 2001},
        headers=_auth(admin_token),
    )
    assert rejected.status_code == 422, rejected.text


async def test_admin_cannot_review_their_own_expense(
    clean_db,  # noqa: ARG001
    admin_token: str,
    client: AsyncClient,
) -> None:
    """Segregation of duties: nobody approves their own expense."""
    project_id, type_id = await _setup(client, _auth(admin_token))
    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(admin_token),
    )
    assert submitted.status_code == 201, submitted.text
    expense_id = submitted.json()["expense_id"]

    approved = await client.post(
        f"/api/v1/expenses/{expense_id}/approve", json={}, headers=_auth(admin_token)
    )
    assert approved.status_code == 403, approved.text


async def test_info_request_round_trip_keeps_the_question_and_the_answer(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    project_id, type_id = await _setup(client, _auth(admin_token))
    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(member_token),
    )
    assert submitted.status_code == 201, submitted.text
    expense_id = submitted.json()["expense_id"]

    asked = await client.post(
        f"/api/v1/expenses/{expense_id}/request-info",
        json={"comments": "Where is the invoice?"},
        headers=_auth(admin_token),
    )
    assert asked.status_code == 200, asked.text
    assert asked.json()["info_message"] == "Where is the invoice?"

    answered = await client.post(
        f"/api/v1/expenses/{expense_id}/resubmit",
        json={"response": "Invoice attached, dated today."},
        headers=_auth(member_token),
    )
    assert answered.status_code == 200, answered.text
    body = answered.json()
    assert body["status"] == "pending"
    # The question survives, and so does the answer.
    assert body["info_message"] == "Where is the invoice?"
    assert body["info_response"] == "Invoice attached, dated today."


async def test_marking_a_notification_read_twice_is_not_an_error(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """Marking read is idempotent — a retry must not turn into a 404."""
    project_id, type_id = await _setup(client, _auth(admin_token))
    await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project_id),
            "expense_type_id": str(type_id),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        files={"files": ("receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=_auth(member_token),
    )
    listed = await client.get("/api/v1/notifications", headers=_auth(admin_token))
    assert listed.status_code == 200, listed.text
    items = listed.json()["items"]
    assert items, "the admin should have been notified about the submission"
    notification_id = items[0]["notification_id"]
    first = await client.post(
        f"/api/v1/notifications/{notification_id}/read", headers=_auth(admin_token)
    )
    second = await client.post(
        f"/api/v1/notifications/{notification_id}/read", headers=_auth(admin_token)
    )
    assert first.status_code == 204, first.text
    assert second.status_code == 204, second.text


async def test_audit_log_is_scoped_to_the_organization(
    clean_db,  # noqa: ARG001
    admin_token: str,
    other_org_admin_token: str,
    client: AsyncClient,
) -> None:
    """Audit rows belong to an organization, not to the actor's memberships."""
    logs = await client.get("/api/v1/audit-logs", headers=_auth(admin_token))
    assert logs.status_code == 200, logs.text
    for item in logs.json()["items"]:
        assert item["organization_id"] == 1

    other = await client.get("/api/v1/audit-logs", headers=_auth(other_org_admin_token))
    assert other.status_code == 200, other.text
    for item in other.json()["items"]:
        assert item["organization_id"] == 2
