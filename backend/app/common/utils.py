"""Small shared utilities. Add nothing here without a second real use case
(§46 — no mega-utils)."""

from __future__ import annotations

import re
from datetime import UTC, datetime

_SLUG_RE = re.compile(r"[^a-z0-9]+")


def utc_now() -> datetime:
    """Timezone-aware UTC now — for JWT claims and internal comparisons."""
    return datetime.now(UTC)


def slugify(value: str) -> str:
    """Lowercase ASCII slug — organization slugs and similar identifiers."""
    return _SLUG_RE.sub("-", value.strip().lower()).strip("-")
