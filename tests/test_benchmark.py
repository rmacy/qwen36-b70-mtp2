#!/usr/bin/env python3
"""End-to-end smoke test for the public streaming benchmark client."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCHMARK = ROOT / "benchmark.py"


class StreamingHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        assert self.path == "/v1/chat/completions"
        assert request["stream"] is True
        assert request["stream_options"] == {"include_usage": True}
        assert request["messages"][0]["content"].split()[0].isalnum()

        events = [
            {"choices": [{"delta": {"content": "one"}, "finish_reason": None}]},
            {
                "choices": [{"delta": {"content": " two"}, "finish_reason": "length"}],
                "usage": {"completion_tokens": 2},
            },
        ]
        body = "".join(f"data: {json.dumps(event)}\n\n" for event in events)
        body += "data: [DONE]\n\n"
        encoded = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    spec = importlib.util.spec_from_file_location("public_benchmark", BENCHMARK)
    assert spec is not None and spec.loader is not None
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    assert benchmark.api_url("http://127.0.0.1:8000/v1/").endswith(
        "/v1/chat/completions"
    )
    assert benchmark.unique_prompt("c1", 0).split()[0].isalnum()

    server = ThreadingHTTPServer(("127.0.0.1", 0), StreamingHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "results.json"
            subprocess.run(
                [
                    sys.executable,
                    str(BENCHMARK),
                    "--endpoint",
                    f"http://127.0.0.1:{server.server_port}",
                    "--model",
                    "release-audit-model",
                    "--output",
                    str(output),
                    "--concurrency",
                    "1,2",
                    "--samples",
                    "2",
                    "--max-tokens",
                    "2",
                    "--timeout",
                    "10",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(output.read_text())
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result["version"] == "qwen36-bmg-mtp2-public-v1.1"
    assert result["model"] == "release-audit-model"
    assert result["contract"]["cache_resistant_nonce_first_block"] is True
    assert [lane["concurrency"] for lane in result["lanes"]] == [1, 2]
    assert all(
        sample["completion_tokens"] == 2
        for lane in result["lanes"]
        for sample in lane["samples"]
    )
    print("Public benchmark end-to-end smoke test passed")


if __name__ == "__main__":
    main()
