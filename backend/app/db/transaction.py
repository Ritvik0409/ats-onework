"""Explicit transaction helpers (arch. doc §7).

A connection from ``get_connection`` already carries one request-scoped
transaction (commit/rollback at context exit). Use these helpers to scope
multi-write workflows explicitly; nesting is safe — psycopg3 creates a
SAVEPOINT inside an outer transaction.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from app.db.types import Conn


@asynccontextmanager
async def transaction(conn: Conn) -> AsyncIterator[None]:
    """Explicit transaction block — commit on success, rollback on error."""
    async with conn.transaction():
        yield
