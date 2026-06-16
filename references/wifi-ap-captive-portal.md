# Wi-Fi setup AP + captive portal on the UNO Q

**Status: VERIFIED on real hardware (board `NICE-Adruino`, 2026-05-27).** This is the
0-to-hero playbook for first-run "headless onboarding" on the UNO Q: raise a setup
Wi-Fi AP, serve a captive portal, join the buyer's home Wi-Fi, set the hostname.
Written because App Lab / Bricks have **no** abstraction for host networking — this
was net-new and had no prior reference. First worked implementation lives at
`apps/onboarding/` in this repo; use it as the reference code.

> Why this isn't an App Lab Brick: App Lab apps run in **Docker containers**.
> Raising an AP (hostapd), driving `nmcli` over the host NetworkManager, setting the
> hostname/avahi, and binding port 80 are **privileged host operations a container
> cannot do**. Onboarding therefore runs as a **host-level systemd service**; the
> product (wellness) app stays a normal App Lab app and takes over afterward.

---

## 1. The hard constraint: ONE radio

The UNO Q has a single Wi-Fi radio. `iw list` (verified on NICE-Adruino) reports:

```
valid interface combinations:
  * #{ managed } <= 2, #{ AP, P2P-client, P2P-GO } <= 2, #{ P2P-device } <= 1,
    total <= 4, #channels <= 1
```

So **AP + STA can coexist only on the SAME channel** (`#channels <= 1`). Two
consequences that bite hard:

1. **You cannot scan for home networks while the interface is the AP.** A station
   scan and AP mode can't run at once. → **Scan BEFORE raising the AP and cache the
   result**; serve the cache from the portal.
2. **You cannot join a different-channel home network while broadcasting the AP.**
   The setup AP defaults to 2.4 GHz ch6; home Wi-Fi is often 5 GHz (e.g. ch157). →
   **Defer the actual `nmcli` join to the final step**, after tearing the AP down and
   freeing the radio. Collect creds during the flow, apply once at the end.

## 2. NetworkManager vs hostapd — who owns wlan0

NM manages `wlan0` by default and **auto-reconnects any saved STA profile**, which
**clobbers** a static AP IP and steals the iface from hostapd. Verified failure:
after `ip addr add 192.168.4.1`, NM re-associated to a saved 5 GHz network and
`wlan0` ended up `172.16.x` / `type managed` — portal at 192.168.4.1 unreachable.

**Bring-up order that works (run as root):**
```
nmcli device disconnect wlan0
nmcli device set wlan0 managed no      # stops NM reclaiming the radio
ip addr flush dev wlan0
ip addr add 192.168.4.1/24 dev wlan0
ip link set wlan0 up
systemctl restart <dnsmasq-unit>
systemctl restart <hostapd-unit>
```
**Tear-down (at completion):** stop hostapd + dnsmasq, `ip addr del`, then
`nmcli device set wlan0 managed yes` to hand the radio back so the box uses home
Wi-Fi normally.

## 3. The AP→station settle gotcha (scan returns 0)

After `nmcli device set wlan0 managed yes` (coming off AP mode), NM marks the device
**`unavailable` for several seconds**. A scan fired too soon returns **0 networks**
(observed: `set managed yes` → 3 s sleep → `cached 0`). Fix = **poll then retry**:

```python
prepare_station()                       # sudo nmcli device set wlan0 managed yes
for _ in range(12):                     # up to ~24 s
    if device_state(wlan0) not in ("unavailable", "unmanaged"): break
    sleep(2)
for _ in range(5):                      # rescan retries (first rescan often empty)
    nets = scan()
    if nets: break
    sleep(2)
```
On a **factory boot** `wlan0` starts managed, so the first-boot scan works on the
first try; the poll/retry only matters when a prior run left the iface as the AP.

`nmcli` scan that works (terse, parse it — handle backslash-escaped `:` in SSIDs):
`nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan yes`. Also offer a
**manual SSID entry** in the portal as a fallback (hidden/stale networks).

## 3b. Joining the home network (the `key-mgmt` trap)

