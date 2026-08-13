#!/usr/bin/env python3
"""Cache-resistant streaming C1/C4/C8 benchmark for OpenAI-compatible servers."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import statistics
import time
import urllib.request
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def api_url(endpoint: str) -> str:
    base = endpoint.rstrip("/")
    return base + ("/chat/completions" if base.endswith("/v1") else "/v1/chat/completions")


def unique_prompt(lane: str, sample: int) -> str:
    nonce = uuid.uuid4().hex
    return (
        f"UNCACHED-NONCE {nonce} lane={lane} sample={sample}.\n"
        "Write distinct, one-sentence financial control observations in plain text. "
        "Continue until the output limit and do not summarize."
    )


def stream_once(
    endpoint: str,
    model: str,
    api_key: str | None,
    lane: str,
    sample: int,
    max_tokens: int,
    timeout: int,
) -> dict[str, Any]:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": unique_prompt(lane, sample)}],
        "max_tokens": max_tokens,
        "temperature": 0.7,
        "top_p": 0.8,
        "top_k": 20,
        "presence_penalty": 1.5,
        "seed": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(
        api_url(endpoint),
        data=json.dumps(payload).encode(),
        headers=headers,
        method="POST",
    )
    started = time.perf_counter()
    first_token: float | None = None
    completion_tokens = 0
    finish_reason: str | None = None
    with urllib.request.urlopen(request, timeout=timeout) as response:
        for raw_line in response:
            line = raw_line.decode(errors="replace").strip()
            if not line.startswith("data: ") or line == "data: [DONE]":
                continue
            event = json.loads(line[6:])
            usage = event.get("usage") or {}
            completion_tokens = int(usage.get("completion_tokens") or completion_tokens)
            for choice in event.get("choices") or []:
                finish_reason = choice.get("finish_reason") or finish_reason
                delta = choice.get("delta") or {}
                if (delta.get("content") or delta.get("reasoning_content")) and first_token is None:
                    first_token = time.perf_counter()
    finished = time.perf_counter()
    first_token = first_token or finished
    return {
        "sample": sample,
        "completion_tokens": completion_tokens,
        "ttft_seconds": first_token - started,
        "elapsed_seconds": finished - started,
        "tokens_per_second": completion_tokens / max(finished - first_token, 1e-6),
        "finish_reason": finish_reason,
    }


def run_lane(args: argparse.Namespace, concurrency: int) -> dict[str, Any]:
    lane = f"c{concurrency}-short"
    samples = max(args.samples, concurrency)
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
        rows = list(
            pool.map(
                lambda sample: stream_once(
                    args.endpoint,
                    args.model,
                    args.api_key,
                    lane,
                    sample,
                    args.max_tokens,
                    args.timeout,
                ),
                range(samples),
            )
        )
    wall = time.perf_counter() - started
    return {
        "concurrency": concurrency,
        "samples": rows,
        "wall_seconds": wall,
        "aggregate_tokens_per_second": sum(row["completion_tokens"] for row in rows) / wall,
        "median_request_tokens_per_second": statistics.median(
            row["tokens_per_second"] for row in rows
        ),
        "median_ttft_seconds": statistics.median(row["ttft_seconds"] for row in rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--api-key-env")
    parser.add_argument("--concurrency", default="1,4,8")
    parser.add_argument("--samples", type=int, default=8)
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    args.api_key = os.environ.get(args.api_key_env) if args.api_key_env else None
    if args.api_key_env and not args.api_key:
        parser.error(f"environment variable is unset: {args.api_key_env}")

    stream_once(args.endpoint, args.model, args.api_key, "warmup", 0, 16, args.timeout)
    lanes = [run_lane(args, int(value)) for value in args.concurrency.split(",")]
    result = {
        "version": "qwen36-bmg-mtp2-public-v1",
        "finished_at": datetime.now(UTC).isoformat(),
        "endpoint": args.endpoint,
        "model": args.model,
        "contract": {
            "cache_resistant_nonce_first": True,
            "sampling": {
                "temperature": 0.7,
                "top_p": 0.8,
                "top_k": 20,
                "presence_penalty": 1.5,
                "enable_thinking": False,
            },
            "max_tokens": args.max_tokens,
        },
        "lanes": lanes,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
