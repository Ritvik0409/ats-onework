"""Shared pytest fixtures — composed, minimal, deterministic (§29).

Design principles:

- Fixtures compose: ``test_database`` → ``db_connection`` → ``seeded_orgs``
  → ``admin_token``.
- Unit tests never touch PostgreSQL; integration tests (marked
  ``@pytest.mark.integration``) run against a **throwaway database the
  harness creates on the fly** — never the development DB (§41).
- Database credentials are discrete env vars (§40, read from
  ``backend/.env``): ``DB_HOST`` ``DB_PORT`` ``DB_USER`` ``DB_PASSWORD``
  ``DB_NAME``. Optional per-test overrides: ``TEST_DB_HOST`` /
  ``TEST_DB_PORT`` / ``TEST_DB_USER`` / ``TEST_DB_PASSWORD``, with the
  test database named ``TEST_DB_NAME`` (default ``<DB_NAME>_test``).
  A full ``TEST_DATABASE_URL`` still works as an escape hatch.
- The harness: connects to the server's ``postgres`` maintenance DB,
  ``CREATE DATABASE``s the throwaway (fresh name per run), applies all
  migrations into it via the shared ``apply_migrations`` core, yields,
  then ``DROP DATABASE ... (FORCE)`` — so integration runs leave your
  server exactly as they found it.
- Auth fixtures mint real JWTs via ``create_access_token`` so tenant-scoping
  tests exercise the actual decode path in ``get_current_user``.
- Seed data is created with explicit SQL (transparent, no hidden ORM magic);
  cleanup uses ``TRUNCATE ... CASCADE`` helpers scoped per test.
"""

from __future__ import annotations

import os
import sys
import uuid
from collections.abc import AsyncIterator, Iterator
from contextlib import suppress

import psycopg
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from psycopg import AsyncConnection
from psycopg.rows import dict_row

from app.core.config import get_settings
from app.core.security.jwt import create_access_token
from app.core.security.tokens import hash_token, utc_now_naive
from app.db.migrations import apply_migrations
from app.main import create_app


def _first_env(*names: str, default: str | None = None) -> str | None:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return default


def _url_host(value: str) -> str:
    from urllib.parse import quote_plus

    return quote_plus(value)


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


@pytest.fixture(scope="session")
def event_loop_policy():
    """psycopg async needs the Selector loop — Windows defaults to Proactor."""
    if sys.platform == "win32":
        from asyncio import WindowsSelectorEventLoopPolicy

        return WindowsSelectorEventLoopPolicy()
    import asyncio

    return asyncio.DefaultEventLoopPolicy()


@pytest.fixture(scope="session")
def test_database() -> Iterator[str]:
    """Session-scoped throwaway database created on the configured server.

    Credentials resolve per key from the environment OR ``backend/.env``
    (Settings reads the file): ``TEST_DB_*`` overrides ``DB_*``. A fresh
    ``<DB_NAME>_test`` database is created, every migration is applied
    into it, and it is dropped afterward — the development database is
    never touched. Keep ``DB_PASSWORD`` empty to skip integration runs.
    """
    settings = get_settings()
    db_host = _first_env("TEST_DB_HOST", "DB_HOST", default=settings.db_host)
    db_port = _first_env("TEST_DB_PORT", "DB_PORT", default=str(settings.db_port))
    db_user = _first_env("TEST_DB_USER", "DB_USER", default=settings.db_user)
    db_password = _first_env("TEST_DB_PASSWORD", "DB_PASSWORD", default=settings.db_password)

    # Escape hatch: a caller-provided full DSN owns its own database.
    explicit_url = os.environ.get("TEST_DATABASE_URL")
    if explicit_url:
        with psycopg.connect(explicit_url) as conn:
            apply_migrations(conn, log=lambda _msg: None)
        yield explicit_url
        return

    if not db_user or not db_password:
        pytest.skip(
            "No test database configured — leave DB_PASSWORD empty in .env "
            "to skip, or fill in credentials to run integration tests."
        )
    host_for_url = _url_host(db_user)
    pwd_for_url = _url_host(db_password)
    server_dsn = f"postgresql://{host_for_url}:{pwd_for_url}@{db_host}:{db_port}/postgres"
    db_name = _first_env("TEST_DB_NAME", default=f"{settings.db_name}_test")
    quoted = f'"{db_name}"'
    test_database_dsn = f"postgresql://{host_for_url}:{pwd_for_url}@{db_host}:{db_port}/{db_name}"

    with psycopg.connect(server_dsn, autocommit=True) as admin:
        # Fresh schema every run — leftovers from a crashed prior session die here.
        with suppress(psycopg.errors.InvalidCatalogName):
            admin.execute(f"DROP DATABASE {quoted} WITH (FORCE)")
        admin.execute(f"CREATE DATABASE {quoted}")

    try:
        with psycopg.connect(test_database_dsn) as conn:
            apply_migrations(conn, log=lambda msg: print(f"[migrate] {msg}"))
        yield test_database_dsn
    finally:
        with (
            psycopg.connect(server_dsn, autocommit=True) as admin,
            suppress(psycopg.errors.InvalidCatalogName),
        ):
            admin.execute(f"DROP DATABASE {quoted} WITH (FORCE)")


@pytest_asyncio.fixture
async def db_connection(test_database: str) -> AsyncIterator[AsyncConnection[dict]]:
    """Raw async connection to the throwaway test database."""
    async with await AsyncConnection.connect(test_database, row_factory=dict_row) as conn:
        # The sign-in endpoints are rate limited, and every request in
        # this suite arrives from the same address, so the counters are
        # cleared for each test that uses a connection.
        await conn.execute("DELETE FROM rate_limit_buckets")
        await conn.commit()
        yield conn


@pytest_asyncio.fixture
async def seeded_orgs(db_connection: AsyncConnection[dict]) -> dict[str, dict]:
    """Two orgs (A/B) each with an admin and a member — the tenant-isolation
    layout §27 requires. Rolls back nothing; callers truncate explicitly.

    The fixture writes rows directly, so it also installs the access model
    the way the application does: the standard capabilities and roles
    into each organization, and a role on each membership. Without a
    role a membership holds no capability at all, so the seeded accounts
    could do nothing.
    """
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
            # The standard access model, installed the same way an
            # organization created through the API gets it.
            await cur.execute("SELECT ats_install_permissions(%s)", (org_id,))
            await cur.execute("SELECT ats_install_roles(%s)", (org_id,))
            for role, admin in (("admin", True), ("member", False)):
                email = _unique(f"{key}-{role}") + "@test.invalid"
                await cur.execute(_SEED_USER_SQL, (f"{key} {role}", email))
                user = await cur.fetchone()
                assert user is not None
                emp_id = user["employee_id"]
                await cur.execute(_SEED_MEMBERSHIP_SQL, (emp_id, org_id, admin))
                # The membership holds a role: an administrator the
                # ``admin`` role, everyone else the ``employee`` role.
                await cur.execute(
                    """
                    INSERT INTO membership_roles (membership_id, role_id, organization_id)
                    SELECT m.membership_id, r.role_id, m.organization_id
                      FROM memberships m
                      JOIN roles r
                        ON r.organization_id = m.organization_id
                       AND r.name = %s
                     WHERE m.employee_id = %s AND m.organization_id = %s
                    """,
                    ("admin" if admin else "employee", emp_id, org_id),
                )
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
                memberships, employee_status, users, organizations,
                rate_limit_buckets
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
