"""The sign-in rate limits (real PostgreSQL required).

The sign-in endpoints were open. Two things follow from that: a password
can be guessed without limit, and — because verifying a password is
deliberately expensive — an open endpoint is a way to make the server
spend all its time hashing.
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


async def test_repeated_failed_sign_ins_are_refused(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    """After enough attempts against one account, the endpoint says 429."""
    await client.post(
        "/api/v1/auth/register",
        json={"name": "Target", "email": "target@example.com", "password": "StrongPass1!"},
    )

    statuses = []
    for _ in range(20):
        response = await client.post(
            "/api/v1/auth/login",
            json={"email": "target@example.com", "password": "WrongPassword1!"},
        )
        statuses.append(response.status_code)

    assert 429 in statuses, "the account limit never kicked in"
    # The first few attempts are answered normally, so the limit is not
    # refusing genuine sign-ins.
    assert statuses[0] == 401


async def test_the_limit_says_how_long_to_wait(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    await client.post(
        "/api/v1/auth/register",
        json={"name": "Target", "email": "waiting@example.com", "password": "StrongPass1!"},
    )
    for _ in range(20):
        response = await client.post(
            "/api/v1/auth/login",
            json={"email": "waiting@example.com", "password": "WrongPassword1!"},
        )
        if response.status_code == 429:
            body = response.json()
            assert body["error"]["code"] == "rate_limited"
            assert body["error"]["details"]["retry_after_seconds"] > 0
            return
    pytest.fail("the account limit never kicked in")


async def test_a_successful_sign_in_clears_the_account_counter(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    """A person who fat-fingers their password a few times is not left
    throttled once they get it right."""
    await client.post(
        "/api/v1/auth/register",
        json={"name": "Target", "email": "careful@example.com", "password": "StrongPass1!"},
    )
    for _ in range(5):
        await client.post(
            "/api/v1/auth/login",
            json={"email": "careful@example.com", "password": "WrongPassword1!"},
        )
    good = await client.post(
        "/api/v1/auth/login",
        json={"email": "careful@example.com", "password": "StrongPass1!"},
    )
    assert good.status_code == 200, good.text

    # The counter was cleared, so the next few attempts are answered.
    for _ in range(5):
        response = await client.post(
            "/api/v1/auth/login",
            json={"email": "careful@example.com", "password": "WrongPassword1!"},
        )
        assert response.status_code == 401, response.text


async def test_registration_is_rate_limited(
    clean_db,  # noqa: ARG001
    client: AsyncClient,
) -> None:
    statuses = []
    for index in range(25):
        response = await client.post(
            "/api/v1/auth/register",
            json={
                "name": f"Spammer {index}",
                "email": f"spammer{index}@example.com",
                "password": "StrongPass1!",
            },
        )
        statuses.append(response.status_code)
    assert 429 in statuses, "the registration limit never kicked in"
