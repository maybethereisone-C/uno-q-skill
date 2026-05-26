# Troubleshooting & Gotchas — Arduino UNO Q

Practical symptom → cause → fix guide for App Lab apps on the UNO Q. Entries are sourced from official Arduino docs / the agent contract (authoritative) and enriched with field tips from a Thai tutorial series. Tips are labelled **[official]**, **[tutorial: EPxx]**, or **[tutorial, unverified]** where the transcript implied something not confirmed in official docs.

Related rules: [../rules/best-practices.md](../rules/best-practices.md) · [../rules/quality-standards.md](../rules/quality-standards.md)

---

## Setup & OS install

### Board won't enter setup / "Outdated OS" warning in App Lab
- **Cause:** the shipped OS predates your App Lab version. App Lab flags it before you can build (EP2).
- **Fix (current, 0.6.0+):** in App Lab → **Settings/Flash**, pick the Debian image and choose **"Clear all data"**, let it download/extract, then enter **flash mode** (unplug power → use a **jumper to short the J control pins** → re-power), watch the progress (~5 min on the 4 GB board), then **remove the jumper and USB before rebooting**. **[tutorial: EP77]**
- **Fix (older flow):** download the standalone **Arduino Flasher CLI** from arduino.cc, short the outermost pins to enter flash mode, run the flash command (downloads ~2.3 GB image), power-cycle, remove jumpers. **[tutorial: EP2]**
- **Gotcha:** flashing **erases the board** ("Clear all data"). Back up `/home/arduino/ArduinoApps/` first if needed.
- **Verify success:** the Qualcomm and STM LEDs / "heart" boot indicator behave normally after power-cycle (EP2). **[tutorial: EP2]**

### First-boot setup: Wi-Fi connection fails
- **Symptom:** Wi-Fi step errors out during initial setup.
- **Fix:** **restart the App Lab app and re-plug the board**, then retry the Wi-Fi step — the tutorial hits this and recovers exactly this way. **[tutorial: EP3]**
- Have ready before you start: Wi-Fi SSID + password, a board name, and the user password you'll set. **[tutorial: EP3]**

### After flashing, things behave oddly / CLI missing features
- **Cause:** stale on-board components (Server, ADBD, CLI).
- **Fix:** run the **system update** in setup (or `arduino-app-cli update`) right after flashing to pull the latest core components **before** building apps. **[tutorial: EP3, EP77]**

### First-run sudo / password
- You set the **user password during initial setup** (EP3/EP77). That's the password for SSH and for `sudo` on the board. If you skipped/forgot it, you can reset board name/network/password later from App Lab settings. **[tutorial: EP3, EP77]**

---

## Connecting to the board

### Board not detected over USB (adb)
- **Cause:** wrong cable, wrong mode, or ADBD not up.
- **Fix:**
  - Use a **data-capable USB-C cable** (not power-only) — the single USB-C provides both power and data in **PC Host Mode**. **[tutorial: EP63]**
  - Confirm it appears in App Lab's board-status panel (shows USB, serial number, storage, RAM, CPU, internet). **[tutorial: EP4]**
  - Off-board CLI runs through `adb shell arduino-app-cli ...`; if adb sees nothing, re-plug and re-run `update`. **[official]**

### Can't SSH / want wireless (no USB)
- **Fix:** enable **Network Mode** (`arduino-app-cli network-mode`, or via App Lab) to put the board on Wi-Fi/LAN, then SSH in from your Mac/PC. Useful for headless installs in hard-to-reach spots. **[tutorial: EP7]**
- Find the board on the network via App Lab (it lists the device) or your router; then `ssh arduino@<board-ip>` with the password set at setup. **[tutorial: EP7]**

---

## Running apps

### App won't start
- **Check `App.run()` is the LAST line** of `python/main.py` — anything after it is ignored, and a misplaced call means your app effectively never runs. **[official]**
- **Check `app.yaml`** lists every Brick you imported under `bricks:`. A missing entry = import/start failure. **[official]**
- **WebUI fails to start:** `assets/index.html` MUST exist at the configured `assets_dir_path` (default maps to repo `assets/`). No index, no UI. **[official]**
- View failures: `arduino-app-cli log` (Python side) + the **Serial Monitor** (MCU side). **[tutorial: EP63]**

### Bridge call silently does nothing
- **#1 cause: argument type mismatch.** Python `int/float/bool/str` must match C++ `int/float/bool/const char*`. Mismatches **fail silently** — no error at all. Coerce explicitly (`int(x)`, `float(x)`) before calling. **[official]**
- **#2 cause: RPC service-name typo.** The name string must be **identical** on both sides. **[tutorial: EP57]**
- **#3 cause:** you called `Bridge.call(...)` or `Monitor.print(...)` **inside a `Bridge.provide*` callback** → deadlock. Move the outbound call to a periodic loop or a queue. **[official]**

### System hangs / freezes intermittently when MCU touches hardware
- **Cause:** a hardware-touching callback exposed with plain `Bridge.provide` runs in the Bridge thread and **races the main loop** for the hardware, and can fail the Linux↔MCU **handshake**. **[tutorial: EP57]**
- **Fix:** expose it with **`Bridge.provide_safe`** so it's queued into `loop()` context. Use plain `provide` only for non-hardware, non-Arduino-API work. **[official + tutorial: EP57]**
- **Also:** never use the **high-speed UART reserved for the Arduino Router** for your own serial — it carries Bridge traffic and using it breaks the system. **[tutorial: EP57, unverified]**

