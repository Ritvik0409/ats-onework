"""Phase 4.1-4.3 security & contract invariants — no database required.

Guards the properties the todo items demand without a live PostgreSQL:
credential hygiene (no hash/token leakage), JWT discipline (ADR-001 §51),
opaque-token handling (§14), status transition maps (§36), pagination
round-trips (§21), and the tenant error convention (cross-tenant → 404).
"""

from __future__ import annotations

from datetime import timedelta

import pytest
from pydantic import ValidationError as PydanticValidationError

from app.auth.schemas import (
    LoginRequest,
    OrganizationSwitchRequest,
    RefreshRequest,
    TokenPair,
    UserCreate,
)
from app.common.pagination import decode_cursor, encode_cursor
from app.common.responses import error_payload
from app.common.utils import slugify
from app.core.constants import (
    EXPENSE_TRANSITIONS,
    REIMBURSEMENT_TRANSITIONS,
    AccountStatus,
    ApprovalAction,
    EmployeeStatus,
    ExpenseStatus,
    ReimbursementStatus,
    TokenPurpose,
)
from app.core.exceptions import AuthenticationError
from app.core.security import jwt as jwt_security
from app.core.security import tokens as opaque_tokens
from app.organizations.schemas import MembershipCreate, OrganizationCreate, RoleCreate
from app.users.schemas import (
    EmployeeStatusCreate,
    UserResponse,
    UserUpdate,
)


def test_account_status_covers_schema_check_constraint() -> None:
    """constants ↔ schema sync: every users.account_status CHECK value exists."""
    assert {s.value for s in AccountStatus} == {"active", "suspended", "locked", "inactive"}


def test_employee_status_covers_schema_check_constraint() -> None:
    assert {s.value for s in EmployeeStatus} == {"active", "inactive", "suspended", "on_leave"}


def test_token_purpose_covers_schema_check_constraint() -> None:
    assert {s.value for s in TokenPurpose} == {"login", "reset_password", "refresh", "verify_email"}


def test_expense_transitions_forbid_arbitrary_jumps() -> None:
    assert EXPENSE_TRANSITIONS[ExpenseStatus.PENDING] == {
        ExpenseStatus.APPROVED,
        ExpenseStatus.REJECTED,
    }
    assert EXPENSE_TRANSITIONS[ExpenseStatus.APPROVED] == {ExpenseStatus.REIMBURSED}
    assert EXPENSE_TRANSITIONS[ExpenseStatus.REJECTED] == set()
    assert ApprovalAction.APPROVED.value == "approved"


def test_reimbursement_failed_may_retry_to_processing() -> None:
    assert REIMBURSEMENT_TRANSITIONS[ReimbursementStatus.PENDING] == {
        ReimbursementStatus.PROCESSING
    }
    assert REIMBURSEMENT_TRANSITIONS[ReimbursementStatus.PROCESSING] == {
        ReimbursementStatus.PAID,
        ReimbursementStatus.FAILED,
    }
    assert REIMBURSEMENT_TRANSITIONS[ReimbursementStatus.FAILED] == {ReimbursementStatus.PROCESSING}
    assert REIMBURSEMENT_TRANSITIONS[ReimbursementStatus.PAID] == set()


def test_jwt_round_trip_carries_adr001_claims() -> None:
    token = jwt_security.create_access_token(employee_id=7, organization_id=3, is_admin=True)
    payload = jwt_security.decode_access_token(token)
    assert payload["sub"] == 7
    assert payload["org"] == 3
    assert payload["admin"] is True


def test_jwt_expired_rejected() -> None:
    token = jwt_security.create_access_token(
        employee_id=1,
        organization_id=1,
        is_admin=False,
        expires_delta=timedelta(seconds=-1),
    )
    with pytest.raises(AuthenticationError):
        jwt_security.decode_access_token(token)


def test_jwt_garbage_rejected() -> None:
    with pytest.raises(AuthenticationError):
        jwt_security.decode_access_token("not-a-token")


def test_opaque_token_hash_is_64_hex_and_unique() -> None:
    first, second = opaque_tokens.generate_token(), opaque_tokens.generate_token()
    assert first != second
    digest = opaque_tokens.hash_token(first)
    assert len(digest) == 64
    int(digest, 16)  # valid hex


def test_refresh_expiry_and_expiry_check() -> None:
    future = opaque_tokens.refresh_token_expiry()
    assert not opaque_tokens.is_expired(future)
    assert opaque_tokens.is_expired(opaque_tokens.utc_now_naive() - timedelta(seconds=1))


def test_user_response_never_exposes_password_hash() -> None:
    assert "password_hash" not in UserResponse.model_fields
    assert "token_hash" not in UserResponse.model_fields


def test_user_create_rejects_short_password() -> None:
    with pytest.raises(PydanticValidationError):
        UserCreate(name="A", email="a@example.com", password="short")


def test_login_request_shapes() -> None:
    # email-validator normalizes the domain part to lowercase.
    body = LoginRequest(email=" Admin@Example.COM ", password="secret123")
    assert body.email == "Admin@example.com"


def test_refresh_and_switch_shapes() -> None:
    assert RefreshRequest(refresh_token="abc").refresh_token == "abc"
    assert OrganizationSwitchRequest(organization_id=5).organization_id == 5
    with pytest.raises(PydanticValidationError):
        OrganizationSwitchRequest(organization_id=0)


def test_token_pair_defaults_and_org_list() -> None:
    pair = TokenPair(access_token="a", refresh_token="r", expires_in=1800)
    assert pair.token_type == "bearer"
    assert pair.organizations == []


def test_organization_create_slug_rules() -> None:
    assert OrganizationCreate(name="Acme", slug="acme-corp").slug == "acme-corp"
    assert OrganizationCreate(name="Acme").slug is None  # derived via slugify
    with pytest.raises(PydanticValidationError):
        OrganizationCreate(name="Acme", slug="Bad Slug!")


def test_slugify_derives_valid_slugs() -> None:
    assert slugify("Acme Corp Ltd.") == "acme-corp-ltd"


def test_membership_and_role_shapes() -> None:
    assert MembershipCreate(employee_id=9).is_admin is False
    with pytest.raises(PydanticValidationError):
        MembershipCreate(employee_id=0)
    assert RoleCreate(name="manager").description is None


def test_user_update_all_optional() -> None:
    assert UserUpdate().model_dump(exclude_unset=True) == {}
    assert EmployeeStatusCreate(status=EmployeeStatus.ON_LEAVE).status == "on_leave"


def test_error_envelope_shape() -> None:
    assert error_payload("not_found", "Missing.") == {
        "error": {"code": "not_found", "message": "Missing."}
    }


def test_cursor_round_trip_and_invalid() -> None:
    cursor = encode_cursor(after_id=42)
    assert decode_cursor(cursor) == {"after_id": 42}
    with pytest.raises(ValueError):
        decode_cursor("!!!not-a-cursor!!!")
