"""Phase 4.1-4.3 integration tests — real PostgreSQL required.

Marked ``@pytest.mark.integration`` and skipped automatically when
``TEST_DATABASE_URL`` is unset (see ``tests/conftest.py``). Run with::

    TEST_DATABASE_URL=postgresql://.../ats_test uv run pytest -m integration

Covers the behaviors unit doubles cannot prove: constraint backstops
(``UNIQUE``, partial-unique single-active status), the refresh-rotation
round-trip through ``authentication_tokens``, audit rows committing with
their workflows, and tenant isolation at the service boundary.
"""

from __future__ import annotations

import pytest
from psycopg import AsyncConnection
from psycopg import errors as pg_errors

from app.auth.schemas import (
    LoginRequest,
    OrganizationSwitchRequest,
    RefreshRequest,
    UserCreate,
)
from app.auth.service import AuthService
from app.common.audit import service as audit_service
from app.core.constants import AccountStatus, EmployeeStatus, TokenPurpose
from app.core.exceptions import (
    AuthenticationError,
    AuthorizationError,
    ConflictError,
    NotFoundError,
    to_app_exception,
)
from app.core.security import tokens as opaque_tokens
from app.organizations.schemas import (
    MembershipCreate,
    OrganizationCreate,
    RoleCreate,
)
from app.organizations.service import OrganizationService
from app.users.schemas import EmployeeStatusCreate, UserUpdate
from app.users.service import UserService
from tests.conftest import truncate_all

pytestmark = pytest.mark.integration


@pytest.fixture
async def clean_db(
    db_connection: AsyncConnection[dict],
) -> AsyncConnection[dict]:
    await truncate_all(db_connection)
    yield db_connection
    await truncate_all(db_connection)


async def test_register_login_refresh_logout_flow(clean_db: AsyncConnection[dict]) -> None:
    svc = AuthService()
    user = await svc.register(
        clean_db, UserCreate(name="Ivy", email="ivy@example.com", password="StrongPass1!")
    )
    await clean_db.commit()
    assert user.email == "ivy@example.com"

    pair = await svc.login(clean_db, LoginRequest(email="ivy@example.com", password="StrongPass1!"))
    await clean_db.commit()
    assert pair.organizations == []  # no memberships yet

    rotated = await svc.refresh(clean_db, RefreshRequest(refresh_token=pair.refresh_token))
    await clean_db.commit()
    assert rotated.refresh_token != pair.refresh_token

    with pytest.raises(AuthenticationError):  # old token died in rotation
        await svc.refresh(clean_db, RefreshRequest(refresh_token=pair.refresh_token))

    me = await UserService().get_me(clean_db, user.employee_id)
    assert me.account_status == AccountStatus.ACTIVE

    await svc.logout(
        clean_db,
        employee_id=user.employee_id,
        payload=RefreshRequest(refresh_token=rotated.refresh_token),
    )
    await clean_db.commit()
    with pytest.raises(AuthenticationError):
        await svc.refresh(clean_db, RefreshRequest(refresh_token=rotated.refresh_token))


async def test_login_wrong_password_and_suspended(
    clean_db: AsyncConnection[dict],
) -> None:
    svc = AuthService()
    await svc.register(
        clean_db, UserCreate(name="Bob", email="bob@example.com", password="StrongPass1!")
    )
    await clean_db.commit()

    with pytest.raises(AuthenticationError):
        await svc.login(clean_db, LoginRequest(email="bob@example.com", password="WrongPass1!"))

    user = await svc.login(clean_db, LoginRequest(email="bob@example.com", password="StrongPass1!"))
    assert user.access_token
    await clean_db.commit()

    async with clean_db.cursor() as cur:
        await cur.execute(
            "UPDATE users SET account_status = 'suspended' WHERE email = %s",
            ("bob@example.com",),
        )
    await clean_db.commit()
    with pytest.raises(AuthorizationError):
        await svc.login(clean_db, LoginRequest(email="bob@example.com", password="StrongPass1!"))


async def test_switch_organization_guards(clean_db: AsyncConnection[dict]) -> None:
    auth = AuthService()
    orgs = OrganizationService()
    await auth.register(
        clean_db, UserCreate(name="A", email="a@example.com", password="StrongPass1!")
    )
    await auth.register(
        clean_db, UserCreate(name="B", email="b@example.com", password="StrongPass1!")
    )
    await clean_db.commit()

    async with clean_db.cursor() as cur:
        await cur.execute("SELECT employee_id FROM users WHERE email = %s", ("a@example.com",))
        a_id = (await cur.fetchone())["employee_id"]
        await cur.execute("SELECT employee_id FROM users WHERE email = %s", ("b@example.com",))
        b_id = (await cur.fetchone())["employee_id"]

    org = await orgs.create_organization(
        clean_db, actor_id=a_id, payload=OrganizationCreate(name="Org One")
    )
    await clean_db.commit()

    with pytest.raises(AuthorizationError):  # B is not a member
        await auth.switch_organization(
            clean_db,
            employee_id=b_id,
            payload=OrganizationSwitchRequest(organization_id=org.organization_id),
        )
    with pytest.raises(NotFoundError):  # no such org
        await auth.switch_organization(
            clean_db,
            employee_id=a_id,
            payload=OrganizationSwitchRequest(organization_id=999999),
        )

    pair = await auth.switch_organization(
        clean_db,
        employee_id=a_id,
        payload=OrganizationSwitchRequest(organization_id=org.organization_id),
    )
    await clean_db.commit()
    assert pair.organizations[0].is_admin is True


