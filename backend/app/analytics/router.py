"""Analytics endpoints — HTTP only (§49).

Both routes are nested under the organization they report on, so the
tenant check is the path's organization rather than the token's active
one. The organization-wide view needs ``expense.read_all``; the personal
view needs ``expense.read_own`` and is always scoped to the caller.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.analytics.schemas import AnalyticsOverview, PersonalAnalytics
from app.analytics.service import service as analytics_service
from app.api.v1.deps import CurrentUser
from app.common.permissions import RequirePathPermission
from app.db.connection import get_connection
from app.db.types import Conn

router = APIRouter(prefix="/organizations", tags=["analytics"])


@router.get("/{organization_id}/analytics/overview", response_model=AnalyticsOverview)
async def analytics_overview(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(RequirePathPermission("expense.read_all"))],
    conn: Annotated[Conn, Depends(get_connection)],
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> AnalyticsOverview:
    return await analytics_service.overview(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        from_date=from_date,
        to_date=to_date,
    )


@router.get("/{organization_id}/analytics/me", response_model=PersonalAnalytics)
async def my_analytics(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(RequirePathPermission("expense.read_own"))],
    conn: Annotated[Conn, Depends(get_connection)],
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> PersonalAnalytics:
    return await analytics_service.personal(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        from_date=from_date,
        to_date=to_date,
    )
