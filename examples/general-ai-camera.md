# Worked Example — AI Camera (Object Detection)

A complete, general-purpose App: the browser captures a camera frame, sends it to
Linux, the `object_detection` brick runs inference, and the annotated image comes
back. This proves the **browser ↔ Linux AI** path — **no MCU, no `sketch/`**.

> Distilled from `app-bricks-examples/examples/object-detection/`. The Python side
> below is the real `main.py` (lightly trimmed). Same pattern works for
> `image_classification`, `video_face_detection`, etc. by swapping the brick.

## Tree

```
ai-camera/
├── app.yaml
├── python/main.py
└── assets/
    ├── index.html
    ├── app.js
    ├── style.css
    └── libs/socket.io.min.js
```

No `sketch/` — this App never touches the microcontroller. All compute is on the
Qualcomm/Linux side via the brick.

## `app.yaml`

```yaml
name: AI Camera
icon: 🏞️
description: Object detection on camera frames in the browser

bricks:
  - arduino:web_ui
  - arduino:object_detection
```

## `python/main.py` (real, from object-detection)

```python
from arduino.app_utils import *
from arduino.app_bricks.web_ui import WebUI
from arduino.app_bricks.object_detection import ObjectDetection
from PIL import Image
import io, base64, time

object_detection = ObjectDetection()

def on_detect_objects(client_id, data):
    """Handle a detection request: {image: <base64>, confidence: <float>}."""
    try:
        image_data = data.get('image')
        confidence = data.get('confidence', 0.5)
        if not image_data:
            ui.send_message('detection_error', {'error': 'No image data'})
            return

        pil_image = Image.open(io.BytesIO(base64.b64decode(image_data)))

        start = time.time() * 1000
        results = object_detection.detect(pil_image, confidence=confidence)
        diff = time.time() * 1000 - start

        if results is None:
            ui.send_message('detection_error', {'error': 'No results returned'})
            return

        img = object_detection.draw_bounding_boxes(pil_image, results) or pil_image
        buf = io.BytesIO(); img.save(buf, format="PNG"); buf.seek(0)
        b64 = base64.b64encode(buf.getvalue()).decode("utf-8")

        ui.send_message('detection_result', {
            'success': True,
            'result_image': b64,
            'detection_count': len(results.get("detection", [])),
            'processing_time': f"{diff:.2f} ms",
        })
    except Exception as e:
        ui.send_message('detection_error', {'error': str(e)})

ui = WebUI()
ui.on_message('detect_objects', on_detect_objects)
App.run()
```

Note the heavy `try/except` — a brick that returns `None` or raises must not kill
the socket loop.

## `assets/index.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Camera</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="header"><h1 class="arduino-text">AI Camera</h1></div>
    <main class="container">
        <video id="cam" autoplay playsinline></video>
        <button id="snap">Detect objects</button>
        <p id="stats" class="metric">–</p>
        <img id="result" alt="annotated result">
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
const cam = document.getElementById('cam');
const result = document.getElementById('result');
const stats = document.getElementById('stats');
const err = document.getElementById('error-container');

document.addEventListener('DOMContentLoaded', async () => {
    // grab the camera (served over a secure/localhost origin)
    cam.srcObject = await navigator.mediaDevices.getUserMedia({ video: true });
    document.getElementById('snap').addEventListener('click', capture);

    socket.on('detection_result', (msg) => {
        result.src = `data:image/png;base64,${msg.result_image}`;
        stats.textContent = `${msg.detection_count} objects · ${msg.processing_time}`;
        err.style.display = 'none';
    });
    socket.on('detection_error', (msg) => {
        err.textContent = msg.error; err.style.display = 'block';
    });
    socket.on('disconnect', () => {
        err.textContent = 'Connection lost.'; err.style.display = 'block';
    });
});

function capture() {
    // draw the current frame to a canvas, export base64 (no data: prefix)
    const c = document.createElement('canvas');
    c.width = cam.videoWidth; c.height = cam.videoHeight;
    c.getContext('2d').drawImage(cam, 0, 0);
    const b64 = c.toDataURL('image/png').split(',')[1];
    socket.emit('detect_objects', { image: b64, confidence: 0.5 });
}
```

`style.css` — copy the skill's `templates/webui-assets/style.css` (add `video,img { max-width: 100%; }`).

## Data path

```
browser camera → canvas → base64
  → socket.emit("detect_objects", {image, confidence})
  → main.py on_detect_objects() → object_detection.detect(...) → draw_bounding_boxes(...)
  → ui.send_message("detection_result", {result_image, count, time})
  → browser socket.on("detection_result") → <img>
```

## Deploy

```bash
.claude/skills/arduino-uno-q/scripts/deploy.sh ./ai-camera
.claude/skills/arduino-uno-q/scripts/logs.sh   ./ai-camera
# open http://<board>:7000  (allow camera permission)
```

## Adapt it

- **Different model task:** swap `arduino:object_detection` for
  `arduino:image_classification` (and the matching import/class). The browser
  contract (`detect_objects` → `detection_result`) is yours to rename.
- **Add an MCU reaction:** want a buzzer/LED when a class is seen? Add a `sketch/`,
  `Bridge.provide(...)` the actuator on the MCU, and `Bridge.call(...)` from
  `on_detect_objects` — combining this example with the blink/sensor pattern.
- **Confidence slider:** add an `<input type="range">` and pass its value as
  `confidence`.
