"""Path-organization guards for resource-scoped routes (§8, §49 conventions).

``require_membership`` (``app.api.v1.deps``) validates the **token's** org —
the right check for collection routes (``POST /organizations``,
``GET /users``), but the wrong error code for resource routes: a caller
probing another org's ID must get **404** (undiscoverable), never 403.

Services behind org-scoped resource paths MUST therefore:

1. read the membership row for ``(employee_id, path organization_id)``
   with their repository's ``get_membership`` (SQL stays in repositories,
   §5 — this module holds no SQL, only the branching);
2. pass it through ``require_path_member`` (member reads) or
   ``require_path_admin`` (admin writes).

The organizations module is the reference implementation; projects (4.4),
expenses (4.5), and reimbursements (4.6) copy this shape instead of
re-inventing the 404-vs-403 branch.
"""

from __future__ import annotations

from app.core.exceptions import AuthorizationError, NotFoundError
from app.db.types import Row


def require_path_member(membership: Row | None) -> Row:
    """Member gate for resource reads — missing membership reads as 404 so
    callers cannot tell "no such org" apart from "not a member" (§49)."""
    if membership is None:
        raise NotFoundError("Organization not found.")
    return membership


def require_path_admin(membership: Row | None) -> Row:
    """Admin gate for resource writes — 404 when not a member (same
    indistinguishability as reads), 403 only for members lacking admin."""
    membership = require_path_member(membership)
    if not bool(membership["is_admin"]):
        raise AuthorizationError("Administrator privileges required.")
    return membership
