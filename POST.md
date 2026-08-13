# How I got Qwen3.6-27B to 52.9 tok/s on two Intel Arc Pro B70s

I wanted the fastest local Qwen3.6-27B setup I could get without buying new
hardware or lowering model quality. The machine has two Arc Pro B70s: 64 GB of
aggregate VRAM and about 1.216 TB/s of aggregate theoretical memory bandwidth.

The starting point was the official `Qwen/Qwen3.6-27B-FP8` checkpoint on Intel's
XPU vLLM image. With tensor parallelism across both cards and no speculative
decoding, it produced 31.90 tok/s in an isolated, cache-resistant single-stream
test.

The winning profile kept the full official block-FP8 weights. It uses FP8 KV,
FP16 activations and Mamba state, TP=2, a 262,144-token context, 8,192 max
batched tokens, 86% GPU-memory utilization, compiled execution, async
scheduling, and no prefix caching. I pinned the GPUs at their advertised max
clock and set the CPU governor to performance.

The largest gain came from making Qwen's native MTP path work efficiently on
dual BMG GPUs. Four changes mattered:

1. The MTP output projection started and ended replicated, but vLLM sharded it
   and performed an all-gather on every draft step. That collective could reset
   the dual-GPU process. Replicating this roughly 50 MiB FP8 projection on each
   card removed the collective without changing its math.
2. Draft-token selection used a full-vocabulary TP gather. I replaced it with a
   local per-rank argmax plus a tiny reduction. Padding the small oneCCL payload
   to the known-stable 512 bytes per rank avoided the broken eager-message path.
3. The first MTP proposal otherwise performed multiple serial draft forwards
   before the first token. The patched path primes the hybrid state once and
   reuses that draft as placeholders. Every proposed token is still verified by
   the full 27B target, and subsequent proposals use the normal loop.
4. MTP helped short decode but hurt very long prompts, so it is enabled only
   through 8,192 prompt tokens. Longer requests automatically use the target
   model without speculation.

Two proposals, MTP2, were the best measured tradeoff. The result was 52.94
tok/s median C1 decode, up 66% from 31.90. Three cold passes measured
169.48-175.94 tok/s aggregate at C4 and 267.37-282.57 at C8. Short-prompt TTFT
rose 6.06%; a 104k-token prompt rose only 1.74% because of the MTP guard.

I did not accept speed alone. The local endpoint and a separate hosted endpoint
running the exact same official FP8 checkpoint received the same frozen
financial-operator workload. Both scored 73.440476/85, every critical category
tied, and all 82 blinded response comparisons were ties. A one-hour mixed
C1/C4/C8 soak completed 6,981/6,981 correct requests and 612,470 output tokens
with no request errors, container restarts, GPU losses, kernel resets, or hangs.

The main lesson: this was not a lower-bit quantization or a warm-prefix-cache
benchmark. It was mostly removing unnecessary communication from native MTP,
guarding where speculation is useful, and measuring cold, end-to-end behavior.

I packaged the Docker patch, launcher, and cache-resistant benchmark alongside
this post. It is pinned to Intel's `0.21.0-b3` image because these are internal
vLLM changes; do not apply it blindly to another vLLM revision. Treat the kit as
a reproducible reference until the changes are rebased or upstreamed.
