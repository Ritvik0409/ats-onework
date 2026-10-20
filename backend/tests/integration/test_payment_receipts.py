"""Payment receipt on a reimbursement — real PostgreSQL required.

The "mark as paid" flow collects a receipt image. It used to be read
into memory and then discarded while the UI reported it as attached.
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


async def _approved_expense(
    client: AsyncClient, admin_headers: dict[str, str], member_token: str
) -> int:
    org_id = 1
    budget = await client.post(
        f"/api/v1/organizations/{org_id}/budgets",
        json={"amount": "10000.00", "start_date": "2026-01-01", "end_date": "2026-12-31"},
        headers=admin_headers,
    )
    assert budget.status_code == 201, budget.text
    project = await client.post(
        f"/api/v1/organizations/{org_id}/projects",
        json={"budget_id": budget.json()["budget_id"], "name": "Payout Project"},
        headers=admin_headers,
    )
    assert project.status_code == 201, project.text
    etype = await client.post(
        f"/api/v1/organizations/{org_id}/expense-types",
        json={"name": "Travel", "requires_receipt": False},
        headers=admin_headers,
    )
    assert etype.status_code == 201, etype.text
    submitted = await client.post(
        "/api/v1/expenses",
        data={
            "project_id": str(project.json()["project_id"]),
            "expense_type_id": str(etype.json()["expense_type_id"]),
            "amount": "250.00",
            "expense_date": "2026-10-20",
        },
        headers=_auth(member_token),
    )
    assert submitted.status_code == 201, submitted.text
    expense_id = submitted.json()["expense_id"]
    approved = await client.post(
        f"/api/v1/expenses/{expense_id}/approve", json={}, headers=admin_headers
    )
    assert approved.status_code == 200, approved.text
    return expense_id


async def _paid_reimbursement(
    client: AsyncClient, admin_headers: dict[str, str], expense_id: int
) -> int:
    created = await client.post(
        f"/api/v1/expenses/{expense_id}/reimbursement", json={}, headers=admin_headers
    )
    assert created.status_code == 201, created.text
    reimbursement_id = created.json()["reimbursement_id"]
    for target in ("processing", "paid"):
        step = await client.post(
            f"/api/v1/reimbursements/{reimbursement_id}/transition",
            json={"target_status": target, "payment_reference": "TXN-1"},
            headers=admin_headers,
        )
        assert step.status_code == 200, step.text
    return reimbursement_id


async def test_payment_receipt_is_stored(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    admin_headers = _auth(admin_token)
    expense_id = await _approved_expense(client, admin_headers, member_token)
    reimbursement_id = await _paid_reimbursement(client, admin_headers, expense_id)

    uploaded = await client.post(
        f"/api/v1/reimbursements/{reimbursement_id}/receipt",
        files={"file": ("payment-receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=admin_headers,
    )
    assert uploaded.status_code == 200, uploaded.text
    body = uploaded.json()
    assert body["payment_receipt_url"], "the receipt URL must be recorded"
    assert body["payment_receipt_url"].endswith(".jpg")


async def test_payment_receipt_rejects_a_non_image(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    admin_headers = _auth(admin_token)
    expense_id = await _approved_expense(client, admin_headers, member_token)
    reimbursement_id = await _paid_reimbursement(client, admin_headers, expense_id)

    uploaded = await client.post(
        f"/api/v1/reimbursements/{reimbursement_id}/receipt",
        files={"file": ("payment-receipt.jpg", HTML_BYTES, "image/jpeg")},
        headers=admin_headers,
    )
    assert uploaded.status_code == 422, uploaded.text


async def test_payment_receipt_requires_a_paid_reimbursement(
    clean_db,  # noqa: ARG001
    admin_token: str,
    member_token: str,
    client: AsyncClient,
) -> None:
    """A receipt for money that has not moved yet says nothing."""
    admin_headers = _auth(admin_token)
    expense_id = await _approved_expense(client, admin_headers, member_token)
    created = await client.post(
        f"/api/v1/expenses/{expense_id}/reimbursement", json={}, headers=admin_headers
    )
    assert created.status_code == 201, created.text
    reimbursement_id = created.json()["reimbursement_id"]

    uploaded = await client.post(
        f"/api/v1/reimbursements/{reimbursement_id}/receipt",
        files={"file": ("payment-receipt.jpg", JPEG_BYTES, "application/octet-stream")},
        headers=admin_headers,
    )
    assert uploaded.status_code == 409, uploaded.text
