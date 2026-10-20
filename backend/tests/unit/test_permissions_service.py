"""Role-scoped permission evaluation — no database required.

The evaluation is database-backed, so these tests use a fake connection
that records the query and returns the requested rows.
"""

from __future__ import annotations

from typing import Any

import pytest

from app.api.v1.deps import CurrentUser
from app.common.permissions import (
    RequireAnyPermission,
    RequirePermission,
    granted_permissions,
    has_permission,
)
from app.core.exceptions import AuthorizationError


class _FakeCursor:
    """A cursor over a queue of result sets.

    ``results`` is a list of result sets; each fetch pops the next one.
    """

    def __init__(self, results: list[list[dict[str, Any]]]) -> None:
        self._results = results

    async def execute(self, query: str, params: Any) -> None:
        pass

    async def fetchall(self) -> list[dict[str, Any]]:
        return self._results.pop(0) if self._results else []

    async def fetchone(self) -> dict[str, Any] | None:
        rows = self._results.pop(0) if self._results else []
        return rows[0] if rows else None

    async def __aenter__(self) -> _FakeCursor:
        return self

    async def __aexit__(self, *_exc: Any) -> None:
        return None


class _RecordingConn:
    """A connection that records the statements it was given."""

    def __init__(self, results: list[list[dict[str, Any]]]) -> None:
        self._results = results
        self.queries: list[tuple[str, Any]] = []

    def cursor(self) -> _FakeCursor:
        outer = self

        class _RecordingCursor(_FakeCursor):
            async def execute(self, query: str, params: Any) -> None:  # type: ignore[override]
                outer.queries.append((query, params))

        return _RecordingCursor(self._results)


def _user(*, is_superuser: bool = False) -> CurrentUser:
    return CurrentUser(employee_id=7, organization_id=3, is_admin=False, is_superuser=is_superuser)


async def test_granted_permissions_returns_the_names() -> None:
    conn = _RecordingConn([[{"api_name": "expense.read_own"}, {"api_name": "project.read"}]])
    granted = await granted_permissions(conn, employee_id=7, organization_id=3)
    assert granted == {"expense.read_own", "project.read"}


async def test_granted_permissions_is_scoped_to_the_organization() -> None:
    conn = _RecordingConn([])
    await granted_permissions(conn, employee_id=7, organization_id=3)
    query, params = conn.queries[0]
    assert "p.organization_id = %s" in query
    assert params == (3, 7, 3, 7, 3)


async def test_has_permission_checks_one_name() -> None:
    conn = _RecordingConn([[{"api_name": "expense.read_own"}]])
    assert await has_permission(conn, employee_id=7, organization_id=3, api_name="expense.read_own")
    assert not await has_permission(
        conn, employee_id=7, organization_id=3, api_name="expense.read_all"
    )


async def test_require_permission_allows_a_granted_capability() -> None:
    conn = _RecordingConn([[{"api_name": "expense.approve"}]])
    dependency = RequirePermission("expense.approve")
    user = _user()
    assert await dependency(user, conn) is user  # type: ignore[arg-type]


async def test_require_permission_rejects_a_missing_capability() -> None:
    conn = _RecordingConn([[{"api_name": "expense.read_own"}]])
    dependency = RequirePermission("expense.approve")
    with pytest.raises(AuthorizationError, match=r"expense\.approve"):
        await dependency(_user(), conn)  # type: ignore[arg-type]


async def test_require_any_permission_accepts_one_of_several() -> None:
    """Reading your own expenses and reading them all open the same door."""
    conn = _RecordingConn([[{"api_name": "expense.read_own"}]])
    dependency = RequireAnyPermission("expense.read_own", "expense.read_all")
    user = _user()
    assert await dependency(user, conn) is user  # type: ignore[arg-type]


async def test_require_any_permission_rejects_when_none_is_held() -> None:
    conn = _RecordingConn([[{"api_name": "project.read"}]])
    dependency = RequireAnyPermission("expense.read_own", "expense.read_all")
    with pytest.raises(AuthorizationError, match=r"expense\.read_own"):
        await dependency(_user(), conn)  # type: ignore[arg-type]
