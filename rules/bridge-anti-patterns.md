# Bridge Anti-Patterns (prescriptive rules)

These are hard rules for the UNO Q Bridge. Each is a **DON'T** + the **correct
alternative**. Violating them causes silent data loss, hangs, or Bridge deadlocks. Sources
are cited; treat unverified claims as marked.

> Full API and architecture: `references/bridge-rpc.md`.

---

## Rule 1 — Never let argument types mismatch across the Bridge (silent failure)

Bridge arguments are typed across the wire and **mismatches fail silently** — no exception,
no log, just a no-op or a failed conversion. (Source:
`arduino-uno-q-agent-template/docs/agent/bridge.md:27`, `AGENTS.md:101` rule 6; the router
returns `ok=false` on bad integer conversions, `arduino-router/msgpackrpc/type_conversion.go:39-41`.)

**DON'T** — pass a Python type that doesn't match the C++ signature:

```python
Bridge.call("set_brightness", "128")   # str sent...
```
```cpp
void set_brightness(int level) { analogWrite(LED_BUILTIN, level); }  // ...int expected → silently ignored
```

**DO** — match the declared C++ signature exactly:

| Python | C++ |
| --- | --- |
| `int` | `int` (32-bit) |
| `float` | `float` |
| `bool` | `bool` |
| `str` | `const char*` / `String` |

```python
Bridge.call("set_brightness", 128)     # int ↔ int
```

Declare the C++ function signature explicitly and pass matching types. Don't rely on
implicit coercion (e.g. `1`/`0` for a `bool`, or numeric strings for `int`).

---

## Rule 2 — Never nest `Bridge.call(...)` inside a `Bridge.provide*` callback (deadlock)

A function exposed via `provide`/`provide_safe` is invoked **by** the Bridge while it is
servicing an inbound request. Issuing an outbound `Bridge.call(...)` from inside it can
deadlock the Bridge in either direction. (Source: `docs/agent/bridge.md:38-43,107-121`,
`AGENTS.md:74` rule 4.)

**DON'T:**

```python
def on_button(state: int):
    Bridge.call("ack", state)     # WRONG: nested call inside a provide handler

Bridge.provide("on_button", on_button)
```

(This exact pattern is flagged "wrong" in `docs/agent/bridge.md:113-121`.)

**DO** — decouple the outbound call from the handler. Buffer in the callback; do the
outbound `call` from a separate flow (a periodic `user_loop`, or a queue consumer):

```python
from collections import deque
pending = deque()

def on_button(state: int):
    pending.append(state)         # just record; return fast

def loop():
    while pending:
        Bridge.call("ack", pending.popleft())   # outbound call lives here, not in the handler

Bridge.provide("on_button", on_button)
App.run(user_loop=loop)
```

The same rule holds on the MCU: don't call back into Python from inside a C++ `provide*`
handler — set a flag and act on it in `loop()`.

---

## Rule 3 — Never call `Monitor.print*(...)` inside an MCU `provide*` callback

Logging from inside a `Bridge.provide*` callback on the MCU is called out as a deadlock /
hang source. (Source: `docs/agent/bridge.md:41`, `AGENTS.md:74` rule 4.)

**DON'T:**

```cpp
void set_led_state(bool state) {
  Monitor.println("set_led_state called");   // WRONG: inside a provide callback
  digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
}
Bridge.provide_safe("set_led_state", set_led_state);
```

**DO** — keep the callback to just the hardware action; log elsewhere (in `loop()` guarded
by a flag, or not at all):

```cpp
volatile bool didToggle = false;

void set_led_state(bool state) {
  digitalWrite(LED_BUILTIN, state ? LOW : HIGH);  // action only
  didToggle = true;
}

void loop() {
  if (didToggle) { Monitor.println("led toggled"); didToggle = false; }  // log in loop context
}
```

---

## Rule 4 — Never block in a loop or a callback (`delay()` / `time.sleep()`)

