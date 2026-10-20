"""Analytics service behavior with in-memory doubles — no database.

Pins the dashboard contract: one definition of spend, zero-filled chart
series, previous-period comparison, tenant 404s, and window validation.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any

import pytest

from app.analytics.service import AnalyticsService
from app.core.exceptions import NotFoundError, ValidationError


class _RepositoryStub:
    def __init__(self) -> None:
        self.memberships = {(1, 10): {"membership_id": 1, "is_admin": True}}
        self.summaries: list[dict[str, Any]] = [
            {
                "total_spend": Decimal("1000.00"),
                "pending_count": 2,
                "pending_amount": Decimal("300.00"),
                "info_requested_count": 1,
                "info_requested_amount": Decimal("50.00"),
                "approved_count": 3,
                "approved_amount": Decimal("700.00"),
                "rejected_count": 1,
                "rejected_amount": Decimal("100.00"),
                "reimbursed_count": 1,
                "reimbursed_amount": Decimal("300.00"),
                "total_claims": 7,
                "avg_approval_days": 1.5,
            },
            {"total_spend": Decimal("800.00")},
        ]
        self.calls: list[tuple[str, dict[str, Any]]] = []

    async def get_membership(
        self, _conn: Any, employee_id: int, org_id: int
    ) -> dict[str, Any] | None:
        return self.memberships.get((employee_id, org_id))

    async def summary(self, _conn: Any, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(("summary", kwargs))
        return self.summaries.pop(0)

    async def budget_allocated(self, _conn: Any, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(("budget_allocated", kwargs))
        return {"budget": Decimal("2000.00")}

    async def monthly(self, _conn: Any, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(("monthly", kwargs))
        return [
            {
                "month": "2026-08",
                "label": "Aug",
                "spend": Decimal("200"),
                "budget": Decimal("1000"),
                "pending_count": 1,
            }
        ]

    async def categories(self, _conn: Any, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(("categories", kwargs))
        return [{"name": "Travel", "amount": Decimal("900"), "count": 2}]

    async def projects(self, _conn: Any, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(("projects", kwargs))
        return [
            {
                "project_id": 5,
                "name": "Apollo",
                "amount": Decimal("700"),
                "budget": Decimal("1500"),
                "count": 2,
            }
        ]

    async def aging(self, _conn: Any, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(("aging", kwargs))
        return [{"bucket": "0-2 days", "count": 2, "amount": Decimal("300")}]

    async def top_spenders(self, _conn: Any, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(("top_spenders", kwargs))
        return [{"employee_id": 3, "name": "Asha", "amount": Decimal("800"), "count": 3}]

    async def reimbursements(self, _conn: Any, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(("reimbursements", kwargs))
        return [{"status": "paid", "count": 1, "amount": Decimal("300"), "avg_payment_days": 2.0}]

    async def status_breakdown(self, _conn: Any, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(("status_breakdown", kwargs))
        return [
            {"status": "approved", "count": 3, "amount": Decimal("700")},
            {"status": "pending", "count": 2, "amount": Decimal("300")},
        ]


@pytest.fixture
def repo() -> _RepositoryStub:
    return _RepositoryStub()


async def test_overview_composes_dashboard_payload(repo: _RepositoryStub) -> None:
    overview = await AnalyticsService(repository=repo).overview(  # type: ignore[arg-type]
        object(),
        employee_id=1,
        organization_id=10,
        from_date=date(2026, 8, 1),
        to_date=date(2026, 10, 20),
    )

    assert overview.summary.total_spend == Decimal("1000.00")
    assert overview.summary.budget_allocated == Decimal("2000.00")
    assert overview.summary.budget_utilisation == 0.5
    assert overview.summary.previous_spend == Decimal("800.00")
    assert overview.summary.spend_change_pct == 25.0
    assert overview.summary.avg_approval_days == 1.5

    assert [point.month for point in overview.monthly] == ["2026-08"]
    assert overview.monthly[0].pending_count == 1

    # Aging and status slices are zero-filled in canonical order.
    assert [bucket.label for bucket in overview.aging] == [
        "0-2 days",
        "3-7 days",
        "8-14 days",
        "15+ days",
    ]
    assert overview.aging[1].count == 0
    assert [item.status for item in overview.status_breakdown] == [
        "pending",
        "info_requested",
        "approved",
        "rejected",
        "reimbursed",
    ]
    assert overview.status_breakdown[0].count == 2
    assert overview.status_breakdown[1].count == 0

    assert overview.reimbursements.paid_count == 1
    assert overview.reimbursements.pending_count == 0
    assert overview.reimbursements.avg_payment_days == 2.0

    assert overview.categories[0].name == "Travel"
    assert overview.projects[0].budget == Decimal("1500")
    assert overview.top_spenders[0].employee_id == 3


async def test_personal_view_is_scoped_to_the_caller(repo: _RepositoryStub) -> None:
    analytics = await AnalyticsService(repository=repo).personal(  # type: ignore[arg-type]
        object(),
        employee_id=1,
        organization_id=10,
        from_date=date(2026, 10, 1),
        to_date=date(2026, 10, 31),
    )
    assert analytics.summary.total_claims == 7
    summary_call = next(call for call in repo.calls if call[0] == "summary")
    assert summary_call[1]["employee_id"] == 1
    monthly_call = next(call for call in repo.calls if call[0] == "monthly")
    assert monthly_call[1]["employee_id"] == 1


async def test_default_window_covers_six_months(repo: _RepositoryStub) -> None:
    overview = await AnalyticsService(repository=repo).overview(  # type: ignore[arg-type]
        object(),
        employee_id=1,
        organization_id=10,
        from_date=None,
        to_date=date(2026, 10, 20),
    )
    assert overview.from_date == date(2026, 5, 1)
    assert overview.to_date == date(2026, 10, 20)


async def test_window_validation(repo: _RepositoryStub) -> None:
    service = AnalyticsService(repository=repo)  # type: ignore[arg-type]
    with pytest.raises(ValidationError):
        await service.overview(
            object(),
            employee_id=1,
            organization_id=10,
            from_date=date(2026, 10, 2),
            to_date=date(2026, 10, 1),
        )
    with pytest.raises(ValidationError):
        await service.overview(
            object(),
            employee_id=1,
            organization_id=10,
            from_date=date(2023, 1, 1),
            to_date=date(2026, 10, 1),
        )


async def test_cross_org_is_404(repo: _RepositoryStub) -> None:
    with pytest.raises(NotFoundError):
        await AnalyticsService(repository=repo).overview(  # type: ignore[arg-type]
            object(),
            employee_id=1,
            organization_id=99,
            from_date=None,
            to_date=None,
        )
