# Worked Example — Sensor → Live Dashboard

A complete, general-purpose App: the MCU reads a Modulino Movement sensor and
streams accelerometer samples up to Linux; Linux pushes them to a browser
dashboard over Socket.IO. This proves the **MCU → Linux → browser** path.

> Distilled from `app-bricks-examples/examples/real-time-accelerometer/`
> (simplified to a plain live chart, motion-classification brick omitted for
> clarity). Swap the Modulino for any sensor by changing the sketch's read line.

## Tree

```
sensor-dashboard/
├── app.yaml
├── python/main.py
├── sketch/
│   ├── sketch.ino
│   └── sketch.yaml          # Zephyr template, unchanged
└── assets/
    ├── index.html
    ├── app.js
    ├── style.css
    └── libs/socket.io.min.js
```

## `app.yaml`

```yaml
name: Sensor Dashboard
icon: 📈
description: Live accelerometer stream from a Modulino Movement sensor

bricks:
  - arduino:web_ui
```

> Only `web_ui` is needed: we read the raw sensor in the sketch and forward
> samples ourselves, so no AI brick is required. (Add `arduino:motion_detection`
> if you want gesture classification — see the upstream example.)

## `sketch/sketch.ino`

```cpp
#include <Arduino_Modulino.h>
#include <Arduino_RouterBridge.h>

ModulinoMovement movement;
unsigned long previousMillis = 0;
const long interval = 50;            // ms -> 20 Hz

void setup() {
    Bridge.begin();
    Modulino.begin(Wire1);           // Modulino sensors are I2C on Wire1
    while (!movement.begin()) delay(1000);
}

void loop() {
    unsigned long now = millis();
    if (now - previousMillis >= interval) {
        previousMillis = now;
        if (movement.update() == 1) {
            // fire-and-forget push to Linux
            Bridge.notify("record_sample",
                          movement.getX(), movement.getY(), movement.getZ());
        }
    }
}
```

## `python/main.py`

```python
from arduino.app_utils import *
from arduino.app_bricks.web_ui import WebUI
from collections import deque
import time

logger = Logger("sensor-dashboard")

ui = WebUI()

# keep the last N samples so a freshly-connected client gets recent history
SAMPLES_MAX = 200
samples = deque(maxlen=SAMPLES_MAX)

# REST endpoint: GET /samples -> recent history (used on first load)
ui.expose_api("GET", "/samples", lambda: list(samples))

# on connect, nothing to push yet; the browser fetches /samples itself
ui.on_connect(lambda sid: logger.info(f"client connected: {sid}"))

def record_sample(x: float, y: float, z: float):
    """Called from the sketch via Bridge.notify('record_sample', x, y, z)."""
    sample = {"t": time.time(), "x": float(x), "y": float(y), "z": float(z)}
    samples.append(sample)
    try:
        ui.send_message("sample", sample)        # realtime push to all clients
    except Exception:
        logger.debug("failed to emit sample")

# expose the receiver so the sketch's notify can reach it
Bridge.provide("record_sample", record_sample)

logger.info("Starting App...")
App.run()
```

## `assets/index.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sensor Dashboard</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="header"><h1 class="arduino-text">Sensor Dashboard</h1></div>
    <main class="container">
        <p>x: <span id="x" class="metric">–</span></p>
        <p>y: <span id="y" class="metric">–</span></p>
        <p>z: <span id="z" class="metric">–</span></p>
        <div id="error-container" class="error-message" style="display:none;"></div>
    </main>
    <script src="libs/socket.io.min.js"></script>
    <script src="app.js"></script>
</body>
</html>
```

## `assets/app.js`

```js
const socket = io(`http://${window.location.host}`);
const el = { x: document.getElementById('x'),
             y: document.getElementById('y'),
             z: document.getElementById('z') };
const err = document.getElementById('error-container');

document.addEventListener('DOMContentLoaded', async () => {
    // seed with recent history via REST
    const history = await fetch('/samples').then(r => r.json()).catch(() => []);
    if (history.length) render(history[history.length - 1]);

    socket.on('connect', () => { err.style.display = 'none'; });
    socket.on('sample', render);                       // realtime stream
    socket.on('disconnect', () => {
        err.textContent = 'Connection lost.';
        err.style.display = 'block';
    });
});

function render(s) {
    el.x.textContent = s.x.toFixed(3);
    el.y.textContent = s.y.toFixed(3);
    el.z.textContent = s.z.toFixed(3);
}
```

`style.css` — copy the skill's `templates/webui-assets/style.css` unchanged.

## Data path

```
Modulino → sketch.loop() → Bridge.notify("record_sample", x,y,z)
  → main.py record_sample() → ui.send_message("sample", {...})
  → browser socket.on("sample") → render()
```

## Deploy

```bash
.claude/skills/arduino-uno-q/scripts/deploy.sh ./sensor-dashboard
.claude/skills/arduino-uno-q/scripts/logs.sh   ./sensor-dashboard   # watch the stream
# open http://<board>:7000
```

## Adapt it

- **Different sensor:** change `movement.getX/Y/Z()` to your sensor's read; keep
  one `Bridge.notify(...)` per push.
- **Add a chart:** vendor `chart.js` into `assets/libs/` and draw `sample` events.
- **Add classification:** add `arduino:motion_detection`, feed samples to the brick
  (`motion_detection.accumulate_samples(...)`) as in the upstream example.
