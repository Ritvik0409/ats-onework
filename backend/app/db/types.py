"""Shared DB type aliases.

Row factory: ``dict_row`` — repositories return dicts, Pydantic validates via
``model_validate(dict)``. Decided once, used everywhere (§3.2, plan decision).
"""

from __future__ import annotations

from psycopg import AsyncConnection

type Conn = AsyncConnection[dict]
type Row = dict
