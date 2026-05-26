# `arduino-app-cli` — Complete Command Reference

`arduino-app-cli` is the command-line tool that runs **on** the Arduino UNO Q (the Linux/A53
"Debian" side). It manages **Arduino Apps** — a bundle of a Python program (runs on Linux) plus an
optional MCU sketch (runs on the integrated STM32 microcontroller), wired together over an
RPC bridge. It also exposes an HTTP daemon (the REST API that Arduino App Lab talks to) and
auto-updates itself and related components.

> Source of truth for everything below: the cloned repo
> `skill-sources/arduino-app-cli/` (README.md, `cmd/arduino-app-cli/**`, `docs/`,
> `internal/api/docs/openapi.yaml`) and `skill-sources/arduino-uno-q-agent-template/docs/agent/cli.md`.
> The repo binary version constant is `0.0.0-dev` (`cmd/arduino-app-cli/main.go`), i.e. this is
> **pre-1.0 software — the command surface and flags can change between App Lab releases.** Always
> confirm with `arduino-app-cli <cmd> --help` on the actual board before relying on exact syntax.

---

## 0. Where commands run (execution context)

Per `docs/agent/cli.md`, there are two contexts:

| Context | Detect | How you run commands |
| --- | --- | --- |
| **On-board** (on the UNO Q Linux side) | `command -v arduino-app-cli` resolves | Run `arduino-app-cli ...` directly. App code already lives at `/home/arduino/ArduinoApps/<name>/`. |
| **Off-board** (your laptop) | `arduino-app-cli` is absent, but `adb devices` lists the board | `adb push` your code, then run lifecycle via `adb shell arduino-app-cli ...`. |

Off-board, **prefix every command with `adb shell`**. Use `adb shell -t` to allocate a TTY when you
need interactive streaming (e.g. following logs or the serial monitor). If neither path works, the
board is not connected — connect it over USB-C so `adb` sees it.

`arduino@<board-name>.local` over SSH is an alternative transport once `system network-mode enable`
has turned SSH on (see board-connect.sh and deploy-safety.md).

---

## 1. Top-level command map

Verified from `cmd/arduino-app-cli/main.go` (`Use: "arduino-app-cli"`) and the per-package
`AddCommand` registrations:

```
arduino-app-cli
├── app          Manage Arduino Apps (lifecycle: new/start/stop/logs/...)
│   ├── new          Creates a new Arduino App
│   ├── start        Start an Arduino App
│   ├── stop         Stop an Arduino App
│   ├── restart      Restart or Start an Arduino App
│   ├── logs         Show the logs of the Python app
│   ├── list         List the Arduino apps
│   ├── destroy      Destroy (delete) an Arduino App
│   ├── clean-cache  Delete an app's .cache
│   ├── export       Export an existing App to a zip
│   └── import       Import an App from a zip
├── brick        Inspect available Bricks (read-only)
│   ├── list         List available bricks
│   └── details      Show details of a brick
├── model        Manage AI models (Edge Impulse, etc.)
│   ├── list         List available models
│   └── delete       Delete a model
├── config       Manage Arduino App CLI config
│   └── get          Get configuration
├── properties   Manage apps properties (variable values)
├── system       Manage the board's system configuration
│   ├── update        Update upgradable packages on the system
│   ├── cleanup       Remove unused/obsolete app images to free disk
│   ├── network-mode  enable | disable | status  (SSH/network on/off)
│   ├── keyboard      Manage the keyboard layout
│   └── set-name      Set the custom name of the board
├── monitor      Attach to the microcontroller serial monitor
├── daemon       Run the CLI as an HTTP daemon (REST API)
├── version      Print the version number
└── completion   Generate shell completion (bash|zsh|fish|powershell)
```

> `system init` and `system download-image` also exist in the source but are
> internal/provisioning subcommands; treat them as **(unverified for end-user use)** and avoid
> unless you know why you need them.

### Global / persistent flags

From `cmd/arduino-app-cli` root registration:

| Flag | Default | Meaning |
| --- | --- | --- |
| `--format` | `text` | Output format: `text` or `json`. Use `--format json` for scripting. |
| `--log-level` | `error` | Log verbosity: `debug`, `info`, `warn`, `error`. |

---

## 2. `app` — lifecycle (the commands you use 90% of the time)

App identity. An App is a directory under `ARDUINO_APP_CLI__APPS_DIR`
(default `/home/arduino/ArduinoApps`). Most `app` subcommands take an **`app_path`** argument and
accept either:

- a **full path**: `/home/arduino/ArduinoApps/my-app`
- a **namespace shortcut**: `user:my-app` (a user app) or `examples:blink` (a built-in example).

