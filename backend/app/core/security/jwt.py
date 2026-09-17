"""JWT access tokens — PyJWT with an explicit algorithm allow-list
(arch. doc §12; claims per ADR-001 §51).

Access token claims::

    sub   employee_id (string, per RFC 7519; int-validated on decode)
    org   active organization_id
    admin is_admin for that organization
    iat   issued-at
    exp   expiry
    typ   "access" (guards against token-type confusion)
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import jwt

from app.core.config import get_settings
from app.core.exceptions import AuthenticationError

_TYPE_CLAIM = "typ"
_ACCESS_TYPE = "access"


def create_access_token(
    *,
    employee_id: int,
    organization_id: int,
    is_admin: bool,
    expires_delta: timedelta | None = None,
) -> str:
    settings = get_settings()
    now = datetime.now(UTC)
    payload: dict[str, Any] = {
        "sub": str(employee_id),
        "org": organization_id,
        "admin": is_admin,
        "iat": now,
        "exp": now + (expires_delta or timedelta(minutes=settings.jwt_access_token_expire_minutes)),
        _TYPE_CLAIM: _ACCESS_TYPE,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict[str, Any]:
    """Decode and validate an access token.

    Raises AuthenticationError on any failure (expired, malformed, wrong type).
    The accepted algorithms come from settings only — the token's ``alg`` header
    is never trusted (§12).
    """
    settings = get_settings()
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
    except jwt.ExpiredSignatureError as exc:
        raise AuthenticationError("Token has expired.") from exc
    except jwt.InvalidTokenError as exc:
        raise AuthenticationError("Invalid token.") from exc

    if payload.get(_TYPE_CLAIM) != _ACCESS_TYPE:
        raise AuthenticationError("Invalid token type.")
    try:
        payload["sub"] = int(payload["sub"])
        payload["org"] = int(payload["org"])
    except (KeyError, TypeError, ValueError) as exc:
        raise AuthenticationError("Invalid token claims.") from exc
    return payload