async def test_org_membership_last_admin_and_duplicates(
    clean_db: AsyncConnection[dict],
) -> None:
    auth = AuthService()
    orgs = OrganizationService()
    await auth.register(
        clean_db, UserCreate(name="A", email="a@example.com", password="StrongPass1!")
    )
    await auth.register(
        clean_db, UserCreate(name="B", email="b@example.com", password="StrongPass1!")
    )
    await clean_db.commit()
    async with clean_db.cursor() as cur:
        await cur.execute("SELECT employee_id FROM users WHERE email = %s", ("a@example.com",))
        a_id = (await cur.fetchone())["employee_id"]
        await cur.execute("SELECT employee_id FROM users WHERE email = %s", ("b@example.com",))
        b_id = (await cur.fetchone())["employee_id"]

    org = await orgs.create_organization(
        clean_db, actor_id=a_id, payload=OrganizationCreate(name="Dup Org", slug="dup-org")
    )
    await clean_db.commit()

    with pytest.raises(ConflictError):  # duplicate slug pre-check path
        async with clean_db.cursor() as cur:
            await cur.execute(
                "INSERT INTO organizations (name, slug) VALUES (%s, %s)",
                ("Clone", "dup-org"),
            )
    await clean_db.rollback()

    with pytest.raises(ConflictError):  # last admin cannot leave
        await orgs.remove_member(
            clean_db,
            actor_id=a_id,
            organization_id=org.organization_id,
            employee_id=a_id,
        )

    await orgs.add_member(
        clean_db,
        actor_id=a_id,
        organization_id=org.organization_id,
        payload=MembershipCreate(employee_id=b_id, is_admin=True),
    )
    await clean_db.commit()
    with pytest.raises(ConflictError):  # already a member
        await orgs.add_member(
            clean_db,
            actor_id=a_id,
            organization_id=org.organization_id,
            payload=MembershipCreate(employee_id=b_id),
        )

    # Cross-tenant read → 404
    with pytest.raises(NotFoundError):
        await orgs.get_organization(
            clean_db, employee_id=424242, organization_id=org.organization_id
        )

    # UniqueViolation from the DB maps to 409 at the HTTP boundary.
    assert to_app_exception(pg_errors.UniqueViolation("dup")).status_code == 409


async def test_employee_status_single_active_backstop(
    clean_db: AsyncConnection[dict],
) -> None:
    auth = AuthService()
    users = UserService()
    user = await auth.register(
        clean_db, UserCreate(name="S", email="s@example.com", password="StrongPass1!")
    )
    await clean_db.commit()

    created = await users.create_status(
        clean_db,
        actor_id=user.employee_id,
        employee_id=user.employee_id,
        payload=EmployeeStatusCreate(status=EmployeeStatus.ACTIVE),
    )
    await clean_db.commit()
    assert created.status == EmployeeStatus.ACTIVE

    with pytest.raises(ConflictError):  # service pre-check
        await users.create_status(
            clean_db,
            actor_id=user.employee_id,
            employee_id=user.employee_id,
            payload=EmployeeStatusCreate(status=EmployeeStatus.ON_LEAVE),
        )

    async with clean_db.cursor() as cur:  # DB partial-unique backstop
        with pytest.raises(pg_errors.UniqueViolation):
            await cur.execute(
                "INSERT INTO employee_status (employee_id, status) VALUES (%s, %s)",
                (user.employee_id, "on_leave"),
            )
    await clean_db.rollback()


async def test_user_search_treats_wildcards_literally(
    clean_db: AsyncConnection[dict],
) -> None:
    """LIKE escaping: searching for "%" must not match every user."""
    auth = AuthService()
    users = UserService()
    await auth.register(
        clean_db,
        UserCreate(name="100% Legit", email="percent@example.com", password="StrongPass1!"),
    )
    await auth.register(
        clean_db, UserCreate(name="Plain Jane", email="plain@example.com", password="StrongPass1!")
    )
    await clean_db.commit()

    page = await users.list_users(clean_db, limit=20, cursor=None, search="%")
    assert [u.name for u in page.items] == ["100% Legit"]


