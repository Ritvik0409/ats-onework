"""Changing a password — real PostgreSQL required.

Nobody could change a password before: the client said they were
"admin-managed", and the administration endpoint could not do it either.
Changing one must also end the account's other sessions.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app

pytestmark = pytest.mark.integration

OLD_PASSWORD = "StrongPass1!"
NEW_PASSWORD = "AnotherGood1!"


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


async def _register_and_login(client: AsyncClient, email: str) -> tuple[str, str]:
    registered = await client.post(
        "/api/v1/auth/register",
        json={"name": "Changer", "email": email, "password": OLD_PASSWORD},
    )
    assert registered.status_code == 201, registered.text
    logged_in = await client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": OLD_PASSWORD},
    )
    assert logged_in.status_code == 200, logged_in.text
    body = logged_in.json()
    return body["access_token"], body["refresh_token"]


async def test_a_user_can_change_their_password(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    access, _ = await _register_and_login(client, "changer@example.com")

    changed = await client.post(
        "/api/v1/auth/change-password",
        json={"current_password": OLD_PASSWORD, "new_password": NEW_PASSWORD},
        headers={"Authorization": f"Bearer {access}"},
    )
    assert changed.status_code == 204, changed.text

    old_fails = await client.post(
        "/api/v1/auth/login",
        json={"email": "changer@example.com", "password": OLD_PASSWORD},
    )
    assert old_fails.status_code == 401, old_fails.text

    new_works = await client.post(
        "/api/v1/auth/login",
        json={"email": "changer@example.com", "password": NEW_PASSWORD},
    )
    assert new_works.status_code == 200, new_works.text


async def test_the_current_password_must_be_right(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    access, _ = await _register_and_login(client, "wrongcurrent@example.com")

    changed = await client.post(
        "/api/v1/auth/change-password",
        json={"current_password": "NotMyPassword1!", "new_password": NEW_PASSWORD},
        headers={"Authorization": f"Bearer {access}"},
    )
    assert changed.status_code == 401, changed.text


async def test_a_weak_password_is_refused(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    access, _ = await _register_and_login(client, "weak@example.com")

    changed = await client.post(
        "/api/v1/auth/change-password",
        json={"current_password": OLD_PASSWORD, "new_password": "password123"},
        headers={"Authorization": f"Bearer {access}"},
    )
    assert changed.status_code == 422, changed.text


async def test_changing_the_password_ends_the_other_sessions(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    """A password change is how someone recovers from a compromise, so
    the sessions that were alive before it must not be."""
    access, refresh = await _register_and_login(client, "sessions@example.com")

    changed = await client.post(
        "/api/v1/auth/change-password",
        json={"current_password": OLD_PASSWORD, "new_password": NEW_PASSWORD},
        headers={"Authorization": f"Bearer {access}"},
    )
    assert changed.status_code == 204, changed.text

    refreshed = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert refreshed.status_code == 401, refreshed.text


async def test_registration_refuses_a_common_password(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    registered = await client.post(
        "/api/v1/auth/register",
        json={"name": "Common", "email": "common@example.com", "password": "password123"},
    )
    assert registered.status_code == 422, registered.text
