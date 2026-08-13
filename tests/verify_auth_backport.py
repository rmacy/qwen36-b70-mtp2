#!/usr/bin/env python3
"""Regression check for the CVE-2026-48746 authentication-bypass backport."""

from __future__ import annotations

import asyncio
import inspect
from typing import Any

from vllm.entrypoints.openai.server_utils import AuthenticationMiddleware


async def downstream(scope, receive, send) -> None:
    await send({"type": "http.response.start", "status": 200, "headers": []})
    await send({"type": "http.response.body", "body": b"downstream"})


async def status_for(host: bytes) -> int:
    middleware = AuthenticationMiddleware(downstream, ["expected-test-token"])
    scope: dict[str, Any] = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": "/v1/models",
        "raw_path": b"/v1/models",
        "query_string": b"",
        "root_path": "",
        "headers": [(b"host", host)],
        "client": ("127.0.0.1", 12345),
        "server": ("127.0.0.1", 8000),
    }
    messages: list[dict[str, Any]] = []

    async def receive() -> dict[str, Any]:
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message: dict[str, Any]) -> None:
        messages.append(message)

    await middleware(scope, receive, send)
    return next(message["status"] for message in messages if message["type"] == "http.response.start")


async def main() -> None:
    source = inspect.getsource(AuthenticationMiddleware.__call__)
    assert 'URL(scope=scope)' not in source
    assert 'scope["path"]' in source
    assert await status_for(b"localhost") == 401
    assert await status_for(b"localhost/health?") == 401
    print("CVE-2026-48746 regression check passed")


if __name__ == "__main__":
    asyncio.run(main())
