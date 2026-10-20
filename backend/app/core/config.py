"""Application configuration via pydantic-settings (arch. doc §40)."""

from __future__ import annotations

import secrets
from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Published in .env.example — never a real key. Production refuses it and
# every other environment replaces it with a random per-process secret.
INSECURE_DEFAULT_SECRET = "change-me-generate-a-long-random-secret"

# The shortest key we accept in production (HMAC-SHA256 wants ≥ 256 bits).
MIN_SECRET_LENGTH = 32


def _ephemeral_secret() -> str:
    """Random per-process signing key for runs that did not configure one.

    A key published in this repository must never sign real tokens, but
    requiring one would break a fresh checkout with no ``.env``. An
    unconfigured run therefore gets a random key: it changes on restart,
    which only costs a re-login.
    """
    return secrets.token_urlsafe(48)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Application
    app_env: Literal["development", "test", "production"] = "development"
    log_level: str = "INFO"

    # Database — discrete credentials (§40). Compose the DSN from these;
    # ``DATABASE_URL`` is only an escape hatch for single-string deploys.
    db_host: str = "localhost"
    db_port: int = 5432
    db_user: str = "ats"
    db_password: str = "ats_dev_password"
    db_name: str = "ats"
    database_url: str | None = None
    db_pool_min_size: int = 2
    db_pool_max_size: int = 10
    db_statement_timeout_ms: int = 15_000

    @property
    def effective_database_url(self) -> str:
        """The DSN the pool/runners connect with.

        ``DATABASE_URL`` wins when explicitly provided; otherwise one is
        composed from HOST/PORT/USER/PASSWORD/NAME (values are URL-escaped
        so passwords with special characters are safe).
        """
        if self.database_url:
            return self.database_url
        from urllib.parse import quote_plus

        return (
            f"postgresql://{quote_plus(self.db_user)}:{quote_plus(self.db_password)}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )

    # JWT / auth (ADR-001, arch. doc §51)
    jwt_secret: str = Field(default_factory=_ephemeral_secret, min_length=MIN_SECRET_LENGTH)
    jwt_algorithm: Literal["HS256"] = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 30

    # CORS — explicit origin allow-list. The Flutter *web* build picks a
    # random localhost port, so development also allows the localhost
    # pattern; production never does (see ``cors_origin_regex``).
    cors_origins: list[str] = Field(
        default_factory=lambda: ["http://localhost:3000", "http://localhost:8080"],
    )
    cors_origin_regex: str | None = None

    # Object storage (S3/MinIO — local disk used when unset, arch. doc §15)
    s3_endpoint: str | None = None
    s3_bucket: str | None = None
    s3_access_key: str | None = None
    s3_secret_key: str | None = None

    # Password for the accounts created by ``scripts/seed.py``. Left unset
    # the seeder generates a random one and prints it, so no shared
    # credential constant can reach a deployed environment.
    seed_password: str | None = None

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @model_validator(mode="after")
    def _never_sign_with_the_published_key(self) -> Settings:
        """Replace the .env.example key outside production.

        In production the published key is left in place so
        :func:`check_production_readiness` can refuse to start.
        """
        if self.jwt_secret == INSECURE_DEFAULT_SECRET and not self.is_production:
            object.__setattr__(self, "jwt_secret", _ephemeral_secret())
        return self


def check_production_readiness(settings: Settings) -> None:
    """Fail fast on insecure configuration — never ship defaults to production.

    The signing key's length is already enforced by the schema
    (``min_length`` on :attr:`Settings.jwt_secret`), so this only covers
    the values that are well-formed but wrong.
    """
    if not settings.is_production:
        return
    if settings.jwt_secret == INSECURE_DEFAULT_SECRET:
        msg = "JWT_SECRET must be set to a strong, unique value in production."
        raise RuntimeError(msg)
    if settings.db_password == "ats_dev_password":
        msg = "DB_PASSWORD must be set to a strong value in production."
        raise RuntimeError(msg)


@lru_cache
def get_settings() -> Settings:
    return Settings()
