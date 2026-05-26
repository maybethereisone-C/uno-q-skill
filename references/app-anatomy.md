# App Project Anatomy

The definitive map of an Arduino App Lab project for the UNO Q. Every App is a
folder with a fixed shape. Get the shape right and the App Lab runtime wires the
pieces together for you.

> Derived from real examples in `app-bricks-examples/examples/` (blink-with-ui,
> unoq-pin-toggle, real-time-accelerometer, object-detection, keyword-spotting).
> Frontend conventions cross-checked against
> `arduino-uno-q-agent-template/docs/agent/frontend.md`.

---

## The folder tree

A full-stack App (Linux brain + MCU + web UI) looks like this. This is the exact
tree of `blink-with-ui`, the canonical reference:

```
my-app/
├── app.yaml              # App manifest: name, icon, description, bricks list
├── python/
│   └── main.py           # Linux entry point — runs on the Qualcomm side (Debian)
├── sketch/
│   ├── sketch.ino        # MCU firmware — runs on the STM32U585 microcontroller
│   └── sketch.yaml       # MCU build profile (platform: arduino:zephyr)
└── assets/               # Web UI, served by the web_ui brick on port 7000
    ├── index.html        # REQUIRED entrypoint — brick fails to start without it
    ├── app.js            # Your front-end logic (socket.io client wiring)
    ├── style.css         # Your styles
    ├── libs/
    │   └── socket.io.min.js   # Vendored — NO CDN at runtime
    ├── img/              # Icons, logos, favicon
    └── fonts/            # Optional vendored fonts
```

Not every App needs every folder. Drop what you don't use:

| App kind | Needs `sketch/`? | Needs `assets/`? | Example |
| --- | --- | --- | --- |
| LED blink, web button → pin | yes | yes | `blink-with-ui`, `unoq-pin-toggle` |
| Sensor → live dashboard | yes (reads sensor) | yes | `real-time-accelerometer` |
| Browser-only AI (camera, LLM) | **no** | yes | `object-detection`, `edge-ai-assistant` |
| MCU-only reaction (no UI) | yes | **no** | `blink` (headless), `keyword-spotting` |

Rule of thumb: include `sketch/` only when you touch the microcontroller (GPIO,
Modulino sensors, LED matrix). Include `assets/` only when you want a web page.
`python/main.py` is **always** present — it is the App's process.

---

## File-by-file roles

### `app.yaml` — the manifest

Declares the App's identity and which **bricks** (pre-built capabilities) it pulls
in. The brick list is what the runtime installs and makes importable in `main.py`.

Real example (`real-time-accelerometer/app.yaml`):

```yaml
name: Real-time Accelerometer
icon: 🐍
description: Real-time Accelerometer data visualization and movement detection using Modulino Movement sensor

bricks:
  - arduino:web_ui
  - arduino:motion_detection
```

- `name` / `icon` / `description` — how the App shows up in App Lab's launcher.
- `bricks:` — a list of `arduino:<brick_name>` identifiers. Each entry maps to a
  Python import like `from arduino.app_bricks.motion_detection import MotionDetection`.
  See `references/bricks-catalog.md` for the full brick list. (unverified: exact
  catalog file name — cross-check with the bricks reference in this skill.)

If a brick is not listed in `app.yaml`, importing it in `main.py` will fail.

### `python/main.py` — the Linux entry point

Runs on the Qualcomm Dragonwing application processor (Debian Linux). This is
where your orchestration logic lives: it instantiates bricks, registers
callbacks, and calls `App.run()` to hand control to the runtime.

The universal skeleton (all examples follow this):

```python
from arduino.app_utils import *                       # App, Bridge, Logger, ...
from arduino.app_bricks.web_ui import WebUI            # one import per brick

ui = WebUI()                                           # instantiate bricks
ui.on_message('some_event', handler)                   # register handlers

App.run()                                              # blocks — runs forever
```

Key objects pulled in by `from arduino.app_utils import *`:

- `App.run()` — starts the runtime, supervises bricks, blocks. **Always last.**
- `Bridge` — the RPC link to the MCU. See `references/bridge-rpc.md`.
- `Logger("name")` — structured logging (`logger.debug/info/warning/exception`).

### `sketch/sketch.ino` — the MCU firmware

Runs on the STM32U585 microcontroller. Standard Arduino `setup()` / `loop()`. Its
job is real-time, deterministic I/O: read sensors, drive pins, blink the matrix —
and talk to Linux over the `Bridge`.

Minimal skeleton (`blink-with-ui/sketch/sketch.ino`):

