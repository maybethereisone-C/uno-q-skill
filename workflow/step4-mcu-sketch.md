# Step 4 — MCU Sketch (`sketch/sketch.ino`)

Goal: write the firmware that runs on the STM32U585 microcontroller — real-time
I/O plus the Bridge link to Linux. Skip this step entirely for browser-only AI
apps (no `sketch/` folder).

## The fixed skeleton

```cpp
#include <Arduino_RouterBridge.h>     // always — gives you Bridge

void setup() {
    // hardware init (pinMode, sensor.begin(), matrix.begin(), ...)
    Bridge.begin();                                  // open the link to Linux
    Bridge.provide("set_led_state", set_led_state);  // expose RPCs Linux can call
}

void loop() {}                                       // empty for RPC-driven apps

void set_led_state(bool state) {                     // exposed function
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
}
```

`Bridge.begin()` must come before any `Bridge.provide(...)`. (verified in every
example.)

## Two patterns

### A. RPC-driven (Linux calls the MCU)

`loop()` is empty; everything happens in functions exposed with
`Bridge.provide`. The Python side drives it with `Bridge.call`. From
`blink-with-ui` and `keyword-spotting`.

```cpp
void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
}
void loop() {}
void set_led_state(bool state) { digitalWrite(LED_BUILTIN, state ? LOW : HIGH); }
```

### B. Sensor streaming (MCU pushes to Linux)

`loop()` samples on a timed interval (non-blocking `millis()` pattern) and pushes
each reading up with `Bridge.notify(...)`. Python receives it via a provided
function. From `real-time-accelerometer`:

```cpp
#include <Arduino_Modulino.h>
#include <Arduino_RouterBridge.h>

ModulinoMovement movement;
unsigned long previousMillis = 0;
const long interval = 16;            // ms (≈62.5 Hz)

void setup() {
    Bridge.begin();
    Modulino.begin(Wire1);           // Modulino sensors use I2C on Wire1
    while (!movement.begin()) delay(1000);
}

void loop() {
    unsigned long now = millis();
    if (now - previousMillis >= interval) {
        previousMillis = now;
        if (movement.update() == 1) {
            Bridge.notify("record_sensor_movement",
                          movement.getX(), movement.getY(), movement.getZ());
        }
    }
}
```

## Includes you'll commonly need

| Hardware | Include | Notes |
| --- | --- | --- |
| Bridge (always) | `<Arduino_RouterBridge.h>` | required for any MCU↔Linux comms |
| Modulino sensors | `<Arduino_Modulino.h>` | `Modulino.begin(Wire1)` then `sensor.begin()` |
| LED matrix | `<Arduino_LED_Matrix.h>` | `matrix.begin()`, `loadFrame()`, `playSequence()` |

Matching `sketch.yaml` stays the Zephyr template from Step 1 — no edits needed.

## Gotchas

- Built-in LED is **active-LOW**: `LOW` = on, `HIGH` = off (see `set_led_state`).
- Modulino is I2C on **`Wire1`**, not `Wire` — `Modulino.begin(Wire1)`.
- Use the non-blocking `millis()` interval pattern in `loop()`, not `delay()`, so
  the Bridge stays responsive.
- `Bridge.notify` is fire-and-forget (no return); `Bridge.provide`+`Bridge.call`
  is request/response. Match the direction to your need — see
  `references/bridge-rpc.md`.
- RPC names must match **exactly** on both sides (`"set_led_state"` here ↔
  `Bridge.call("set_led_state", ...)` in Python).

## Done when

`sketch.ino` compiles conceptually: `Bridge.begin()` first, every `provide`/`notify`
name matches `main.py`, and hardware init is in `setup()`.

Next: `workflow/step5-webui.md` (or skip to Step 6 if headless).
