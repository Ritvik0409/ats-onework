"""The platform super administrator (real PostgreSQL).

A super administrator manages the access model itself: the capability
catalogue, and any organization's roles and grants. It is not an
organization role, so it does not require a membership.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

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


async def _promote(conn, employee_id: int) -> None:
    async with conn.cursor() as cur:
        await cur.execute(
            "UPDATE users SET is_superuser = TRUE WHERE employee_id = %s", (employee_id,)
        )
    await conn.commit()


async def test_an_ordinary_admin_cannot_reach_the_platform_endpoints(
    clean_db,  # noqa: ARG001
    admin_token: str,
    client: AsyncClient,
) -> None:
    denied = await client.get("/api/v1/system/catalog", headers=_auth(admin_token))
    assert denied.status_code == 403, denied.text

    denied_orgs = await client.get("/api/v1/system/organizations", headers=_auth(admin_token))
    assert denied_orgs.status_code == 403, denied_orgs.text


async def test_a_super_admin_reaches_the_platform_endpoints(
    clean_db,
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    admin_id = seeded_orgs["a"]["users"]["admin"]["employee_id"]
    await _promote(clean_db, admin_id)

    catalogue = await client.get("/api/v1/system/catalog", headers=_auth(admin_token))
    assert catalogue.status_code == 200, catalogue.text
    entries = catalogue.json()
    assert any(e["kind"] == "permission" and e["name"] == "expense.create" for e in entries)
    assert any(e["kind"] == "role" and e["name"] == "manager" for e in entries)

    organizations = await client.get("/api/v1/system/organizations", headers=_auth(admin_token))
    assert organizations.status_code == 200, organizations.text
    assert len(organizations.json()) >= 2

    superusers = await client.get("/api/v1/system/users/superusers", headers=_auth(admin_token))
    assert superusers.status_code == 200, superusers.text
    assert [row["employee_id"] for row in superusers.json()] == [admin_id]


async def test_a_super_admin_configures_another_organization(
    clean_db,
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    """The super administrator is not a member of the organization they
    administer, and can still configure it."""
    admin_id = seeded_orgs["a"]["users"]["admin"]["employee_id"]
    other_org = seeded_orgs["b"]["organization_id"]
    await _promote(clean_db, admin_id)

    roles = await client.get(
        f"/api/v1/organizations/{other_org}/access/roles", headers=_auth(admin_token)
    )
    assert roles.status_code == 200, roles.text
    manager = next(r for r in roles.json() if r["name"] == "manager")
    assert manager["permissions"], "the standard role should carry its grants"

    # Withhold a capability from the manager role.
    without = [p for p in manager["permissions"] if p != "expense.approve"]
    updated = await client.put(
        f"/api/v1/organizations/{other_org}/access/roles/{manager['role_id']}/permissions",
        json={"permissions": without},
        headers=_auth(admin_token),
    )
    assert updated.status_code == 200, updated.text
    assert "expense.approve" not in updated.json()


async def test_a_super_admin_grants_super_admin_rights(
    clean_db,
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    admin_id = seeded_orgs["a"]["users"]["admin"]["employee_id"]
    member_id = seeded_orgs["a"]["users"]["member"]["employee_id"]
    await _promote(clean_db, admin_id)

    granted = await client.put(
        f"/api/v1/system/users/{member_id}/superuser",
        json={"is_superuser": True},
        headers=_auth(admin_token),
    )
    assert granted.status_code == 200, granted.text
    assert granted.json()["is_superuser"] is True

    listed = await client.get("/api/v1/system/users/superusers", headers=_auth(admin_token))
    assert listed.status_code == 200, listed.text
    assert member_id in [row["employee_id"] for row in listed.json()]


async def test_a_super_admin_cannot_remove_their_own_rights(
    clean_db,
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    """Otherwise one person could lock the platform out of its own admin."""
    admin_id = seeded_orgs["a"]["users"]["admin"]["employee_id"]
    await _promote(clean_db, admin_id)

    revoked = await client.put(
        f"/api/v1/system/users/{admin_id}/superuser",
        json={"is_superuser": False},
        headers=_auth(admin_token),
    )
    assert revoked.status_code == 409, revoked.text
