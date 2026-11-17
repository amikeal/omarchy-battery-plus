#!/usr/bin/env bash
# Battery+ — remove the root-installed sleep hook from earlier versions.
#
# Sleep-drain tracking no longer needs it: bin/battery-plus-sleepwatch runs
# as your user and holds a logind delay-inhibitor lock instead. Its history
# was copied to ~/.local/state/battery-plus/sleep.log the first time it ran.
# Run as your normal user.
set -euo pipefail

HOOK=/usr/lib/systemd/system-sleep/battery-plus-sleep
OLDLOG=/var/log/battery-plus-sleep.log

if [ ! -e "$HOOK" ]; then
  echo "The old sleep hook isn't installed. Nothing to do."
else
  sudo rm -f "$HOOK"
  echo "Removed $HOOK."
fi

if [ -e "$OLDLOG" ]; then
  echo
  echo "$OLDLOG is still there. Battery+ has its own copy now,"
  read -rp "so it can go. Delete it? [y/N] " a
  if [[ ${a,,} == y ]]; then sudo rm -f "$OLDLOG"; echo "Deleted."; fi
fi