`nmcli device wifi connect <ssid> ifname wlan0 password <pw>` works for most WPA2
networks, but some networks/drivers reject it with
**`Error: 802-11-wireless-security.key-mgmt: property is missing`** — nmcli won't
infer the key management (observed on `SuperAISS6_4`). Robust join = two-step:

1. Try the simple `nmcli device wifi connect …` first.
2. On failure (with a password), build an **explicit saved profile** and bring it up,
   trying WPA2-PSK then WPA3-SAE:

```bash
nmcli connection delete <ssid>            # clear any half-made profile (best-effort)
nmcli connection add type wifi con-name <ssid> ifname wlan0 ssid <ssid> \
      wifi-sec.key-mgmt wpa-psk wifi-sec.psk <pw>     # then retry with: key-mgmt sae
nmcli connection up <ssid>
```

A saved profile also auto-reconnects after reboot. Open networks have no fallback.
Implemented in `apps/onboarding/python/onboarding/wifi.py:connect()`, unit-tested with
an injected runner (`tests/test_wifi_connect.py`). **(Code + regression tests done;
confirm the live join on a `key-mgmt`-strict network on hardware — Phase 6.)**

## 4. hostapd + dnsmasq

- `hostapd` is **not preinstalled** on the board image — `apt-get install -y hostapd`
  (bake into the factory image). `dnsmasq`, `avahi-daemon`, `hostnamectl`, `nmcli`,
  `iw` are present. python3 is 3.13 (stdlib `http.server`/`sqlite3` → zero pip deps).
- Mask the **stock** `hostapd`/`dnsmasq` units; run your own scoped units pointed at
  `/etc/gutguard/*.conf` so only your instances bind the AP iface.
- hostapd WPA2 minimal: `wpa=2`, `wpa_key_mgmt=WPA-PSK`, `rsn_pairwise=CCMP`,
  `wpa_passphrase=` (8–63 chars), `driver=nl80211`, `hw_mode=g`, `channel=6`.
- dnsmasq for the AP: `interface=wlan0`, `bind-interfaces`, a `dhcp-range`, and
  **`address=/#/192.168.4.1`** (wildcard DNS → gateway) — this is what makes captive
  detection fire.

## 5. Captive-portal auto-open

Run the portal on **port 80** at the gateway. Return a **302 redirect** (not the
OS's expected success token) for the probe paths so the device shows the portal:
`/hotspot-detect.html` `/library/test/success.html` (iOS/macOS) · `/generate_204`
`/gen_204` (Android) · `/ncsi.txt` `/connecttest.txt` (Windows). Verified: all → 302.

## 6. Privilege model

Run onboarding as a **systemd service with no `User=`** → runs as **root**, so no
password is ever needed (factory-provisioned). For a dev board / running the logic as
the `arduino` user, install a **narrow sudoers allowlist** (specific arg patterns for
`hostnamectl set-hostname *`, `systemctl restart <units>`, `ip addr add/del/flush`,
`nmcli device set * managed *`, `nmcli device disconnect *`) — never blanket sudo.
**Do not** ask the customer to type a Linux/system password in the portal (breaks the
sealed-appliance promise; default-creds-over-open-AP is an IoT security anti-pattern).

## 7. Hostname / mDNS

`hostnamectl set-hostname <name>` + `systemctl restart avahi-daemon` → `<name>.local`.
DNS-safe names only (`a–z 0–9 -`, no leading/trailing hyphen). mDNS is reliable on
Apple, flaky on some Android/Windows → **always also surface the plain LAN IP** at the
end of setup, and print the fixed AP gateway IP (192.168.4.1) on the quick-start card.

## 8. Deploy / test loop (adb over USB survives Wi-Fi/AP changes)

- `adb push` the app to `/home/arduino/ArduinoApps/<app>/` (lands owned `arduino`).
- `adb reboot` / `adb root` are **not supported** on this board image.
- Starting/stopping the service needs root → one `sudo systemctl …` on the board
  terminal (or the systemd boot path). adb stays usable for read-only verification:
  `iw dev`, `ip addr`, `nmcli -t device`, `journalctl -u <svc>`, `ss -ltn`, and
  hitting the portal with `python3 urllib` to `http://192.168.4.1`.

See `apps/onboarding/install/README.md` for the exact provisioning + verification steps.
