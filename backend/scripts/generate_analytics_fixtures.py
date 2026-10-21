"""Regenerate the analytics contract fixtures used by the Flutter client.

The Flutter dashboards parse the analytics payloads with hand-written
decoders, so the field names have to match the API exactly. The fixtures
below are serialized from the real Pydantic models, which makes that
match verifiable instead of a matter of hope: run this script after any
change to ``app/analytics/schemas.py`` and the Flutter contract test
fails if the client and the server have drifted apart.

Usage::

    .venv\\Scripts\\python.exe scripts\\generate_analytics_fixtures.py
"""

from __future__ import annotations

import json
import sys
from datetime import date
from decimal import Decimal
from pathlib import Path

# `python scripts/generate_analytics_fixtures.py` puts scripts/ (not
# backend/) on sys.path - the app package lives one level up.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

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

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "test" / "fixtures"


def _overview() -> AnalyticsOverview:
    return AnalyticsOverview(
        from_date=date(2026, 5, 1),
        to_date=date(2026, 10, 20),
        summary=AnalyticsSummary(
            total_spend=Decimal("482500.50"),
            pending_count=7,
            pending_amount=Decimal("91300.25"),
            info_requested_count=2,
            info_requested_amount=Decimal("15400.00"),
            approved_count=18,
            approved_amount=Decimal("245000.00"),
            rejected_count=3,
            rejected_amount=Decimal("22100.25"),
            reimbursed_count=25,
            reimbursed_amount=Decimal("237500.50"),
            total_claims=55,
            avg_approval_days=2.4,
            budget_allocated=Decimal("600000.00"),
            budget_utilisation=0.8042,
            previous_spend=Decimal("401000.00"),
            spend_change_pct=20.3,
        ),
        monthly=[
            MonthlyPoint(
                month="2026-05",
                label="May",
                spend=Decimal("62000.00"),
                budget=Decimal("100000.00"),
                pending_count=3,
                pending_amount=Decimal("12000.00"),
                approved_count=5,
                approved_amount=Decimal("30000.00"),
                rejected_count=1,
                rejected_amount=Decimal("5000.00"),
            ),
            MonthlyPoint(
                month="2026-06",
                label="Jun",
                spend=Decimal("84500.00"),
                budget=Decimal("100000.00"),
                pending_count=2,
                pending_amount=Decimal("9000.25"),
                approved_count=6,
                approved_amount=Decimal("42000.00"),
                rejected_count=1,
                rejected_amount=Decimal("7100.25"),
            ),
        ],
        categories=[
            CategorySlice(name="Travel", amount=Decimal("212000.00"), count=19),
            CategorySlice(name="Meals", amount=Decimal("120500.50"), count=24),
            CategorySlice(name="Software", amount=Decimal("98000.00"), count=6),
        ],
        projects=[
            ProjectSlice(
                project_id=7,
                name="Q4 Launch",
                amount=Decimal("180000.00"),
                budget=Decimal("250000.00"),
                count=12,
            ),
            ProjectSlice(
                project_id=9,
                name="Field Ops",
                amount=Decimal("96000.00"),
                budget=Decimal("90000.00"),
                count=8,
            ),
        ],
        aging=[
            AgingBucket(label="0-2 days", count=4, amount=Decimal("31000.00")),
            AgingBucket(label="3-7 days", count=3, amount=Decimal("42300.25")),
            AgingBucket(label="8-14 days", count=2, amount=Decimal("18000.00")),
            AgingBucket(label="15+ days", count=1, amount=Decimal("15400.00")),
        ],
        top_spenders=[
            TopSpender(
                employee_id=42,
                name="Aarav Mehta",
                amount=Decimal("96400.00"),
                count=11,
            ),
            TopSpender(
                employee_id=51,
                name="Diya Nair",
                amount=Decimal("71250.50"),
                count=9,
            ),
        ],
        reimbursements=ReimbursementStats(
            pending_count=4,
            pending_amount=Decimal("58000.00"),
            processing_count=2,
            processing_amount=Decimal("31500.00"),
            paid_count=25,
            paid_amount=Decimal("237500.50"),
            failed_count=1,
            failed_amount=Decimal("4200.00"),
            avg_payment_days=3.1,
        ),
        status_breakdown=[
            StatusSlice(
                status="pending",
                label="Pending review",
                count=7,
                amount=Decimal("91300.25"),
            ),
            StatusSlice(
                status="info_requested",
                label="Info requested",
                count=2,
                amount=Decimal("15400.00"),
            ),
            StatusSlice(
                status="approved",
                label="Approved",
                count=18,
                amount=Decimal("245000.00"),
            ),
            StatusSlice(
                status="rejected",
                label="Rejected",
                count=3,
                amount=Decimal("22100.25"),
            ),
            StatusSlice(
                status="reimbursed",
                label="Reimbursed",
                count=25,
                amount=Decimal("237500.50"),
            ),
        ],
    )


def _personal() -> PersonalAnalytics:
    return PersonalAnalytics(
        from_date=date(2026, 5, 1),
        to_date=date(2026, 10, 20),
        summary=AnalyticsTotals(
            total_spend=Decimal("48500.00"),
            pending_count=2,
            pending_amount=Decimal("9400.00"),
            info_requested_count=1,
            info_requested_amount=Decimal("2100.00"),
            approved_count=6,
            approved_amount=Decimal("19500.00"),
            rejected_count=1,
            rejected_amount=Decimal("1500.00"),
            reimbursed_count=8,
            reimbursed_amount=Decimal("29000.00"),
            total_claims=18,
            avg_approval_days=1.8,
        ),
        monthly=[
            MonthlyPoint(
                month="2026-09",
                label="Sep",
                spend=Decimal("12000.00"),
                budget=Decimal("0"),
                pending_count=1,
                pending_amount=Decimal("4000.00"),
                approved_count=3,
                approved_amount=Decimal("8000.00"),
                rejected_count=0,
                rejected_amount=Decimal("0"),
            ),
            MonthlyPoint(
                month="2026-10",
                label="Oct",
                spend=Decimal("18500.00"),
                budget=Decimal("0"),
                pending_count=1,
                pending_amount=Decimal("5400.00"),
                approved_count=3,
                approved_amount=Decimal("11500.00"),
                rejected_count=1,
                rejected_amount=Decimal("1500.00"),
            ),
        ],
        categories=[
            CategorySlice(name="Travel", amount=Decimal("31000.00"), count=5),
            CategorySlice(name="Meals", amount=Decimal("17500.00"), count=13),
        ],
        status_breakdown=[
            StatusSlice(
                status="pending",
                label="Pending review",
                count=2,
                amount=Decimal("9400.00"),
            ),
            StatusSlice(
                status="info_requested",
                label="Info requested",
                count=1,
                amount=Decimal("2100.00"),
            ),
            StatusSlice(
                status="approved",
                label="Approved",
                count=6,
                amount=Decimal("19500.00"),
            ),
            StatusSlice(
                status="rejected",
                label="Rejected",
                count=1,
                amount=Decimal("1500.00"),
            ),
            StatusSlice(
                status="reimbursed",
                label="Reimbursed",
                count=8,
                amount=Decimal("29000.00"),
            ),
        ],
    )


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / "analytics_overview.json").write_text(
        json.dumps(_overview().model_dump(mode="json"), indent=2) + "\n",
        encoding="utf-8",
    )
    (FIXTURES / "analytics_personal.json").write_text(
        json.dumps(_personal().model_dump(mode="json"), indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote fixtures to {FIXTURES}")


if __name__ == "__main__":
    main()
