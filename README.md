# Qwen3.6-27B MTP2 kit for dual Intel BMG / Arc Pro B70

This is a sanitized, version-pinned reproduction kit for the profile described
in [POST.md](POST.md). It contains no model weights, credentials, endpoints,
machine names, personal paths, benchmark responses, or private application
data.

Read [SECURITY.md](SECURITY.md) before exposing the service. The image includes
the upstream fix for CVE-2026-48746, backported because the pinned Intel vLLM
revision predates vLLM 0.22.0.

Published runtime images:

```text
ghcr.io/rmacy/qwen36-b70-mtp2:0.1.1
us-central1-docker.pkg.dev/home-504803/open-models/qwen36-b70-mtp2:0.1.1
```

## Validated result

- Hardware envelope: two Arc Pro B70 GPUs, 64 GB aggregate VRAM, roughly
  1.216 TB/s aggregate theoretical bandwidth.
- Model: official `Qwen/Qwen3.6-27B-FP8` checkpoint.
- C1 decode: 52.94 tok/s median, versus 31.90 without MTP.
- Cold aggregate: 169.48-175.94 tok/s at C4; 267.37-282.57 at C8.
- Quality: tied the separately hosted copy on the frozen score and all 82
  blinded response comparisons.
- Stability: 6,981/6,981 correct requests in a 3,604-second mixed soak.

The tested host used Linux 7.0, Intel compute runtime `26.05.37020.3`, Level
Zero loader `1.28.2`, Docker 29.7.2, and the pinned Intel image below. Newer
software may be better, but it has not been validated by these results.

## What the patch changes

The patch is relative to:

```text
intel/llm-scaler-vllm:0.21.0-b3
digest: sha256:7a526dcfc49c77afeabf77e2e2a41a9a0221126580d144d2d1a15e320befb210
vLLM: 0.21.1.dev0+gad7125a43.d20260810.xpu
PyTorch: 2.11.0+xpu
```

It touches five vLLM files to replicate the small MTP projection, use local
argmax reduction, stabilize the small oneCCL reduction, shorten first-proposal
work, and bypass MTP above a configurable prompt length. Target-model
verification remains authoritative.

This is intentionally not advertised as a universal vLLM patch. Internal line
numbers and Intel XPU behavior are revision-specific.

## Build and run

Prerequisites are a Linux host with both BMG GPUs working through `/dev/dri`,
Docker, and a complete local copy of the official FP8 checkpoint. Review the
model's own license before downloading or redistributing it. The validated
checkpoint revision is `e89b16ebf1988b3d6befa7de50abc2d76f26eb09`.

Use the prebuilt image:

```bash
docker pull ghcr.io/rmacy/qwen36-b70-mtp2:0.1.1

MODEL_DIR=/absolute/path/to/Qwen3.6-27B-FP8 \
IMAGE=ghcr.io/rmacy/qwen36-b70-mtp2:0.1.1 \
  ./run.sh
```

Or build the exact image from source:

```bash
docker build -t qwen36-bmg-mtp2:0.1.1 .

MODEL_DIR=/absolute/path/to/Qwen3.6-27B-FP8 \
  ./run.sh
```

The OpenAI-compatible endpoint listens on `http://127.0.0.1:8000/v1` by
default. `run.sh` only replaces its own named container; it does not stop other
inference containers to acquire the port.

Important overrides:

```bash
PORT=8001 GPU_UTIL=0.84 MAX_MODEL_LEN=131072 ./run.sh
MTP_TOKENS=0 ./run.sh                    # matched no-MTP control
MTP_MAX_PROMPT_TOKENS=0 ./run.sh         # no long-prompt bypass
API_KEY='replace-with-a-long-random-value' ./run.sh
```

The selected defaults are MTP2, local argmax reduction, an 8,192-token MTP
guard, FP8 KV, FP16 state, TP=2, async scheduling, and prefix caching off.

## Measure it correctly

Wait until `/health` reports ready, then run cache-resistant C1/C4/C8 traffic:

```bash
python3 benchmark.py \
  --endpoint http://127.0.0.1:8000 \
  --model qwen3.6-27b-fp8 \
  --output results.json
```

The unique nonce is in the first prompt block, so automatic prefix caching
cannot turn a cold test into a cached one. Report TTFT, isolated C1 decode, and
aggregate concurrency separately. Do not compare this number with a benchmark
that uses different output length, sampling, context, quantization, cache state,
or MTP.

Before production use, run your own deterministic quality suite and at least a
one-hour mixed-concurrency soak. The included benchmark measures performance;
it does not prove output quality for your workload.

## Optional host policy

The `systemd/` units pin CPU policy and Intel GPU frequency. They are opt-in
because they increase idle power use and write host sysfs controls. Read them
before installing, and use `systemctl stop` to restore their defined defaults.

```bash
sudo install -m 0644 systemd/cpu-performance.service /etc/systemd/system/
sudo install -m 0644 systemd/gpu-max-clocks.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-performance.service gpu-max-clocks.service

# Restore the unit-defined normal policies and disable persistence:
sudo systemctl disable --now cpu-performance.service gpu-max-clocks.service
```

## Publishing or upstreaming

This directory is ready to become its own Git repository. A sensible next step
is:

1. publish the reproduction kit and exact measurement contract;
2. open separate, small upstream issues or pull requests for the replicated MTP
   projection, XPU local argmax, and prompt-length guard;
3. include correctness tests for every patch and disclose that the first-token
   optimization is BMG/oneCCL-motivated;
4. rebase against the current upstream vLLM revision instead of loosening the
   Docker pin.

The repository redistributes no model checkpoint weights. The prebuilt image
does include the pinned third-party base layers identified above. The kit is
provided under Apache-2.0 because the patch modifies Apache-2.0 vLLM files;
retain the included license and all upstream source notices when publishing it.
