# Step 1 — Scaffold the App

Goal: an empty-but-valid App folder in the right shape, ready to fill in. End
state is a tree that App Lab will accept even before you write logic.

Prereqs: UNO Q reachable (USB or network), App Lab / Arduino App CLI installed on
the board or host. See `references/setup.md` (unverified file name) if not set up.

## 1. Decide the shape

Use `references/app-anatomy.md` to pick which folders you need:

- Touch the MCU (GPIO / Modulino / LED matrix)? → include `sketch/`.
- Want a web page? → include `assets/`.
- `python/main.py` and `app.yaml` are **always** required.

## 2. Create the tree

For a full-stack app (Linux + MCU + UI):

```bash
mkdir -p my-app/python my-app/sketch my-app/assets/libs my-app/assets/img
cd my-app
```

Drop `sketch/` for a browser-only AI app; drop `assets/` for a headless app.

## 3. Copy the templates

Copy from this skill's `templates/` and rename:

```bash
SK=.claude/skills/arduino-uno-q/templates    # adjust to where this skill lives
cp "$SK/app.yaml.tmpl"            app.yaml
cp "$SK/python-main.py.tmpl"      python/main.py
cp "$SK/sketch.ino.tmpl"          sketch/sketch.ino     # if using the MCU
cp "$SK/sketch.yaml.tmpl"         sketch/sketch.yaml     # if using the MCU
cp "$SK/webui-assets/index.html"  assets/index.html      # if using a UI
cp "$SK/webui-assets/app.js"      assets/app.js
cp "$SK/webui-assets/style.css"   assets/style.css
```

## 4. Vendor the Socket.IO client (UI apps only)

The page must be self-contained — no CDN at runtime. Download once and commit:

```bash
curl -L -o assets/libs/socket.io.min.js https://cdn.socket.io/4.7.5/socket.io.min.js
```

(unverified: exact 4.x version the shipped brick pins — 4.7.5 is compatible per
`frontend.md`. If realtime fails to connect, try matching the server's version.)

## 5. Edit the manifest

Open `app.yaml` and set `name`, `icon`, `description`, and the `bricks:` list.
You will refine bricks in Step 2.

## Done when

```
my-app/
├── app.yaml          # named, with at least one brick
├── python/main.py    # template, App.run() present
├── sketch/           # sketch.ino + sketch.yaml (if MCU)
└── assets/           # index.html + app.js + style.css + libs/socket.io.min.js (if UI)
```

Next: `workflow/step2-select-bricks.md`.
