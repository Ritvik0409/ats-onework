"""Health endpoints (arch. doc §49 #1-2). Registered at the root, not under /api/v1."""

from __future__ import annotations

import logging

from fastapi import APIRouter

from app.core.exceptions import TransientError
from app.db.pool import get_pool

logger = logging.getLogger(__name__)
router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    """Liveness — the process is up. No database dependency."""
    return {"status": "ok"}


@router.get("/ready")
async def ready() -> dict[str, str]:
    """Readiness — verifies a database round-trip (`SELECT 1`)."""
    try:
        async with get_pool().connection() as conn:
            await conn.execute("SELECT 1")
    except Exception:
        logger.exception("readiness check failed")
        raise TransientError("Database unavailable.") from None
    return {"status": "ok", "database": "up"}
