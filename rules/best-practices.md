# Best Practices — Building Arduino UNO Q Apps Well

The prescriptive DO list for App Lab applications on the Arduino UNO Q (Qualcomm Dragonwing QRB2210 MPU running Debian Linux + STM32U585 MCU running Zephyr, talking over the **Bridge** RPC layer). These rules are authoritative (sourced from the official `AGENTS.md` agent contract and Arduino docs) and enriched with field tips from a Thai tutorial series (cited per-episode). Where a tutorial tip differs from the official position, both are shown and flagged.

Cross-references:
- Code-quality bar: [quality-standards.md](./quality-standards.md)
- Symptom/fix lookup: [../references/troubleshooting.md](../references/troubleshooting.md)

---

## 1. Put each job on the right brain

The UNO Q is a dual-processor board. Decide where work belongs *before* writing code.

- **MCU (STM32U585 / Zephyr) — real-time, deterministic.** GPIO, sensor sampling, motor/PWM, debouncing, precise timing, anything that must not be jittered by Linux scheduling. Keep timing-critical loops here.
- **MPU (Qualcomm / Debian Linux) — high-level, resource-heavy.** Python logic, AI inference (Bricks), networking, web UI, databases, cloud calls.
- **Do NOT** push high-frequency sensor sampling up to Python and back — sample on the MCU, send results up via `Bridge.notify(...)`.
- **Do NOT** try to run real-time PWM/timing from Python — Linux is not deterministic; delegate to the MCU sketch.
- The MCU runs a real-time OS (Zephyr) and supports multitasking; treat it as a true co-processor, not a dumb peripheral (EP54 - What is Arduino UNO Q?).

## 2. Compose official Bricks before building custom

Bricks are pre-packaged services (Docker containers on the Linux side) reused via Python APIs. They are the intended unit of reuse.

- **Reach for an existing Brick first** — object detection, image classification, mood detection, keyword spotting, audio classification, database (SQL / time-series), web UI (HTML / Streamlit), cloud LLM, ASR, Telegram bot, etc. all ship as Bricks.
- Only build a **custom Brick** (EP89 - Custom Bricks, from tutorial) when no official Brick fits — and follow the new-brick discovery workflow (scrape `arduino/app-bricks-examples` and `arduino/app-bricks-py`, draft the doc, confirm, then write) rather than hand-rolling from scratch.
- **You own `app.yaml`.** Every Brick the code imports MUST be listed under `bricks:` in `app.yaml` (e.g. `- arduino:web_ui: {}`). Edit the file directly — never instruct the user to add Bricks through the App Lab GUI.
- Every sketch library the `.ino` uses MUST be listed under `libraries:` in `sketch/sketch.yaml`.

## 3. Never hand-build the project tree — scaffold it

- Start from **`arduino-app-cli app new <name>`** or by **copying an official Example** in App Lab (e.g. the Weather Forecast example, EP4/EP15). Copying a working Example and editing it is the fastest reliable on-ramp (EP4 - first app).
- The layout is **fixed**: `app.yaml`, `python/main.py`, `python/requirements.txt`, `sketch/sketch.ino`, `sketch/sketch.yaml`, `assets/`. Respect it.
- Deployed apps live on the board at `/home/arduino/ArduinoApps/<app-name>/`.

## 4. Respect the Bridge contract (Python ↔ MCU)

The Bridge is RPC between Python (Boss/caller) and C++ (Subordinate/provider). Treat its rules as hard constraints — violations fail *silently* or *deadlock*.

- **`App.run()` is the LAST line of `python/main.py`.** Anything after it is ignored.
- In C++, expose callbacks with **`Bridge.provide_safe(name, fn)`** by default — it queues the work into `loop()` context. Reserve plain `Bridge.provide` for advanced, no-hardware, no-Arduino-API cases. Using plain `provide` for Arduino API calls (digitalWrite/Read, Serial) risks a race condition with the main loop and can fail the Linux↔MCU handshake, hanging the system (EP57 - Bridge).
- **Match argument types exactly** across the wire: Python `int`↔C++ `int` (32-bit), `float`↔`float`, `bool`↔`bool`, `str`↔`const char*`/`String`. Mismatches **fail silently** — no error, the call just does nothing.
- **Never call `Bridge.call(...)` or `Monitor.print(...)` inside a `Bridge.provide*` callback** — it deadlocks the Bridge. Move outbound calls to a periodic loop or a queue consumed elsewhere.
- **`call` waits** for a return value; **`notify` is fire-and-forget** — use `notify` for high-frequency telemetry (sensor streams) so the MCU loop never blocks (EP57 - Bridge).
- For long MPU-side computation without blocking the MCU, use the async **`RpcCall`** + result-polling pattern instead of a blocking `call` (EP72 - Using RpcCall, from tutorial).
- `Arduino_RouterBridge` is bundled on Zephyr core ≥ 0.55.0 — just `#include <Arduino_RouterBridge.h>`; do NOT add it to `sketch.yaml`.
- **Do not touch the high-speed UART reserved for the Arduino Router** — it carries the Bridge traffic; using it for your own serial breaks the system (EP57 - Bridge, from tutorial).

