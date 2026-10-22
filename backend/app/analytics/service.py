"""Analytics business rules — date windows, comparison, label mapping.

The repository returns raw aggregate rows; this service turns them into
the response models the dashboards consume, and keeps every figure on one
definition of spend (approved + reimbursed).
"""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

from app.analytics.repository import AnalyticsRepository
from app.analytics.schemas import (
    AgingBucket,
    AnalyticsOverview,
    AnalyticsSummary,
    AnalyticsTotals,
    CategorySlice,
    MonthlyPoint,
    PersonalAnalytics,
    ProjectSlice,
    ReimbursementStats,
    StatusSlice,
    TopSpender,
)
from app.common.tenant import require_path_member
from app.core.constants import ExpenseStatus
from app.core.exceptions import ValidationError
from app.core.security.tokens import ist_now_naive
from app.db.types import Conn

_repository = AnalyticsRepository()

_MAX_WINDOW_DAYS = 750  # two years of monthly points at most

_STATUS_LABELS = {
    ExpenseStatus.PENDING: "Pending review",
    ExpenseStatus.INFO_REQUESTED: "Info requested",
    ExpenseStatus.APPROVED: "Approved",
    ExpenseStatus.REJECTED: "Rejected",
    ExpenseStatus.REIMBURSED: "Reimbursed",
}

_AGING_LABELS = ("0-2 days", "3-7 days", "8-14 days", "15+ days")

_REIMBURSEMENT_LABELS = ("pending", "processing", "paid", "failed")


def _decimal(value: object) -> Decimal:
    if value is None:
        return Decimal("0")
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def _rounded_pct(current: Decimal, previous: Decimal) -> float | None:
    if previous <= 0:
        return None
    return round(float((current - previous) / previous * 100), 1)


