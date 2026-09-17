"""Object storage abstraction (arch. doc §15, §39).

Expense receipt files are stored outside PostgreSQL; only the URL/key lives
in ``expense_media.receipt_url``. Domain services depend on this
``ObjectStorage`` interface — never on a concrete provider — so S3 / R2 /
MinIO implementations can replace the local-disk dev default without
touching domain code.

Use ``get_object_storage()`` (a tiny singleton honoring ``UPLOAD_DIR`` /
``BASE_STORAGE_URL`` settings) in services, or pass an explicit instance in
tests.
"""

from __future__ import annotations

import contextlib
import os
import shutil
from pathlib import Path
from typing import BinaryIO, Protocol, runtime_checkable

DEFAULT_UPLOAD_DIR = Path("uploads")
CHUNK_SIZE = 1024 * 1024


@runtime_checkable
class ObjectStorage(Protocol):
    async def upload(self, *, key: str, data: BinaryIO, content_type: str) -> str:
        """Persist binary content and return the stored URL/key."""
        ...

    async def delete(self, *, key: str) -> None:
        """Best-effort delete — absence is not an error."""
        ...


class LocalObjectStorage:
    """Filesystem-backed dev implementation (never for production)."""

    def __init__(self, upload_dir: Path | None = None, base_url: str = "/uploads") -> None:
        upload_env = os.environ.get("UPLOAD_DIR")
        base_env = os.environ.get("BASE_STORAGE_URL")
        self.upload_dir = Path(upload_env) if upload_env else (upload_dir or DEFAULT_UPLOAD_DIR)
        self.base_url = (base_env or base_url).rstrip("/")

    def _path_for(self, key: str) -> Path:
        safe = key.lstrip("/").replace("..", "_")
        return self.upload_dir / safe

    async def upload(self, *, key: str, data: BinaryIO, content_type: str) -> str:  # noqa: ARG002
        dest = self._path_for(key)
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("wb") as out:
            shutil.copyfileobj(data, out, CHUNK_SIZE)
        return f"{self.base_url}/{key.lstrip('/')}"

    async def delete(self, *, key: str) -> None:
        target = self._path_for(key)
        with contextlib.suppress(OSError):
            target.unlink(missing_ok=True)


_storage: ObjectStorage | None = None


def get_object_storage() -> ObjectStorage:
    """Process-wide storage singleton — configurable via env, swappable in tests."""
    global _storage
    if _storage is None:
        _storage = LocalObjectStorage()
    return _storage


def set_object_storage(storage: ObjectStorage | None) -> None:
    """Override the singleton (tests) — pass ``None`` to reset to the default."""
    global _storage
    _storage = storage
