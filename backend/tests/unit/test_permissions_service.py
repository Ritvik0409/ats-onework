"""Role-scoped permission evaluation — no database required.

The permission catalog is database-backed, so these tests use a fake
connection that records the query and returns the requested rows.
"""

from __future__ import annotations

from typing import Any

import pytest

from app.common.permissions import RequirePermission, has_permission
from app.core.exceptions import AuthorizationError


class _FakeCursor:
    def __init__(self, results: list[dict[str, Any]]) -> None:
        self._results = results
        self._index = 0

    async def execute(self, _query: str, _params: Any) -> None:
        pass

    async def fetchone(self) -> dict[str, Any]:
        row = self._results[self._index]
        self._index += 1
        return row

    async def __aenter__(self) -> _FakeCursor:
        return self

    async def __aexit__(self, *_exc: Any) -> None:
        return None


class _FakeConn:
    def __init__(self, results: list[dict[str, Any]]) -> None:
        self._results = results
        self.queries: list[tuple[str, Any]] = []

    def cursor(self) -> _FakeCursor:
        return _FakeCursor(self._results)


class _RecordingConn(_FakeConn):
    """Cursor that records the statements it was given."""

    def cursor(self) -> _FakeCursor:
        outer = self

        class _RecordingCursor(_FakeCursor):
            async def execute(self, query: str, params: Any) -> None:  # type: ignore[override]
                outer.queries.append((query, params))

        return _RecordingCursor(self._results)


async def test_permission_granted_through_a_role() -> None:
    conn = _FakeConn([{"exists": True}, {"exists": False}])
    assert await has_permission(
        conn, employee_id=1, organization_id=2, api_name="expense.create"
    )


async def test_permission_granted_directly() -> None:
    conn = _FakeConn([{"exists": False}, {"exists": True}])
    assert await has_permission(
        conn, employee_id=1, organization_id=2, api_name="expense.create"
    )


async def test_permission_not_granted() -> None:
    conn = _FakeConn([{"exists": False}, {"exists": False}])
    assert not await has_permission(
        conn, employee_id=1, organization_id=2, api_name="expense.create"
    )


async def test_role_grant_is_scoped_to_the_organization() -> None:
    conn = _RecordingConn([{"exists": True}, {"exists": False}])
    await has_permission(conn, employee_id=7, organization_id=3, api_name="expense.create")
    role_query, role_params = conn.queries[0]
    _, direct_params = conn.queries[1]
    assert "m.organization_id = %s" in role_query
    assert role_params == (7, 3, "expense.create")
    assert direct_params == (7, "expense.create", 3)


async def test_require_permission_rejects_a_missing_permission() -> None:
    conn = _FakeConn([{"exists": False}, {"exists": False}])
    dependency = RequirePermission("expense.approve")
    from app.api.v1.deps import CurrentUser

    with pytest.raises(AuthorizationError, match=r"expense\.approve"):
        await dependency(
            CurrentUser(employee_id=1, organization_id=2, is_admin=False),  # type: ignore[arg-type]
            conn,  # type: ignore[arg-type]
        )


async def test_require_permission_allows_an_admin_without_a_grant() -> None:
    conn = _FakeConn([])
    dependency = RequirePermission("expense.approve")
    from app.api.v1.deps import CurrentUser

    user = CurrentUser(employee_id=1, organization_id=2, is_admin=True)
    assert await dependency(user, conn) is user  # type: ignore[arg-type]
