"""Application entry point — small factory (arch. doc §24).

No business logic here: middleware, exception handlers, and routers are
registered by dedicated functions; the pool lifecycle lives in ``lifespan``.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.health import router as health_router
from app.api.v1.router import api_v1_router
from app.common.object_storage import LocalObjectStorage
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
    # allow_origin_regex covers Flutter web (random localhost ports) and the
    # Android-emulator origin; no settings dependency needed.
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"^http://localhost:\d+$",
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(RequestLoggingMiddleware)


def register_routers(app: FastAPI) -> None:
    app.include_router(health_router)
    app.include_router(api_v1_router)


def register_static_files(app: FastAPI) -> None:
    """Serve locally-stored receipt files (arch. doc §15).

    Receipt *files* live outside Postgres — ``expense_media.receipt_url``
    holds the URL only. With the default local-disk storage the URLs point
    at ``/uploads/...`` on this app, so mount it. When S3/MinIO is
    configured, the object store serves the files directly and no local
    mount is needed. No base64/byte blobs ever go through the DB.
    """
    settings = get_settings()
    if settings.s3_endpoint is not None:
        return
    # Resolve the directory the same way the storage layer does
    # (UPLOAD_DIR / BASE_STORAGE_URL env vars) so served URLs always
    # match the ones persisted into expense_media.receipt_url.
    storage = LocalObjectStorage()
    if storage.base_url != "/uploads":
        return  # a custom base URL implies an external file server
    storage.upload_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        "/uploads",
        StaticFiles(directory=str(storage.upload_dir)),
        name="uploads",
    )


def create_app() -> FastAPI:
    app = FastAPI(
        title="ATS Backend",
        version="0.1.0",
        lifespan=lifespan,
    )
    register_middleware(app)
    register_exception_handlers(app)
    register_routers(app)
    register_static_files(app)
    return app


app = create_app()
