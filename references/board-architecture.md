# UNO Q Board Architecture — the mental model

The Arduino UNO Q is a **dual-brain** board. Internalize this first; almost every design decision follows from it.

```
┌──────────────────────── Arduino UNO Q ─────────────────────────┐
│                                                                 │
│   ┌─────────────────────────┐      ┌─────────────────────────┐  │
│   │  MPU  (the "Linux brain")│      │  MCU  (the "real-time   │  │
│   │  Qualcomm Dragonwing     │      │       brain")           │  │
│   │  QRB2210                 │◄────►│  STM32U585              │  │
│   │  quad Cortex-A53 @ 2GHz  │ Bridge│  Arduino Core on Zephyr │  │
│   │  Debian Linux + Docker   │ (RPC) │  (RTOS)                 │  │
│   │                          │      │                         │  │
│   │  • Python "Bricks"       │      │  • GPIO / pins          │  │
│   │  • AI models (.eim)      │      │  • timing-critical I/O  │  │
│   │  • web app / dashboard   │      │  • sensors / actuators  │  │
│   │  • on-device LLM         │      │  • PWM / I2C / SPI / ADC │  │
│   │  • networking, storage   │      │  • interrupts           │  │
│   └─────────────────────────┘      └─────────────────────────┘  │
│                                                                 │
│   Wi-Fi 5 (2.4/5GHz) + BT 5.1 · USB-C (host/device/power +      │
│   video out) · I2C/I3C, SPI, PWM, CAN, UART, GPIO, ADC          │
└─────────────────────────────────────────────────────────────────┘
```

## The two processors

| | MPU — Linux brain | MCU — real-time brain |
|---|---|---|
| Chip | Qualcomm Dragonwing **QRB2210**, quad-core Arm **Cortex-A53 @ 2.0 GHz** | **STM32U585** |
| Runs | **Debian Linux** (upstream-supported) + **Docker / Docker Compose** | **Arduino Core on Zephyr** RTOS |
| You write | **Python** (Bricks, app logic, AI, web) | **C/C++ sketch** (`.ino`) |
| Good at | AI inference, web/UI, networking, heavy compute, storage | deterministic timing, GPIO, sensors, low-latency I/O |
| Deployed by | App Lab / `arduino-app-cli` (Apps run as containers) | App Lab (bundled with the App); or `arduino-cli` for isolated builds |

Source: official store/spec page (store.arduino.cc/products/uno-q, SKU ABX00162) and docs.arduino.cc/hardware/uno-q.

## The golden rule: right brain for the job

- **Timing-critical, pin-level, or interrupt-driven work → MCU sketch.** Reading a sensor at a fixed rate, debouncing a button, driving a servo, bit-banging a protocol.
- **Everything else (Python, AI, web, LLM, networking, files) → Linux/MPU.** Camera vision, the dashboard, the on-device language model, databases.
- The two halves talk over the **Bridge** (an RPC link served by the `arduino-router` service). See `references/bridge-rpc.md` for the full API — do not duplicate sensor-reading logic across both; pick the right side and bridge the result.

## RAM variants (matters a lot)

| Variant | RAM | Storage | Use for |
|---|---|---|---|
| 2 GB | 2 GB | (smaller) | light apps; tight once Docker + AI + web run together |
| **4 GB** | **4 GB** | **32 GB eMMC** | **required for on-device LLM + vision + web simultaneously** |

For an on-device LLM + camera AI + local web app, the **4 GB / 32 GB variant is required**. See `rules/resource-limits.md`.

## OS & runtime model

- The MPU runs full **Debian Linux**; App "Bricks" run inside **Docker containers** managed by App Lab / `arduino-app-cli`.
- Networking: **Wi-Fi 5** (2.4/5 GHz) + **Bluetooth 5.1**. The board is reachable on the LAN (e.g. `arduino@<board>.local` via SSH, or `adb`).
- **USB-C** does host/device/power-role switching and carries **video output** (you can drive a display).
- Rich interface set on the headers: **I2C/I3C, SPI, PWM, CAN, UART, PSSI, GPIO, JTAG, ADC**. UNO form factor (68.85 × 53.34 mm).

## Why this board (vs a classic Arduino)

A classic Arduino is *just* the MCU side. The UNO Q adds a full Linux computer next to it, so a single board can run real AI, host a web app, and still do hard-real-time I/O. That is why you cannot build a UNO Q product with the classic Arduino IDE alone — it only addresses the MCU third. See `references/arduino-cli-zephyr.md` and `references/arduino-app-cli.md`.