class AnalyticsService:
    def __init__(self, repository: AnalyticsRepository | None = None) -> None:
        self._repository = repository or _repository

    async def overview(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        from_date: date | None,
        to_date: date | None,
    ) -> AnalyticsOverview:
        await self._require_member(conn, employee_id, organization_id)
        start, end = self._window(from_date, to_date)

        summary_row = await self._repository.summary(
            conn,
            organization_id=organization_id,
            from_date=start,
            to_date=end,
        )
        budget_row = await self._repository.budget_allocated(
            conn, organization_id=organization_id, from_date=start, to_date=end
        )
        totals = AnalyticsTotals.model_validate(summary_row)
        budget = _decimal(budget_row.get("budget"))
        utilisation = float(totals.total_spend / budget) if budget > 0 else 0.0

        previous_start, previous_end = self._previous_window(start, end)
        previous_row = await self._repository.summary(
            conn,
            organization_id=organization_id,
            from_date=previous_start,
            to_date=previous_end,
        )
        previous_spend = _decimal(previous_row.get("total_spend"))

        month_start = start.replace(day=1)
        month_end = end.replace(day=1)
        # The organization view is not scoped to the caller: the whole
        # tenant's spend and the whole tenant's budget.
        monthly_rows = await self._repository.monthly(
            conn,
            organization_id=organization_id,
            month_start=month_start,
            month_end=month_end,
        )
        category_rows = await self._repository.categories(
            conn, organization_id=organization_id, from_date=start, to_date=end
        )
        project_rows = await self._repository.projects(
            conn, organization_id=organization_id, from_date=start, to_date=end
        )
        aging_rows = await self._repository.aging(conn, organization_id=organization_id)
        spender_rows = await self._repository.top_spenders(
            conn, organization_id=organization_id, from_date=start, to_date=end
        )
        reimbursement_rows = await self._repository.reimbursements(
            conn, organization_id=organization_id, from_date=start, to_date=end
        )
        status_rows = await self._repository.status_breakdown(
            conn, organization_id=organization_id, from_date=start, to_date=end
        )

        summary = AnalyticsSummary(
            **totals.model_dump(),
            budget_allocated=budget,
            budget_utilisation=round(utilisation, 4),
            previous_spend=previous_spend,
            spend_change_pct=_rounded_pct(totals.total_spend, previous_spend),
        )

        return AnalyticsOverview(
            from_date=start,
            to_date=end,
            summary=summary,
            monthly=[MonthlyPoint.model_validate(row) for row in monthly_rows],
            categories=[CategorySlice.model_validate(row) for row in category_rows],
            projects=[ProjectSlice.model_validate(row) for row in project_rows],
            aging=self._aging(aging_rows),
            top_spenders=[TopSpender.model_validate(row) for row in spender_rows],
            reimbursements=self._reimbursements(reimbursement_rows),
            status_breakdown=self._statuses(status_rows),
        )

    async def personal(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        from_date: date | None,
        to_date: date | None,
    ) -> PersonalAnalytics:
        await self._require_member(conn, employee_id, organization_id)
        start, end = self._window(from_date, to_date)

        summary_row = await self._repository.summary(
            conn,
            organization_id=organization_id,
            from_date=start,
            to_date=end,
            employee_id=employee_id,
        )
        month_start = start.replace(day=1)
        month_end = end.replace(day=1)
        monthly_rows = await self._repository.monthly(
            conn,
            organization_id=organization_id,
            month_start=month_start,
            month_end=month_end,
            employee_id=employee_id,
        )
        category_rows = await self._repository.categories(
            conn,
            organization_id=organization_id,
            from_date=start,
            to_date=end,
            employee_id=employee_id,
        )
        status_rows = await self._repository.status_breakdown(
            conn,
            organization_id=organization_id,
            from_date=start,
            to_date=end,
            employee_id=employee_id,
        )

        return PersonalAnalytics(
            from_date=start,
            to_date=end,
            summary=AnalyticsTotals.model_validate(summary_row),
            monthly=[MonthlyPoint.model_validate(row) for row in monthly_rows],
            categories=[CategorySlice.model_validate(row) for row in category_rows],
            status_breakdown=self._statuses(status_rows),
        )

    # -- helpers ----------------------------------------------------------

    @staticmethod
    def _window(from_date: date | None, to_date: date | None) -> tuple[date, date]:
        """Resolve the requested window, defaulting to the last six months."""
        today = ist_now_naive().date()
        end = to_date or today
        if from_date is None:
            # First day of the month five months before ``end``.
            month_index = end.year * 12 + end.month - 1 - 5
            start = date(month_index // 12, month_index % 12 + 1, 1)
        else:
            start = from_date
        if start > end:
            raise ValidationError("from must be on or before to.")
        if (end - start).days > _MAX_WINDOW_DAYS:
            raise ValidationError("The analytics window is limited to two years.")
        return start, end

    @staticmethod
    def _previous_window(start: date, end: date) -> tuple[date, date]:
        """The same number of days immediately before the window."""
        duration = (end - start).days + 1
        previous_end = start - timedelta(days=1)
        previous_start = previous_end - timedelta(days=duration - 1)
        return previous_start, previous_end

    @staticmethod
    def _aging(rows: list[dict]) -> list[AgingBucket]:
        found = {row["bucket"]: row for row in rows}
        buckets: list[AgingBucket] = []
        for label in _AGING_LABELS:
            row = found.get(label, {})
            buckets.append(
                AgingBucket(
                    label=label,
                    count=int(row.get("count") or 0),
                    amount=_decimal(row.get("amount")),
                )
            )
        return buckets

    @staticmethod
    def _statuses(rows: list[dict]) -> list[StatusSlice]:
        found = {row["status"]: row for row in rows}
        slices: list[StatusSlice] = []
        for status in ExpenseStatus:
            row = found.get(status.value, {})
            slices.append(
                StatusSlice(
                    status=status.value,
                    label=_STATUS_LABELS[status],
                    count=int(row.get("count") or 0),
                    amount=_decimal(row.get("amount")),
                )
            )
        return slices

    @staticmethod
    def _reimbursements(rows: list[dict]) -> ReimbursementStats:
        found = {row["status"]: row for row in rows}
        avg = next(
            (
                row.get("avg_payment_days")
                for row in rows
                if row.get("avg_payment_days") is not None
            ),
            None,
        )
        stats = ReimbursementStats(avg_payment_days=float(avg) if avg is not None else None)
        for status in _REIMBURSEMENT_LABELS:
            row = found.get(status, {})
            setattr(stats, f"{status}_count", int(row.get("count") or 0))
            setattr(stats, f"{status}_amount", _decimal(row.get("amount")))
        return stats

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> None:
        require_path_member(await self._repository.get_membership(conn, employee_id, org_id))


service = AnalyticsService()
