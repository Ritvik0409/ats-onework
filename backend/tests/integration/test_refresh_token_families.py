"""Refresh token rotation and replay detection — real PostgreSQL required.

Rotation used to delete the old row, so a replayed token was
indistinguishable from an unknown one and a client that retried after a
lost response lost its session. Refresh tokens now belong to a family,
which makes a replay recognisable.
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


async def _login(client: AsyncClient, email: str) -> tuple[str, str]:
    """Register and log in; return the (access, refresh) token pair."""
    registered = await client.post(
        "/api/v1/auth/register",
        json={"name": "Rotator", "email": email, "password": "StrongPass1!"},
    )
    assert registered.status_code == 201, registered.text
    logged_in = await client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": "StrongPass1!"},
    )
    assert logged_in.status_code == 200, logged_in.text
    body = logged_in.json()
    return body["access_token"], body["refresh_token"]


async def test_rotation_issues_a_new_token(client: AsyncClient) -> None:
    _, refresh = await _login(client, "rotate@example.com")
    response = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["refresh_token"]
    assert body["refresh_token"] != refresh
    assert body["access_token"]


async def test_retrying_a_rotated_token_continues_the_chain(
    client: AsyncClient,
) -> None:
    """A response lost in transit must not end the session."""
    _, refresh = await _login(client, "retry@example.com")
    first = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert first.status_code == 200, first.text
    # The client did not see the response and retries with the old token.
    retry = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert retry.status_code == 200, retry.text
    assert retry.json()["refresh_token"] != refresh


async def test_replaying_a_stale_token_revokes_the_family(
    client: AsyncClient,
) -> None:
    """Once the chain has moved on, the old token is treated as stolen."""
    _, refresh = await _login(client, "replay@example.com")
    first = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert first.status_code == 200, first.text
    second_token = first.json()["refresh_token"]

    # The chain moves on a second time.
    second = await client.post("/api/v1/auth/refresh", json={"refresh_token": second_token})
    assert second.status_code == 200, second.text
    third_token = second.json()["refresh_token"]

    # Now the original token comes back -- that is a replay.
    replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert replay.status_code == 401, replay.text

    # The whole family is dead, including the token the client holds.
    after = await client.post("/api/v1/auth/refresh", json={"refresh_token": third_token})
    assert after.status_code == 401, after.text


async def test_logout_revokes_the_whole_family(client: AsyncClient) -> None:
    access, refresh = await _login(client, "logout@example.com")
    rotated = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert rotated.status_code == 200, rotated.text

    logged_out = await client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": rotated.json()["refresh_token"]},
        headers={"Authorization": f"Bearer {access}"},
    )
    assert logged_out.status_code == 204, logged_out.text

    after = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": rotated.json()["refresh_token"]}
    )
    assert after.status_code == 401, after.text
