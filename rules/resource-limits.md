# Rules: respecting the UNO Q's resource budget

The MPU is a quad Cortex-A53 with **2 GB or 4 GB RAM**, running Debian + Docker. It is capable but **not** a workstation. Treat RAM as the scarce resource.

## DO

- **Target the 4 GB / 32 GB variant** for any app combining on-device LLM + vision + web. The 2 GB variant is for light apps only.
- **Budget RAM explicitly.** A ~3B-parameter LLM at **Q4_K_M ≈ 2 GB**. Add OS + Docker + Python + web + a vision model and 4 GB fills fast.
- **Sequence heavy AI, don't parallelize it.** Run camera/vision inference **or** the LLM at a given moment, not both at once. Gate them behind app state.
- **Quantize sensibly.** Q4_K_M is the practical floor for reliable LLM function-calling; going lower (Q3/Q2) breaks tool-calls before it breaks chat. (See `references/on-device-llm.md`.)
- **Keep models on the 32 GB eMMC**, load on demand, unload when idle. Disk is plentiful; RAM is not.
- **Offload to cloud when it genuinely doesn't fit.** Deep/long conversations, heavy training → cloud. Keep the daily, privacy-sensitive, latency-sensitive paths on-device.
- **Train models off-device** (Edge Impulse), deploy the compiled `.eim` to the board for **inference only**.
- **Mind Docker overhead.** Each Brick may bring its own container; fewer, composed Bricks beat many heavyweight ones.

## DON'T

- ❌ Don't run two large models (vision + LLM) simultaneously on 4 GB — expect OOM / killed containers.
- ❌ Don't assume a model that runs on your laptop runs the same here — the A53 has no big cores and modest AI acceleration; expect lower tokens/sec.
- ❌ Don't hold large buffers (full-res frames, long histories) in Python memory; stream/window them.
- ❌ Don't pick the 2 GB board and then add an on-device LLM.

## Quick budget sketch (4 GB board)

| Consumer | Approx RAM |
|---|---|
| Debian + system | ~0.5–0.8 GB |
| Docker + app runtime | ~0.3–0.5 GB |
| Web app + Python logic | ~0.2–0.4 GB |
| **One** AI model active (LLM ~3B Q4 *or* a vision model) | ~1.5–2 GB |
| Headroom | keep some free — don't run to the edge |

If both an LLM and vision must "feel" concurrent, alternate them on app state and/or use a smaller LLM (~1.5–3B). Measure on the real board; these are planning estimates, not guarantees.
