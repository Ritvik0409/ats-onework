"""Windows-safe dev server entry point.

psycopg3 async cannot run on a ProactorEventLoop — the default on Windows —
and uvicorn 0.53 hardcodes a Proactor loop factory for its single-process
mode, so plain ``uvicorn app.main:app`` boots but the connection pool never
connects ("cannot use the 'ProactorEventLoop'" retries forever). This entry
point runs uvicorn's own supervise/reload machinery but always creates the
server loop via ``SelectorEventLoop``.

Usage (from ``backend/``)::

    uv run python scripts/dev.py                # http://127.0.0.1:8000
    uv run python scripts/dev.py --reload       # watch-mode dev server
    uv run python scripts/dev.py --port 8010
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from contextlib import suppress
from pathlib import Path

# `python scripts/dev.py` puts scripts/ (not backend/) on sys.path —
# uvicorn's lazy "app.main:app" import needs backend/ importable.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--reload", action="store_true")
    args = parser.parse_args()

    import uvicorn

    config = uvicorn.Config("app.main:app", host=args.host, port=args.port)
    server = uvicorn.Server(config)

    if args.reload:
        # uvicorn's reload supervisor runs the app in a subprocess, where
        # it already selects a Selector loop on Windows — safe as-is.
        from uvicorn.supervisors import ChangeReload

        sock = config.bind_socket()
        ChangeReload(config, target=server.run, sockets=[sock]).run()
        return 0

    # Single process: build the loop ourselves with a Selector factory
    # (works on every platform; asyncio.run accepts loop_factory 3.12+).
    with suppress(KeyboardInterrupt):
        asyncio.run(server.serve(), loop_factory=asyncio.SelectorEventLoop)
    if not server.started:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