```cpp
#include <Arduino_RouterBridge.h>

void setup() {
    Bridge.begin();                                    // open the link to Linux
    Bridge.provide("set_led_state", set_led_state);    // expose an RPC the Python side can call
}

void loop() {}                                         // often empty for RPC-driven apps

void set_led_state(bool state) {                       // the exposed function
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
}
```

Two directions of MCU↔Linux comms (both via `Bridge`, both shown in real apps):

- **Linux calls MCU**: sketch does `Bridge.provide("name", fn)`, Python does
  `Bridge.call("name", args)` (request/response). Used in `blink-with-ui`.
- **MCU pushes to Linux**: sketch does `Bridge.notify("name", a, b, c)` (fire and
  forget), Python registers `Bridge.provide("name", fn)`. Used in
  `real-time-accelerometer` to stream accelerometer samples.

Full RPC semantics live in `references/bridge-rpc.md`.

### `sketch/sketch.yaml` — the MCU build profile

Tells the build which platform to compile the sketch for. For the UNO Q this is
always Zephyr (verbatim from every example):

```yaml
profiles:
  default:
    platforms:
      - platform: arduino:zephyr
default_profile: default
```

You rarely edit this. If you add MCU libraries (e.g. `Arduino_Modulino`,
`Arduino_LED_Matrix`), they are included via `#include` in the sketch; the build
resolves them. (unverified: whether some libraries must be declared here vs.
auto-resolved — every example relies on `#include` alone.)

### `assets/` — the web UI

Static files served by the `web_ui` brick on **port 7000**. `index.html` is the
required entrypoint. The page must be **self-contained — no CDN at runtime**;
vendor `socket.io.min.js` locally under `assets/libs/`.

The real examples use a **flat layout** (`assets/app.js`, `assets/style.css`,
`assets/libs/socket.io.min.js`) — this skill's templates follow that.

> Alternative convention: the agent-template's `frontend.md` prescribes a nested
> layout (`assets/js/app.js`, `assets/js/vendor/socket.io.min.js`,
> `assets/css/app.css`). Both work — the brick just serves `assets/` as the static
> root. Pick one and be consistent. We use the flat layout because that is what the
> shipped examples use.

The UI talks to `main.py` over Socket.IO (the `web_ui` brick mounts the server).
See `references/webui-brick.md` (unverified file name) and step 5 of the workflow.

---

## How the pieces connect

```
                          app.yaml
                       (declares bricks)
                             │
                   installs & exposes bricks
                             │
                             ▼
   ┌──────────────────────────────────────────────────────┐
   │  python/main.py   (Linux / Debian on Qualcomm)         │
   │                                                        │
   │  ui = WebUI()  ◄──── Socket.IO (port 7000) ──────┐     │
   │  ui.on_message('toggle_led', handler)             │     │
   │                                                   │     │
   │  Bridge.call("set_led_state", state) ──┐          │     │
   └────────────────────────────────────────┼─────────┼─────┘
                                             │         │
                       Router Bridge (RPC)   │         │  WebSocket
                                             ▼         │
   ┌──────────────────────────────────┐               │
   │  sketch/sketch.ino  (STM32U585)   │               │
   │  Bridge.provide("set_led_state")  │               │
   │  digitalWrite(LED_BUILTIN, ...)   │               │
   └──────────────────────────────────┘               │
                                                       ▼
                                            ┌────────────────────┐
                                            │  assets/index.html │
                                            │  assets/app.js     │  (browser)
                                            │  socket.emit(...)  │
                                            └────────────────────┘
```

Data flow for the blink example, end to end:

1. Browser loads `assets/index.html` → `app.js` opens a socket: `io(...)`.
2. User clicks the button → `socket.emit('toggle_led', {})`.
3. `main.py` handler fires (`ui.on_message('toggle_led', toggle_led_state)`).
4. Handler calls `Bridge.call("set_led_state", led_is_on)` → travels the Router
   Bridge to the MCU.
5. Sketch's `set_led_state(bool)` runs → `digitalWrite(LED_BUILTIN, ...)`.
6. `main.py` then `ui.send_message('led_status_update', ...)` → browser updates.

For sensor streaming (accelerometer) the flow reverses: the sketch calls
`Bridge.notify(...)`, `main.py`'s provided function runs, then
`ui.send_message(...)` pushes to the browser.

---

## Mental model

- **`app.yaml` = what** (which capabilities this App has).
- **`main.py` = brain** (orchestration, runs on Linux, always present).
- **`sketch.ino` = reflexes** (real-time I/O on the MCU, optional).
- **`assets/` = face** (the web UI, optional).
- **`Bridge` = nervous system** connecting brain ↔ reflexes.
- **`WebUI` + Socket.IO = voice/ears** connecting brain ↔ face.

Next: scaffold one with `workflow/step1-scaffold.md`.
