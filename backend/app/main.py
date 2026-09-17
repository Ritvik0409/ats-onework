"""Application entry point — small factory (arch. doc §24).

No business logic here: middleware, exception handlers, and routers are
registered by dedicated functions; the pool lifecycle lives in ``lifespan``.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.health import router as health_router
from app.api.v1.router import api_v1_router
from app.core.config import check_production_readiness, get_settings
from app.core.exceptions import register_exception_handlers
from app.core.logging import RequestLoggingMiddleware, configure_logging
from app.db.pool import close_pool, create_pool


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    configure_logging()
    check_production_readiness(settings)
    pool = create_pool(settings)
    await pool.open()  # explicit open — constructor-open is deprecated
    try:
        yield
    finally:
        await close_pool()


def register_middleware(app: FastAPI) -> None:
    settings = get_settings()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(RequestLoggingMiddleware)


def register_routers(app: FastAPI) -> None:
    app.include_router(health_router)
    app.include_router(api_v1_router)


def create_app() -> FastAPI:
    app = FastAPI(
        title="ATS Backend",
        version="0.1.0",
        lifespan=lifespan,
    )
    register_middleware(app)
    register_exception_handlers(app)
    register_routers(app)
    return app


app = create_app()
