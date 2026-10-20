"""Tenant-isolation tests for the user admin surface — real PostgreSQL required.

The admin routes under ``/users`` act on *people*, not on an
organization-scoped resource, so the organization boundary has to come
from the caller's membership. These tests exercise the real SQL against
a throwaway database (see ``tests/conftest.py``) and assert that an
admin of one organization can neither read nor modify the roster of
another.

Run with::

    uv run pytest -m integration
"""

from __future__ import annotations

import uuid

import pytest
from psycopg import AsyncConnection

from app.core.constants import AccountStatus, EmployeeStatus
from app.core.exceptions import NotFoundError
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


async def _make_user(conn: AsyncConnection[dict], name: str, org_id: int, *, is_admin: bool) -> int:
    """Create a user plus their membership in ``org_id``; return the id."""
    email = f"{uuid.uuid4().hex}@test.invalid"
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s)"
            " RETURNING employee_id",
            (name, email, "argon2$not-a-real-hash"),
        )
        row = await cur.fetchone()
        assert row is not None
        employee_id = int(row["employee_id"])
        await cur.execute(
            "INSERT INTO memberships (employee_id, organization_id, is_admin) VALUES (%s, %s, %s)",
            (employee_id, org_id, is_admin),
        )
    await conn.commit()
    return employee_id


async def _make_org(conn: AsyncConnection[dict], slug: str) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO organizations (name, slug, description) VALUES (%s, %s, %s)"
            " RETURNING organization_id",
            (slug, slug, "tenant isolation fixture"),
        )
        row = await cur.fetchone()
        assert row is not None
    await conn.commit()
    return int(row["organization_id"])


async def test_list_users_returns_only_own_organization(
    clean_db: AsyncConnection[dict],
) -> None:
    org_a = await _make_org(clean_db, "org-a")
    org_b = await _make_org(clean_db, "org-b")
    a_admin = await _make_user(clean_db, "A Admin", org_a, is_admin=True)
    a_member = await _make_user(clean_db, "A Member", org_a, is_admin=False)
    await _make_user(clean_db, "B Admin", org_b, is_admin=True)

    svc = UserService()
    page = await svc.list_users(clean_db, organization_id=org_a, limit=50, cursor=None)
    listed = {u.employee_id for u in page.items}
    assert listed == {a_admin, a_member}
    assert all(u.email.endswith("@test.invalid") for u in page.items)

    # The other tenant's roster is invisible from org A.
    other = await svc.list_users(clean_db, organization_id=org_b, limit=50, cursor=None)
    assert a_admin not in {u.employee_id for u in other.items}


async def test_update_user_cannot_reach_another_organization(
    clean_db: AsyncConnection[dict],
) -> None:
    org_a = await _make_org(clean_db, "org-a")
    org_b = await _make_org(clean_db, "org-b")
    await _make_user(clean_db, "A Admin", org_a, is_admin=True)
    b_member = await _make_user(clean_db, "B Member", org_b, is_admin=False)

    svc = UserService()
    with pytest.raises(NotFoundError):
        await svc.update_user(
            clean_db,
            actor_id=1,
            organization_id=org_a,
            employee_id=b_member,
            payload=UserUpdate(account_status=AccountStatus.SUSPENDED),
        )

    # The target's account status is untouched.
    me = await svc.get_me(clean_db, b_member)
    assert me.account_status == AccountStatus.ACTIVE


async def test_update_user_cannot_touch_another_organization_status_log(
    clean_db: AsyncConnection[dict],
) -> None:
    org_a = await _make_org(clean_db, "org-a")
    org_b = await _make_org(clean_db, "org-b")
    await _make_user(clean_db, "A Admin", org_a, is_admin=True)
    b_member = await _make_user(clean_db, "B Member", org_b, is_admin=False)

    svc = UserService()
    with pytest.raises(NotFoundError):
        await svc.create_status(
            clean_db,
            actor_id=1,
            organization_id=org_a,
            employee_id=b_member,
            payload=EmployeeStatusCreate(status=EmployeeStatus.ON_LEAVE),
        )
    with pytest.raises(NotFoundError):
        await svc.list_statuses(clean_db, organization_id=org_a, employee_id=b_member)

    async with clean_db.cursor() as cur:
        await cur.execute("SELECT count(*) AS n FROM employee_status")
        row = await cur.fetchone()
    assert row is not None and int(row["n"]) == 0


async def test_user_in_two_organizations_appears_in_both_rosters(
    clean_db: AsyncConnection[dict],
) -> None:
    """A shared person is a member of both rosters — but only once each."""
    org_a = await _make_org(clean_db, "org-a")
    org_b = await _make_org(clean_db, "org-b")
    shared = await _make_user(clean_db, "Shared", org_a, is_admin=False)
    async with clean_db.cursor() as cur:
        await cur.execute(
            "INSERT INTO memberships (employee_id, organization_id, is_admin) VALUES (%s, %s, %s)",
            (shared, org_b, False),
        )
    await clean_db.commit()

    svc = UserService()
    page_a = await svc.list_users(clean_db, organization_id=org_a, limit=50, cursor=None)
    page_b = await svc.list_users(clean_db, organization_id=org_b, limit=50, cursor=None)
    assert [u.employee_id for u in page_a.items] == [shared]
    assert [u.employee_id for u in page_b.items] == [shared]
