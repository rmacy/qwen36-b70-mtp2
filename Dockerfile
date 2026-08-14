ARG BASE_IMAGE=intel/llm-scaler-vllm@sha256:7a526dcfc49c77afeabf77e2e2a41a9a0221126580d144d2d1a15e320befb210
FROM ${BASE_IMAGE}

# Keep the Intel runtime pinned while replacing the vulnerable userspace Linux
# headers inherited from that image. This package does not change the running
# kernel or the XPU driver stack.
ARG LINUX_LIBC_DEV_VERSION=6.8.0-137.137
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --only-upgrade \
      "linux-libc-dev=${LINUX_LIBC_DEV_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

LABEL org.opencontainers.image.source="https://github.com/rmacy/qwen36-b70-mtp2" \
      org.opencontainers.image.title="Qwen3.6-27B MTP2 for dual Intel BMG" \
      org.opencontainers.image.description="Version-pinned Intel XPU vLLM runtime with the validated dual-BMG MTP2 patch" \
      org.opencontainers.image.licenses="Apache-2.0"

COPY patches/vllm-bmg-mtp2.patch /tmp/vllm-bmg-mtp2.patch
COPY patches/CVE-2026-48746-auth-bypass.patch /tmp/CVE-2026-48746-auth-bypass.patch
COPY tests/verify_auth_backport.py tests/verify_mtp_patch.py /tmp/qwen-tests/
WORKDIR /opt/venv/lib/python3.12/site-packages
RUN patch --batch --forward -p1 < /tmp/vllm-bmg-mtp2.patch \
    && patch --batch --forward -p1 < /tmp/CVE-2026-48746-auth-bypass.patch \
    && /opt/venv/bin/python -m py_compile \
      vllm/entrypoints/openai/server_utils.py \
      vllm/model_executor/layers/logits_processor.py \
      vllm/model_executor/models/qwen3_5_mtp.py \
      vllm/v1/core/sched/async_scheduler.py \
      vllm/v1/spec_decode/llm_base_proposer.py \
      vllm/v1/worker/gpu_model_runner.py \
    && /opt/venv/bin/python /tmp/qwen-tests/verify_mtp_patch.py \
    && /opt/venv/bin/python /tmp/qwen-tests/verify_auth_backport.py \
    && rm -rf \
      /tmp/vllm-bmg-mtp2.patch \
      /tmp/CVE-2026-48746-auth-bypass.patch \
      /tmp/qwen-tests

COPY launch.sh /usr/local/bin/qwen36-bmg-launch
COPY tests/verify_launcher.sh /tmp/qwen-launcher-tests/verify_launcher.sh
RUN chmod 0755 /usr/local/bin/qwen36-bmg-launch \
    && bash /tmp/qwen-launcher-tests/verify_launcher.sh \
    && rm -rf /tmp/qwen-launcher-tests

ENTRYPOINT ["/usr/local/bin/qwen36-bmg-launch"]