Source: `docs/agent/cli.md` "App lifecycle"; the `user:`/`examples:` prefixes are confirmed in the
CLI's app-ID handling (`internal` tests reference `user:` IDs, and the API lists apps with
`ShowApps`/`ShowExamples`).

### `app new` — scaffold a new App

```
arduino-app-cli app new <name> [flags]
```

Args: `cobra.ExactArgs(1)` — exactly one name. Creates
`/home/arduino/ArduinoApps/<name>/` with `app.yaml`, `README.md`, `python/main.py`, and (unless
suppressed) `sketch/sketch.ino` + `sketch/sketch.yaml`.

Flags (verified in source `flags definitions`):

| Flag | Short | Default | Meaning |
| --- | --- | --- | --- |
| `--icon` | `-i` | `""` | Icon for the app (e.g. an emoji like `🌿`). |
| `--description` | `-d` | `""` | Description for the app. |
| `--bricks` | `-b` | `[]` | Bricks to include (repeatable, e.g. `-b arduino:dbstorage -b arduino:objectdetection`). |
| `--from-app` | | `""` | Create the new app from the path of an existing app (clone-style). |
| `--no-sketch` | | `false` | Do not include sketch files (Python-only App). |

```bash
arduino-app-cli app new "my-app"
arduino-app-cli app new "smart-garden" -i "🌿" -d "AI irrigation" -b arduino:dbstorage
arduino-app-cli app new "py-only" --no-sketch
```

### `app start` — start (and flash the sketch)

```
arduino-app-cli app start [app_path]
```

Args: `cobra.MaximumNArgs(1)` (omit to act on the default/current app).
**`app start` is what compiles and flashes the MCU sketch and launches the Python side** — you do
**not** use `arduino-cli upload` for an App's MCU half (see rules/deploy-safety.md).

```bash
arduino-app-cli app start /home/arduino/ArduinoApps/my-app
arduino-app-cli app start user:my-app          # shortcut
arduino-app-cli app start examples:blink        # built-in example
```

### `app stop`

```
arduino-app-cli app stop [app_path]
```
`cobra.MaximumNArgs(1)`. Stops the running App (Python container + bridge).

### `app restart`

```
arduino-app-cli app restart [app_path]
```
`cobra.MaximumNArgs(1)`. "Restart or Start an Arduino App." Use this after editing files in place so
the new code actually loads (you must restart — see deploy-safety.md).

### `app logs` — read the Python app's logs

```
arduino-app-cli app logs [app_path] [--all] [--follow]
```
`cobra.MaximumNArgs(1)`. Shows the **Python** side's logs.

| Flag | Default | Meaning |
| --- | --- | --- |
| `--all` | `false` | Show all logs (full history, not just the tail). |
| `--follow` | `false` | Follow/stream the logs (like `tail -f`). |

```bash
arduino-app-cli app logs user:my-app --all
adb shell -t arduino-app-cli app logs /home/arduino/ArduinoApps/my-app --follow
```

> MCU-side serial output is **not** in `app logs` — use `arduino-app-cli monitor` for the serial monitor.

### `app list`

```
arduino-app-cli app list [--show-broken-apps]
```
Lists apps and their status. `--show-broken-apps` also outputs apps that failed to parse/build.

### `app destroy`

```
arduino-app-cli app destroy [app_path]
```
`cobra.MaximumNArgs(1)`. **Deletes** the App. Destructive — see deploy-safety.md.

### `app clean-cache`

```
arduino-app-cli app clean-cache <app-id> [--force]
```
`cobra.ExactArgs(1)`. Deletes the App's `.cache/` (build/deps). `--force` cleans even while the app
is running.

### `app export` / `app import`

```
arduino-app-cli app export <app_path> [output_path] [--include-data] [--overwrite]
arduino-app-cli app import <zip_path>
```
- `export`: write the App as a zip. Use `-` as `output_path` to write the zip to **stdout**.
  `--include-data` bundles the App's `data/` directory; `--overwrite` replaces an existing output
  file. Secret-flagged Brick variables are auto-redacted on export (`docs/app-specification.md`).
- `import`: read an App from a zip. Use `-` as `zip_path` to read from **stdin**.

---

## 3. `brick` — inspect Bricks (read-only)

Bricks are modular components (DB storage, computer vision, AI models, etc.) declared in `app.yaml`.

```
arduino-app-cli brick list
arduino-app-cli brick details <brick-id>
```
These are read-only listings. You **add** a brick to an App by editing `app.yaml`'s `bricks:` list
(or via `app new -b`), then `app start` to materialize it. Example `app.yaml` brick entry:

```yaml
bricks:
  - arduino:dbstorage:
      variables:
        DB_PASSWORD: "password"
  - arduino:objectdetection:
      model: yolo-v8
      devices:
        - remote_camera_0
```

---

## 4. `model` — AI models

