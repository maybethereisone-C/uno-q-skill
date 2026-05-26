# Authoring Your Own Brick

App Lab 0.7+ lets you build **custom Bricks** — your own reusable Python
component that plugs into the same `App` lifecycle as the official ones. This
guide is grounded in the verified mechanics of the official bricks
(`app-bricks-py`); where the 0.7 GUI/registration UX is involved and not
confirmable from source, it's marked **(unverified)**.

Sources (verified):
- `app-bricks-py/src/arduino/app_utils/brick.py` — the `@brick` decorator
- `app-bricks-py/src/arduino/app_utils/app.py` — `App` controller / lifecycle
- `app-bricks-py/src/arduino/app_bricks/mood_detector/__init__.py` — simplest pure-Python brick
- `app-bricks-py/src/arduino/app_bricks/*/brick_config.yaml` — brick metadata schema
- `app-bricks-py/src/arduino/app_bricks/dbstorage_tsstore/brick_compose.yaml`, `object_detection/brick_compose.yaml` — Docker-backed bricks
- `arduino-uno-q-agent-template/docs/agent/bricks/_template.md` — doc template

---

## 1. When to build a custom Brick vs. just compose existing ones

**Don't build a brick** if you can compose existing ones. For most apps, the
right unit of reuse is plain functions/classes in your `python/` folder driven
from `main.py`. Build a brick when **all** of these hold:
- the logic is **reusable across apps** (not one app's glue), and
- it has a **lifecycle** (background thread, start/stop, a model runner, a DB,
  an external service) that benefits from `App` managing it, and/or
- it needs its own **Docker Compose infrastructure** (a model runner, a
  database, a broker).

If you just need a helper, write a module. If you need a managed,
infrastructure-backed, reusable component — build a brick.

---

## 2. Anatomy of a Brick

A brick is a normal Python package directory whose main class is decorated with
`@brick`. Official bricks live at
`src/arduino/app_bricks/<name>/` and contain:

```
<name>/
├── __init__.py          # exports the @brick class (the public API)
├── <impl>.py            # optional extra modules
├── brick_config.yaml    # metadata: id, category, requirements, variables
├── brick_compose.yaml   # optional: Docker Compose infra (container bricks)
├── README.md
└── examples/            # optional runnable snippets
```

The **simplest** verified brick is `mood_detector` — a single `__init__.py`:

```python
from arduino.app_utils import brick

@brick
class MoodDetector:
    def __init__(self):
        self._analyzer = SentimentIntensityAnalyzer()

    def get_sentiment(self, text: str) -> str:
        scores = self._analyzer.polarity_scores(text)
        if scores["compound"] >= 0.05:  return "positive"
        if scores["compound"] <= -0.05: return "negative"
        return "neutral"
```

with `brick_config.yaml`:
```yaml
id: arduino:mood_detector
name: Mood Detection
description: |
  This brick analyzes text sentiment to detect the mood expressed.
category: text
```

That's a complete brick: `@brick` + a config with an `id`.

---

## 3. The `@brick` decorator and lifecycle

From `app_utils/brick.py`, `brick` is an instance of `BrickDecorator` exposing
three forms:

### `@brick` (class decorator) — register with the App
It patches `__init__` so that **constructing an instance auto-registers it** with
the central `App` controller for lifecycle management. Use `@brick` or `@brick()`.

```python
from arduino.app_utils import brick

@brick
class MyBrick:
    def __init__(self, threshold: float = 0.5):
        self.threshold = threshold
```

### `@brick.execute` (method) — one-shot background task
Marks a method to run **once**, in its own dedicated thread, when the app starts.
Use for blocking work (a server loop, a consume loop you manage yourself).

```python
@brick
class Worker:
    @brick.execute
    def run(self):
        while True:
            do_blocking_work()
```

### `@brick.loop` (method) — repeated background task
Marks a method the controller calls **repeatedly** in a dedicated thread. Use for
a non-blocking step you want ticked continuously.

```python
@brick
class Poller:
    @brick.loop
    def step(self):
        sample = read_sensor()
        self.process(sample)
```

### Conventional lifecycle methods
Official bricks also implement plain `start()` / `stop()` methods (e.g.
`SQLStore.start()`, `TimeSeriesStore.stop()`, `WebUI.start()/stop()`). These are
called as part of the managed lifecycle. Implement `start()`/`stop()` for
resources you open/close (connections, devices, threads).

`App.run()` (from `app_utils/app.py`) starts all registered bricks, runs their
`@brick.execute`/`@brick.loop` methods, then blocks until Ctrl+C / SIGTERM and
shuts bricks down. Your `python/main.py` constructs your brick and calls
`App.run()`:

```python
from arduino.app_utils import App
from my_pkg.my_brick import MyBrick

mb = MyBrick(threshold=0.7)   # auto-registers
App.run()
```

---

## 4. `brick_config.yaml` reference (the metadata contract)

Verified fields seen across official bricks:

```yaml
id: arduino:my_brick          # the id used under `bricks:` in app.yaml
name: My Brick                # display name
description: "What it does."
category: text                # text|audio|video|image|storage|ui|miscellaneous

# --- requirements (all optional) ---
requires_container: true      # brick has a brick_compose.yaml to run
requires_model: true          # needs an AI model asset
model: my-model               # default model id (with requires_model)
model_by_platform:            # branch model by board
  - platform: ventunoq
    model: my-model-qnn
  - platform: unoq
    model: my-model
requires_services: ["arduino:genie"]   # depends on a platform service
supported_boards: ["ventunoq"]         # restrict to boards
required_devices:                      # hardware bindings
  - camera                             # camera|microphone|speaker
mount_devices_into_container: true
ai_frameworks_compatibility: [edgeimpulse]   # edgeimpulse|genie|qnn

# --- configuration surfaced to the user ---
variables:
  - name: API_KEY
    description: API key for the service
    secret: true              # hidden + treated as a secret
  - name: BIND_ADDRESS
    description: Bind address
    hidden: true              # not shown in UI
    default_value: 127.0.0.1

ports:
  - 7000                      # ports the brick exposes (e.g. web_ui)
```

Pick a unique `id`. Official bricks use the `arduino:` prefix; for your own use
a distinct namespace to avoid collisions, e.g. `myorg:my_brick`. **(The exact
namespace rules enforced by App Lab 0.7 are unverified — confirm in the App Lab
0.7 docs/blog.)**

---

## 5. Two packaging models

### A) Pure-Python brick (a library)
If your brick is just Python (no infra), it's a package with `@brick` class(es)
and a `brick_config.yaml`. Ship it as an importable module. `mood_detector`,
`web_ui`, `weather_forecast`, `dbstorage_sqlstore` are pure-Python (note
`requires_container: false` for sqlstore). Any pip deps your brick needs are
declared so they're installed into the app's Python environment (official bricks
declare deps in the package's `pyproject.toml`; an app can also carry a
`python/requirements.txt`). Target **Python ≥ 3.13** (the official package's
`requires-python`).

### B) Docker-backed brick (infrastructure)
If your brick needs a service (model runner, database, broker), add a
`brick_compose.yaml` and set `requires_container: true`. App Lab brings the
Compose service up alongside the app; your `@brick` class is the Python client
that talks to it.

Verified container-brick shape — `dbstorage_tsstore` runs InfluxDB:
```yaml
# brick_compose.yaml
services:
  dbstorage-influx:
    image: influxdb:2.7-alpine
    ports:
      - "${BIND_ADDRESS:-127.0.0.1}:8086:8086"
    volumes:
      - "${APP_HOME:-.}/data/influx-data:/var/lib/influxdb2"
    environment:
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: "${DB_USERNAME:-admin}"
      # ...
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8086/health || exit 1"]
      interval: 2s
      timeout: 3s
      retries: 10
```

`object_detection` follows the same model for a model-runner container (pulls
`ghcr.io/arduino/app-bricks/ei-models-runner`, exposes an HTTP port, mounts the
`.eim` model, has a healthcheck). Patterns to copy:
- Use `${VAR:-default}` so values come from `brick_config.yaml` `variables`.
- Bind to `${BIND_ADDRESS:-127.0.0.1}` by default (loopback) for safety.
- Always add a `healthcheck` so the app waits for readiness.
- Cap logs (`max-size`, `max-file`) — the board has limited storage.
- A `brick_compose.ventunoq.yaml` variant lets you ship board-specific
  (e.g. QNN) images; several official bricks do this.

---

## 6. Registering and using a custom brick

1. Place the brick package where your app's Python can import it (your
   `python/` tree, or an installed package).
