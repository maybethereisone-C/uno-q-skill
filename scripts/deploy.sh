#!/bin/sh
# deploy.sh — push a local App directory to the UNO Q, fix ownership, and (re)start it.
#
# Implements the canonical off-board deploy loop (see ../references/arduino-app-cli.md sec.10
# and ../rules/deploy-safety.md):  mkdir -> adb push -> chown -> app stop -> app start.
#
# Usage:
#   ./deploy.sh [app-name] [local-source-dir]
#
#   app-name         Directory name under /home/arduino/ArduinoApps on the board.
#                    Default: the basename of the source dir.
#   local-source-dir Local folder to push. Default: current directory ".".
#
# Examples:
#   cd ~/projects/my-app && /path/to/deploy.sh          # push CWD -> user:my-app
#   ./deploy.sh my-app ~/projects/my-app                # explicit name + source
set -eu

SRC="${2:-.}"
# Resolve a clean absolute-ish basename for the default app name.
APP="${1:-$(basename "$(cd "${SRC}" && pwd)")}"
DEST="/home/arduino/ArduinoApps/${APP}"

if [ ! -d "${SRC}" ]; then
  echo "ERROR: source dir '${SRC}' does not exist." >&2
  exit 1
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

echo ">> Deploying '${SRC}'  ->  board:${DEST}"

echo ">> [1/5] mkdir -p ${DEST}"
adb shell "mkdir -p ${DEST}"

echo ">> [2/5] adb push ${SRC}/ -> ${DEST}/"
adb push "${SRC}/" "${DEST}/"

# MANDATORY: adb writes as root; the App runs as 'arduino'. See deploy-safety.md rule 1.
echo ">> [3/5] chown -R arduino:arduino ${DEST}  (mandatory after every push)"
adb shell "chown -R arduino:arduino ${DEST}"

echo ">> [4/5] stop (ignore error if not running)"
adb shell arduino-app-cli app stop "${DEST}" 2>/dev/null || true

# `app start` compiles+flashes the MCU sketch and launches the Python side. Do NOT use arduino-cli upload.
echo ">> [5/5] start (compiles/flashes MCU + launches Python)"
adb shell arduino-app-cli app start "${DEST}"

echo ">> Deployed and started '${APP}'."
echo "   Tail logs:    ./logs.sh ${APP}"
echo "   MCU serial:   adb shell -t arduino-app-cli monitor"