```
arduino-app-cli model list [--exclude-builtin]
arduino-app-cli model delete <id> [--force]
```
`--exclude-builtin` hides Arduino built-in models; `--force` deletes a model that is in use.
Custom Edge Impulse models live under `ARDUINO_APP_BRICKS__CUSTOM_MODEL_DIR`
(default `$HOME/.arduino-bricks/models`). See `docs/edge-impulse-models-specfication.md`.

---

## 5. `system` — board administration

```
arduino-app-cli system update [--only-arduino] [--only-docker-images] [--only-arduino-platform] [--yes]
arduino-app-cli system cleanup
arduino-app-cli system network-mode <enable|disable|status>
arduino-app-cli system keyboard [layout]
arduino-app-cli system set-name <name>
```

- **`system update`** — "Launches an update of the upgradable packages on the system." Flags:
  `--yes` (auto-confirm all prompts), `--only-arduino` (only Arduino-specific packages),
  `--only-docker-images` (only app docker images), `--only-arduino-platform` (only the Arduino
  platform + libraries). **Back up first** — see deploy-safety.md.
- **`system cleanup`** — removes unused/obsolete application images and networks to reclaim disk.
- **`system network-mode enable|disable|status`** — turn the board's network mode (incl. SSH) on/off
  or report its state. `enable` is what you run to be able to `ssh arduino@<board>.local`.
- **`system keyboard [layout]`** — manage the keyboard layout.
- **`system set-name <name>`** — rename the board (affects the `<name>.local` mDNS hostname).

---

## 6. `monitor` — MCU serial monitor

```
arduino-app-cli monitor
```
Attaches to the microcontroller's serial monitor — this is how you see `Serial.print()` output from
the sketch (the MCU half). Off-board, run with a TTY: `adb shell -t arduino-app-cli monitor`.

---

## 7. `config` / `properties` / `version` / `completion`

```
arduino-app-cli config get               # print current CLI configuration
arduino-app-cli properties ...           # manage stored variable values (properties.msgpack)
arduino-app-cli version                  # CLI version (+ daemon version if the daemon is running)
arduino-app-cli completion bash|zsh|fish|powershell [--no-descriptions]
```
`version` queries the local daemon at `/v1/version` and appends the daemon version when reachable;
it warns (not fatal) if the daemon is not listening.

---

## 8. `daemon` — the REST API (what App Lab talks to)

```
arduino-app-cli daemon [--port 8080]
```
Runs the CLI as an HTTP server (`cmd/arduino-app-cli/daemon/daemon.go`). The flag default in the
`daemon` command is **`--port 8080`**, and it binds to **`127.0.0.1`** (localhost only, CORS-wrapped).
Note: the version-check client and the published `openapi.yaml` reference a **different default**
(`http://localhost:6060`) — there is **port drift in this pre-1.0 build**, so confirm the actual port
with `--help` / `ss -ltnp` on the board rather than hardcoding it. On a normal board the daemon is
already running as a service (App Lab uses it); you rarely start it by hand.

### REST surface (from `internal/api/docs/openapi.yaml`, `version: 0.1.0`)

41 routes under `/v1`. The ones you'll actually use mirror the CLI:

```
GET    /v1/version                          application version
GET    /v1/config                           application configuration

# Apps
GET    /v1/apps                              list apps/examples (?filter=apps,examples,default &status=)
POST   /v1/apps                              create app (?skip-sketch=true)
GET    /v1/apps/{id}                         app/example detail
PATCH  /v1/apps/{id}                         update app details
DELETE /v1/apps/{id}                         delete app
POST   /v1/apps/{id}/start                   start app/example
POST   /v1/apps/{id}/stop                    stop app/example
POST   /v1/apps/{id}/clone                   clone from another app/example
GET    /v1/apps/{id}/logs                    logs of a running app
GET    /v1/apps/{id}/events                  application events
GET    /v1/apps/events                       application events (all)
GET    /v1/apps/{id}/export                  export app as ZIP
POST   /v1/apps/import                       import app from ZIP
GET    /v1/apps/{appID}/exposed-ports        ports the app exposes

# Bricks on an app
GET    /v1/apps/{appID}/bricks               brick instances for an app
POST   /v1/apps/{appID}/bricks               create a local brick
GET    /v1/apps/{appID}/bricks/{brickID}     brick instance by id
PATCH  /v1/apps/{appID}/bricks/{brickID}     update brick instance
PUT    /v1/apps/{appID}/bricks/{brickID}     upsert brick instance
DELETE /v1/apps/{appID}/bricks/{brickID}     delete brick instance
POST   /v1/apps/{appID}/bricks/{brickID}/rename     rename a local brick

# Sketch libraries on an app
GET    /v1/apps/{appID}/sketch/libraries            list sketch libraries
PUT    /v1/apps/{appID}/sketch/libraries/{libRef}   add a library
DELETE /v1/apps/{appID}/sketch/libraries/{libRef}   remove a library

# Catalog (read-only)
GET    /v1/bricks                            available bricks
GET    /v1/bricks/{id}                       brick detail
GET    /v1/models                            available AI models
GET    /v1/models/{id}                       model detail
DELETE /v1/models/{id}                       delete model
PUT    /v1/models/ei/projects/{projectID}    install a custom Edge Impulse model
GET    /v1/libraries                         search Arduino libraries

# Properties (variable values)
GET    /v1/properties                        all properties
GET    /v1/properties/{key}                  one property
PUT    /v1/properties/{key}                  upsert property
DELETE /v1/properties/{key}                  delete property

# System
GET    /v1/system/resources                  CPU/mem/disk usage
GET    /v1/system/update/check               packages needing upgrade
PUT    /v1/system/update/apply               start upgrade in background
GET    /v1/system/update/events              SSE stream of update progress
```

