"""Auth business rules — registration, login, rotation, logout, switch
(arch. doc §12-14, ADR-001 §51; contracts §49 #3-7).

Transaction notes (§7): ``register``/``login``/``refresh`` each perform
multiple writes (user row, token rows, last-login stamp) on the single
request-scoped connection from ``get_connection`` — commit/rollback happens
at context exit, so no explicit transaction block is needed for these
single-connection flows. Refresh rotation deletes the old token and inserts
the replacement on the same connection, so the old token can never survive
alongside the new one.
"""

from __future__ import annotations

from app.auth.repository import AuthRepository
from app.auth.schemas import (
    LoginRequest,
    OrganizationSummary,
    OrganizationSwitchRequest,
    RefreshRequest,
    TokenPair,
    UserCreate,
    UserResponse,
)
from app.common.audit import service as audit_service
from app.core.config import get_settings
from app.core.constants import AccountStatus, TokenPurpose
from app.core.exceptions import (
    AuthenticationError,
    AuthorizationError,
    ConflictError,
    NotFoundError,
)
from app.core.security import jwt as jwt_security
from app.core.security import passwords
from app.core.security import tokens as opaque_tokens
from app.db.types import Conn, Row

_INVALID_CREDENTIALS = "Invalid email or password."
_UNKNOWN_REFRESH = "Invalid or expired refresh token."

_repository = AuthRepository()