While either side is blocked, the Bridge **cannot service requests**. Long `delay()` (MCU)
or `time.sleep()` (Python) inside loops or callbacks starves the RPC layer. (Source:
`docs/agent/bridge.md:42`, `AGENTS.md:79` rule 5: "No blocking delay()/sleep() longer than
a few ms".)

**DON'T** — busy-block the MCU loop:

```cpp
void loop() {
  readAndSend();
  delay(1000);            // WRONG: 1s where the Bridge can't run
}
```

**DO** — pace with non-blocking `millis()` (the verified telemetry pattern,
`real-time-accelerometer/sketch/sketch.ino:29-47`):

```cpp
unsigned long previousMillis = 0;
const long interval = 16;            // ~62.5 Hz

void loop() {
  unsigned long now = millis();
  if (now - previousMillis >= interval) {
    previousMillis = now;
    readAndSend();
  }
}
```

> `delay()` is acceptable **only in `setup()`** (e.g. sensor init retry:
> `while (!movement.begin()) { delay(1000); }`, `real-time-accelerometer/.../sketch.ino:24`)
> — never in `loop()` or a callback.

On the Python side, blocking work belongs in a `user_loop` (the framework loops it), not in
a `provide` handler — handlers run on the Bridge read thread (`bridge.py:300,530-580`) and
must return quickly. A short `time.sleep` to pace a `user_loop` is fine
(`docs/agent/bridge.md:51-54`); long sleeps inside a `provide` callback are not.

---

## Rule 5 — Never hand-install `Arduino_RouterBridge` on Zephyr core ≥ 0.55.0

The `Arduino_RouterBridge` library is **bundled** in the UNO Q Zephyr core ≥ 0.55.0. Adding
it to `sketch.yaml` (or installing it manually) causes a conflict. (Source:
`AGENTS.md:103` rule 7; version corroborated by `docs/agent/bridge.md:23`, which notes
`Serial.print` also works on Zephyr core ≥ 0.55.0.)

**DON'T:**

```yaml
# sketch/sketch.yaml — WRONG
libraries:
  - Arduino_RouterBridge   # already bundled; do not add
```

**DO** — just include the header; add to `sketch.yaml` only the *other* libraries you use:

```cpp
#include <Arduino_RouterBridge.h>   // resolved from the bundled core
```
```yaml
# sketch/sketch.yaml — only non-bundled libs
libraries:
  - Modulino                 # example: a real sensor lib you actually use
```

---

## Rule 6 — Prefer `provide_safe` over `provide` on the MCU (loop-context safety)

The agent guidance: expose MCU callbacks with `Bridge.provide_safe(name, fn)` (runs in
`loop()` context — safe for hardware access) **by default**, and reserve `Bridge.provide`
for advanced use (Bridge-thread context, no hardware/interrupts). (Source:
`AGENTS.md:72` rule 3, `docs/agent/bridge.md:19-20`.)

> Note: the real example sketches in `app-bricks-examples` actually use `Bridge.provide`
> (e.g. `blink-with-ui/sketch/sketch.ino:13`). Both compile; the loop-context vs
> Bridge-thread distinction is the agent's documented rule. The concrete runtime
> difference is **(unverified)** here because the `Arduino_RouterBridge` C++ source is
> bundled in the core, not in the cloned repos. When a handler touches hardware, follow the
> rule and use `provide_safe`.

**DO:**

```cpp
void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Bridge.begin();
  Bridge.provide_safe("set_led_state", set_led_state);   // default: loop context
}
```

---

## Rule 7 — Always check the `ok` from a C++ `Bridge.call(...).result(out)`

On the MCU, `Bridge.call(...)` returns a result handle; `.result(out)` writes the value by
reference and returns a `bool ok`. If you use `out` without checking `ok`, you read garbage
on a failed/timed-out call. (Source: `weather-forecast/sketch/sketch.ino:23-24`,
`air-quality-monitoring/sketch/sketch.ino:21-22`, `mascot-jump-game/sketch/sketch.ino:24-71`.)

**DON'T:**

```cpp
String weather;
Bridge.call("get_weather_forecast", city).result(weather);
matrix.loadSequence(pickFrame(weather));   // WRONG: weather may be invalid
```

**DO:**

```cpp
String weather;
bool ok = Bridge.call("get_weather_forecast", city).result(weather);
if (ok) {
  matrix.loadSequence(pickFrame(weather));
} else {
  matrix.loadFrame(unknown);               // safe fallback
}
```

---

## Rule 8 — `App.run()` is the last line of `python/main.py`

Anything after `App.run()` is ignored by the framework. Register all `Bridge.provide`
handlers, WebUI handlers, and bricks **before** it. (Source: `AGENTS.md:88` rule 1,
`docs/agent/bridge.md:12`.)

**DON'T:**

```python
App.run()
Bridge.provide("on_sample", on_sample)   # WRONG: never registered
```

**DO:**

```python
Bridge.provide("on_sample", on_sample)
App.run()                                 # LAST LINE
```

---

## Deadlock cheat-sheet

| Pattern | Why it deadlocks/fails | Fix |
| --- | --- | --- |
| `Bridge.call` inside a `provide*` handler | Outbound RPC while servicing an inbound one | Buffer + call from a separate loop/queue |
| `Monitor.print` inside an MCU `provide*` handler | Blocks the handler context | Log from `loop()` via a flag |
| Long `delay()`/`time.sleep()` in loop/callback | Bridge can't service requests | Non-blocking `millis()` pacing / `user_loop` |
| Type mismatch on `call`/`notify` args | Silent no-op or failed conversion | Match int/float/bool/str ↔ C++ types exactly |
| Using `.result(out)` without checking `ok` | Reads invalid `out` on failure | Always branch on `bool ok` |
| `Arduino_RouterBridge` in `sketch.yaml` | Conflicts with bundled core ≥ 0.55.0 | Just `#include`, don't declare |
| Code after `App.run()` | Never executes | Put everything before `App.run()` |