Tags in the spec: `Application`, `Brick`, `AIModels`, `System`, `Libraries`. The spec ships rendered
docs at `internal/api/docs/index.html`.

---

## 9. App layout & key paths

App skeleton (`docs/app-specification.md`):

```
my-app/
├── app.yaml          # App descriptor: name, description, icon, ports, bricks
├── README.md
├── python/
│   └── main.py       # Linux-side program (uses arduino.app_utils: App, Bridge)
├── sketch/
│   ├── sketch.ino    # MCU sketch (uses Arduino_RouterBridge.h)
│   └── sketch.yaml
└── .cache/           # build/deps (safe to clean-cache)
```

Environment variables (`docs/app-specification.md`):

| Variable | Default | Purpose |
| --- | --- | --- |
| `ARDUINO_APP_CLI__APPS_DIR` | `/home/arduino/ArduinoApps` | Where user apps live. |
| `ARDUINO_APP_CLI__DATA_DIR` | `/var/lib/arduino-app-cli` | Internal data: assets, built-in examples, `properties.msgpack`. |
| `ARDUINO_APP_BRICKS__CUSTOM_MODEL_DIR` | `$HOME/.arduino-bricks/models` | Custom AI models. |
| `ARDUINO_APP_CLI__ALLOW_ROOT` | `false` | Allow running as root (not recommended). |
| `DOCKER_REGISTRY_BASE` | `ghcr.io/arduino/` | Registry for app images. |

Built-in examples and version-pinned assets (`bricks-list.yaml`, `models-list.yaml`) live under
`/var/lib/arduino-app-cli/`.

---

## 10. End-to-end deploy loop (off-board, from your laptop)

This is the canonical loop from `docs/agent/cli.md` ("Typical agent deploy loop"). The provided
`scripts/` wrap each step.

```bash
# 0. Connect: confirm the board is visible.
adb devices                              # board should be listed (scripts/board-connect.sh)

# 1. Scaffold (once). Either on the board, or off-board via adb shell:
adb shell arduino-app-cli app new "my-app"        # scripts/new-app.sh

# 2. Edit code ON THE HOST (python/main.py, sketch/sketch.ino, app.yaml) in your editor.

# 3. Push + fix ownership + (re)start:
APP=my-app
DEST=/home/arduino/ArduinoApps/$APP
adb shell "mkdir -p $DEST"
adb push ./ "$DEST/"
adb shell "chown -R arduino:arduino $DEST"         # MANDATORY after every push
adb shell arduino-app-cli app stop  "$DEST" 2>/dev/null || true
adb shell arduino-app-cli app start "$DEST"        # compiles+flashes MCU, launches Python
                                                   # (scripts/deploy.sh does push+chown+start)

# 4. Observe:
adb shell -t arduino-app-cli app logs "$DEST" --all     # Python logs (scripts/logs.sh)
adb shell -t arduino-app-cli monitor                    # MCU serial

# 5. Iterate: edit on host -> deploy.sh again (it stops, pushes, chowns, restarts).

# 6. Stop when done:
adb shell arduino-app-cli app stop "$DEST"
```

Pull state/logs back to the host:

```bash
adb pull /home/arduino/ArduinoApps/my-app ./local-folder
```

---

## 11. Version-drift checklist (this is pre-1.0)

Because the binary reports `0.0.0-dev` and App Lab ships rapidly (the 0.x line), treat these as
soft facts and re-verify on the board:

- Daemon port: `8080` (daemon flag default) **vs** `6060` (openapi/version-check default) — drift;
  check live.
- New subcommands/flags may appear or be renamed between App Lab releases.
- Always run `arduino-app-cli <cmd> --help` on the actual board to confirm before scripting.
