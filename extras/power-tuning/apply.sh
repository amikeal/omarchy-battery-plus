#!/usr/bin/env bash
# Omarchy power tuning for the MacBook Air 9,1 (T2, Ice Lake).
# Run as your normal user:   bash ~/.config/omarchy/power-tuning/apply.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=/etc/tlp.d/01-omarchy-macbookair.conf

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root — it calls sudo itself."; exit 1; }

PLUGIN=$(cd "$HERE/../.." && pwd)

cat <<EOF
This will:
  • install   tlp  powertop  (pacman)
  • mask      power-profiles-daemon      → omarchy.power profile buttons go inert
  • write     $CONF
  • enable    tlp.service  and apply it now
  • install   /usr/local/bin/battery-plus-priv   (root-owned tuning helper)
  • add       /etc/sudoers.d/battery-plus   (passwordless: tlp, tlp-stat, powertop, battery-plus-priv)
  • add       /etc/udev/rules.d/99-rapl-readable.rules  (RAPL stats without root)
  • restart   the Omarchy shell

thermald is left running. Undo anytime with ./revert.sh
EOF
read -rp $'\nProceed? [y/N] ' a
[[ ${a,,} == y ]] || { echo "aborted"; exit 0; }

echo "==> packages"
sudo pacman -S --needed --noconfirm tlp powertop

echo "==> TLP drop-in"
sudo install -Dm644 "$HERE/tlp-macbookair.conf" "$CONF"
nvme=$(lspci -D 2>/dev/null | awk '/Non-Volatile memory|NVMe/{print $1; exit}')
if [ -n "${nvme:-}" ]; then
  printf '\n# auto-detected on install\nRUNTIME_PM_DENYLIST="%s"\n' "$nvme" | sudo tee -a "$CONF" >/dev/null
  echo "    NVMe $nvme kept out of runtime PM"
fi

echo "==> services"
sudo systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
sudo systemctl mask --now power-profiles-daemon.service 2>/dev/null || true
sudo systemctl enable --now tlp.service
sudo tlp start

echo "==> privileged tuning helper"
if [ -f "$PLUGIN/bin/battery-plus-priv" ]; then
  sudo install -Dm755 -o root -g root "$PLUGIN/bin/battery-plus-priv" /usr/local/bin/battery-plus-priv
  echo "    installed /usr/local/bin/battery-plus-priv"
else
  echo "    (plugin not found at $PLUGIN — skipping; tuning toggles will use pkexec prompts)"
fi

echo "==> passwordless helpers"
tlp_bin=$(command -v tlp); stat_bin=$(command -v tlp-stat); pt_bin=$(command -v powertop)
{
  printf '%s ALL=(root) NOPASSWD: %s, %s, %s\n' "$USER" "$tlp_bin" "$stat_bin" "$pt_bin"
  [ -f /usr/local/bin/battery-plus-priv ] && \
    printf '%s ALL=(root) NOPASSWD: /usr/local/bin/battery-plus-priv\n' "$USER"
} | sudo install -Dm440 /dev/stdin /etc/sudoers.d/battery-plus
sudo visudo -cf /etc/sudoers.d/battery-plus

echo "==> RAPL readable by group wheel"
printf '%s\n' \
  'SUBSYSTEM=="powercap", ACTION=="add", RUN+="/bin/chgrp wheel /sys%p/energy_uj", RUN+="/bin/chmod g+r /sys%p/energy_uj"' \
  | sudo tee /etc/udev/rules.d/99-rapl-readable.rules >/dev/null
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=powercap || true
# apply to the already-registered domains right now
for d in /sys/class/powercap/intel-rapl:*/energy_uj; do
  [ -e "$d" ] && sudo chgrp wheel "$d" && sudo chmod g+r "$d"
done

echo "==> restart shell"
omarchy restart shell 2>/dev/null || true

cat <<EOF

Done.
  • Verify tunables:   sudo tlp-stat -s   /   tlp-stat -b   /   tlp-stat -p
  • Click the Battery+ widget — the Power mode / CPU / device toggles are now live.
  • Baseline your idle draw for a few minutes on battery, screen at a fixed
    brightness, then compare after a reboot (kernel params in README.md).
EOF
