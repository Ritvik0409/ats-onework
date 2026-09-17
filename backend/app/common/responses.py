"""Shared HTTP response helpers — the single error envelope (arch. doc §22).

Every error response is shaped as::

    {"error": {"code": "...", "message": "...", "details": ...}}

``details`` is omitted when absent. Success responses return their Pydantic
model directly (§49) — no data envelope.
"""

from __future__ import annotations

from typing import Any

from fastapi.responses import JSONResponse


def error_payload(code: str, message: str, details: Any = None) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if details is not None:
        error["details"] = details
    return {"error": error}


def json_error(
    status_code: int,
    code: str,
    message: str,
    details: Any = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content=error_payload(code, message, details),
        headers=headers,
    )
