#!/usr/bin/env bash
# Undo apply.sh — put TLP and power-profiles-daemon back the way apply.sh
# found them, using the state it recorded in $STATEDIR.
set -uo pipefail   # no -e: every step runs, and each failure is reported

CONF=/etc/tlp.d/01-omarchy-macbookair.conf
PERSIST=/etc/tlp.d/02-battery-plus.conf
STATEDIR=/var/lib/battery-plus/power-tuning
PPD=power-profiles-daemon.service
TLP=tlp.service

[ "$EUID" -ne 0 ] || { echo "Run as your normal user."; exit 1; }

read -rp "Remove the Battery+ TLP tuning and restore the previous power setup? [y/N] " a
[[ ${a,,} == y ]] || exit 0

failed=()
run() {
  local desc=$1; shift
  if "$@"; then echo "  ok    $desc"; else echo "  FAIL  $desc"; failed+=("$desc"); fi
}
unit_exists() { systemctl list-unit-files --no-legend "$1" | grep -q .; }

# ---- read the recorded state ------------------------------------------------
# Trusted only if root owns it (apply.sh writes it as root into a root-owned
# directory); every value is checked against what systemctl can report.
declare -A S=()
if [ -f "$STATEDIR/state" ] && [ ! -L "$STATEDIR/state" ] \
   && [ "$(stat -c %u "$STATEDIR")" = 0 ] && [ "$(stat -c %u "$STATEDIR/state")" = 0 ]; then
  while IFS='=' read -r k v; do
    case $k in prior|conf_backup|ppd_enabled|ppd_active|tlp_enabled|tlp_active) ;; *) continue ;; esac
    [[ $v =~ ^[a-z-]*$ ]] && S[$k]=$v
  done < "$STATEDIR/state"
fi

if [ "${S[prior]:-}" != known ]; then
  cat <<EOF
No record of the setup before apply.sh ran (it was installed by an older
version that didn't keep one). Falling back to Omarchy's defaults:
TLP disabled and stopped, power-profiles-daemon enabled and running.

EOF
  S=([prior]=unknown [conf_backup]=no [tlp_enabled]=disabled [tlp_active]=inactive
     [ppd_enabled]=enabled [ppd_active]=active)
fi

# Put a unit's enablement back. Only the states a plain enable/disable/mask
# can recreate are restored; anything else is reported for a manual look.
restore_enabled() {
  local u=$1 want=$2
  unit_exists "$u" || { [ "$want" = not-found ] || echo "  note  $u is no longer installed"; return 0; }
  case $want in
    enabled)   run "unmask $u"  sudo systemctl unmask "$u"
               run "enable $u"  sudo systemctl enable "$u" ;;
    disabled|not-found)
               run "unmask $u"  sudo systemctl unmask "$u"
               run "disable $u" sudo systemctl disable "$u" ;;
    masked)    run "mask $u"    sudo systemctl mask "$u" ;;
    static|indirect|generated|"")
               run "unmask $u"  sudo systemctl unmask "$u" ;;
    *)         echo "  FAIL  $u was '$want' before apply.sh — restore that by hand"
               failed+=("restore $u enablement ($want)") ;;
  esac
}
restore_active() {
  local u=$1 want=$2
  unit_exists "$u" || return 0
  [ "$(systemctl is-enabled "$u" 2>/dev/null)" = masked ] && return 0
  if [ "$want" = active ]; then
    run "restart $u" sudo systemctl restart "$u"
  else
    run "stop $u"    sudo systemctl stop "$u"
  fi
}

echo "==> TLP drop-ins"
if [ "${S[conf_backup]:-}" = yes ]; then
  run "restore your original $CONF" \
    sudo install -m 644 -o root -g root "$STATEDIR/tlp-dropin.orig" "$CONF"
else
  run "remove $CONF" sudo rm -f "$CONF"
fi
# Written by battery-plus-priv for the panel's "Keep after reboot" toggles.
run "remove $PERSIST" sudo rm -f "$PERSIST"

echo "==> services"
# TLP first, so its restart (if it was running before) reads the restored
# drop-ins, then power-profiles-daemon.
restore_enabled "$TLP" "${S[tlp_enabled]:-}"
restore_active  "$TLP" "${S[tlp_active]:-}"
restore_enabled "$PPD" "${S[ppd_enabled]:-}"
restore_active  "$PPD" "${S[ppd_active]:-}"

echo "==> helper + passwordless rule"
run "remove /etc/sudoers.d/battery-plus"     sudo rm -f /etc/sudoers.d/battery-plus
run "remove /usr/local/bin/battery-plus-priv" sudo rm -f /usr/local/bin/battery-plus-priv

echo "==> RAPL counters root-only"
# Rule from versions before RAPL went through the helper; restore the kernel's
# root-only default on the counters it opened up.
run "remove 99-rapl-readable.rules" sudo rm -f /etc/udev/rules.d/99-rapl-readable.rules
run "reload udev rules"             sudo udevadm control --reload
for d in /sys/class/powercap/intel-rapl*/energy_uj; do
  [ -e "$d" ] || continue
  run "make $d root-only" sudo sh -c 'chgrp root "$1" && chmod 0400 "$1"' _ "$d"
done

echo
if [ ${#failed[@]} -gt 0 ]; then
  echo "Revert did NOT finish cleanly. These steps failed:"
  printf '  • %s\n' "${failed[@]}"
  echo "The record in $STATEDIR was kept so you can fix the cause and re-run."
  exit 1
fi

if ! sudo rm -rf -- "$STATEDIR"; then
  echo "Reverted, but couldn't remove $STATEDIR — delete it by hand before re-running apply.sh." >&2
  exit 1
fi
sudo rmdir --ignore-fail-on-non-empty /var/lib/battery-plus
echo "Reverted. 'tlp' and 'powertop' packages left installed — remove with:"
echo "  sudo pacman -Rns tlp powertop"
echo "Restart the shell:  omarchy restart shell"
