#!/bin/sh
# new-app.sh — scaffold a new Arduino App on the UNO Q via `arduino-app-cli app new`.
#
# Runs the scaffold ON THE BOARD through `adb shell`. Creates
#   /home/arduino/ArduinoApps/<name>/   with app.yaml, README.md, python/main.py,
#   and (unless --no-sketch) sketch/sketch.ino + sketch/sketch.yaml.
#
# Usage:
#   ./new-app.sh <app-name> [extra arduino-app-cli flags...]
#
# Examples:
#   ./new-app.sh my-app
#   ./new-app.sh smart-garden -i "garden" -d "AI irrigation" -b arduino:dbstorage
#   ./new-app.sh py-only --no-sketch
#
# Supported `app new` flags (passed straight through): -i/--icon, -d/--description,
# -b/--bricks (repeatable), --from-app <path>, --no-sketch.   See ../references/arduino-app-cli.md.
set -eu

APP="${1:-}"
if [ -z "${APP}" ]; then
  echo "ERROR: app name required.  Usage: ./new-app.sh <app-name> [flags...]" >&2
  exit 1
fi
shift  # remaining args are extra flags for `app new`

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: 'adb' not found. Connect the UNO Q over USB-C and install platform-tools." >&2
  exit 1
fi

echo ">> Verifying board is attached..."
if [ "$(adb devices | awk 'NR>1 && $2=="device" {n++} END{print n+0}')" -eq 0 ]; then
  echo "ERROR: no board detected by adb." >&2
  exit 1
fi

echo ">> Creating app '${APP}' on the board: arduino-app-cli app new \"${APP}\" $*"
# shellcheck disable=SC2086  # we intentionally word-split the passthrough flags
adb shell arduino-app-cli app new "${APP}" "$@"

DEST="/home/arduino/ArduinoApps/${APP}"
echo ">> Done. App scaffolded at ${DEST} on the board."
echo "   Next: edit code on your host, then deploy with:  ./deploy.sh ${APP}"
echo "   (To pull the scaffold to your host:  adb pull ${DEST} ./${APP})"
