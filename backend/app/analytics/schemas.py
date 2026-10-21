"""Analytics DTOs — aggregate read models for the dashboards.

Every figure is computed by the database over the whole tenant, not from
the first page of expenses the client happens to hold. Money fields stay
``Decimal``; Pydantic serializes them as strings, which the Flutter client
already parses tolerantly.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class AnalyticsTotals(BaseModel):
    """Status totals for one date window."""

    model_config = ConfigDict(from_attributes=True)

    total_spend: Decimal = Decimal("0")
    pending_count: int = 0
    pending_amount: Decimal = Decimal("0")
    info_requested_count: int = 0
    info_requested_amount: Decimal = Decimal("0")
    approved_count: int = 0
    approved_amount: Decimal = Decimal("0")
    rejected_count: int = 0
    rejected_amount: Decimal = Decimal("0")
    reimbursed_count: int = 0
    reimbursed_amount: Decimal = Decimal("0")
    total_claims: int = 0
    avg_approval_days: float | None = None


class AnalyticsSummary(AnalyticsTotals):
    """Organization totals plus budget context and period comparison."""

    budget_allocated: Decimal = Decimal("0")
    budget_utilisation: float = 0.0
    previous_spend: Decimal = Decimal("0")
    spend_change_pct: float | None = None


class MonthlyPoint(BaseModel):
    """One month of the trend series. ``month`` is ``YYYY-MM``."""

    month: str
    label: str
    spend: Decimal = Decimal("0")
    budget: Decimal = Decimal("0")
    pending_count: int = 0
    pending_amount: Decimal = Decimal("0")
    approved_count: int = 0
    approved_amount: Decimal = Decimal("0")
    rejected_count: int = 0
    rejected_amount: Decimal = Decimal("0")


class CategorySlice(BaseModel):
    name: str
    amount: Decimal = Decimal("0")
    count: int = 0


class ProjectSlice(BaseModel):
    project_id: int
    name: str
    amount: Decimal = Decimal("0")
    budget: Decimal = Decimal("0")
    count: int = 0


class AgingBucket(BaseModel):
    """How long the current review queue has been waiting."""

    label: str
    count: int = 0
    amount: Decimal = Decimal("0")


class TopSpender(BaseModel):
    employee_id: int
    name: str
    amount: Decimal = Decimal("0")
    count: int = 0


class ReimbursementStats(BaseModel):
    pending_count: int = 0
    pending_amount: Decimal = Decimal("0")
    processing_count: int = 0
    processing_amount: Decimal = Decimal("0")
    paid_count: int = 0
    paid_amount: Decimal = Decimal("0")
    failed_count: int = 0
    failed_amount: Decimal = Decimal("0")
    avg_payment_days: float | None = None


class StatusSlice(BaseModel):
    status: str
    label: str
    count: int = 0
    amount: Decimal = Decimal("0")


class AnalyticsOverview(BaseModel):
    """Everything the management dashboards need in one round-trip."""

    from_date: date
    to_date: date
    summary: AnalyticsSummary
    monthly: list[MonthlyPoint]
    categories: list[CategorySlice]
    projects: list[ProjectSlice]
    aging: list[AgingBucket]
    top_spenders: list[TopSpender]
    reimbursements: ReimbursementStats
    status_breakdown: list[StatusSlice]


class PersonalAnalytics(BaseModel):
    """The employee's own activity for the same window."""

    from_date: date
    to_date: date
    summary: AnalyticsTotals
    monthly: list[MonthlyPoint]
    categories: list[CategorySlice]
    status_breakdown: list[StatusSlice]
