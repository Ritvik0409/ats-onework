"""An organization's own administrator manages their own access (real
PostgreSQL required).

The access model has three tiers: a platform super administrator, an
organization's administrator, and a role member. This file covers the
middle one -- the person who owns an organization and configures its
roles, its grants and who holds them -- against another organization's
boundaries.
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
async def client(
    test_database: str,
    db_connection: object,  # noqa: ARG001 - clears the sign-in rate limits
) -> AsyncIterator[AsyncClient]:
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


async def test_an_organization_admin_can_read_their_own_access(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    org_id = seeded_orgs["a"]["organization_id"]

    roles = await client.get(
        f"/api/v1/organizations/{org_id}/access/roles", headers=_auth(admin_token)
    )
    assert roles.status_code == 200, roles.text
    names = {role["name"] for role in roles.json()}
    assert {"employee", "manager", "finance", "director", "hr", "admin"} <= names

    permissions = await client.get(
        f"/api/v1/organizations/{org_id}/access/permissions", headers=_auth(admin_token)
    )
    assert permissions.status_code == 200, permissions.text
    assert any(p["api_name"] == "expense.approve" for p in permissions.json())


async def test_an_organization_admin_can_change_a_role(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    """This is the thing the question was about: the org admin edits the
    grants of their own organization's roles."""
    org_id = seeded_orgs["a"]["organization_id"]

    roles = await client.get(
        f"/api/v1/organizations/{org_id}/access/roles", headers=_auth(admin_token)
    )
    assert roles.status_code == 200, roles.text
    manager = next(r for r in roles.json() if r["name"] == "manager")
    assert "expense.approve" in manager["permissions"]

    # Withhold a capability from the manager role.
    without = [p for p in manager["permissions"] if p != "expense.approve"]
    updated = await client.put(
        f"/api/v1/organizations/{org_id}/access/roles/{manager['role_id']}/permissions",
        json={"permissions": without},
        headers=_auth(admin_token),
    )
    assert updated.status_code == 200, updated.text
    assert "expense.approve" not in updated.json()

    # And put it back.
    restored = await client.put(
        f"/api/v1/organizations/{org_id}/access/roles/{manager['role_id']}/permissions",
        json={"permissions": manager["permissions"]},
        headers=_auth(admin_token),
    )
    assert restored.status_code == 200, restored.text
    assert "expense.approve" in restored.json()


async def test_an_organization_admin_can_create_a_role_and_a_capability(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    org_id = seeded_orgs["a"]["organization_id"]

    capability = await client.post(
        f"/api/v1/organizations/{org_id}/access/permissions",
        json={"api_name": "project.export", "description": "Export a project"},
        headers=_auth(admin_token),
    )
    assert capability.status_code == 201, capability.text

    role = await client.post(
        f"/api/v1/organizations/{org_id}/access/roles",
        json={
            "name": "auditor",
            "description": "Reads the audit log",
            "permissions": ["audit.read", "project.export"],
        },
        headers=_auth(admin_token),
    )
    assert role.status_code == 201, role.text
    assert set(role.json()["permissions"]) == {"audit.read", "project.export"}


async def test_an_organization_admin_can_assign_a_role_to_someone(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    org_id = seeded_orgs["a"]["organization_id"]
    member_id = seeded_orgs["a"]["users"]["member"]["employee_id"]

    roles = await client.get(
        f"/api/v1/organizations/{org_id}/access/roles", headers=_auth(admin_token)
    )
    assert roles.status_code == 200, roles.text
    manager_role = next(r for r in roles.json() if r["name"] == "manager")

    assigned = await client.put(
        f"/api/v1/organizations/{org_id}/access/members/{member_id}/roles",
        json={"role_ids": [manager_role["role_id"]]},
        headers=_auth(admin_token),
    )
    assert assigned.status_code == 200, assigned.text
    assert assigned.json()["roles"] == ["manager"]
    assert "expense.read_all" in assigned.json()["effective_permissions"]


async def test_an_organization_admin_cannot_reach_another_organization(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    admin_token: str,
    client: AsyncClient,
) -> None:
    """Owning one organization is not a key to another."""
    other_org = seeded_orgs["b"]["organization_id"]

    roles = await client.get(
        f"/api/v1/organizations/{other_org}/access/roles", headers=_auth(admin_token)
    )
    assert roles.status_code == 404, roles.text

    changed = await client.put(
        f"/api/v1/organizations/{other_org}/access/roles/1/permissions",
        json={"permissions": []},
        headers=_auth(admin_token),
    )
    assert changed.status_code == 404, changed.text


async def test_a_plain_member_cannot_manage_the_access(
    clean_db,  # noqa: ARG001
    seeded_orgs: dict,
    member_token: str,
    client: AsyncClient,
) -> None:
    """A membership is not the same thing as the administration of one.

    Reading the organization's roles is open to its members — the
    contract has always allowed that — but changing them is not.
    """
    org_id = seeded_orgs["a"]["organization_id"]

    roles = await client.get(
        f"/api/v1/organizations/{org_id}/access/roles", headers=_auth(member_token)
    )
    assert roles.status_code == 200, roles.text

    changed = await client.put(
        f"/api/v1/organizations/{org_id}/access/roles/1/permissions",
        json={"permissions": []},
        headers=_auth(member_token),
    )
    # 403, not 404: the member is in this organization, they simply may
    # not administer it. A target outside the organization is a 404.
    assert changed.status_code == 403, changed.text

    member_id = seeded_orgs["a"]["users"]["member"]["employee_id"]
    assigned = await client.put(
        f"/api/v1/organizations/{org_id}/access/members/{member_id}/roles",
        json={"role_ids": []},
        headers=_auth(member_token),
    )
    assert assigned.status_code == 403, assigned.text
