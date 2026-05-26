# Step 6 — Deploy & Test

Goal: push the App to the UNO Q, run it, open the UI, and watch logs to confirm
both the Linux process and the MCU sketch are alive.

## 1. Pre-flight checks

- `app.yaml` lists every brick `main.py` imports (Step 2).
- Every `ui.on_message`/`ui.send_message` name matches `app.js` (Step 5).
- Every `Bridge.provide`/`Bridge.call`/`Bridge.notify` name matches across
  `main.py` and `sketch.ino` (Steps 3–4).
- `assets/index.html` exists and `assets/libs/socket.io.min.js` is present (UI apps).

## 2. Deploy

Use this skill's deploy helper (written by the scripts agent):

```bash
.claude/skills/arduino-uno-q/scripts/deploy.sh ./my-app
```

This builds the sketch (Zephyr) and uploads it to the MCU, installs the Python
side + bricks, and starts the App. (unverified: exact flags/behavior of
`deploy.sh` — confirm against the script once written. Under the hood it wraps the
Arduino App CLI; see `references/cli-commands.md` (unverified file name).)

## 3. Open the UI

For a `web_ui` app, browse to the board on **port 7000**:

```
http://<board-ip-or-hostname>:7000
```

(Or launch from the App Lab UI on the board.) The page should load and the socket
should connect — no "connection lost" banner.

## 4. Watch logs

Stream combined Linux + MCU logs with the logs helper:

```bash
.claude/skills/arduino-uno-q/scripts/logs.sh ./my-app
```

What healthy output looks like:
- Linux side: your `Logger(...)` lines (`logger.info("Starting App...")`, etc.).
- Socket connects logged when you open the browser.
- For sensor apps: a steady stream of `Bridge.notify` → handler → `send_message`.

## 5. Verify the data path end-to-end

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| UI loads but button does nothing | event-name mismatch | align `socket.emit` ↔ `ui.on_message` (Step 5) |
| `ImportError` on a brick at startup | brick missing from `app.yaml` | add it (Step 2) |
| Socket never connects | `socket.io.min.js` not vendored / wrong order | vendor it; load before `app.js` |
| MCU never responds to `Bridge.call` | sketch not uploaded, or name mismatch | redeploy; check `Bridge.provide` name |
| No sensor data | `Bridge.begin()` missing / wrong `Wire` | `Bridge.begin()` first; Modulino on `Wire1` |
| Handler crashes silently | unguarded exception in handler | wrap in `try/except`, `logger.exception(...)` |

See `references/troubleshooting.md` (unverified file name) for the full table.

## 6. Iterate

Edit → redeploy with `deploy.sh` → re-check `logs.sh`. Python-only changes
redeploy fast; sketch changes recompile the Zephyr firmware (slower).

## Done when

The App runs on the board, the UI is reachable on `:7000`, logs are clean, and the
full data path (browser ↔ Linux ↔ MCU) works as designed.

This completes the build workflow. For full worked builds see
`examples/general-sensor-dashboard.md` and `examples/general-ai-camera.md`.
