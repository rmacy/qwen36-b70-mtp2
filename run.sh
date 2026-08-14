#!/usr/bin/env bash
set -euo pipefail

: "${MODEL_DIR:?Set MODEL_DIR to the absolute host path of Qwen3.6-27B-FP8}"

IMAGE="${IMAGE:-qwen36-bmg-mtp2:0.1.3}"
CONTAINER="${CONTAINER:-qwen36-bmg-mtp2}"
PORT="${PORT:-8000}"
CACHE_DIR="${CACHE_DIR:-${PWD}/.vllm-cache}"

if [[ ! -f "${MODEL_DIR}/config.json" || ! -f "${MODEL_DIR}/model.safetensors.index.json" ]]; then
  echo "MODEL_DIR does not contain a complete indexed checkpoint: ${MODEL_DIR}" >&2
  exit 1
fi

python3 - "${MODEL_DIR}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
index = json.loads((root / "model.safetensors.index.json").read_text())
required = sorted(set(index["weight_map"].values()))
missing = [
    name
    for name in required
    if not (root / name).is_file() or (root / name).stat().st_size == 0
]
if missing:
    raise SystemExit("Missing or empty checkpoint shards: " + ", ".join(missing))
print(f"Validated {len(required)} checkpoint shards")
PY

mkdir -p "${CACHE_DIR}"
docker image inspect "${IMAGE}" >/dev/null
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true

docker_args=(
  run -d --name "${CONTAINER}"
  --restart unless-stopped
  --device /dev/dri
  --ipc=host --shm-size 32g
  -p "127.0.0.1:${PORT}:8000"
)

if [[ -d /dev/dri/by-path ]]; then
  docker_args+=(
    --mount "type=bind,source=/dev/dri/by-path,target=/dev/dri/by-path,readonly"
  )
fi

if [[ -n "${API_KEY:-}" ]]; then
  docker_args+=(-e "API_KEY=${API_KEY}")
fi

docker_args+=(
  --mount "type=bind,source=${MODEL_DIR},target=/models/qwen,readonly"
  --mount "type=bind,source=${CACHE_DIR},target=/root/.cache/vllm"
  -e "ZE_AFFINITY_MASK=${ZE_AFFINITY_MASK:-0,1}"
  -e "TP_SIZE=${TP_SIZE:-2}"
  -e "GPU_UTIL=${GPU_UTIL:-0.86}"
  -e "MAX_MODEL_LEN=${MAX_MODEL_LEN:-262144}"
  -e "MAX_BATCHED_TOKENS=${MAX_BATCHED_TOKENS:-8192}"
  -e "BLOCK_SIZE=${BLOCK_SIZE:-64}"
  -e "MODEL_DTYPE=${MODEL_DTYPE:-float16}"
  -e "MAMBA_SSM_CACHE_DTYPE=${MAMBA_SSM_CACHE_DTYPE:-float16}"
  -e "KV_CACHE_DTYPE=${KV_CACHE_DTYPE:-fp8}"
  -e "MTP_TOKENS=${MTP_TOKENS:-2}"
  -e "MTP_LOCAL_ARGMAX=${MTP_LOCAL_ARGMAX:-1}"
  -e "QWEN_MTP_MAX_PROMPT_TOKENS=${MTP_MAX_PROMPT_TOKENS:-8192}"
  -e "PREFIX_CACHE=${PREFIX_CACHE:-0}"
  -e "ENFORCE_EAGER=${ENFORCE_EAGER:-0}"
  -e "VLLM_USE_AOT_COMPILE=${VLLM_USE_AOT_COMPILE:-0}"
  -e "CCL_TOPO_P2P_ACCESS=${CCL_TOPO_P2P_ACCESS:-1}"
  -e "CCL_ZE_IPC_EXCHANGE=${CCL_ZE_IPC_EXCHANGE:-drmfd}"
  -e "CCL_SYCL_ALLGATHERV_TMP_BUF=${CCL_SYCL_ALLGATHERV_TMP_BUF:-0}"
  -e "CCL_SYCL_ALLREDUCE_TMP_BUF=${CCL_SYCL_ALLREDUCE_TMP_BUF:-0}"
  -e "CCL_ENABLE_SYCL_KERNELS=${CCL_ENABLE_SYCL_KERNELS:-1}"
  -e "CCL_SYCL_ALLGATHERV_SMALL_THRESHOLD=${CCL_SYCL_ALLGATHERV_SMALL_THRESHOLD:-131072}"
  -e "CCL_SYCL_ALLGATHERV_SCALEOUT_THRESHOLD=${CCL_SYCL_ALLGATHERV_SCALEOUT_THRESHOLD:-1048576}"
  -e "UR_L0_V2_FORCE_DISABLE_COPY_OFFLOAD=${UR_L0_V2_FORCE_DISABLE_COPY_OFFLOAD:-0}"
  "${IMAGE}"
)

docker "${docker_args[@]}"

echo "Started ${CONTAINER} on http://127.0.0.1:${PORT}/v1"
