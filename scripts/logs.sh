#!/bin/sh
# logs.sh — show the Python-side logs of an App on the UNO Q (`arduino-app-cli app logs --all`).
#
# Uses `adb shell -t` so streaming/following works over a TTY.
# NOTE: this shows the PYTHON side only. For MCU serial output use:
#   adb shell -t arduino-app-cli monitor
#
# Usage:
#   ./logs.sh <app-name> [--follow]
#
#   app-name   Directory name under /home/arduino/ArduinoApps. Required.
#   --follow   Stream new logs as they arrive (in addition to --all history).
#
# Examples:
#   ./logs.sh my-app
#   ./logs.sh my-app --follow
set -eu

APP="${1:-}"
if [ -z "${APP}" ]; then
  echo "ERROR: app name required.  Usage: ./logs.sh <app-name> [--follow]" >&2
  exit 1
fi
shift || true

FOLLOW=""
if [ "${1:-}" = "--follow" ] || [ "${1:-}" = "-f" ]; then
  FOLLOW="--follow"
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: 'adb' not found. Connect the UNO Q over USB-C and install platform-tools." >&2
  exit 1
fi

echo ">> Verifying board is attached..."
if [ "$(adb devices | awk 'NR>1 && $2=="device" {n++} END{print n+0}')" -eq 0 ]; then
  echo "ERROR: no board detected by adb." >&2
  exit 1
fi

DEST="/home/arduino/ArduinoApps/${APP}"
echo ">> Logs for ${DEST}  (--all ${FOLLOW})"
# -t allocates a TTY so --follow streams interactively.
exec adb shell -t arduino-app-cli app logs "${DEST}" --all ${FOLLOW}
