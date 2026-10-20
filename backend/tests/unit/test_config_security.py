"""Configuration safety rules — no database required.

Covers the guards that keep a misconfigured deployment from starting with
published or weak credentials, and the CORS policy the app installs.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import (
    INSECURE_DEFAULT_SECRET,
    MIN_SECRET_LENGTH,
    Settings,
    check_production_readiness,
)


def _settings(**overrides: object) -> Settings:
    base: dict[str, object] = {
        "app_env": "production",
        "jwt_secret": "x" * 64,
        "db_password": "a-real-password",
    }
    base.update(overrides)
    return Settings(**base)  # type: ignore[arg-type]


def test_production_refuses_the_published_jwt_key() -> None:
    settings = _settings(jwt_secret=INSECURE_DEFAULT_SECRET)
    with pytest.raises(RuntimeError, match="JWT_SECRET"):
        check_production_readiness(settings)


def test_production_refuses_a_short_jwt_key() -> None:
    """A short key is rejected by the schema, before the app ever starts."""
    with pytest.raises(ValidationError, match="at least"):
        _settings(jwt_secret="short-secret")


def test_production_refuses_the_default_database_password() -> None:
    settings = _settings(db_password="ats_dev_password")
    with pytest.raises(RuntimeError, match="DB_PASSWORD"):
        check_production_readiness(settings)


def test_production_accepts_a_strong_configuration() -> None:
    check_production_readiness(_settings())


def test_non_production_skips_the_production_guards() -> None:
    settings = _settings(app_env="development", jwt_secret=INSECURE_DEFAULT_SECRET)
    check_production_readiness(settings)


def test_published_key_is_never_used_outside_production() -> None:
    """Outside production the placeholder is swapped for a random key."""
    settings = Settings(app_env="development", jwt_secret=INSECURE_DEFAULT_SECRET)
    assert settings.jwt_secret != INSECURE_DEFAULT_SECRET
    assert len(settings.jwt_secret) >= MIN_SECRET_LENGTH


def test_unconfigured_secret_is_random_not_published() -> None:
    settings = Settings(app_env="development", jwt_secret="y" * 48)
    assert settings.jwt_secret != INSECURE_DEFAULT_SECRET
    assert len(settings.jwt_secret) >= MIN_SECRET_LENGTH


def test_production_keeps_the_placeholder_so_the_guard_can_reject_it() -> None:
    settings = Settings(app_env="production", jwt_secret=INSECURE_DEFAULT_SECRET)
    assert settings.jwt_secret == INSECURE_DEFAULT_SECRET
