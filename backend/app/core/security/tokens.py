"""Opaque token helpers — generation, hashing, expiry (arch. doc §14).

Client-visible refresh/reset tokens are random; only their SHA-256 hash is
stored in ``authentication_tokens``. No SQL lives here — persistence belongs
to repositories (§5, §32). Expired-token cleanup is an auth-repository
responsibility.
"""

from __future__ import annotations

import hashlib
import secrets
from datetime import UTC, datetime, timedelta

from app.core.config import get_settings

_TOKEN_BYTES = 48


def generate_token() -> str:
    """Cryptographically random opaque token — the client-visible value."""
    return secrets.token_urlsafe(_TOKEN_BYTES)


def hash_token(token: str) -> str:
    """SHA-256 hex digest — the only form ever persisted or indexed."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def utc_now_naive() -> datetime:
    """Naive UTC now.

    The schema uses ``TIMESTAMP`` (without time zone) — naive UTC datetimes are
    the convention for every value written to those columns.
    """
    return datetime.now(UTC).replace(tzinfo=None)


def refresh_token_expiry(now: datetime | None = None) -> datetime:
    """Expiry timestamp for a freshly issued refresh token (naive UTC)."""
    current = now or utc_now_naive()
    return current + timedelta(days=get_settings().jwt_refresh_token_expire_days)


def is_expired(expires_at: datetime, now: datetime | None = None) -> bool:
    """Expiry check, tolerant of naive values read from PostgreSQL."""
    if expires_at.tzinfo is not None:
        expires_at = expires_at.astimezone(UTC).replace(tzinfo=None)
    return expires_at <= (now or utc_now_naive())
