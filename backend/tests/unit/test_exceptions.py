"""Exception mapping (§50) and path-org guards — no database required.

Locks the psycopg → HTTP contract, including the PL/pgSQL ``RAISE``
prefix routing that keeps cross-tenant trigger violations at 404, and the
shared 404-vs-403 branching future resource modules must reuse.
"""

from __future__ import annotations

import pytest
from psycopg import Error as PsycopgError
from psycopg import errors as pg_errors

from app.common.tenant import require_path_admin, require_path_member
from app.core.exceptions import (
    AuthorizationError,
    NotFoundError,
    to_app_exception,
)


def test_unique_violation_maps_to_409() -> None:
    mapped = to_app_exception(pg_errors.UniqueViolation("duplicate key"))
    assert mapped.status_code == 409


def test_foreign_key_violation_maps_to_400() -> None:
    mapped = to_app_exception(pg_errors.ForeignKeyViolation("fk broken"))
    assert mapped.status_code == 400


def test_check_and_not_null_violations_map_to_422() -> None:
    assert to_app_exception(pg_errors.CheckViolation("chk")).status_code == 422
    assert to_app_exception(pg_errors.NotNullViolation("nn")).status_code == 422


def test_exclusion_violation_maps_to_409() -> None:
    assert to_app_exception(pg_errors.ExclusionViolation("excl")).status_code == 409


def test_raise_cross_tenant_prefix_maps_to_404_without_leaking() -> None:
    server_text = "Cross-tenant violation: employee 1 is not an active member of org 2"
    mapped = to_app_exception(pg_errors.RaiseException(server_text))
    assert mapped.status_code == 404
    assert isinstance(mapped, NotFoundError)
    assert mapped.message == "Resource not found."
    assert "employee 1" not in mapped.message
    assert "Cross-tenant" not in mapped.message


def test_raise_other_message_maps_to_422() -> None:
    mapped = to_app_exception(pg_errors.RaiseException("Business rule broken"))
    assert mapped.status_code == 422


def test_unknown_error_maps_to_500() -> None:
    mapped = to_app_exception(PsycopgError("something unexpected"))
    assert mapped.status_code == 500


def test_require_path_member_none_is_404() -> None:
    with pytest.raises(NotFoundError):
        require_path_member(None)


def test_require_path_member_passes_row_through() -> None:
    row = {"membership_id": 1, "is_admin": False}
    assert require_path_member(row) is row  # type: ignore[arg-type]


def test_require_path_admin_none_is_404_not_403() -> None:
    """Indistinguishability: "no such org" and "not a member" look identical."""
    with pytest.raises(NotFoundError):
        require_path_admin(None)


def test_require_path_admin_member_is_403() -> None:
    with pytest.raises(AuthorizationError) as exc:
        require_path_admin({"membership_id": 1, "is_admin": False})  # type: ignore[arg-type]
    assert exc.value.status_code == 403


def test_require_path_admin_admin_passes() -> None:
    row = {"membership_id": 1, "is_admin": True}
    assert require_path_admin(row) is row  # type: ignore[arg-type]
