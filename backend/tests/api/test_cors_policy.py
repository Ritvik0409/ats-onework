"""CORS policy and production hardening — no database required.

Exercises the ASGI app directly so the actual middleware behaviour is
asserted: which origins are echoed back, and whether credentialed
cross-origin requests are possible.
"""

from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import get_settings
from app.main import create_app


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=create_app()), base_url="http://test")


async def test_configured_origin_is_allowed() -> None:
    settings = get_settings()
    origin = settings.cors_origins[0]
    async with _client() as client:
        response = await client.get("/health", headers={"Origin": origin})
    assert response.headers.get("access-control-allow-origin") == origin


async def test_unknown_origin_is_not_echoed() -> None:
    async with _client() as client:
        response = await client.get("/health", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in response.headers


async def test_credentialed_cross_origin_requests_are_not_allowed() -> None:
    """The API authenticates with a bearer token, never with cookies.

    Echoing the origin *and* allowing credentials is what turns a
    permissive CORS policy into a token-theft primitive, so the policy
    must not offer that combination.
    """
    settings = get_settings()
    origin = settings.cors_origins[0]
    async with _client() as client:
        response = await client.get("/health", headers={"Origin": origin})
    assert response.headers.get("access-control-allow-credentials") is None


async def test_preflight_advertises_only_the_expected_methods_and_headers() -> None:
    settings = get_settings()
    origin = settings.cors_origins[0]
    async with _client() as client:
        response = await client.options(
            "/api/v1/expenses",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )
    assert response.status_code == 200
    allowed = response.headers.get("access-control-allow-methods", "")
    assert "POST" in allowed
    headers = response.headers.get("access-control-allow-headers", "").lower()
    assert "authorization" in headers


@pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json"])
async def test_api_documentation_is_served_in_development(path: str) -> None:
    async with _client() as client:
        response = await client.get(path)
    assert response.status_code == 200
