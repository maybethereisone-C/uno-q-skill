# Classic `arduino-cli` for the UNO Q MCU (Zephyr)

**Scope:** use `arduino-cli` ONLY for the MCU sketch side in isolation — quick compiles, CI of the firmware unit, or low-level debugging. **App Lab / `arduino-app-cli` owns real deployment** (it bundles and flashes the sketch as part of an App). Do not use `arduino-cli upload` to flash a sketch that belongs to an App — see `rules/deploy-safety.md`.

## When to reach for it

| Use `arduino-cli` | Use App Lab / `arduino-app-cli` |
|---|---|
| Compile just the `.ino` to check it builds | Build/run/deploy the whole App (Python + sketch) |
| CI: headless build of the firmware unit | Anything touching Bricks, Python, web, AI |
| Isolated MCU debugging | Normal development + on-board run |

## Install (dev host)

Installed on this machine via Homebrew:

```sh
brew install arduino-cli
arduino-cli version
```

(Alternatively: official install script from arduino.github.io/arduino-cli.)

## Board core / FQBN

The UNO Q MCU is a **Zephyr-backed** Arduino target. FQBN: **`arduino:zephyr:unoq`**.

```sh
arduino-cli config init                      # first-time config
arduino-cli core update-index
arduino-cli core install arduino:zephyr      # installs the Zephyr-based core
arduino-cli board listall | grep -i uno      # confirm unoq target is present
```

(unverified) Exact core package id and any extra board-manager URL — confirm with `core search zephyr` / docs.arduino.cc/hardware/uno-q if `core install arduino:zephyr` does not resolve.

## Compile & (isolated) upload

```sh
# compile a sketch directory for the UNO Q MCU
arduino-cli compile -b arduino:zephyr:unoq path/to/sketch

# isolated upload (debug only — NOT for App-owned sketches)
arduino-cli upload  -b arduino:zephyr:unoq -p <port> path/to/sketch
```

Upload on the UNO Q goes through Arduino's **`remoteocd`** tool (a board-platform dependency), not the classic AVR bootloader. (Source: github.com/arduino/remoteocd, github.com/arduino/ArduinoCore-zephyr.)

## Serial monitor

```sh
arduino-cli monitor -p <port> -c baudrate=115200
```

On macOS the port is typically `/dev/cu.usbmodem*`. Note: within an App, prefer `Monitor.println()` on the MCU side + `arduino-app-cli ... monitor` (see `references/arduino-app-cli.md`) over raw serial.

## Zephyr core vs classic AVR — gotchas

- The core is **Zephyr RTOS-based**, not bare-metal AVR. Some classic assumptions (timing of `delay()`, low-level register tricks, AVR-only libraries) do not carry over.
- `Arduino_RouterBridge` (the Bridge library used to talk to the Linux side) is **bundled with the Zephyr core** on recent versions — do **not** hand-install it (see `rules/bridge-anti-patterns.md`). (Zephyr core ≥ 0.55.0 per agent-template docs — version unverified against changelog.)
- Sketches that are part of an App declare their platform in `sketch/sketch.yaml` as `platform: arduino:zephyr` (see `references/app-anatomy.md`).
- The classic CLI has **no visibility** into the Linux/Docker/Python/Bricks side — it sees only the sketch.

## Helper

Use the polished classic-Arduino skill `wedsamuel1230/arduino-skills` (cloned under `skill-sources/arduino-skills/`) for general `arduino-cli` patterns, library management, and serial workflows. This skill owns the UNO Q / App Lab layer that the classic skill does not cover.
