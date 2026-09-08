#!/usr/bin/env bash
# Battery+ — install the BCM4377b (Intel MacBook Air 9,1 / T2) suspend fix.
# Run as your normal user:   bash extras/wifi-suspend-fix/apply.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK=/usr/lib/systemd/system-sleep/battery-plus-wifi-suspend-fix
RULE=/etc/udev/rules.d/81-battery-plus-disable-wifi-wakeup.rules

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root — it calls sudo itself."; exit 1; }

if ! lspci -nn 2>/dev/null | grep -q '14e4:4488'; then
  echo "This machine doesn't report a BCM4377b (PCI 14e4:4488) Wi-Fi adapter —"
  echo "this fix is specific to that chip and is unlikely to help here."
  read -rp "Install anyway? [y/N] " a
  [[ ${a,,} == y ]] || { echo "aborted"; exit 0; }
fi

cat <<EOF
This will:
  • install   $HOOK
                (unloads brcmfmac before suspend, reloads it after resume —
                works around a known PCI power-management timeout on this
                chip that can otherwise crash-loop suspend and drain the
                battery in hours)
  • install   $RULE
                (stops the Wi-Fi card being armed as a suspend wakeup source)

Undo anytime with ./revert.sh
EOF
read -rp $'\nProceed? [y/N] ' a
[[ ${a,,} == y ]] || { echo "aborted"; exit 0; }

sudo install -Dm755 -o root -g root "$HERE/battery-plus-wifi-suspend-fix" "$HOOK"
sudo install -Dm644 -o root -g root "$HERE/81-disable-wifi-wakeup.rules" "$RULE"
sudo udevadm control --reload
addr=$(lspci -Dnn 2>/dev/null | awk '/14e4:4488/{print $1; exit}')
if [ -n "$addr" ]; then
  sudo udevadm trigger --action=add --subsystem-match=pci --sysname-match="$addr" || true
fi

cat <<EOF

Done. Verify next time the laptop sleeps:
  cat /sys/power/suspend_stats
  journalctl -t battery-plus-wifi-suspend-fix -b
EOF
