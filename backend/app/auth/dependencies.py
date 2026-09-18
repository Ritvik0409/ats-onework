"""Auth-local dependency aliases (plan §4 folder layout).

The canonical implementations live in ``app.api.v1.deps`` — this module
re-exports them so the auth feature reads self-contained and future
auth-specific dependencies (e.g. optional-user for login-adjacent routes)
have a home that does not create import cycles.
"""

from app.api.v1.deps import CurrentUser, get_current_user, require_admin, require_membership

__all__ = ["CurrentUser", "get_current_user", "require_admin", "require_membership"]
