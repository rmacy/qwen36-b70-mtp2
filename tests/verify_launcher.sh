#!/usr/bin/env bash
set -euo pipefail

fake_dir=$(mktemp -d)
cleanup() {
  find "${fake_dir}" -type f -delete 2>/dev/null || true
  rmdir "${fake_dir}" 2>/dev/null || true
}
trap cleanup EXIT
launcher=${LAUNCHER_PATH:-/usr/local/bin/qwen36-bmg-launch}

printf '%s\n' '#!/usr/bin/env bash' 'printf "<%s>\\n" "$@"' > "${fake_dir}/vllm"
chmod 0755 "${fake_dir}/vllm"

run_launcher() {
  PATH="${fake_dir}:${PATH}" "${launcher}"
}

default_output=$(run_launcher)
grep -Fxq '<serve>' <<<"${default_output}"
grep -Fxq '<--max-model-len>' <<<"${default_output}"
grep -Fxq '<262144>' <<<"${default_output}"
grep -Fxq '<--speculative-config>' <<<"${default_output}"
grep -Fxq '<{"method":"qwen3_next_mtp","num_speculative_tokens":2,"use_local_argmax_reduction":true}>' <<<"${default_output}"

secured_output=$(API_KEY=release-audit-placeholder PREFIX_CACHE=1 ENFORCE_EAGER=1 run_launcher)
grep -Fxq '<--api-key>' <<<"${secured_output}"
grep -Fxq '<release-audit-placeholder>' <<<"${secured_output}"
grep -Fxq '<--enable-prefix-caching>' <<<"${secured_output}"
grep -Fxq '<--enforce-eager>' <<<"${secured_output}"

no_mtp_output=$(MTP_TOKENS=0 run_launcher)
if grep -Fxq '<--speculative-config>' <<<"${no_mtp_output}"; then
  echo 'MTP_TOKENS=0 still emitted --speculative-config' >&2
  exit 1
fi

echo 'Qwen launcher regression checks passed'
