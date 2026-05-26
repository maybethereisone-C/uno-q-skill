# Quality Standards — Arduino UNO Q Apps

The code-quality bar for App Lab applications. A UNO Q app spans two languages on two processors (Python on the Linux MPU, C++ on the Zephyr MCU) plus optional web assets — these standards apply across all of them. Use this as a pre-merge / pre-"done" checklist.

Cross-references:
- The prescriptive DO list: [best-practices.md](./best-practices.md)
- Symptom/fix lookup: [../references/troubleshooting.md](../references/troubleshooting.md)

---

## File & function size

- [ ] Files focused: **200–400 lines typical, 800 hard max**. Split by feature/domain, not by type.
- [ ] Functions small: **< 50 lines**, single responsibility.
- [ ] Nesting **≤ 4 levels** — prefer early returns over stacked conditionals.
- [ ] `python/main.py` stays thin (wiring + run shape); business logic lives in separate modules.
- [ ] `assets/js/app.js` and `assets/css/app.css` stay focused; large UI logic split into modules.

## Naming

- [ ] Python/JS: `camelCase` functions/vars; `PascalCase` classes/types; `UPPER_SNAKE_CASE` constants.
- [ ] Booleans prefixed `is` / `has` / `should` / `can`.
- [ ] **Bridge RPC service names match exactly** on both sides and are descriptive (the string is the contract; a typo = silent no-op).
- [ ] C++ functions use clear names and an **explicit signature with typed params** (the Bridge types arguments across the wire).

## Immutability

- [ ] Prefer returning new objects/dicts over mutating in place (Python state, JS UI state).
- [ ] Use `const` for read-only values in C++/JS; constants for thresholds, intervals, pins, ports.
- [ ] No magic numbers — name sample rates, timeouts, port numbers, model dimensions.

## Validation at boundaries

- [ ] Validate every value crossing the **Python↔MCU Bridge** — types must match (`int`/`float`/`bool`/`str` ↔ `int`/`float`/`bool`/`const char*`); a mismatch fails silently, so coerce explicitly (e.g. `int(data["value"])`) before `Bridge.call`.
- [ ] Validate all **web/REST/WebSocket payloads** before use (schema or explicit checks); never trust browser/cloud input.
- [ ] Check **Brick / peripheral / model init** return values and cloud-call results; fail fast with a clear message.
- [ ] Bounds-check arrays/buffers on the MCU side.

## Secrets — never in code

- [ ] **No API keys, tokens, passwords, or Wi-Fi credentials in source** (`main.py`, `.ino`, JS).
- [ ] Cloud credentials (Gemini / OpenAI / Anthropic, ASR) are deployed via **App Lab app config**, not inlined — matches the tutorial's deploy-via-App-Lab flow (EP51 - Cloud LLM Brick).
- [ ] No secrets committed to git; if a key is exposed, rotate it.

## Logging

- [ ] **MCU side:** log via `Monitor.begin()` / `Monitor.print()` / `Monitor.println()` to the App Lab Serial Monitor (`Serial.print` also works on Zephyr core ≥ 0.55.0). **Never** call `Monitor.print()` inside a `Bridge.provide*` callback — it deadlocks the Bridge.
- [ ] **Python side:** use real logging (`print`/`logging`) on the Linux MPU; view with `arduino-app-cli ... log`.
- [ ] No debug spew left in tight MCU loops (blocking serial in a timing loop jitters it); no leftover commented-out code.
- [ ] Error messages are actionable and do not leak secrets.

## Timing & concurrency (MCU)

- [ ] No blocking `delay()` > a few ms in `loop()` or callbacks; use `millis()`-based non-blocking timing (`unsigned long`, overflow-safe subtraction `now - last >= INTERVAL`).
- [ ] No blocking `time.sleep()` > a few ms in Python loops/callbacks — the Bridge must keep servicing.
- [ ] Hardware-touching callbacks use `Bridge.provide_safe` (loop context), not plain `Bridge.provide` (avoids race conditions / handshake failure, EP57 - Bridge).
- [ ] High-frequency MCU→Python data uses `Bridge.notify` (non-blocking), not `Bridge.call`.

## Resource discipline (MPU, 2–4 GB RAM)

- [ ] Heavy AI Bricks run **one at a time**; no concurrent large models.
- [ ] Models exported small for the target: appropriate input size (e.g. 96×96), grayscale where acceptable, **int8 quantization** (EP31 / EP36 training, from tutorial).
- [ ] Web assets vendored locally under `assets/.../vendor/` with `VERSIONS.md`; no runtime CDN.

## Configuration integrity

- [ ] `app.yaml` lists **every** Brick the code imports, under `bricks:`.
- [ ] `sketch/sketch.yaml` lists **every** sketch library used, under `libraries:`.
- [ ] `Arduino_RouterBridge` is NOT added to `sketch.yaml` (bundled on core ≥ 0.55.0).
- [ ] `.eim` model path in `app.yaml` uses the **exact key/syntax from the matching model-type example** — verify against the official example, a small syntax slip silently degrades inference (EP35 - Repair clip Ep.33, from tutorial).
- [ ] `App.run()` is the last executable line of `python/main.py`.

## Testing approach (embedded + Python)

- [ ] **Python logic:** unit-test pure functions off-board (parsing, transforms, payload validation, state). Aim for the 80% bar on testable logic; mock the Bridge and Bricks.
- [ ] **Bridge contract:** for each RPC pair, assert the Python-side arg types match the C++ signature; add a smoke test that the call returns/notifies as expected on hardware.
- [ ] **MCU sketch:** exercise on-device via the Serial Monitor; verify each `provide_safe` callback responds and the loop stays non-blocking. There is no full host emulator — plan a hardware smoke pass.
- [ ] **End-to-end:** deploy with `arduino-app-cli` and watch `... log` + Serial Monitor for one full happy-path and one failure-path run before declaring done.
- [ ] **AI Bricks:** validate the model against a held-out test set in Edge Impulse (accuracy + inference time + RAM/Flash) **before** deploying the `.eim`; re-check live behavior on-device (lighting/mic conditions differ from training).

## Documentation

- [ ] `app.yaml` `name` / `description` / `ports` / `icon` are sensible.
- [ ] README (if present) states which board SKU (2 GB vs 4 GB), required peripherals, and any cloud keys needed.
- [ ] Comments explain *why*, in English.
