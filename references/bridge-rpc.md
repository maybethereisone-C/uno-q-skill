# Bridge RPC — Python ↔ MCU (the heart of an UNO Q app)

The **Bridge** is the RPC layer that lets the Linux/Python side (`python/main.py`, runs on
the Qualcomm A53 MPU) and the Zephyr/MCU sketch side (`sketch/sketch.ino`, runs on the
STM32U585) call each other's functions. It is implemented by:

- **`arduino-router`** — a Go daemon (a MessagePack-RPC router) that brokers all calls.
- **Python side**: `arduino.app_utils.Bridge` / `App` (the `arduino` package, `app-bricks-py`).
- **MCU side**: the `Arduino_RouterBridge` C++ library (`#include <Arduino_RouterBridge.h>`).

Everything below is verified against the cloned sources; paths are cited. Anything not
confirmed from source is marked **(unverified)**.

---

## 1. Architecture — how the router brokers a call

`arduino-router` is a **MessagePack-RPC router** wiring multiple clients into a **star
topology** with the router as the central node. The Python process and the MCU are each
just clients of the router. (Source: `arduino-router/README.md` lines 1-7.)

```
  Python (main.py)                 arduino-router (Go daemon)              MCU sketch
  app_utils.Bridge        <----->   /var/run/arduino-router.sock   <----->  Arduino_RouterBridge
  (unix socket client)              (broker: register + forward)            (serial transport)
```

How it works (Source: `arduino-router/README.md` lines 11-46):

1. A client **registers** the methods it wants to expose by RPC-calling the router's
   built-in `$/register <METHOD_NAME>`. Example wire exchange:
   `[REQUEST, 50, "$/register", ["ping"]]` >> ; `[RESPONSE, 50, null, true]` <<.
2. When the router receives a request for a registered method, it **forwards** the request
   to the owning client and **forwards the response back** to the originator.
3. The router **remaps the `msgid`** so IDs from different clients never collide
   (`README.md` line 32).
4. Calling an **unregistered** method returns an error response:
   `[RESPONSE, 33, "method xxxx not available", null]` (`README.md` lines 34-41).
5. When a client **disconnects, all of its registered methods are dropped**
   (`README.md` lines 43-45).

The router connects to the MCU over a **serial port** (set via the `-p PORT` CLI flag); it
auto-retries the serial connection every 5 seconds if it fails, and exposes
`$/serial/open` / `$/serial/close` to manage that link (`README.md` lines 56-65).

### Router built-in methods (the `$/...` namespace)

| Method | Purpose | Source |
| --- | --- | --- |
| `$/register <name>` | Register a method this client will serve. | `arduino-router/README.md:13-22` |
| `$/reset` (no args) | Drop **all** methods this client registered. | `arduino-router/README.md:47-54` |
| `$/serial/open` / `$/serial/close` | Open/close the router's serial link to the MCU. | `arduino-router/README.md:56-65` |
| `$/setMaxMsgSize <bytes>` | Cap message size; oversized CALL → error, oversized NOTIFY → silently dropped. | `arduino-router/README.md:67-75` |
| `$/unregister <name>` | Unregister one method (used by Python `Bridge.unprovide`). | `app-bricks-py/.../bridge.py:380` |
| `$/cancelRequest <msgid>` | Cancel a pending request on timeout. | `app-bricks-py/.../bridge.py:349` |

---

## 2. The wire protocol (MessagePack-RPC)

Three message shapes, each a MessagePack **array**. (Source:
`arduino-router/msgpackrpc/README.md:5-22`, confirmed by the Python encoder in
`app-bricks-py/.../bridge.py:305,317,613`.)

| Type | Array shape | Meaning |
| --- | --- | --- |
| REQUEST | `[0, msgid, method, params]` | Call expecting a response. `msgid` is a 32-bit unsigned sequence number. |
| RESPONSE | `[1, msgid, error, result]` | Reply. `error` is `null` on success; `result` is `null` on error. |
| NOTIFICATION | `[2, method, params]` | Fire-and-forget. No `msgid`, no response. |