## 5. Keep timing-critical work on the MCU — and keep both loops non-blocking

- **No blocking `delay()` (MCU) or `time.sleep()` (Python) longer than a few ms** in any loop or callback — the Bridge must keep servicing requests. Use `millis()`-based non-blocking timing on the MCU.
- Push samples up with `Bridge.notify("on_sample", x, y, z)` from a rate-limited MCU loop (e.g. gate on `millis()` for ~60 Hz), not a busy spin.

## 6. Respect 4 GB RAM — sequence AI work, don't stack it

The MPU has limited RAM (2 GB or 4 GB depending on SKU; AI Bricks run as Docker containers). Memory, not CPU, is the usual ceiling.

- **Prefer the 4 GB board for any AI workload.** Run vision/audio Bricks one at a time; do not load multiple heavy models concurrently.
- **Expect a slow first run** of any Brick — the Docker image/model downloads and starts on first use. This is normal, not a hang (EP4 - first app; EP54).
- Train models small for the target: object detection via **FOMO** at **96×96 grayscale** keeps RAM/Flash and inference time low (~14 ms inference reported); use **int8 quantization** on export so the model fits the device (EP31 - Object Detection training; EP36 - Keyword Spotting training, from tutorial).
- Free RAM, CPU and storage are visible in the App Lab board-status panel — check it before deploying a heavy app (EP4 - first app).

## 7. On-device first; cloud only when it earns it

- **Default to local inference** (Edge Impulse `.eim` models + vision/audio Bricks) for privacy, latency, offline operation, and zero per-call cost.
- Use **cloud Bricks** (Cloud LLM, Cloud ASR) only when the task genuinely needs a large model. They require an internet connection and an API key, which adds cost, latency, and a privacy surface (EP51 - Cloud LLM Brick).
- **Never hardcode cloud API keys** in `main.py` — deploy credentials through App Lab / app config, not source. See [quality-standards.md](./quality-standards.md) §secrets. (EP51 deploys keys via App Lab config, not inline — follow that.)

## 8. Vendor all web assets — no runtime CDN

- `WebUI` serves `assets/` as static root and **requires `assets/index.html`** at the configured `assets_dir_path` or the Brick fails to start.
- **Download third-party JS/CSS into `assets/js/vendor/` (or `assets/css/vendor/`)** and reference via relative paths. No `<script src="https://cdn...">` at runtime — the board may be offline or behind a captive network.
- Record pinned versions + source URLs in `assets/js/vendor/VERSIONS.md`.

## 9. Structure apps cleanly

- Keep `python/main.py` thin: wiring + the chosen run shape (periodic `user_loop=` **or** event-driven `App.run()`), never both mixed. Extract logic into small modules.
- Python deps go in **`python/requirements.txt` only** — never a `requirements.txt` at repo root.
- Write all code comments and docs in English.
- Keep changes minimal and focused; no speculative refactors.

## 10. Handle errors at the boundaries

- Validate Bridge inputs and web/API payloads at the edge — never trust data crossing the Python↔MCU boundary or arriving from a browser/cloud.
- Check Brick/peripheral initialization and cloud-call return values; surface failures (log on MPU, `Monitor` on MCU) instead of swallowing them.
- For `.eim` deployment, point `app.yaml` at the model with the **exact syntax from the official model-type example** — a missing bracket/wrong key silently degrades or breaks inference (EP35 - Repair clip Ep.33, from tutorial). See troubleshooting for the deploy steps.

## 11. Deploy & operate deliberately

- Detect execution context: on-board use `arduino-app-cli`; off-board use `adb shell arduino-app-cli` (USB) or **Network Mode + SSH** (wireless) — see [../references/troubleshooting.md](../references/troubleshooting.md).
- Core app CLI verbs: `new`, `start`, `stop`, `list`, `log`, `clean-cache`; system verbs: `update`, `reboot`, `set-name`, `network-mode`, `clean-up` (EP63 - Arduino App CLI).
- Run `update` after a fresh OS flash to bring Server/ADBD/CLI current before building (EP3 / EP77 - initial setup).
- Use App Lab's **Run at Startup** to make an app launch headless on power-up (e.g. powered by a power bank); remember to disable it when reconnecting to a PC for development (EP62 - Run at Startup).