### Long MCU `delay()` or Python `time.sleep()` makes everything unresponsive
- **Cause:** blocking longer than a few ms starves the Bridge — it can't service requests. **[official]**
- **Fix:** non-blocking `millis()` timing on the MCU; short or no `sleep` in Python loops/callbacks. For long MPU computation, use the async **`RpcCall` + result-polling** pattern so the MCU loop keeps running. **[tutorial: EP72]**

---

## AI Bricks, camera & models

### Brick/model seems to "hang" on first run
- **Cause:** AI Bricks are Docker containers; the **first run downloads the image/model** and is slow. **[tutorial: EP4, EP54]**
- **Fix:** wait it out; subsequent runs are fast. Don't kill it as a hang. Check internet in the board-status panel. **[tutorial: EP4]**

### Out of memory on the 4 GB (or 2 GB) board
- **Cause:** multiple heavy AI Bricks / large models loaded at once; RAM (not CPU) is the ceiling.
- **Fix:** **run AI tasks one at a time**; sequence them. Prefer the **4 GB SKU** for any vision/audio work. Export models small: appropriate input size (e.g. **96×96**), **grayscale** where acceptable, **int8 quantization**. **[tutorial: EP31, EP36]**

### Camera / model not loading
- Confirm the camera peripheral is wired/declared and the Brick that consumes it is in `app.yaml`. **[official]**
- For a custom `.eim` model, confirm `app.yaml` points at the **correct file path** and uses the **right key for the model type** (Object Detection vs Visual Anomaly vs Classification differ). **[tutorial: EP33]**

### Poor accuracy / model behaves worse on-device than in training
- **Cause:** real lighting/mic/background differs from the training set; class imbalance; too-small dataset.
- **Fix:** balance classes; KWS needs Keyword + **Unknown** + **Noise** categories and diverse voices/environments; min ~30 samples/class, production 100–300. For object detection, label tight bounding boxes and use **FOMO**. Re-validate accuracy + inference time + RAM/Flash in Edge Impulse before re-deploy. **[tutorial: EP31, EP36]**

---

## Edge Impulse `.eim` deployment

### Steps to deploy a trained model (the working sequence)
1. In Edge Impulse, **set the target board to Arduino UNO Q**, train, then **Deployment → export as the Arduino UNO Q `.eim` binary**. **[tutorial: EP31, EP33]**
2. Format a USB flash drive as **FAT32**, copy the `.eim` onto it. **[tutorial: EP33]**
3. In App Lab, **create the app/container** for the model type.
4. SSH into the board (Network Mode). Identify the USB drive (often `sdb1`), **mount** it, `mkdir` a storage dir, and **copy the `.eim`** from USB into the board's internal storage. **[tutorial: EP33]**
5. Edit `app.yaml` with `nano` to **point at the custom model file**. **Unmount** the USB when done. **[tutorial: EP33]**

### `.eim` deployed but inference is broken / error rate high — config syntax
- **Cause:** a **syntax error in `app.yaml`** (e.g. a **missing bracket**) for the model entry. The app still "runs" but the model misbehaves. This was the exact failure corrected in the repair clip. **[tutorial: EP35]**
- **Fix:** SSH in (Network Mode), open `app.yaml` in `nano`, and **match the model block precisely to the official example for that model type**. A small slip silently degrades results. **[tutorial: EP35]**
- **Gotcha:** model-type config keys differ between Object Detection / Visual Anomaly Detection / Image Classification — copy the right example. **[tutorial: EP33, EP35]**

---

## Cloud Bricks (LLM / ASR)

### Cloud LLM/ASR Brick fails or returns nothing
- **Needs internet** + a valid **API key** (Gemini via Google AI Studio, OpenAI Platform, or Anthropic Console). No connection / bad key = silent failure or error. **[tutorial: EP51]**
- **Deploy the API key via App Lab app config — do NOT hardcode it in `main.py`.** **[tutorial: EP51 + official secrets rule]**
- Tune behavior with system prompt / temperature / **timeout** params; a too-short timeout on a slow network looks like a failure. **[tutorial: EP51]**

---

## Storage / database / autostart

### Where does Database (SQL / Time-Series) data live?
- Data persists on the board's Linux filesystem; explore it over **SSH** to confirm the DB file exists. Define schema (tables/fields/primary key) in Python via the `SQLStore` class; primary keys prevent duplicate records. **[tutorial: EP16, EP17]**

### Make an app run headless on power-up
- Use App Lab → **Run at Startup** to set a default app (a "default" tag marks it in My Apps). The board then runs it standalone (e.g. on a power bank), no PC needed. **Disable Run at Startup when you reconnect to a PC for development**, or it relaunches. **[tutorial: EP62]**

---

## Docker / containers

- Bricks run as **Docker containers** on the Linux side — that is why the first launch downloads and is slow, and why RAM pressure matters when several are active. **[tutorial: EP4, EP54]**
- If a Brick won't start after edits, `arduino-app-cli clean-cache` (app) and re-deploy; `clean-up` (system) clears accumulated state. **[tutorial: EP63]**
- If containers behave oddly after an OS update, run `arduino-app-cli update` then `reboot`. **[tutorial: EP63, unverified]**

---

## Quick triage checklist

1. Board in status panel? → cable/mode/`update`.
2. App starts? → `App.run()` last line; Bricks in `app.yaml`; `index.html` for WebUI.
3. Bridge call does nothing? → arg types match; service names match; not called inside a `provide*` callback.
4. System hangs on hardware access? → use `provide_safe`; no long `delay`/`sleep`.
5. Model wrong/slow? → first-run download; one model at a time; `app.yaml` model block matches the official example exactly.
6. Cloud Brick silent? → internet + API key (deployed via config, not inlined).
