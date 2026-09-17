"""psycopg3 ``AsyncConnectionPool`` lifecycle (arch. doc §3.2, §25).

The pool is created with ``open=False`` and opened explicitly in the app
lifespan — constructor-open is deprecated in psycopg3. All connections use
``dict_row`` and inherit a ``statement_timeout`` from settings.
"""

from __future__ import annotations

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from app.core.config import Settings

_pool: AsyncConnectionPool | None = None


def create_pool(settings: Settings) -> AsyncConnectionPool:
    """Create (but do not open) the process-wide pool."""
    global _pool
    _pool = AsyncConnectionPool(
        conninfo=settings.database_url,
        min_size=settings.db_pool_min_size,
        max_size=settings.db_pool_max_size,
        open=False,
        kwargs={
            "row_factory": dict_row,
            "options": f"-c statement_timeout={settings.db_statement_timeout_ms}",
        },
    )
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def get_pool() -> AsyncConnectionPool:
    if _pool is None:
        msg = "Database pool is not initialised — check lifespan setup."
        raise RuntimeError(msg)
    return _pool
