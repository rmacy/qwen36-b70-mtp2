#!/usr/bin/env bash
set -euo pipefail

export ZE_AFFINITY_MASK="${ZE_AFFINITY_MASK:-0,1}"
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export VLLM_USE_AOT_COMPILE="${VLLM_USE_AOT_COMPILE:-0}"

speculative_args=()
if (( ${MTP_TOKENS:-2} > 0 )); then
  local_argmax=""
  if [[ "${MTP_LOCAL_ARGMAX:-1}" == "1" ]]; then
    local_argmax=',"use_local_argmax_reduction":true'
  fi
  speculative_args=(
    --speculative-config
    "{\"method\":\"qwen3_next_mtp\",\"num_speculative_tokens\":${MTP_TOKENS:-2}${local_argmax}}"
  )
fi

prefix_args=()
if [[ "${PREFIX_CACHE:-0}" == "1" ]]; then
  prefix_args=(--enable-prefix-caching)
fi

eager_args=()
if [[ "${ENFORCE_EAGER:-0}" == "1" ]]; then
  eager_args=(--enforce-eager)
fi

exec vllm serve --host 0.0.0.0 --port "${IN_CONTAINER_PORT:-8000}" \
  --model "${MODEL_PATH:-/models/qwen}" \
  --served-model-name "${SERVED_MODEL_NAME:-qwen3.6-27b-fp8}" \
  --tensor-parallel-size "${TP_SIZE:-2}" \
  --gpu-memory-util "${GPU_UTIL:-0.86}" \
  --max-num-batched-tokens "${MAX_BATCHED_TOKENS:-8192}" \
  --max-model-len "${MAX_MODEL_LEN:-262144}" \
  --block-size "${BLOCK_SIZE:-64}" \
  --dtype "${MODEL_DTYPE:-float16}" \
  --mamba-ssm-cache-dtype "${MAMBA_SSM_CACHE_DTYPE:-float16}" \
  --kv-cache-dtype "${KV_CACHE_DTYPE:-fp8}" \
  --trust-remote-code \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 \
  --default-chat-template-kwargs '{"enable_thinking":false}' \
  --async-scheduling \
  "${prefix_args[@]}" \
  "${eager_args[@]}" \
  "${speculative_args[@]}"