2. Declare it in `app.yaml`:
   ```yaml
   bricks:
     - myorg:my_brick: {}
   ```
   (The agent-template shows the GUI-free form: edit `app.yaml` directly to add
   `- <id>: {}` under `bricks:`, plus any `required_devices` entries.)
3. Import and instantiate it in `python/main.py`, then `App.run()`.

> **(Unverified)** App Lab 0.7 also exposes custom bricks through its GUI brick
> picker and a registration/discovery step. The exact discovery path (where App
> Lab scans for `brick_config.yaml`, how third-party bricks are listed/installed
> in the GUI) is not confirmable from the cloned source — verify against
> `docs.arduino.cc/software/app-lab/` and the 2026 "App Lab 0.7 custom bricks"
> blog before relying on it.

---

## 7. Authoring checklist

- [ ] One cohesive responsibility; reusable beyond a single app.
- [ ] Main class decorated `@brick`; constructor args have sane defaults + type hints.
- [ ] `start()`/`stop()` for any resource you open; `@brick.execute`/`@brick.loop` for background work.
- [ ] Register callbacks via `on_*` methods (the official convention) rather than blocking the caller.
- [ ] `brick_config.yaml` with a unique `id`, `category`, requirements, and `variables` (mark secrets `secret: true`).
- [ ] If infra-backed: `brick_compose.yaml` with `${VAR:-default}`, loopback bind, healthcheck, capped logs; set `requires_container: true`.
- [ ] Declare pip deps; target Python ≥ 3.13.
- [ ] A `README.md` and a runnable `examples/` snippet (≤120-line doc per `_template.md`).
- [ ] Document gotchas: ports, env vars, model assets, threading rules, Bridge deadlock (never `Bridge.call` inside a `Bridge.provide` handler).

