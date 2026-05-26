# Step 2 — Select Bricks

Goal: lock the `bricks:` list in `app.yaml` so every capability `main.py` needs is
available, and nothing extra is pulled in.

## What a brick is

A brick is a pre-built capability the App Lab runtime provides. Listing
`arduino:web_ui` in `app.yaml` makes `from arduino.app_bricks.web_ui import WebUI`
work in `main.py`. No entry in `app.yaml` → import fails at startup.

See the full list in `references/bricks-catalog.md` (unverified file name —
cross-check the bricks reference in this skill).

## Map capability → brick (verified from examples)

| You want to… | Brick (`app.yaml`) | Import in `main.py` |
| --- | --- | --- |
| Serve a web UI + realtime socket | `arduino:web_ui` | `from arduino.app_bricks.web_ui import WebUI` |
| Detect objects in an image | `arduino:object_detection` | `from arduino.app_bricks.object_detection import ObjectDetection` |
| Classify motion from accelerometer | `arduino:motion_detection` | `from arduino.app_bricks.motion_detection import MotionDetection` |
| Run a local LLM chatbot | `arduino:llm` | `from arduino.app_bricks.llm import ...` (unverified class name) |
| Spot a wake word from the mic | `arduino:keyword_spotting` | (callback-driven; see keyword-spotting example) |

These mappings are taken verbatim from `object-detection`,
`real-time-accelerometer`, `edge-ai-assistant`, and `keyword-spotting`. For any
brick not in this table, confirm the exact class name against the matching example
in `app-bricks-examples/examples/` before importing.

## Rules

1. **One line per brick** under `bricks:`, prefixed `arduino:`.
2. Add a brick **only** when `main.py` imports it. Unused bricks waste resources.
3. `web_ui` is needed for any browser UI — including AI apps that have no sketch
   (`object-detection` uses `web_ui` + `object_detection`, no `sketch/`).
4. A brick may need supporting hardware (e.g. `motion_detection` expects a Modulino
   Movement sensor wired and read in the sketch). Check the example's sketch.

## Example manifests (real)

```yaml
# Browser AI, no MCU (object-detection)
bricks:
  - arduino:web_ui
  - arduino:object_detection
```

```yaml
# Sensor dashboard, MCU streams data (real-time-accelerometer)
bricks:
  - arduino:web_ui
  - arduino:motion_detection
```

```yaml
# Headless MCU reaction, no UI (keyword-spotting)
bricks:
  - arduino:keyword_spotting
```

## Done when

`app.yaml` lists exactly the bricks `main.py` will import — no more, no less.

Next: `workflow/step3-python-logic.md`.