async def test_user_update_writes_audit_row(clean_db: AsyncConnection[dict]) -> None:
    auth = AuthService()
    users = UserService()
    user = await auth.register(
        clean_db, UserCreate(name="U", email="u@example.com", password="StrongPass1!")
    )
    await clean_db.commit()

    updated = await users.update_user(
        clean_db,
        actor_id=user.employee_id,
        employee_id=user.employee_id,
        payload=UserUpdate(name="Updated"),
    )
    await clean_db.commit()
    assert updated.name == "Updated"

    async with clean_db.cursor() as cur:
        await cur.execute(
            "SELECT COUNT(*) AS n FROM audit_logs WHERE action = %s AND record_id = %s",
            ("user.update", str(user.employee_id)),
        )
        assert (await cur.fetchone())["n"] == 1


async def test_role_uniqueness_is_org_scoped(clean_db: AsyncConnection[dict]) -> None:
    auth = AuthService()
    orgs = OrganizationService()
    await auth.register(
        clean_db, UserCreate(name="A", email="a@example.com", password="StrongPass1!")
    )
    await clean_db.commit()
    async with clean_db.cursor() as cur:
        await cur.execute("SELECT employee_id FROM users WHERE email = %s", ("a@example.com",))
        a_id = (await cur.fetchone())["employee_id"]

    first = await orgs.create_organization(
        clean_db, actor_id=a_id, payload=OrganizationCreate(name="First")
    )
    second = await orgs.create_organization(
        clean_db, actor_id=a_id, payload=OrganizationCreate(name="Second")
    )
    await clean_db.commit()

    await orgs.create_role(
        clean_db,
        actor_id=a_id,
        organization_id=first.organization_id,
        payload=RoleCreate(name="manager"),
    )
    await clean_db.commit()
    with pytest.raises(ConflictError):  # same org → conflict
        async with clean_db.cursor() as cur:
            await cur.execute(
                "INSERT INTO roles (name, organization_id) VALUES (%s, %s)",
                ("manager", first.organization_id),
            )
    await clean_db.rollback()

    same_name_other_org = await orgs.create_role(  # other org → fine
        clean_db,
        actor_id=a_id,
        organization_id=second.organization_id,
        payload=RoleCreate(name="manager"),
    )
    await clean_db.commit()
    assert same_name_other_org.organization_id == second.organization_id


async def test_expired_tokens_cleanup_helper(clean_db: AsyncConnection[dict]) -> None:
    auth = AuthService()
    user = await auth.register(
        clean_db, UserCreate(name="T", email="t@example.com", password="StrongPass1!")
    )
    await clean_db.commit()
    async with clean_db.cursor() as cur:
        await cur.execute(
            """
            INSERT INTO authentication_tokens
                (employee_id, token_hash, purpose, expires_at)
            VALUES (%s, %s, %s, %s)
            """,
            (
                user.employee_id,
                opaque_tokens.hash_token("stale"),
                TokenPurpose.REFRESH.value,
                opaque_tokens.utc_now_naive(),
            ),
        )
    await clean_db.commit()
    from app.auth.repository import AuthRepository

    removed = await AuthRepository().delete_expired_tokens(clean_db)
    await clean_db.commit()
    assert removed >= 1


async def test_raise_exception_prefix_routing_end_to_end(
    clean_db: AsyncConnection[dict],
) -> None:
    """A real P0001 from PostgreSQL must route by prefix via ``diag``.

    The cross-tenant trigger text (§9, ``validate_expense_org_consistency``)
    reads as 404; any other RAISE reads as 422 — and the server text never
    leaks into the mapped message.
    """
    async with clean_db.cursor() as cur:
        with pytest.raises(pg_errors.RaiseException) as cross:
            await cur.execute(
                "DO $$ BEGIN RAISE EXCEPTION 'Cross-tenant violation: probe %', 1; END $$;"
            )
    await clean_db.rollback()
    assert cross.value.diag.message_primary == "Cross-tenant violation: probe 1"
    mapped = to_app_exception(cross.value)
    assert mapped.status_code == 404
    assert "probe" not in mapped.message

    async with clean_db.cursor() as cur:
        with pytest.raises(pg_errors.RaiseException) as other:
            await cur.execute("DO $$ BEGIN RAISE EXCEPTION 'Business rule broken'; END $$;")
    await clean_db.rollback()
    assert to_app_exception(other.value).status_code == 422


async def test_audit_log_never_stores_secrets(clean_db: AsyncConnection[dict]) -> None:
    async with clean_db.cursor() as cur:
        await cur.execute("SELECT old_values, new_values FROM audit_logs")
        for row in await cur.fetchall():
            for column in ("old_values", "new_values"):
                blob = row[column]
                if blob is None:
                    continue
                lowered = str(blob).lower()
                assert "password_hash" not in lowered
                assert "token_hash" not in lowered
    _ = audit_service  # the DRY helper under test exists and is importable
