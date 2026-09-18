"""Application exception tree + global handlers (arch. doc §22, §50).

Every error leaves the API as the shared error envelope; raw SQL messages and
stack traces never reach clients. PostgreSQL constraint names are stable
identifiers — specific ones map to friendly messages via ``CONSTRAINT_MESSAGES``.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from psycopg import Error as PsycopgError
from psycopg import errors as pg_errors
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.common.responses import json_error

logger = logging.getLogger(__name__)


class AppException(Exception):
    status_code: int = 500
    code: str = "internal_error"
    message: str = "An unexpected error occurred."

    def __init__(
        self,
        message: str | None = None,
        *,
        details: dict | list | None = None,
        status_code: int | None = None,
    ) -> None:
        super().__init__(message or self.message)
        self.message = message or self.message
        self.details = details
        if status_code is not None:
            self.status_code = status_code


class AuthenticationError(AppException):
    status_code = 401
    code = "authentication_error"
    message = "Authentication required or invalid."


class AuthorizationError(AppException):
    status_code = 403
    code = "authorization_error"
    message = "You do not have permission to perform this action."


class NotFoundError(AppException):
    status_code = 404
    code = "not_found"
    message = "Resource not found."


class ConflictError(AppException):
    status_code = 409
    code = "conflict"
    message = "The request conflicts with the current state."


class ValidationError(AppException):
    status_code = 422
    code = "validation_error"
    message = "The request is semantically invalid."


class TransientError(AppException):
    status_code = 503
    code = "service_unavailable"
    message = "The service is temporarily unavailable."


# Human-friendly messages for known unique constraints (§50).
CONSTRAINT_MESSAGES: dict[str, str] = {
    "users_email_key": "An account with this email already exists.",
    "organizations_slug_key": "An organization with this slug already exists.",
    "roles_name_organization_id_key": (
        "A role with this name already exists in this organization."
    ),
    "expense_types_name_organization_id_key": (
        "An expense type with this name already exists in this organization."
    ),
    "memberships_employee_id_organization_id_key": (
        "This user is already a member of the organization."
    ),
    "categories_name_organization_id_key": (
        "A category with this name already exists in this organization."
    ),
}


def _server_message(exc: PsycopgError) -> str:
    """Best-effort server message without ever leaking it to clients.

    Live server errors carry ``diag.message_primary`` (e.g. the text of a
    PL/pgSQL ``RAISE EXCEPTION``); client-constructed errors only have
    ``str(exc)``. Used solely for prefix routing below — the returned
    string never leaves the server.
    """
    primary = getattr(getattr(exc, "diag", None), "message_primary", None)
    return primary or str(exc) or ""


# Prefix → HTTP mapping for PL/pgSQL RAISE EXCEPTION texts (arch. doc §50).
# Trigger messages are part of the API contract: the prefix decides the
# status code, and the server text itself is NEVER returned to clients.
RAISE_MESSAGE_ROUTES: tuple[tuple[str, type[AppException]], ...] = (
    # Cross-tenant trigger violations must not reveal whether the probed
    # row exists — they read as 404, exactly like a missing own-org row.
    ("Cross-tenant violation", NotFoundError),
)


def to_app_exception(exc: PsycopgError) -> AppException:
    """Map a psycopg3 exception to an AppException (§50). Never leaks SQL text."""
    constraint = getattr(exc.diag, "constraint_name", None)
    if isinstance(exc, pg_errors.UniqueViolation):
        message = CONSTRAINT_MESSAGES.get(constraint) or "The resource already exists."
        return ConflictError(message)
    if isinstance(exc, pg_errors.ForeignKeyViolation):
        return ValidationError(
            "A referenced record does not exist or is still in use.",
            status_code=400,
        )
    if isinstance(exc, (pg_errors.CheckViolation, pg_errors.NotNullViolation)):
        return ValidationError("The request violates a data constraint.")
    if isinstance(exc, pg_errors.ExclusionViolation):
        return ConflictError("The request conflicts with an existing resource.")
    if isinstance(exc, pg_errors.RaiseException):
        server_message = _server_message(exc)
        for prefix, app_error in RAISE_MESSAGE_ROUTES:
            if server_message.startswith(prefix):
                return app_error()
        return ValidationError("The request violates a data constraint.")
    if isinstance(exc, (pg_errors.LockNotAvailable, pg_errors.QueryCanceled)):
        return TransientError("The database is busy; please retry shortly.")
    return AppException("A database error occurred.")


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppException)
    async def handle_app_exception(_request: Request, exc: AppException):
        log = logger.warning if exc.status_code < 500 else logger.error
        log(
            "request failed: %s",
            exc.message,
            extra={
                "error_type": type(exc).__name__,
                "status_code": exc.status_code,
            },
        )
        return json_error(exc.status_code, exc.code, exc.message, exc.details)

    @app.exception_handler(RequestValidationError)
    async def handle_request_validation(_request: Request, exc: RequestValidationError):
        details = [
            {"loc": list(err.get("loc", [])), "msg": err.get("msg"), "type": err.get("type")}
            for err in exc.errors()
        ]
        return json_error(422, "validation_error", "Request validation failed.", details)

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_exception(_request: Request, exc: StarletteHTTPException):
        code_by_status = {
            401: "authentication_error",
            403: "authorization_error",
            404: "not_found",
            409: "conflict",
            422: "validation_error",
        }
        code = code_by_status.get(exc.status_code, "http_error")
        return json_error(exc.status_code, code, str(exc.detail))

    @app.exception_handler(PsycopgError)
    async def handle_psycopg_error(_request: Request, exc: PsycopgError):
        # Full detail goes to logs only (§22: never expose SQL errors to clients).
        logger.exception("database error", extra={"error_type": type(exc).__name__})
        app_exc = to_app_exception(exc)
        return json_error(app_exc.status_code, app_exc.code, app_exc.message, app_exc.details)
