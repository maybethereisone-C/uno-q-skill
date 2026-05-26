# WebUI Brick — Deep Guide

The **WebUI Brick** embeds a web server in your app: it serves a static
frontend, REST APIs, and a bidirectional **Socket.IO** WebSocket channel. It's
built on **FastAPI + Uvicorn + fastapi-socketio**. This is how an UNO Q app gets
a browser dashboard that talks live to Python (and through Python, to the MCU
sketch via the Bridge).

Sources (verified):
- `app-bricks-py/src/arduino/app_bricks/web_ui/web_ui.py` — `WebUI`
- `app-bricks-py/src/arduino/app_bricks/web_ui/__init__.py`, `.../brick_config.yaml`
- `app-bricks-py/src/arduino/app_bricks/web_ui/examples/{1..5}_*.py`
- Example app: `app-bricks-examples/examples/blink-with-ui/`
- Agent-template doc: `arduino-uno-q-agent-template/docs/agent/bricks/web_ui.md`

`brick_config.yaml`: `id: arduino:web_ui`, `category: ui`,
`requires_display: webview`, `ports: [7000]`.

---

## 1. Declare it

```yaml
# app.yaml
bricks:
  - arduino:web_ui
```
Pure Python — no sketch library required (unless you also drive the MCU, in
which case the *sketch* uses `Arduino_RouterBridge.h`, not the brick).

---

## 2. Constructor

```python
WebUI(
    addr: str = "0.0.0.0",
    port: int = 7000,                  # 0 => pick a free port
    ui_path_prefix: str = "",          # URL prefix for UI routes
    api_path_prefix: str = "",         # URL prefix for API routes
    assets_dir_path: str = "/app/assets",   # = ./assets/ in your repo
    certs_dir_path: str = "/app/certs",
    use_tls: bool = False,
    cors_origins: str = "*",           # "*", CSV of origins, or "" to disable
)
```

`from arduino.app_bricks.web_ui import WebUI` → `ui = WebUI()`. The instance
auto-registers with `App` (the `@brick` decorator); `App.run()` starts it.

**Hard requirement**: if `assets_dir_path` exists, it **must** contain
`index.html`, or `start()` raises `RuntimeError`. (`assets/` maps to
`/app/assets` inside the container.)

Properties: `ui.local_url` (`http://localhost:7000`) and `ui.url`
(uses `HOST_IP` env if set, else `addr`).

---

## 3. Full public API

| Method | Signature | Purpose |
| --- | --- | --- |
| `expose_api` | `(method: str, path: str, function: Callable)` | Register a REST route (FastAPI-style; return a dict → JSON). Path is prefixed by `api_path_prefix`. |
| `on_message` | `(message_type: str, callback: Callable[[sid, data], Any])` | Handle an inbound Socket.IO event. **Callback receives `(sid, data)`** — two args. If it returns non-`None`, the value is emitted back as `"<message_type>_response"` to that `sid` only. |
| `send_message` | `(message_type: str, message: dict\|str, room: str\|None=None)` | Push an event to all clients, or to a specific `room`/`sid`. Thread-safe. |
| `on_connect` | `(callback: Callable[[sid], None])` | Fires when a client connects. |
| `on_disconnect` | `(callback: Callable[[sid], None])` | Fires when a client disconnects. |
| `expose_camera` | `(path: str, camera: BaseCamera, jpeg_quality: int=80)` | Mount an MJPEG stream at `path`; consume with `<img src="path">`. Starts the camera if needed. |
| `local_url` / `url` | property | Resolved server URLs. |

Built-in Socket.IO events also handled by the brick: `connect`, `disconnect`,
`enter_room`, `leave_room`, plus a generic `*` dispatcher that routes any other
event name to your `on_message` handler. Unhandled events emit an `"error"`
event back to the sender. Max WS buffer is 10 MB.

> **Callback arity gotcha**: the source dispatcher always calls your handler as
> `callback(sid, data)`. Write handlers with **two** parameters
> (`def handler(sid, data): ...`). A one-arg handler will raise at dispatch
> time. (Example file `4_on_message.py` shows a one-arg lambda — that is a
> doc/example slip; the verified contract is two args.)

---

## 4. The `assets/` layout

The brick serves `assets/` statically at the root with `Cache-Control:
no-store` (safe to redeploy without cache busting). `index.html` → `/`,
everything else by relative path. Verified layout from `blink-with-ui`:

```
assets/
├── index.html              # required — entry page
├── app.js                  # your client logic
├── style.css
├── libs/
│   └── socket.io.min.js    # VENDORED — do not use a CDN
├── img/ (favicon.png, logo.svg)
└── fonts/ (…)
```

**Vendor `socket.io.min.js` locally** under `assets/libs/` (or
`assets/js/vendor/`) and reference it with a relative `<script src>`. The device
may have no outbound internet, and CSP/offline use rules out CDNs.

