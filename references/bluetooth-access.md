# Bluetooth access to the app (phone ↔ board, no shared Wi-Fi)

Goal: let a customer use the GutGuard web app over Bluetooth when there's no shared
Wi-Fi (e.g. taking the product somewhere new).

## Board BT stack — VERIFIED on NICE-Adruino, 2026-05-27 (via adb)

| Fact | Value |
|---|---|
| BlueZ | **5.82** (`bluetoothctl 5.82`, `bluetoothd` at `/usr/libexec/bluetooth/bluetoothd`) |
| `bluetooth.service` | **active** |
| Controller | `hci0` present, default; not rfkill soft/hard blocked |
| Packages | `bluez 5.82`, `bluez-obexd 5.82`, `libbluetooth3`, `blueman 2.4.4` |

So the board can do classic BT + BLE. (BLE radio is shared with Wi-Fi at the chip level,
but that's separate from the single-Wi-Fi-radio AP/STA constraint in `wifi-ap-captive-portal.md`.)

## Two ways to "use the app over Bluetooth"

### A. BT-PAN (NAP) — recommended for v1
Board runs a **Bluetooth NAP** (Network Access Point) via BlueZ. The phone pairs, connects
to the NAP, gets an IP over Bluetooth, and **opens the existing web app in its browser**
(`app.<name>.local` through the `proxy/` on :80) — **no UI rewrite, reuses everything.**
- Needs: `bnep` kernel module, a bridge (e.g. `pan0`) + a small DHCP range (dnsmasq on the
  bridge), and bluetoothd's `NetworkServer1` NAP role registered (`bt-network -s nap pan0`
  or the D-Bus API). Pairing should be gated (tie to the onboarding passcode / a shown PIN).
- **Works:** Android + Linux/macOS can join a BT-PAN/NAP. **iOS caveat (UNVERIFIED):** iOS
  historically does **not** expose joining an arbitrary BT-PAN — likely a gap for iPhone.

### B. BLE-GATT + client
Expose pet state/meters + key actions as **BLE GATT characteristics**; a Web Bluetooth page
or a companion app reads/writes them. More portable at the radio level, but **not the full
web UI**, and **iOS Safari has no Web Bluetooth** (needs a native app or a browser like Bluefy).

## Recommendation
**BT-PAN (A)** for v1 — it delivers the *whole* app over Bluetooth with the least new code
(reuses the proxy + web app), great on Android/desktop. Flag iOS as a known limitation
(fall back to Wi-Fi or a later native app for iPhone). Reassess if iOS is a hard requirement.

## To verify on hardware before building (G8b)
- `modprobe bnep` succeeds; `bt-network`/`NetworkServer1` registers a NAP.
- A bridge + dnsmasq hands the phone an IP; the phone reaches `:80` over BT.
- Pairing UX + gating (passcode/PIN). iOS PAN-client behaviour on a real iPhone.

`(BlueZ stack VERIFIED; NAP bring-up + client support are the open items.)`