---

## 8. Minimal custom-brick template

`my_brick/__init__.py`:
```python
from collections.abc import Callable
from arduino.app_utils import brick, Logger

logger = Logger("MyBrick")

@brick
class MyBrick:
    """One-line summary of what this brick does."""

    def __init__(self, threshold: float = 0.5):
        self._threshold = threshold
        self._on_event: Callable[[dict], None] | None = None

    def on_event(self, callback: Callable[[dict], None]):
        """Register a handler fired when the brick detects something."""
        self._on_event = callback

    def start(self):
        logger.info("MyBrick starting")

    def stop(self):
        logger.info("MyBrick stopping")

    @brick.loop
    def _step(self):
        value = self._read()
        if value > self._threshold and self._on_event:
            self._on_event({"value": value})

    def _read(self) -> float:
        ...  # your logic
```

`my_brick/brick_config.yaml`:
```yaml
id: myorg:my_brick
name: My Brick
description: "Detects when a value crosses a threshold."
category: miscellaneous
variables:
  - name: MY_THRESHOLD
    description: Detection threshold
    default_value: "0.5"
```

`python/main.py`:
```python
from arduino.app_utils import App
from my_brick import MyBrick

mb = MyBrick(threshold=0.7)
mb.on_event(lambda e: print("event!", e))
App.run()
```