`params` is always an array of the positional arguments. The Python read loop dispatches
exactly on these three `msg[0]` types (`bridge.py:518,540,565`).

Error responses carry `[err_code, err_msg]`. Python maps exceptions to codes
(`bridge.py:601-611`): `NameError → 0xFE` (function not found), `TypeError`/`ValueError →
0xFD` (malformed call), anything else → `0xFF` (generic). The router defines
`ROUTE_ALREADY_EXISTS_ERR = 0x05` and `BUFFER_LIMIT_EXCEEDED_ERR = 0x06`
(`bridge.py:22-23`). A `$/register` that returns `ROUTE_ALREADY_EXISTS_ERR` is **treated
as success** (idempotent re-register) (`bridge.py:554-556`).

---

## 3. Python API (`from arduino.app_utils import *`)

`from arduino.app_utils import *` exports `App`, `Bridge`, the decorators `notify` / `call`
/ `provide`, and `Logger` (Source: `app-bricks-py/.../app_utils/__init__.py:18-29`).

### `Bridge` static methods (Source: `bridge.py:31-102`)

| Call | Behavior |
| --- | --- |
| `Bridge.call(method_name, *params, timeout=10)` | Synchronously call an MCU method; **returns** the MCU's return value. Default **10s** timeout. Raises `ValueError` (method missing/failed), `TimeoutError`, or `RuntimeError`. |
| `Bridge.notify(method_name, *params)` | Fire-and-forget call into the MCU; no return, never blocks on a response. Failures are swallowed (`bridge.py:308-312`). |
| `Bridge.provide(method_name, handler)` | Expose a Python callable so the MCU can call it. Registers via `$/register`. `handler` must be callable or raises `ValueError`. |
| `Bridge.unprovide(method_name)` | Stop exposing a method (calls `$/unregister`). No-op if not provided. |

> There is **no `Bridge.begin()` on the Python side** — the connection is established
> lazily by a singleton `ClientServer` the first time you touch `Bridge`
> (`bridge.py:265-301`). `Bridge.begin()` exists **only on the C++ side**.

### Decorator forms (Source: `bridge.py:105-246`, examples `examples/1_bridge_call_notify.py`, `examples/2_bridge_provide.py`)

These wrap a function so calling it triggers the RPC. Bodies can be `...` for `@call`/`@notify`
because the real code runs on the MCU.

```python
from arduino.app_utils import *

@call()                                   # method name = function name
def add_numbers(num1: int, num2: int) -> int: ...

@call("math.subtract", timeout=3)         # custom RPC name + default timeout
def sub_numbers(num1: int, num2: int) -> int: ...

@notify()                                  # fire-and-forget into the MCU
def print_result(message: str): ...

@provide()                                 # expose THIS python fn to the MCU
def get_country(lon: str, lat: str) -> str:
    return lookup(lon, lat)

@provide("custom.rpc.name")                # expose under an explicit name
def handler(param): ...

result = add_numbers(1, 2)                 # wait indefinitely (timeout omitted in @call())
result = add_numbers(3, 4, timeout=1)      # per-call timeout override
```

Notes (Source: `bridge.py:151-246`):
- `@call(timeout=None)` waits **indefinitely**; pass `timeout=` at call time to override.
- Decorated functions accept **positional args only** — kwargs (other than `timeout`)
  raise `TypeError`.
- A method, classmethod, or anything with a `self`/`cls` first param is rejected
  (`_is_unbound_or_class_method`, `bridge.py:250-262`).
- All decorators default to `address="unix:///var/run/arduino-router.sock"`, overridable
  by the `APP_SOCKET` env var (`bridge.py:285`). TCP is also supported (`tcp://host:port`).

### `App` (Source: `app-bricks-py/.../app_utils/app.py:91-127`)

| Call | Behavior |
| --- | --- |
| `App.run(user_loop=None)` | Start the app. **MUST be the last line** of `main.py`. With `user_loop`, that callable runs repeatedly inside the framework loop; without it, only bricks and Bridge callbacks drive the app. |

---

