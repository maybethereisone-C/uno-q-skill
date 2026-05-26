# Step 3 — Python Logic (`python/main.py`)

Goal: write the App's brain. Instantiate bricks, register handlers, wire the
Bridge to the MCU, and end with `App.run()`.

## The fixed skeleton

Every example follows this order. Deviate and the runtime won't start cleanly.

```python
from arduino.app_utils import *                  # App, Bridge, Logger
from arduino.app_bricks.web_ui import WebUI       # one import per brick in app.yaml

# 1. instantiate bricks
ui = WebUI()

# 2. define handlers
def on_command(client, data): ...

# 3. register handlers
ui.on_message("command", on_command)

# 4. run (LAST, blocks forever)
App.run()
```

## Handling messages from the browser

`ui.on_message(event, handler)` registers a callback. Handler signature is
`(client, data)`. To reply:

- `ui.send_message(event, payload)` → broadcast to all clients.
- `ui.send_message(event, payload, client)` → send to one client (the 3rd arg).

From `blink-with-ui`:

```python
def toggle_led_state(client, data):
    global led_is_on
    led_is_on = not led_is_on
    Bridge.call("set_led_state", led_is_on)          # tell the MCU
    ui.send_message('led_status_update', get_led_status())   # tell the browser

ui.on_message('toggle_led', toggle_led_state)
ui.on_message('get_initial_state', on_get_initial_state)
```

## Calling the MCU (Linux → MCU)

`Bridge.call("name", args...)` invokes a function the sketch exposed with
`Bridge.provide("name", fn)`. Request/response. See `references/bridge-rpc.md` for
full semantics, timeouts, and arg types.

## Receiving from the MCU (MCU → Linux)

When the sketch pushes data with `Bridge.notify("name", a, b, c)`, register the
receiver in Python with `Bridge.provide("name", fn)`. From
`real-time-accelerometer`:

```python
def record_sensor_movement(x: float, y: float, z: float):
    sample = {"t": time.time(), "x": x, "y": y, "z": z}
    web_ui.send_message('sample', sample)            # forward to the browser

Bridge.provide("record_sensor_movement", record_sensor_movement)
```

## Extra WebUI capabilities (verified)

- `ui.on_connect(lambda sid: ...)` — run something when a client connects (e.g.
  send current state). Used in `real-time-accelerometer`.
- `ui.expose_api("GET", "/path", fn)` — expose a REST endpoint reachable from the
  browser with `fetch("/path")`. Used in `real-time-accelerometer`.
- `Logger("name")` then `logger.debug/info/warning/exception(...)` — structured
  logs that show up in `scripts/logs.sh` output (Step 6).

## AI-brick pattern (no MCU)

Browser-only AI apps skip the Bridge entirely. From `object-detection`: the
browser sends a base64 image, Python runs the brick and sends an annotated image
back.

```python
object_detection = ObjectDetection()

def on_detect_objects(client_id, data):
    image_bytes = base64.b64decode(data['image'])
    pil_image = Image.open(io.BytesIO(image_bytes))
    results = object_detection.detect(pil_image, confidence=data.get('confidence', 0.5))
    img = object_detection.draw_bounding_boxes(pil_image, results)
    # ... encode img back to base64, ui.send_message('detection_result', ...)

ui.on_message('detect_objects', on_detect_objects)
App.run()
```

## Gotchas

- `App.run()` **must be last** — code after it won't run until shutdown.
- Mutating module-level state needs `global` inside the handler.
- Wrap brick calls in `try/except` and log with `logger.exception(...)` — a raised
  exception in a handler can kill the socket loop (`object-detection` and
  `real-time-accelerometer` both guard heavily).
- The event name in `ui.on_message("X", ...)` must exactly match `socket.emit("X")`
  in `app.js` (Step 5).

## Done when

`main.py` instantiates every brick from `app.yaml`, registers all handlers, wires
the Bridge for any MCU comms, and ends with `App.run()`.

Next: `workflow/step4-mcu-sketch.md` (skip to Step 5 if headless / browser-only).
