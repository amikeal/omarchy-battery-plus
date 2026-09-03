# Battery+

A richer replacement for the built-in `omarchy.power` bar widget, built for
this T2 MacBook Air. Left-click opens a panel anchored under the icon (like
the Wi-Fi / display panels) with:

- **Hero** — battery glyph, charge %, and live mode (`ON BATTERY · 9.6 W`).
- **Charge bar** — animated, pulses while charging.
- **Stats** — time left, draw, health, cycles, capacity (Wh), temperature.
- **Power draw** — a rolling sparkline of the last ~60 samples (Intel RAPL
  package power when readable, otherwise the battery's own draw).
- **Power mode** — `Auto` / `Saver` / `Full power` segmented control
  (drives `tlp start` / `tlp bat` / `tlp ac`).
- **CPU** — turbo-boost toggle + energy-preference segmented control (EPP).
- **Device power saving** — Wi-Fi powersave, PCIe runtime PM, USB
  autosuspend (HID excluded), audio codec powersave. Applied for the
  session; make them permanent in the TLP config.
- **Top consumers** — the six busiest process groups with mini bars.
- **PowerTOP scan** / **Full dashboard** buttons open a floating terminal.

Right-click the icon toggles the inline percentage.

## Files

```
manifest.json               plugin manifest (bar-widget, id mikeal.battery-plus)
Panel.qml                   bar button + anchored panel UI
PowerService.qml            runs bin/ helpers, exposes their JSON as reactive state
Model.js                    pure formatting/derivation helpers
bin/battery-plus-data       emits one JSON blob (fast, no privileges)
bin/battery-plus-action     performs an action, then re-emits data
bin/battery-plus-priv       the only privileged entry point (see below)
extras/power-tuning/        TLP install/revert + drop-in config for this MacBook
extras/battery-dashboard    gum TUI opened by the panel's "Full dashboard" button
extras/battery-common.sh    shared battery probe for the TUI
```

`extras/` is a working copy; `~/.config/omarchy/power-tuning/` and
`~/.config/omarchy/bar/scripts/` hold the live copies this machine uses.

## Privileges

The power-mode, CPU, and device toggles need root. `../power-tuning/apply.sh`
installs `bin/battery-plus-priv` to **`/usr/local/bin/battery-plus-priv`**
(root-owned) and whitelists exactly that path in `/etc/sudoers.d/battery-plus`,
so the panel runs it through `sudo -n` with no prompt. Every branch of that
helper is a fixed operation on a fixed sysfs path — no caller string is ever
executed or used to build a path. Without it the panel falls back to a
`pkexec` prompt per action, and the whole tuning section is hidden until TLP
is installed.

## Settings (`shell.json` inline)

| key              | default | meaning                                   |
|------------------|---------|-------------------------------------------|
| `showPercentage` | `true`  | show `%` next to the bar icon             |
| `pollIntervalSec`| `5`     | refresh cadence while the panel is open   |

## Install / remove

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable mikeal.battery-plus     # adds it to the bar (right section)
omarchy plugin disable mikeal.battery-plus    # removes it; re-enable omarchy.power if wanted
```

Editing any file here hot-reloads bindings; structural QML changes need
`omarchy restart shell`.