## 4. C++ / MCU API (`#include <Arduino_RouterBridge.h>`)

The `Arduino_RouterBridge` library ships **bundled in the UNO Q Zephyr core ≥ 0.55.0** — do
**not** add it to `sketch.yaml` (Source: `arduino-uno-q-agent-template/AGENTS.md:103`,
rule 7). Just `#include <Arduino_RouterBridge.h>`.

| Call | Behavior | Source |
| --- | --- | --- |
| `Bridge.begin()` | Initialize the Bridge. Call once in `setup()`. | every example `.ino`, e.g. `blink-with-ui/sketch/sketch.ino:12` |
| `Bridge.provide("name", fn)` | Expose a C++ function so Python can call it. | `blink-with-ui/sketch/sketch.ino:13`, `unoq-pin-toggle/sketch/sketch.ino:47` |
| `Bridge.provide_safe("name", fn)` | Same, but documented to run in **`loop()` context** (the agent guidance prefers this for handlers touching hardware). | `arduino-uno-q-agent-template/docs/agent/bridge.md:19` **(see note below)** |
| `Bridge.call("name", args...)` | Call a Python method. Returns a **result handle**, not the value — see §4.1. | `weather-forecast/sketch/sketch.ino:23` |
| `Bridge.notify("name", args...)` | Fire-and-forget into Python. No return, doesn't block — use for high-frequency telemetry. | `real-time-accelerometer/sketch/sketch.ino:44`, `home-climate-monitoring-and-storage/sketch/sketch.ino:35` |
| `Monitor.begin()` / `Monitor.print()` / `Monitor.println()` | Log to the App Lab "Sketch" serial console. | `learn-docs/02.apps/apps.md:125-130`, `arduino-uno-q-agent-template/docs/agent/bridge.md:23` |

> **`provide` vs `provide_safe` — what the source actually shows.** Every real `.ino` in
> `app-bricks-examples` uses **`Bridge.provide`** (verified: blink, blink-with-ui,
> unoq-pin-toggle, color-your-leds, led-matrix-painter, keyword-spotting, and the
> learn-docs blink at `apps.md:184`). `Bridge.provide_safe` appears **only** in the agent
> template docs (`docs/agent/bridge.md`, `AGENTS.md`), never in a real sketch in these
> repos. The agent guidance is: prefer `provide_safe` (runs in loop context, safe for
> hardware/interrupt-free handlers) and reserve `provide` for advanced use
> (`AGENTS.md:72`). Treat the **semantic difference** (loop-context vs Bridge-thread
> execution) as **(unverified)** here because the `Arduino_RouterBridge` C++ source is
> not in the cloned set — it is bundled in the Zephyr core. When in doubt follow the agent
> rule: `provide_safe` by default.

### 4.1 The C++ `Bridge.call(...).result(out)` pattern (IMPORTANT)

On the MCU, `Bridge.call(...)` does **not** return the value directly. It returns a result
handle whose `.result(&out)` (passed by reference) writes the decoded value into `out` and
returns a `bool ok` indicating success. (Verified across three sketches.)

```cpp
// weather-forecast/sketch/sketch.ino:21-24
String weather_forecast;
bool ok = Bridge.call("get_weather_forecast", city).result(weather_forecast);
if (ok) {
  // use weather_forecast
}
```

```cpp
// air-quality-monitoring/sketch/sketch.ino:20-22   (call with no args)
String airQuality;
bool ok = Bridge.call("get_air_quality").result(airQuality);
if (ok) { /* ... */ }
```

Always check `ok` before using the out value; on a failed/timed-out call the out param is
not valid.

---

## 5. Type matching across the wire (read this twice)

Arguments are typed across the Bridge. The agent docs state plainly: **type mismatches fail
silently** (Source: `arduino-uno-q-agent-template/docs/agent/bridge.md:27`,
`AGENTS.md:101` rule 6). Declare the C++ signature explicitly and pass matching types from
Python.

