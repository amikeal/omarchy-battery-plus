#!/usr/bin/env bash
# Battery+ — remove the BCM4377b suspend fix. Run as your normal user.
set -euo pipefail

sudo rm -f /usr/lib/systemd/system-sleep/battery-plus-wifi-suspend-fix
sudo rm -f /etc/udev/rules.d/81-battery-plus-disable-wifi-wakeup.rules
sudo udevadm control --reload

echo "Removed the Wi-Fi suspend fix. brcmfmac will stay bound across suspend again,"
echo "and the card is re-armable as a wakeup source on next boot."
