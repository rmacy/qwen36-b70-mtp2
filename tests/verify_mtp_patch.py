#!/usr/bin/env python3
"""Validate the complete dual-BMG MTP2 patch in the final image filesystem."""

from pathlib import Path


SITE = Path("/opt/venv/lib/python3.12/site-packages/vllm")

logits = (SITE / "model_executor/layers/logits_processor.py").read_text()
model = (SITE / "model_executor/models/qwen3_5_mtp.py").read_text()
scheduler = (SITE / "v1/core/sched/async_scheduler.py").read_text()
proposer = (SITE / "v1/spec_decode/llm_base_proposer.py").read_text()
runner = (SITE / "v1/worker/gpu_model_runner.py").read_text()

assert "gather_width = 128 if hidden_states.shape[0] == 1 else 64" in logits
assert "gather_output=False" in model
assert "disable_tp=True" in model
assert 'os.environ.get("QWEN_MTP_MAX_PROMPT_TOKENS", "8192")' in scheduler
assert "[] if mtp_disabled_for_request else self._spec_token_placeholders" in scheduler
assert "if self.method == \"mtp\" and getattr(self, \"first_mtp_proposal\", False):" in proposer
assert "return draft_token_ids.view(-1, 1).repeat(" in proposer
assert "skip_mtp_for_long_batch = (" in runner
assert "self.drafter.first_mtp_proposal = first_mtp_proposal" in runner
assert "if not skip_mtp_for_long_batch:" in runner

print("Dual-BMG MTP2 final-filesystem regression check passed")