| Python | C++ | Notes |
| --- | --- | --- |
| `int` | `int` (32-bit) | `msgid`s are 32-bit unsigned; ints cross as 32-bit. (`bridge.py:393`, `msgpackrpc/README.md:9`) |
| `float` | `float` | |
| `bool` | `bool` | e.g. `Bridge.call("set_led_state", led_is_on)` → `void set_led_state(bool state)` (`blink-with-ui` py:25 / ino:18). |
| `str` | `const char*` / `String` | e.g. `Bridge.call("get_weather_forecast", city)` where `String city` (`weather-forecast/sketch/sketch.ino:10,23`). |

The router's Go core widens any integer width (int8…uint64) to a host int where it can, and
**fails the conversion** (returns `ok=false`) for out-of-range or non-integer inputs rather
than guessing (Source: `arduino-router/msgpackrpc/type_conversion.go:11-85`). That is why a
type mismatch surfaces as a silent no-op / failed conversion, not a crash.

---

## 6. Request/response vs notify semantics

| | `call` (REQUEST/RESPONSE) | `notify` (NOTIFICATION) |
| --- | --- | --- |
| Blocks for a reply? | Yes (until response or timeout) | No |
| Returns a value? | Yes | No |
| Has a `msgid`? | Yes (`[0,msgid,…]`) | No (`[2,…]`) |
| Oversized message (`$/setMaxMsgSize`)? | Error returned to caller | Silently dropped (`README.md:73-74`) |
| Use for | Commands needing an ack / a return value | High-frequency telemetry (sensor streams) |

Python `call` cleans up its pending callback and sends `$/cancelRequest` on timeout
(`bridge.py:344-352`). Python `notify` swallows connection errors for true fire-and-forget
(`bridge.py:308-312`).

---

## 7. Registering & calling in both directions

| Direction | Expose with | Invoke with |
| --- | --- | --- |
| Python → MCU | C++ `Bridge.provide("name", fn)` (or `provide_safe`) | Python `Bridge.call("name", ...)` / `Bridge.notify(...)` / `@call`/`@notify` |
| MCU → Python | Python `Bridge.provide("name", fn)` / `@provide()` | C++ `Bridge.call("name", ...).result(out)` / `Bridge.notify("name", ...)` |

---

## 8. Threading & loop-context rules

- **Python**: the Bridge runs a background daemon read thread (`Bridge.read_loop`,
  `bridge.py:300`). Incoming MCU requests/notifications are dispatched **on that read
  thread** (`_handle_msg`, `bridge.py:530-580`). Your `provide` handler therefore runs on
  the Bridge thread — keep it short and **non-blocking**, and guard shared state. Auto
  reconnect runs every 3s and re-registers all provided methods (`bridge.py:398-453`).
- **MCU**: prefer `Bridge.provide_safe` so handlers execute in `loop()` context (safe for
  hardware access). Keep `loop()` non-blocking so the Bridge can service requests
  (`AGENTS.md:73-79`).
- **The deadlock rule (both sides)**: do **not** issue a nested `Bridge.call(...)` from
  inside a function that was exposed via `Bridge.provide*` — it can deadlock the Bridge.
  Do **not** call `Monitor.print(...)` inside an MCU `provide*` callback. (Source:
  `docs/agent/bridge.md:38-43`, `AGENTS.md:74`.) See `rules/bridge-anti-patterns.md`.

---

## 9. Complete working examples (verified, from the real repos)

### 9.1 Python → MCU command round-trip (blink-with-ui)

A WebUI socket message toggles a Python flag, which calls into the sketch to drive the LED.

```python
# python/main.py  — Source: app-bricks-examples/examples/blink-with-ui/python/main.py
from arduino.app_utils import *
from arduino.app_bricks.web_ui import WebUI

led_is_on = False

def toggle_led_state(client, data):
    global led_is_on
    led_is_on = not led_is_on
    # RPC into the sketch; bool ↔ bool
    Bridge.call("set_led_state", led_is_on)
    ui.send_message('led_status_update', {"led_is_on": led_is_on})

ui = WebUI()
ui.on_message('toggle_led', toggle_led_state)

App.run()   # MUST be last line
```

