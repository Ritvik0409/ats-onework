"""Logging configuration + request-ID correlation (arch. doc §23).

- Development: human-readable console lines.
- Production: JSON lines with request correlation fields.
- Every log record carries ``request_id`` via a context variable.
- NEVER log: passwords, password_hash, JWTs, refresh/reset tokens, token_hash,
  private receipt data (§23 never-log list — enforced by review, not runtime).
"""

from __future__ import annotations

import json
import logging
import sys
import time
import uuid
from contextvars import ContextVar

from fastapi import FastAPI, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

_request_id: ContextVar[str] = ContextVar("request_id", default="-")

# Structured fields allowed on records (§23 useful-fields list).
LOG_FIELDS = (
    "employee_id",
    "organization_id",
    "endpoint",
    "method",
    "status_code",
    "duration_ms",
    "error_type",
)


def get_request_id() -> str:
    return _request_id.get()


class RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = _request_id.get()
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
        }
        for key in LOG_FIELDS:
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging() -> None:
    from app.core.config import get_settings  # avoids import-time settings access

    settings = get_settings()
    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(RequestIdFilter())
    if settings.is_production:
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s %(levelname)-7s [%(request_id)s] %(name)s: %(message)s",
            ),
        )
    logging.basicConfig(level=settings.log_level.upper(), handlers=[handler], force=True)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Assigns a request ID, echoes it as ``X-Request-ID``, and logs
    method/path/status/duration (§23)."""

    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        request_id = uuid.uuid4().hex
        token = _request_id.set(request_id)
        start = time.perf_counter()
        response: Response | None = None
        try:
            response = await call_next(request)
        finally:
            duration_ms = round((time.perf_counter() - start) * 1000, 2)
            logging.getLogger("ats.request").info(
                "request completed",
                extra={
                    "endpoint": request.url.path,
                    "method": request.method,
                    "duration_ms": duration_ms,
                    "status_code": response.status_code if response is not None else None,
                },
            )
            _request_id.reset(token)
        assert response is not None
        response.headers["X-Request-ID"] = request_id
        return response


def register_middleware(app: FastAPI) -> None:
    app.add_middleware(RequestLoggingMiddleware)