class AuthService:
    def __init__(self, repository: AuthRepository | None = None) -> None:
        self._repository = repository or _repository

    # -- registration ---------------------------------------------------

    async def register(self, conn: Conn, payload: UserCreate) -> UserResponse:
        existing = await self._repository.get_user_by_email(conn, payload.email)
        if existing is not None:
            raise ConflictError("An account with this email already exists.")
        password_hash = await passwords.hash_password(payload.password)
        row = await self._repository.create_user(
            conn,
            name=payload.name,
            email=payload.email,
            password_hash=password_hash,
        )
        await audit_service.log(
            conn,
            actor_id=row["employee_id"],
            organization_id=None,
            action="user.register",
            table_name="users",
            record_id=str(row["employee_id"]),
            new_values={"email": row["email"], "name": row["name"]},
        )
        return UserResponse.model_validate(row)

    # -- login ----------------------------------------------------------

    async def login(self, conn: Conn, payload: LoginRequest) -> TokenPair:
        row = await self._repository.get_user_by_email(conn, payload.email)
        if row is None:
            raise AuthenticationError(_INVALID_CREDENTIALS)
        ok, new_hash = await passwords.verify_and_update_password(
            payload.password, row["password_hash"]
        )
        if not ok:
            raise AuthenticationError(_INVALID_CREDENTIALS)
        self._ensure_active(row["account_status"])
        if new_hash is not None:
            await self._repository.update_password_hash(conn, row["employee_id"], new_hash)
        return await self._issue_pair(conn, employee_id=row["employee_id"], touch_login=True)

    # -- refresh (rotation) ----------------------------------------------

    async def refresh(self, conn: Conn, payload: RefreshRequest) -> TokenPair:
        """Exchange a refresh token for a fresh pair, rotating the token.

        Rotation keeps the old row and records what replaced it, so a
        token that comes back after it was already rotated can be
        recognised:

        * its replacement is still live — the client retried (a response
          lost in transit); the chain continues instead of ending the
          session
        * its replacement was rotated too — the token was replayed; the
          whole family is revoked and the session ends
        """
        token_hash = opaque_tokens.hash_token(payload.refresh_token)
        stored = await self._repository.get_token(conn, token_hash, TokenPurpose.REFRESH)
        if stored is None:
            raise AuthenticationError(_UNKNOWN_REFRESH)
        if opaque_tokens.is_expired(stored["expires_at"]):
            await self._repository.delete_token(conn, token_hash)
            raise AuthenticationError(_UNKNOWN_REFRESH)
        if stored["revoked_at"] is not None:
            raise AuthenticationError(_UNKNOWN_REFRESH)

        if stored["replaced_by_token_id"] is not None:
            replacement = await self._repository.get_token_by_id(
                conn, int(stored["replaced_by_token_id"])
            )
            if (
                replacement is not None
                and replacement["replaced_by_token_id"] is None
                and replacement["revoked_at"] is None
            ):
                # A retry of the same logical refresh — continue the chain.
                return await self._rotate(
                    conn,
                    employee_id=int(replacement["employee_id"]),
                    previous=replacement,
                    touch_login=False,
                )
            # Replayed token: the family is assumed compromised.
            await self._repository.revoke_family(conn, stored["family_id"])
            # The revocation must outlive this request. The connection
            # carries one request-scoped transaction, so raising here
            # would roll the revocation back and leave the stolen token
            # usable.
            await conn.commit()
            raise AuthenticationError(_UNKNOWN_REFRESH)

        user = await self._repository.get_user_by_id(conn, stored["employee_id"])
        if user is None:
            await self._repository.delete_token(conn, token_hash)
            raise AuthenticationError(_UNKNOWN_REFRESH)
        self._ensure_active(user["account_status"])
        return await self._rotate(
            conn,
            employee_id=int(user["employee_id"]),
            previous=stored,
            touch_login=False,
        )

    # -- logout ----------------------------------------------------------

    async def logout(self, conn: Conn, *, employee_id: int, payload: RefreshRequest) -> None:
        """Idempotent owner-scoped revoke — unknown tokens still yield 204.

        The whole family of the presented token is revoked, so a token
        captured before the logout cannot be used afterwards.
        """
        token_hash = opaque_tokens.hash_token(payload.refresh_token)
        stored = await self._repository.get_token(conn, token_hash, TokenPurpose.REFRESH)
        if stored is None:
            return
        if int(stored["employee_id"]) != employee_id:
            # Owner-scoped: a caller must not revoke another user's token.
            return
        await self._repository.revoke_family(conn, stored["family_id"])

    # -- switch organization ---------------------------------------------

    async def switch_organization(
        self,
        conn: Conn,
        *,
        employee_id: int,
        payload: OrganizationSwitchRequest,
    ) -> TokenPair:
        if not await self._repository.organization_exists(conn, payload.organization_id):
            raise NotFoundError("Organization not found.")
        membership = await self._repository.get_membership(
            conn, employee_id, payload.organization_id
        )
        if membership is None:
            raise AuthorizationError("You are not a member of this organization.")
        # The tokens minted for the previous organization must not survive
        # the switch — they carry the old organization in their access
        # token and would keep working until they expire.
        await self._repository.revoke_refresh_tokens_for_employee(conn, employee_id=employee_id)
        refresh = opaque_tokens.generate_token()
        await self._repository.insert_token(
            conn,
            employee_id=employee_id,
            token_hash=opaque_tokens.hash_token(refresh),
            purpose=TokenPurpose.REFRESH,
            expires_at=opaque_tokens.refresh_token_expiry(),
        )
        access = jwt_security.create_access_token(
            employee_id=employee_id,
            organization_id=payload.organization_id,
            is_admin=bool(membership["is_admin"]),
        )
        summaries = await self._organization_summaries(conn, employee_id)
        return TokenPair(
            access_token=access,
            refresh_token=refresh,
            expires_in=self._access_lifetime_seconds(),
            organizations=summaries,
        )

    # -- helpers ----------------------------------------------------------

    @staticmethod
    def _ensure_active(account_status: str) -> None:
        """Any non-active account is blocked at the gate — 403, never 401,
        so callers can distinguish "bad password" from "disabled account"."""
        if account_status != AccountStatus.ACTIVE.value:
            raise AuthorizationError("This account is not active. Contact your administrator.")

    async def _issue_pair(self, conn: Conn, *, employee_id: int, touch_login: bool) -> TokenPair:
        summaries = await self._organization_summaries(conn, employee_id)
        active_org_id, is_admin = self._default_org(summaries)
        refresh = opaque_tokens.generate_token()
        await self._repository.insert_token(
            conn,
            employee_id=employee_id,
            token_hash=opaque_tokens.hash_token(refresh),
            purpose=TokenPurpose.REFRESH,
            expires_at=opaque_tokens.refresh_token_expiry(),
        )
        if touch_login:
            await self._repository.update_last_login(
                conn, employee_id, opaque_tokens.utc_now_naive()
            )
        access = jwt_security.create_access_token(
            employee_id=employee_id,
            organization_id=active_org_id,
            is_admin=is_admin,
        )
        return TokenPair(
            access_token=access,
            refresh_token=refresh,
            expires_in=self._access_lifetime_seconds(),
            organizations=summaries,
        )

    async def _rotate(
        self,
        conn: Conn,
        *,
        employee_id: int,
        previous: Row,
        touch_login: bool,
    ) -> TokenPair:
        """Mint a replacement token in the same family and retire the old one.

        The old row is kept and marked as replaced, which is what lets a
        later replay be recognised.
        """
        summaries = await self._organization_summaries(conn, employee_id)
        active_org_id, is_admin = self._default_org(summaries)
        refresh = opaque_tokens.generate_token()
        inserted = await self._repository.insert_token(
            conn,
            employee_id=employee_id,
            token_hash=opaque_tokens.hash_token(refresh),
            purpose=TokenPurpose.REFRESH,
            expires_at=opaque_tokens.refresh_token_expiry(),
            family_id=previous["family_id"],
        )
        await self._repository.mark_rotated(
            conn, int(previous["token_id"]), replaced_by_token_id=int(inserted["token_id"])
        )
        if touch_login:
            await self._repository.update_last_login(
                conn, employee_id, opaque_tokens.utc_now_naive()
            )
        access = jwt_security.create_access_token(
            employee_id=employee_id,
            organization_id=active_org_id,
            is_admin=is_admin,
        )
        return TokenPair(
            access_token=access,
            refresh_token=refresh,
            expires_in=self._access_lifetime_seconds(),
            organizations=summaries,
        )

    async def _organization_summaries(
        self, conn: Conn, employee_id: int
    ) -> list[OrganizationSummary]:
        rows = await self._repository.list_memberships(conn, employee_id)
        return [OrganizationSummary.model_validate(row) for row in rows]

    @staticmethod
    def _default_org(
        summaries: list[OrganizationSummary],
    ) -> tuple[int, bool]:
        """ADR-001: a single membership becomes active automatically; with
        several, the lowest organization_id wins until the client switches.
        ``0`` marks "no organization" for users not yet added anywhere —
        every membership-guarded endpoint then answers 403/404 as usual."""
        if not summaries:
            return 0, False
        first = summaries[0]
        return first.organization_id, first.is_admin

    @staticmethod
    def _access_lifetime_seconds() -> int:
        return get_settings().jwt_access_token_expire_minutes * 60


service = AuthService()
