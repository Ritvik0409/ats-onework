"""Analytics repository SQL composition — no database.

The repository builds its statements by composing fixed fragments with
the caller's parameters. The risk is not injection (the fragments are
literals) but *ordering*: a parameter that is added in one place and
forgotten in another silently reads a different column. These tests
pin the fragments and the parameter order.
"""

from __future__ import annotations

from datetime import date
from typing import Any

from app.analytics.repository import AnalyticsRepository


class _FakeCursor:
    def __init__(self, sink: dict[str, Any]) -> None:
        self._sink = sink

    async def __aenter__(self) -> _FakeCursor:
        return self

    async def __aexit__(self, *_: object) -> None:
        return None

    async def execute(self, sql: str, params: tuple[Any, ...]) -> None:
        self._sink["sql"] = sql
        self._sink["params"] = params

    async def fetchone(self) -> dict[str, Any]:
        return {"budget": 0}

    async def fetchall(self) -> list[dict[str, Any]]:
        return []


class _FakeConnection:
    def __init__(self) -> None:
        self.sink: dict[str, Any] = {}

    def cursor(self) -> _FakeCursor:
        return _FakeCursor(self.sink)


async def test_the_organization_budget_is_not_scoped_to_one_employee() -> None:
    conn = _FakeConnection()
    repository = AnalyticsRepository()

    await repository.budget_allocated(
        conn,  # type: ignore[arg-type]
        organization_id=10,
        from_date=date(2026, 5, 1),
        to_date=date(2026, 10, 20),
    )

    assert "employee_id" not in conn.sink["sql"]
    assert conn.sink["params"] == (10, date(2026, 10, 20), date(2026, 5, 1))


async def test_a_personal_budget_is_scoped_to_its_owner() -> None:
    conn = _FakeConnection()
    repository = AnalyticsRepository()

    await repository.budget_allocated(
        conn,  # type: ignore[arg-type]
        organization_id=10,
        from_date=date(2026, 5, 1),
        to_date=date(2026, 10, 20),
        employee_id=7,
    )

    assert "budgets.employee_id = %s" in conn.sink["sql"]
    # The owner is the last parameter, after the organization and the
    # window — a swapped pair would read the wrong column.
    assert conn.sink["params"] == (
        10,
        date(2026, 10, 20),
        date(2026, 5, 1),
        7,
    )


async def test_the_monthly_series_scopes_both_expenses_and_budget() -> None:
    conn = _FakeConnection()
    repository = AnalyticsRepository()

    await repository.monthly(
        conn,  # type: ignore[arg-type]
        organization_id=10,
        month_start=date(2026, 5, 1),
        month_end=date(2026, 10, 1),
        employee_id=7,
    )

    sql = conn.sink["sql"]
    params = conn.sink["params"]
    assert "e.employee_id = %s" in sql
    assert "bd.employee_id = %s" in sql
    # months, months, org, owner, org, owner
    assert params == (
        date(2026, 5, 1),
        date(2026, 10, 1),
        10,
        7,
        10,
        7,
    )


async def test_the_organization_series_carries_no_owner_filter() -> None:
    conn = _FakeConnection()
    repository = AnalyticsRepository()

    await repository.monthly(
        conn,  # type: ignore[arg-type]
        organization_id=10,
        month_start=date(2026, 5, 1),
        month_end=date(2026, 10, 1),
    )

    sql = conn.sink["sql"]
    assert "e.employee_id" not in sql
    assert "bd.employee_id" not in sql
    assert conn.sink["params"] == (
        date(2026, 5, 1),
        date(2026, 10, 1),
        10,
        10,
    )
