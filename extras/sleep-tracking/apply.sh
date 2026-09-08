#!/usr/bin/env bash
# Battery+ — install sleep-drain tracking.
# Run as your normal user:   bash extras/sleep-tracking/apply.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK=/usr/lib/systemd/system-sleep/battery-plus-sleep
LOG=/var/log/battery-plus-sleep.log

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root — it calls sudo itself."; exit 1; }

cat <<EOF
This will:
  • install   $HOOK
                (records battery capacity/charge/voltage before and after
                every suspend, so the panel can show real sleep power draw)
  • create    $LOG   (world-readable, so the panel can read it without root)

Undo anytime with ./revert.sh
EOF
read -rp $'\nProceed? [y/N] ' a
[[ ${a,,} == y ]] || { echo "aborted"; exit 0; }

sudo install -Dm755 -o root -g root "$HERE/battery-plus-sleep" "$HOOK"
sudo touch "$LOG"
sudo chmod 644 "$LOG"

cat <<EOF

Done. The next time this laptop actually sleeps for a while (lid close,
idle timeout, or manual suspend) one line will be appended to $LOG.
Open the Battery+ panel afterward to see it under "Sleep".
EOF
