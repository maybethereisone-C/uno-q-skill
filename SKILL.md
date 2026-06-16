---
name: arduino-uno-q
description: >-
  Use when building ANYTHING on the Arduino UNO Q board with Arduino App Lab —
  Apps and Bricks, the A53<->STM32 Bridge RPC, on-device LLM, vision/audio AI,
  Python + sketch projects, web dashboards, and arduino-app-cli deploy. The
  complete 0-to-hero UNO Q reference. Triggers: "UNO Q", "Arduino App Lab",
  "Brick", "arduino-app-cli", "Bridge.call", "on-device LLM on Arduino",
  "Edge Impulse .eim", "Qualcomm Dragonwing", "STM32U585", "wellness pet on Arduino".
---

# Arduino UNO Q — complete build skill

Everything needed to build real products on the Arduino UNO Q: a dual-brain board
(Qualcomm quad Cortex-A53 running **Debian Linux + Docker** + an **STM32U585 MCU**
on **Zephyr**) programmed through **Arduino App Lab** using **Apps** and **Bricks**.

> **Read this file first, then jump to the linked reference for whatever you're doing.**
> Don't re-derive the architecture each time — it's all captured here.

## The one thing to understand first

The UNO Q has **two brains** that talk over the **Bridge**:

- **Linux brain (A53):** Python, AI models, web app, on-device LLM, networking. → most of your code.
- **Real-time brain (STM32/Zephyr):** GPIO, sensors, timing-critical I/O. → the sketch.
- **Golden rule:** timing-critical/pin work → MCU sketch; everything else → Linux/Python; connect them with the Bridge.

Full model: **`references/board-architecture.md`**.

## What an "App" is

An App bundles BOTH halves + the web UI as one deployable unit:

```
my-app/
  app.yaml           # name, icon, description, bricks: [...]
  python/main.py     # Linux side (Bricks, app logic, Bridge.call to MCU)
  sketch/sketch.ino  # MCU side (Bridge.provide, real-time I/O)
  sketch/sketch.yaml # platform: arduino:zephyr
  assets/            # web UI (index.html, app.js, style.css, vendored socket.io)
```

Full anatomy: **`references/app-anatomy.md`**. Ready-to-copy starters: **`templates/`**.

## 0-to-hero path (new to UNO Q? follow in order)

1. **`references/board-architecture.md`** — the dual-brain mental model.
2. **`references/app-anatomy.md`** — how an App is laid out.
3. **`workflow/step1-scaffold.md` → `step6-deploy-test.md`** — build an App empty → deployed, step by step.
4. **`references/bricks-catalog.md`** — the official Bricks you compose apps from.
5. **`examples/general-sensor-dashboard.md`** and **`examples/general-ai-camera.md`** — full worked apps.

## Reference index

| Topic | File |
|---|---|
| Dual-brain board model, specs, RAM variants | `references/board-architecture.md` |
| App folder anatomy (app.yaml / python / sketch / assets) | `references/app-anatomy.md` |
| `arduino-app-cli` — full command + deploy loop | `references/arduino-app-cli.md` |
| Classic `arduino-cli` for isolated MCU builds (Zephyr) | `references/arduino-cli-zephyr.md` |
| **Bridge RPC** — Python↔MCU, full API + examples | `references/bridge-rpc.md` |
| **Bricks catalog** — all official Bricks | `references/bricks-catalog.md` |
| On-device LLM Brick (+ function-calling, RAM) | `references/on-device-llm.md` |
| Ollama local-LLM runtime + Claude Code on-board | `references/ollama-on-board.md` |
| Web UI Brick (+ socket.io wiring) | `references/web-ui-brick.md` |
| Authoring your own custom Brick | `references/custom-bricks.md` |
| Troubleshooting / gotchas (incl. field tips) | `references/troubleshooting.md` |
| **Wi-Fi setup AP + captive portal** (headless onboarding; hostapd/NM/single-radio) | `references/wifi-ap-captive-portal.md` |
| **Bluetooth access** (phone↔board over BT; BlueZ 5.82 NAP/PAN vs BLE-GATT) | `references/bluetooth-access.md` |

## Keep this skill growing (continuous improvement)

When you hit something on this board that has **no reference or best practice here**
— a new subsystem, a non-obvious failure, a hardware quirk — **research it, verify it
on the real board, then update this skill**: add or extend a `references/*.md` and
link it from the index above. The skill must improve alongside the project, so the
next session starts from what this one learned (don't re-derive). Mark findings
**VERIFIED on <board> <date>** vs **(unverified)**. (Example: `wifi-ap-captive-portal.md`
was added this way — net-new headless-onboarding work with no prior reference.)

## Rules (read before/while coding)

| Rule | File |
|---|---|
| Best practices (the DO list) | `rules/best-practices.md` |
| Code quality standards | `rules/quality-standards.md` |
| Bridge anti-patterns (silent failures!) | `rules/bridge-anti-patterns.md` |
| Deploy safety | `rules/deploy-safety.md` |
| Resource limits (4 GB RAM discipline) | `rules/resource-limits.md` |

## Build workflow

`workflow/step1-scaffold.md` · `step2-select-bricks.md` · `step3-python-logic.md` ·
`step4-mcu-sketch.md` · `step5-webui.md` · `step6-deploy-test.md`

## Templates & scripts

- **Templates:** `templates/app.yaml.tmpl`, `python-main.py.tmpl`, `sketch.ino.tmpl`, `sketch.yaml.tmpl`, `webui-assets/*`.
- **Scripts:** `scripts/new-app.sh` (scaffold), `scripts/deploy.sh` (push + start), `scripts/logs.sh` (tail logs), `scripts/board-connect.sh` (adb/ssh).

## Top gotchas (full list in troubleshooting.md / the rules)

- **Bridge type mismatch fails SILENTLY** — Python and C++ types must match exactly. (`rules/bridge-anti-patterns.md`)
- **Don't run vision + LLM at once on 4 GB** — sequence them. (`rules/resource-limits.md`)
- **Never hand-build the App tree** — use `arduino-app-cli app new` or copy an example.
- **Flashing is App Lab's job**, not `arduino-cli upload`, for App-owned sketches. (`rules/deploy-safety.md`)
- **`chown -R arduino:arduino`** after `adb push`; expect a first-run `sudo` prompt.
- **Compose official Bricks before building custom** — the `llm` and `web_ui` Bricks already exist.

## Source material

This skill was authored from official Arduino sources cloned under `skill-sources/`
(`app-bricks-py`, `app-bricks-examples`, `arduino-app-cli`, `arduino-router`,
`arduino-uno-q-agent-template`) plus the `wedsamuel1230/arduino-skills` classic-CLI skill.
For low-level classic `arduino-cli` tasks, defer to that skill; this one owns the
UNO Q / App Lab / Bricks / Bridge layer. Items that could not be verified against
source are marked "(unverified)" in the reference files — confirm on the real board.
