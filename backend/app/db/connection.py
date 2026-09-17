"""FastAPI dependency yielding a pooled connection (arch. doc §3.2, §25).

Transaction boundary — the ONLY place request-scoped transaction boundaries
live (§7): psycopg3 commits on clean context exit and rolls back on exception.
Services orchestrate multi-write workflows inside this boundary; repositories
never call ``conn.commit()`` themselves.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from app.db.pool import get_pool
from app.db.types import Conn


async def get_connection() -> AsyncIterator[Conn]:
    pool = get_pool()
    async with pool.connection() as conn:
        yield conn
