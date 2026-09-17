"""Application configuration via pydantic-settings (arch. doc §40)."""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

INSECURE_DEFAULT_SECRET = "change-me-generate-a-long-random-secret"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Application
    app_env: Literal["development", "test", "production"] = "development"
    log_level: str = "INFO"

    # Database
    database_url: str = "postgresql://ats:ats_dev_password@localhost:5432/ats"
    db_pool_min_size: int = 2
    db_pool_max_size: int = 10
    db_statement_timeout_ms: int = 15_000

    # JWT / auth (ADR-001, arch. doc §51)
    jwt_secret: str = INSECURE_DEFAULT_SECRET
    jwt_algorithm: Literal["HS256"] = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 30

    # CORS
    cors_origins: list[str] = Field(
        default_factory=lambda: ["http://localhost:3000", "http://localhost:8080"],
    )

    # Object storage (S3/MinIO — local disk used when unset, arch. doc §15)
    s3_endpoint: str | None = None
    s3_bucket: str | None = None
    s3_access_key: str | None = None
    s3_secret_key: str | None = None

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


def check_production_readiness(settings: Settings) -> None:
    """Fail fast on insecure configuration — never ship defaults to production."""
    if settings.is_production and settings.jwt_secret == INSECURE_DEFAULT_SECRET:
        msg = "JWT_SECRET must be set to a strong value in production."
        raise RuntimeError(msg)


@lru_cache
def get_settings() -> Settings:
    return Settings()
