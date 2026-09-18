"""Shared pytest fixtures — composed, minimal, deterministic (§29).

Design principles:

- Fixtures compose: ``db_connection`` → ``seeded_orgs`` → ``admin_token``.
- Unit tests never touch PostgreSQL; integration tests (marked
  ``@pytest.mark.integration``) require ``TEST_DATABASE_URL`` pointing at a
  throwaway database — never development or production (§41).
- Auth fixtures mint real JWTs via ``create_access_token`` so tenant-scoping
  tests exercise the actual decode path in ``get_current_user``.
- Seed data is created with explicit SQL (transparent, no hidden ORM magic);
  cleanup uses ``TRUNCATE ... CASCADE`` helpers scoped per test.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncIterator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from psycopg import AsyncConnection
from psycopg.rows import dict_row

from app.core.security.jwt import create_access_token
from app.core.security.tokens import hash_token, utc_now_naive
from app.main import create_app

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL", "")

_SEED_ORG_SQL = """
INSERT INTO organizations (name, slug, description)
VALUES (%s, %s, %s)
RETURNING organization_id
"""

_SEED_USER_SQL = """
INSERT INTO users (name, email, password_hash)
VALUES (%s, %s, 'argon2$seed-fixture-not-a-real-hash')
RETURNING employee_id
"""

_SEED_MEMBERSHIP_SQL = """
INSERT INTO memberships (employee_id, organization_id, is_admin)
VALUES (%s, %s, %s)
"""


def _unique(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:8]}"


@pytest.fixture(scope="session")
def anyio_backend() -> str:
    return "asyncio"


@pytest_asyncio.fixture
async def db_connection() -> AsyncIterator[AsyncConnection[dict]]:
    """Raw async connection to the throwaway test database.

    Skips (instead of failing) when ``TEST_DATABASE_URL`` is unset so unit
    runs stay green on machines without PostgreSQL.
    """
    if not TEST_DATABASE_URL:
        pytest.skip("TEST_DATABASE_URL is not set — integration fixture skipped.")
    async with await AsyncConnection.connect(TEST_DATABASE_URL, row_factory=dict_row) as conn:
        yield conn


@pytest_asyncio.fixture
async def seeded_orgs(db_connection: AsyncConnection[dict]) -> dict[str, dict]:
    """Two orgs (A/B) each with an admin and a member — the tenant-isolation
    layout §27 requires. Rolls back nothing; callers truncate explicitly."""
    conn = db_connection
    orgs: dict[str, dict] = {}
    async with conn.cursor() as cur:
        for key in ("a", "b"):
            slug = _unique(f"org-{key}")
            await cur.execute(
                _SEED_ORG_SQL, (f"Test Org {key.upper()}", slug, "pytest fixture org")
            )
            row = await cur.fetchone()
            assert row is not None
            org_id = row["organization_id"]
            orgs[key] = {"organization_id": org_id, "slug": slug, "users": {}}
            for role, admin in (("admin", True), ("member", False)):
                email = _unique(f"{key}-{role}") + "@test.invalid"
                await cur.execute(_SEED_USER_SQL, (f"{key} {role}", email))
                user = await cur.fetchone()
                assert user is not None
                emp_id = user["employee_id"]
                await cur.execute(_SEED_MEMBERSHIP_SQL, (emp_id, org_id, admin))
                orgs[key]["users"][role] = {
                    "employee_id": emp_id,
                    "email": email,
                    "is_admin": admin,
                }
    await conn.commit()
    return orgs


@pytest_asyncio.fixture
async def admin_token(seeded_orgs: dict[str, dict]) -> str:
    admin = seeded_orgs["a"]["users"]["admin"]
    return create_access_token(
        employee_id=admin["employee_id"],
        organization_id=seeded_orgs["a"]["organization_id"],
        is_admin=True,
    )


@pytest_asyncio.fixture
async def member_token(seeded_orgs: dict[str, dict]) -> str:
    member = seeded_orgs["a"]["users"]["member"]
    return create_access_token(
        employee_id=member["employee_id"],
        organization_id=seeded_orgs["a"]["organization_id"],
        is_admin=False,
    )


@pytest_asyncio.fixture
async def other_org_admin_token(seeded_orgs: dict[str, dict]) -> str:
    """Org B admin JWT — the cross-tenant caller in §27 isolation tests."""
    admin = seeded_orgs["b"]["users"]["admin"]
    return create_access_token(
        employee_id=admin["employee_id"],
        organization_id=seeded_orgs["b"]["organization_id"],
        is_admin=True,
    )


async def truncate_all(conn: AsyncConnection[dict]) -> None:
    """Wipe all domain tables in FK-safe order — per-test cleanup helper."""
    async with conn.cursor() as cur:
        await cur.execute(
            """
            TRUNCATE TABLE
                audit_logs, expense_media, expense_approvals, reimbursements,
                expenses, project_members, project_categories, projects,
                categories, budgets, authentication_tokens, membership_roles,
                user_permissions, role_permissions, permissions, roles,
                memberships, employee_status, users, organizations
            RESTART IDENTITY CASCADE
            """,
        )
    await conn.commit()


@pytest_asyncio.fixture
async def test_client() -> AsyncIterator[AsyncClient]:
    """ASGI test client — no network, no lifespan (pool untouched)."""
    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


def token_hash_fixture(token: str) -> str:
    """Hash helper exposed for auth tests — mirrors the repository contract."""
    return hash_token(token)


def now_naive_fixture():
    return utc_now_naive()
