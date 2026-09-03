# Battery+ / power tuning — MacBook Air 9,1 (T2, Ice Lake)

## What's here

| File | Purpose |
|------|---------|
| `tlp-macbookair.conf` | TLP drop-in, installed to `/etc/tlp.d/01-omarchy-macbookair.conf` |
| `apply.sh` | Install TLP + PowerTOP, apply the tuning, wire up the widget |
| `revert.sh` | Undo `apply.sh`, restore `power-profiles-daemon` |

The bar widget is separate, in `~/.config/omarchy/bar/scripts/`:
`battery-plus` (bar JSON), `battery-dashboard` (TUI), `battery-common.sh`,
`battery-tlp-toggle` (right-click).

## Apply

```bash
bash ~/.config/omarchy/power-tuning/apply.sh
```

Then, on battery with the screen at a fixed brightness, watch the widget
tooltip (or `watch -n5 'cat /sys/class/power_supply/BAT0/current_now'`) for a
few minutes to get a baseline, and compare after each change below.

## Why Linux trails macOS here — in priority order

1. **Screen brightness.** 2560×1600 backlight is the biggest single draw.
   Each notch ≈ 0.3–0.5 W. Keyboard backlight off when unused.
2. **Browser.** Chromium/Chrome is normally the #1 process. Fewer background
   tabs; enable its Energy Saver; `chrome://discards`.
3. **Peripherals never sleeping** → fixed by TLP (`RUNTIME_PM=auto`).
4. **Wi-Fi power-save off** → fixed by TLP on battery.
5. **CPU energy bias** (`balance_power` + turbo) → TLP sets `power` + no
   turbo on battery.
6. **The T2 tax.** The T2, the Apple NVMe, and the `apple-bce` audio/HID
   bridge have no deep Linux sleep state. Expect a permanent ~1–2 W you
   can't recover. Realistic Linux idle: **~7–9 W (≈ 4–5 h)** vs ~5–6 W on
   macOS. TLP typically buys back **1.5–3 W** from the ~12 W baseline.

## Optional: kernel parameters (advanced, one at a time)

Edit the `cmdline` in `/boot/limine.conf` (Omarchy's `omarchy-refresh-limine`
will reset it — keep a note of your additions), reboot, and re-baseline.
Roll back the last one if suspend, Wi-Fi, or the display misbehave.

| Param | Effect | Risk |
|-------|--------|------|
| `pcie_aspm=force` | ASPM on links the firmware left off | low–med |
| `i915.enable_psr=1` | Panel Self Refresh (idle-screen power) | can flicker |
| `i915.enable_fbc=1` | Framebuffer compression | low |

`mem_sleep_default=deep` is already set by Omarchy.

## Verify

```bash
sudo tlp-stat -s      # overall + which mode is active
sudo tlp-stat -b      # battery detail
sudo tlp-stat -p      # CPU / pstate
sudo tlp-stat -r      # runtime-PM per device
powertop              # interactive; Tab to "Tunables" / "Overview"
```

## Undo

```bash
bash ~/.config/omarchy/power-tuning/revert.sh
```
