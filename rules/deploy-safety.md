# Deploy Safety Rules — Arduino UNO Q

Prescriptive DO/DON'T for pushing and running Arduino Apps on the UNO Q. These are hard rules; the
"why" cites the cloned repo (`skill-sources/arduino-app-cli/`, `arduino-uno-q-agent-template/docs/agent/`).

---

## 1. Ownership: `chown` after every push (MANDATORY)

- **DO** run `adb shell "chown -R arduino:arduino <DEST>"` immediately after **every** `adb push`.
- **DON'T** skip it "because it worked last time."

Why: `adb` writes files as `root` (or the adbd user), but the App, its Python container, and
`arduino-app-cli` run as the **`arduino`** user (`ARDUINO_APP_CLI__ALLOW_ROOT` defaults to `false`,
and the board image does `chown -R arduino:arduino /home/arduino`). Files owned by root cause
permission failures on `app start`, log writes, and `.cache` builds. The canonical deploy loop in
`docs/agent/cli.md` always chowns after push. `scripts/deploy.sh` does this for you.

---

## 2. First run may prompt for `sudo` / the board password

- **DO** expect the first board operation (especially installing the CLI via the repo's
  `task board:install`, or a privileged `system` action) to ask for the **`arduino` user's password**.
- **DO** run it from an interactive terminal the first time so you can answer the prompt
  (`adb shell -t ...` allocates a TTY).
- **DON'T** wrap a first-run privileged command in a non-interactive script and assume it succeeds —
  it will hang or fail waiting for input.

Why: `docs/development.md` ("Running Arduino App CLI on the board") notes the `arduino` user's
password is requested during board install. Normal `app`/`logs` lifecycle commands do not need sudo;
some `system` operations and provisioning do.

---

## 3. Flashing the MCU is App Lab's / `app start`'s job — NOT `arduino-cli upload`

- **DO** flash and run the sketch via `arduino-app-cli app start <app_path>` (or App Lab's Run).
  That command compiles the sketch in `sketch/` and programs the integrated microcontroller as part
  of bringing the App up.
- **DON'T** use `arduino-cli upload` (or the Arduino IDE upload) to push the MCU half of an App.

Why: an Arduino App is a coordinated pair — Python on Linux + sketch on the MCU, joined over the
arduino-router RPC bridge (`docs/app-specification.md`). `app start` orchestrates building/flashing
the sketch and starting the Python side together. A manual `arduino-cli upload` bypasses the App
orchestration, can desync the bridge, and leaves the App in a "broken" state (it shows up under
`app list --show-broken-apps`). Standalone `arduino-cli` is fine for non-App, plain sketches only.

---

## 4. OTA / system updates: back up first, and understand auto-update

- **DO** back up before `arduino-app-cli system update`: export your Apps
  (`arduino-app-cli app export <app> backup.zip --include-data`) and/or `adb pull` the App
  directories to your host.
- **DO** prefer scoped updates when you only need part: `--only-arduino`, `--only-docker-images`,
  or `--only-arduino-platform`.
- **DON'T** run `system update --yes` (auto-confirm all prompts) on a board mid-project without a
  backup — it can pull new platform/library/docker-image versions that change behavior under you.
- **BE AWARE**: `arduino-app-cli` "auto-updates itself and other components" (README.md). The
  component surface (bricks, models, platform) is versioned under `/var/lib/arduino-app-cli/assets/<version>/`,
  so an update can shift the available bricks/models list.

Why: this is pre-1.0 software (binary version `0.0.0-dev`); updates may introduce breaking changes.
Backups are cheap; a bricked mid-hackathon board is not.

---

## 5. Don't edit live App files without restarting

- **DON'T** edit files inside a running App and expect changes to take effect.
- **DO** push your edits, then **restart**: `arduino-app-cli app restart <app_path>` (or
  `app stop` + `app start`). `scripts/deploy.sh` always stops/pushes/chowns/starts.

Why: the Python side runs in a container and the MCU runs the already-flashed sketch. Source changes
on disk are not hot-reloaded — only a restart recompiles/reflashes the sketch and relaunches Python
with the new code. Editing in place gives confusing "my change didn't do anything" results.

---

## 6. Reclaim disk before it bites you

- **DO** run `arduino-app-cli system cleanup` (removes unused/obsolete app images + networks) and
  `arduino-app-cli app clean-cache <app-id>` when builds start failing for no clear reason or disk
  is low.
- **DON'T** `clean-cache --force` a running app unless you intend to disrupt it.

Why: app builds cache docker images and deps; the board's storage is small. `cleanup` and
`clean-cache` are the supported reclaim paths.

---

## 7. SSH / network mode is off until you enable it

- **DO** run `arduino-app-cli system network-mode enable` before relying on
  `ssh arduino@<board-name>.local`. Check with `system network-mode status`.
- **DON'T** assume SSH is reachable on a fresh board; `adb` over USB-C is the always-available
  transport.

Why: `network-mode` gates the board's network/SSH exposure (`cmd/.../system/system.go`).

---

## 8. Destructive commands — confirm intent

- `app destroy <app_path>` **deletes** the App. `app clean-cache` deletes its build cache.
  `model delete --force` removes an in-use model.
- **DO** double-check the `app_path` / id (a wrong `user:` shortcut can target the wrong app).
- **DON'T** script these without an explicit confirmation step.

---

## Quick pre-deploy checklist

1. `adb devices` shows the board.
2. Code edited **on the host**, not on the live board.
3. `deploy.sh` (push → `chown -R arduino:arduino` → stop → start) — never push without chown.
4. MCU flashing left to `app start`; no `arduino-cli upload` on App sketches.
5. Backed up before any `system update`.
6. Restarted (not edited-in-place) to load changes.
