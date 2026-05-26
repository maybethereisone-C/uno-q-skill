#!/bin/sh
# board-connect.sh — list connected UNO Q boards over ADB and (optionally) open an SSH shell.
#
# Usage:
#   ./board-connect.sh                 # just list adb devices
#   ./board-connect.sh <board-name>    # list, then ssh arduino@<board-name>.local
#
# Default board name can also come from the UNOQ_BOARD env var.
# SSH requires `arduino-app-cli system network-mode enable` to have been run on the board
# (see ../rules/deploy-safety.md, rule 7). ADB over USB-C always works.
set -eu

BOARD="${1:-${UNOQ_BOARD:-}}"

# Fail loudly if adb is missing.
if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: 'adb' not found on PATH. Install Android platform-tools and connect the UNO Q over USB-C." >&2
  exit 1
fi

echo ">> adb devices (UNO Q should appear as a device):"
adb devices

# Count attached devices (lines after the header that say 'device').
COUNT="$(adb devices | awk 'NR>1 && $2=="device" {n++} END{print n+0}')"
echo ">> attached devices: ${COUNT}"
if [ "${COUNT}" -eq 0 ]; then
  echo "ERROR: no board detected by adb. Connect the UNO Q over USB-C and retry." >&2
  exit 1
fi

# If no board name was given, stop here — we only listed devices.
if [ -z "${BOARD}" ]; then
  echo ">> No board name provided; skipping SSH. Pass a name (or set UNOQ_BOARD) to open a shell."
  echo "   e.g. ./board-connect.sh my-board   ->   ssh arduino@my-board.local"
  exit 0
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "ERROR: 'ssh' not found on PATH; cannot open a shell to ${BOARD}.local." >&2
  exit 1
fi

echo ">> Opening SSH: ssh arduino@${BOARD}.local"
echo "   (requires network-mode enabled on the board; password is the 'arduino' user's password)"
exec ssh "arduino@${BOARD}.local"