```cpp
// sketch/sketch.ino  — Source: app-bricks-examples/examples/blink-with-ui/sketch/sketch.ino
#include <Arduino_RouterBridge.h>

void set_led_state(bool state) {
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);  // LOW = LED on
}

void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    digitalWrite(LED_BUILTIN, HIGH);                // start OFF
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state); // callable from Python
}

void loop() {}
```

### 9.2 MCU → Python telemetry stream via `notify` (real-time-accelerometer)

High-frequency samples pushed from the MCU without blocking. Python provides the sink.

```cpp
// sketch/sketch.ino  — Source: app-bricks-examples/examples/real-time-accelerometer/sketch/sketch.ino
#include <Arduino_Modulino.h>
#include <Arduino_RouterBridge.h>

ModulinoMovement movement;
unsigned long previousMillis = 0;
const long interval = 16;   // ~62.5 Hz; tune to your model

void setup() {
  Bridge.begin();
  Modulino.begin(Wire1);
  while (!movement.begin()) { delay(1000); }   // OK in setup, not in loop/callbacks
}

void loop() {
  unsigned long now = millis();
  if (now - previousMillis >= interval) {       // non-blocking pacing
    previousMillis = now;
    if (movement.update() == 1) {
      float x = movement.getX(), y = movement.getY(), z = movement.getZ();
      Bridge.notify("record_sensor_movement", x, y, z);  // fire-and-forget, float×3
    }
  }
}
```

```python
# python/main.py  — Source: app-bricks-examples/examples/real-time-accelerometer/python/main.py (trimmed)
from arduino.app_utils import *
from collections import deque

samples = deque(maxlen=200)

def record_sensor_movement(x: float, y: float, z: float):
    # runs on the Bridge read thread — keep it short, no nested Bridge.call here
    samples.append({"x": float(x), "y": float(y), "z": float(z)})

# Expose the sink so the sketch's notify can reach it.
Bridge.provide("record_sensor_movement", record_sensor_movement)

App.run()
```

### 9.3 MCU → Python `call` with a return value (weather-forecast)

The sketch asks Python for a string and drives the LED matrix. Note the
`.result(out)` handle and the `ok` check.

```cpp
// sketch/sketch.ino  — Source: app-bricks-examples/examples/weather-forecast/sketch/sketch.ino
#include <Arduino_LED_Matrix.h>
#include <Arduino_RouterBridge.h>
#include "weather_frames.h"

String city = "Turin";
Arduino_LED_Matrix matrix;

void setup() {
  matrix.begin();
  matrix.clear();
  Bridge.begin();
}

void loop() {
  String weather_forecast;
  bool ok = Bridge.call("get_weather_forecast", city).result(weather_forecast); // str→String
  if (ok) {
    if (weather_forecast == "sunny")  { matrix.loadSequence(sunny);  }
    else if (weather_forecast == "rainy") { matrix.loadSequence(rainy); }
    // ...
  }
}
```

On the Python side a `@provide()`-decorated `get_weather_forecast(city: str) -> str`
serves it (pattern per `bridge.py:209-246` / `examples/2_bridge_provide.py`).

---

## 10. Quick reference card

```
Python                                    | C++ (MCU)
------------------------------------------|------------------------------------------
from arduino.app_utils import *           | #include <Arduino_RouterBridge.h>
(no begin() — lazy connect)               | Bridge.begin();                 // in setup()
Bridge.call("name", *args, timeout=10)    | Bridge.call("name", args).result(out) -> bool
Bridge.notify("name", *args)              | Bridge.notify("name", args);    // no return
Bridge.provide("name", fn)                | Bridge.provide_safe("name", fn);// default
@call()/@notify()/@provide() decorators   | Bridge.provide("name", fn);     // advanced
App.run(user_loop)   # LAST LINE          | loop() { /* keep non-blocking */ }
                                          | Monitor.println(x);  // NOT in provide cb
Types: int<->int32, float<->float, bool<->bool, str<->const char*/String  (mismatch = silent fail)
Socket: unix:///var/run/arduino-router.sock  (override: APP_SOCKET env)
```