`index.html` skeleton (verified shape):
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>My App</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <button id="led-button"><span id="led-text">LED IS OFF</span></button>
  <script src="libs/socket.io.min.js"></script>
  <script src="app.js"></script>
</body>
</html>
```

---

## 5. Event wiring, both directions

**Browser → Python**: `socket.emit("<event>", payload)` → Python
`ui.on_message("<event>", handler)` where `handler(sid, data)`.

**Python → Browser**: `ui.send_message("<event>", data)` → JS
`socket.on("<event>", cb)`. Pass `room=sid` to target a single client.

**Request/response**: return a value from an `on_message` handler and the brick
emits `"<event>_response"` to that sid:
```python
ui.on_message("get_state", lambda sid, data: {"led": led_is_on})   # -> "get_state_response"
```

Client side (verified pattern from `blink-with-ui/assets/app.js`):
```js
const socket = io(`http://${window.location.host}`);   // same-origin
socket.on("connect", () => socket.emit("get_initial_state", {}));
socket.on("led_status_update", (msg) => updateLedStatus(msg));
socket.on("disconnect", () => showError("Connection lost"));
document.getElementById("led-button")
        .addEventListener("click", () => socket.emit("toggle_led", {}));
```

Minimal Python building blocks (from the brick's own examples):
```python
ui = WebUI()
ui.expose_api("GET", "/hello", lambda: {"message": "Hello, world!"})          # REST
ui.on_connect(lambda sid: print(f"{sid} connected"))                          # connect
ui.on_disconnect(lambda sid: print(f"{sid} gone"))                            # disconnect
ui.on_connect(lambda sid: ui.send_message("hello", {"to": sid}))              # push on connect
```

---

## 6. Camera streaming

```python
from arduino.app_peripherals.camera import Camera
cam = Camera("usb:0", resolution=(640, 480), fps=15)
ui = WebUI()
ui.expose_camera("/stream", cam, jpeg_quality=70)
# Frontend:  <img src="/stream">
```
`expose_camera` serves `multipart/x-mixed-replace` MJPEG; the camera is started
automatically if not already running.

---

## 7. Complete dashboard example — LED toggle (Python ↔ browser ↔ MCU)

Verified `blink-with-ui` app. The browser toggles a button → Python flips state
and RPCs the sketch via the Bridge → Python broadcasts the new state to all
clients.

`app.yaml`:
```yaml
name: Blink LED with UI
icon: 💡
description: Blink an LED via microcontroller using RPC calls
bricks:
  - arduino:web_ui
```

`python/main.py`:
```python
from arduino.app_utils import *
from arduino.app_bricks.web_ui import WebUI

led_is_on = False

def get_led_status():
    return {"led_is_on": led_is_on,
            "status_text": "LED IS ON" if led_is_on else "LED IS OFF"}

def toggle_led_state(client, data):          # (sid, data)
    global led_is_on
    led_is_on = not led_is_on
    Bridge.call("set_led_state", led_is_on)  # RPC into the sketch
    ui.send_message("led_status_update", get_led_status())   # broadcast

def on_get_initial_state(client, data):
    ui.send_message("led_status_update", get_led_status(), client)  # to this sid

ui = WebUI()
ui.on_message("toggle_led", toggle_led_state)
ui.on_message("get_initial_state", on_get_initial_state)

App.run()
```

`sketch/sketch.ino` (the MCU side of the Bridge):
```cpp
#include <Arduino_RouterBridge.h>
void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    digitalWrite(LED_BUILTIN, HIGH);     // off
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
}
void loop() {}
void set_led_state(bool state) {
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);  // LOW = on
}
```

---

## 8. Gotchas

- **`index.html` is mandatory** when `assets/` exists, or `start()` raises.
- **Two-arg `on_message` handlers** (`sid, data`) — see §3.
- **Vendor socket.io** — no CDN; device may be offline.
- **Default port `7000`** (`requires_display: webview`). Change only on clash.
- **`send_message` before `App.run()` no-ops** — the asyncio loop isn't up yet;
  it logs a debug line and returns. Only push after the server is running
  (e.g. inside `on_connect`/`on_message` or a brick loop).
- **Bridge deadlock**: don't call `Bridge.call(...)` inside a function you
  exposed via `Bridge.provide(...)`. Calling `Bridge.call(...)` inside
  `on_message`/`expose_api` handlers is fine (different thread).
- **CORS** defaults to `*` (no credentials). Tighten with `cors_origins="https://..."`.
- **TLS**: `use_tls=True` + certs in `/app/certs` (auto-generated via
  `TLSCertificateManager` if absent).
- Returning a value from `on_message` emits `"<event>_response"` to that sid
  only; use `send_message` for broadcast.
