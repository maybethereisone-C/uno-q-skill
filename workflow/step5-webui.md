# Step 5 — Web UI (`assets/`)

Goal: a self-contained web page that talks to `main.py` over Socket.IO. Skip for
headless apps (no `assets/` folder).

## The three files

- `index.html` — entrypoint, **required** or the `web_ui` brick won't start.
- `app.js` — your logic; opens a socket, emits/listens, updates the DOM.
- `style.css` — styles.
- `libs/socket.io.min.js` — vendored client (Step 1), **no CDN at runtime**.

## Wire the socket

The `web_ui` brick serves the page **and** the Socket.IO server on port 7000, so
the client connects back to the same origin. From `blink-with-ui/assets/app.js`:

```js
const socket = io(`http://${window.location.host}`);

document.addEventListener('DOMContentLoaded', () => {
    initSocketIO();
    document.getElementById('led-button').addEventListener('click', handleLedClick);
});

function initSocketIO() {
    socket.on('connect', () => socket.emit('get_initial_state', {}));   // ask for state
    socket.on('led_status_update', updateLedStatus);                    // server -> UI
    socket.on('disconnect', () => showError('Connection lost.'));
}

function handleLedClick() {
    socket.emit('toggle_led', {});                                      // UI -> server
}
```

## The event-name contract

The string in `socket.emit("X")` / `socket.on("Y")` must match `main.py`:

| Direction | Browser (`app.js`) | Python (`main.py`) |
| --- | --- | --- |
| UI → server | `socket.emit('toggle_led', {})` | `ui.on_message('toggle_led', handler)` |
| server → UI | `socket.on('led_status_update', fn)` | `ui.send_message('led_status_update', payload)` |

Mismatched names = silent no-op. This is the #1 web-UI bug. Keep a list of event
names and check both sides.

## REST endpoints (optional)

If `main.py` calls `ui.expose_api("GET", "/samples", fn)`, fetch it:

```js
const samples = await fetch('/samples').then(r => r.json());
```

Use REST for one-shot reads; use Socket.IO for realtime streams. Don't poll a REST
endpoint at high frequency (`frontend.md` rule).

## Vendoring more libraries

Need a chart lib or similar? Download into `assets/libs/` and reference with a
relative path. Never a runtime CDN. From `frontend.md`:

```bash
curl -L -o assets/libs/chart.umd.min.js https://cdn.jsdelivr.net/npm/chart.js
```

```html
<script src="libs/chart.umd.min.js"></script>
```

## Gotchas

- `index.html` **must** exist in `assets/` or the brick fails to start.
- Load `socket.io.min.js` **before** `app.js` (`io` must be defined first).
- Layout is flat (`assets/app.js`, `assets/style.css`, `assets/libs/...`) per the
  shipped examples. The agent-template's nested `assets/js/` layout also works —
  just be consistent. See `references/app-anatomy.md`.

## Done when

The page loads, the socket connects (no disconnect banner), every emitted event
has a matching `ui.on_message` and every `ui.send_message` has a matching
`socket.on`.

Next: `workflow/step6-deploy-test.md`.
