"""Budget service behavior with in-memory doubles — no database.

Covers the §49 #21 additions: member-readable listing with a YYYY-MM
overlap filter, the admin-only PATCH (amount/dates with merged-date
validation), computed ``spent`` exposure, and 404-scoping rules.
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

import pytest

from app.budgets import service as budget_service_module
from app.budgets.schemas import BudgetCreate, BudgetUpdate
from app.budgets.service import BudgetService
from app.core.exceptions import NotFoundError, ValidationError


class _AuditStub:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    async def log(self, _conn: Any, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        return {"log_id": len(self.calls)}


class _RepositoryStub:
    def __init__(self) -> None:
        self.budgets: dict[int, dict[str, Any]] = {}
        self.memberships: dict[tuple[int, int], dict[str, Any]] = {}
        self._next = 1

    async def get_membership(
        self, _conn: Any, employee_id: int, org_id: int
    ) -> dict[str, Any] | None:
        return self.memberships.get((employee_id, org_id))

    def seed(
        self, budget_id: int, org_id: int, amount: str, start: str, end: str, spent: str
    ) -> None:
        self.budgets[budget_id] = {
            "budget_id": budget_id,
            "amount": Decimal(amount),
            "employee_id": 1,
            "organization_id": org_id,
            "start_date": date.fromisoformat(start),
            "end_date": date.fromisoformat(end),
            "created_at": datetime(2026, 1, 1),
            "updated_at": datetime(2026, 1, 1),
            "spent": Decimal(spent),
        }
        self._next = max(self._next, budget_id + 1)

    async def create(
        self,
        _conn: Any,
        *,
        amount: Decimal,
        employee_id: int,
        organization_id: int,
        start_date: date,
        end_date: date,
    ) -> dict[str, Any]:
        row = {
            "budget_id": self._next,
            "amount": amount,
            "employee_id": employee_id,
            "organization_id": organization_id,
            "start_date": start_date,
            "end_date": end_date,
            "created_at": datetime(2026, 1, 1),
            "updated_at": datetime(2026, 1, 1),
            "spent": Decimal("0"),
        }
        self.budgets[row["budget_id"]] = row
        self._next += 1
        return dict(row)

    async def get_by_id(self, _conn: Any, budget_id: int) -> dict[str, Any] | None:
        row = self.budgets.get(budget_id)
        return dict(row) if row else None

    async def list_by_org(
        self,
        _conn: Any,
        organization_id: int,
        *,
        range_start: date | None,
        range_end: date | None,
        limit: int,
        before_id: int | None,
    ) -> list[dict[str, Any]]:
        rows = []
        for row in sorted(self.budgets.values(), key=lambda r: r["budget_id"]):
            if row["organization_id"] != organization_id:
                continue
            if before_id is not None and row["budget_id"] >= before_id:
                continue
            if range_start is not None and row["end_date"] < range_start:
                continue
            if range_end is not None and row["start_date"] >= range_end:
                continue
            rows.append(dict(row))
        return rows[:limit]

    async def update(
        self,
        _conn: Any,
        budget_id: int,
        *,
        amount: Decimal | None = None,
        start_date: date | None = None,
        end_date: date | None = None,
    ) -> dict[str, Any] | None:
        row = self.budgets.get(budget_id)
        if row is None:
            return None
        if amount is not None:
            row["amount"] = amount
        if start_date is not None:
            row["start_date"] = start_date
        if end_date is not None:
            row["end_date"] = end_date
        return dict(row)


@pytest.fixture
def repo() -> _RepositoryStub:
    stub = _RepositoryStub()
    stub.memberships[(1, 10)] = {"membership_id": 1, "is_admin": True, "employee_id": 1}
    stub.memberships[(2, 10)] = {"membership_id": 2, "is_admin": False, "employee_id": 2}
    stub.seed(50, 10, "60000.00", "2026-10-01", "2026-10-31", "12400.00")
    stub.seed(51, 10, "9000.00", "2026-11-01", "2026-11-30", "0")
    stub.seed(52, 20, "777.00", "2026-10-01", "2026-10-31", "10.00")
    return stub


def _service(repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch) -> BudgetService:
    monkeypatch.setattr(budget_service_module, "audit_service", _AuditStub())
    return BudgetService(repository=repo)  # type: ignore[arg-type]


def _audit_of(monkeypatch: pytest.MonkeyPatch) -> _AuditStub:
    audit = _AuditStub()
    monkeypatch.setattr(budget_service_module, "audit_service", audit)
    return audit


async def test_list_budgets_member_readable_with_spent(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    items = await _service(repo, monkeypatch).list_budgets(
        object(), employee_id=2, organization_id=10, month=None, limit=10, before_id=None
    )
    assert [b.budget_id for b in items] == [50, 51]
    spent_by_id = {b.budget_id: b.spent for b in items}
    assert spent_by_id[50] == Decimal("12400.00")  # computed, from the repo
    assert spent_by_id[51] == Decimal("0")


async def test_list_budgets_month_filter_overlaps(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    items = await _service(repo, monkeypatch).list_budgets(
        object(), employee_id=1, organization_id=10, month="2026-10", limit=10, before_id=None
    )
    assert [b.budget_id for b in items] == [50]


async def test_list_budgets_cross_org_404(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    with pytest.raises(NotFoundError):
        await _service(repo, monkeypatch).list_budgets(
            object(), employee_id=2, organization_id=20, month=None, limit=10, before_id=None
        )


async def test_list_budgets_bad_month_422(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    with pytest.raises(ValidationError):
        await _service(repo, monkeypatch).list_budgets(
            object(), employee_id=1, organization_id=10, month="2026/10", limit=10, before_id=None
        )
    with pytest.raises(ValidationError):
        await _service(repo, monkeypatch).list_budgets(
            object(), employee_id=1, organization_id=10, month="2026-13", limit=10, before_id=None
        )


async def test_create_budget_admin_only_and_date_validation(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    svc = _service(repo, monkeypatch)
    response = await svc.create_budget(
        object(),
        actor_id=1,
        organization_id=10,
        payload=BudgetCreate(
            amount=Decimal("5000"), start_date=date(2026, 12, 1), end_date=date(2026, 12, 31)
        ),
    )
    assert response.amount == Decimal("5000")
    with pytest.raises(ValidationError):
        await svc.create_budget(
            object(),
            actor_id=1,
            organization_id=10,
            payload=BudgetCreate(
                amount=Decimal("5000"), start_date=date(2026, 12, 31), end_date=date(2026, 12, 1)
            ),
        )


async def test_patch_budget_amount_audits(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    audit = _audit_of(monkeypatch)
    svc = BudgetService(repository=repo)  # type: ignore[arg-type]
    response = await svc.update_budget(
        object(),
        actor_id=1,
        organization_id=10,
        budget_id=50,
        payload=BudgetUpdate(amount=Decimal("75000")),
    )
    assert response.amount == Decimal("75000")
    assert response.spent == Decimal("12400.00")
    assert audit.calls[-1]["action"] == "budget.update"
    assert repo.budgets[50]["amount"] == Decimal("75000")


async def test_patch_budget_noop_no_audit(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    audit = _audit_of(monkeypatch)
    svc = BudgetService(repository=repo)  # type: ignore[arg-type]
    before = Decimal(repo.budgets[50]["amount"])
    response = await svc.update_budget(
        object(), actor_id=1, organization_id=10, budget_id=50, payload=BudgetUpdate()
    )
    assert response.amount == before
    assert audit.calls == []


async def test_patch_budget_dates_merged_validation_422(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A PATCH that starts the budget AFTER its existing end_date is a 422."""
    svc = _service(repo, monkeypatch)
    with pytest.raises(ValidationError):
        await svc.update_budget(
            object(),
            actor_id=1,
            organization_id=10,
            budget_id=51,  # 2026-11-01..2026-11-30
            payload=BudgetUpdate(start_date=date(2026, 12, 1)),
        )


async def test_patch_budget_cross_org_404(
    repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    svc = _service(repo, monkeypatch)
    with pytest.raises(NotFoundError):
        await svc.update_budget(
            object(),
            actor_id=1,
            organization_id=10,
            budget_id=52,  # belongs to org 20
            payload=BudgetUpdate(amount=Decimal("1")),
        )
    with pytest.raises(NotFoundError):
        await svc.update_budget(
            object(),
            actor_id=1,
            organization_id=10,
            budget_id=999,
            payload=BudgetUpdate(amount=Decimal("1")),
        )
