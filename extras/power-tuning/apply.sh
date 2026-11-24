#!/usr/bin/env bash
# Omarchy power tuning for the MacBook Air 9,1 (T2, Ice Lake).
# Run as your normal user:   bash ~/.config/omarchy/power-tuning/apply.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=/etc/tlp.d/01-omarchy-macbookair.conf
STATEDIR=/var/lib/battery-plus/power-tuning
HELPER=/usr/local/bin/battery-plus-priv

[ "$EUID" -ne 0 ] || { echo "Run as your normal user, not root — it calls sudo itself."; exit 1; }

PLUGIN=$(cd "$HERE/../.." && pwd)
HELPER_SRC="$PLUGIN/bin/battery-plus-priv"

# The sudoers rule below is only ever granted to a helper this run installed
# from the bundled copy and then verified. Without the bundled copy there is
# nothing to verify against, so stop before changing anything rather than
# trusting whatever might already sit at $HELPER.
if [ ! -f "$HELPER_SRC" ]; then
  echo "Bundled helper not found at $HELPER_SRC." >&2
  echo "Run this script from inside the plugin checkout. Nothing was changed." >&2
  exit 1
fi

cat <<EOF
This will:
  • install   tlp  powertop  (pacman)
  • record    the current TLP drop-in and power-profiles-daemon / tlp service
                state in $STATEDIR, so revert.sh can put them back
  • mask      power-profiles-daemon      → omarchy.power profile buttons go inert
  • write     $CONF
  • enable    tlp.service  and apply it now
  • install   $HELPER   (root-owned tuning helper)
  • add       /etc/sudoers.d/battery-plus   (passwordless: battery-plus-priv ONLY —
                its own allowlist covers every action the panel performs; running
                tlp/tlp-stat/powertop by hand still prompts for your password)
  • remove    /etc/udev/rules.d/99-rapl-readable.rules if an earlier version
                added it (CPU energy counters stay root-only; the helper above
                reports coarse CPU watts to the panel instead)
  • restart   the Omarchy shell

thermald is left running. Undo anytime with ./revert.sh
EOF
read -rp $'\nProceed? [y/N] ' a
[[ ${a,,} == y ]] || { echo "aborted"; exit 0; }

echo "==> packages"
sudo pacman -S --needed --noconfirm tlp powertop

echo "==> record prior state"
# Written by root, into a root-owned directory, so revert.sh can trust it.
# Only the FIRST apply records anything: a re-run would otherwise overwrite
# the true original with this script's own changes. A drop-in carrying this
# plugin's header came from an older apply.sh that kept no record, so the
# real original is already gone; that is marked prior=unknown and revert.sh
# falls back to Omarchy's defaults instead of "restoring" our own settings.
sudo /usr/bin/bash -c '
  set -euo pipefail
  conf=$1 statedir=$2
  [ -e "$statedir/state" ] && { echo "    kept the state recorded by the first apply"; exit 0; }
  umask 022
  install -d -m 755 -o root -g root "$statedir"
  unit() { systemctl "$1" "$2" 2>/dev/null || true; }
  prior=known backup=no
  if [ -e "$conf" ]; then
    if grep -q "^# Installed to $conf by ./apply.sh" "$conf"; then
      prior=unknown
    else
      install -m 644 -o root -g root "$conf" "$statedir/tlp-dropin.orig"
      backup=yes
      echo "    backed up the existing $conf"
    fi
  fi
  {
    echo "prior=$prior"
    echo "conf_backup=$backup"
    echo "ppd_enabled=$(unit is-enabled power-profiles-daemon.service)"
    echo "ppd_active=$(unit is-active power-profiles-daemon.service)"
    echo "tlp_enabled=$(unit is-enabled tlp.service)"
    echo "tlp_active=$(unit is-active tlp.service)"
  } > "$statedir/state.new"
  mv -f "$statedir/state.new" "$statedir/state"
  echo "    recorded in $statedir/state"
' _ "$CONF" "$STATEDIR"

echo "==> TLP drop-in"
sudo install -Dm644 -o root -g root "$HERE/tlp-macbookair.conf" "$CONF"
nvme=$(lspci -D 2>/dev/null | awk '/Non-Volatile memory|NVMe/{print $1; exit}')
if [ -n "${nvme:-}" ]; then
  printf '\n# auto-detected on install\nRUNTIME_PM_DENYLIST="%s"\n' "$nvme" | sudo tee -a "$CONF" >/dev/null
  echo "    NVMe $nvme kept out of runtime PM"
fi

echo "==> services"
if systemctl list-unit-files --no-legend power-profiles-daemon.service | grep -q .; then
  sudo systemctl mask --now power-profiles-daemon.service
else
  echo "    power-profiles-daemon not installed — nothing to mask"
fi
sudo systemctl enable --now tlp.service
sudo tlp start

echo "==> privileged tuning helper + passwordless rule"
# NOPASSWD is scoped to battery-plus-priv ONLY. That helper validates a fixed
# verb/value allowlist against fixed sysfs paths and TLP keys (see its header
# comment) — no caller-supplied string is ever executed or used to build a
# path. Granting the same to the bare tlp/tlp-stat/powertop binaries would be
# broader than any panel action needs and would sit as permanent, unrestricted
# root access; run those by hand with `sudo` (a password prompt) instead —
# the "PowerTOP scan" and "Full dashboard" buttons already open an interactive
# terminal for exactly that.
#
# $USER (and an unqualified `id`) are resolved through the caller's own
# PATH — a same-UID process could shadow `id` earlier in PATH and report
# any grammar-valid account name, which would then be written into a root
# sudoers policy. $EUID is a bash builtin populated from geteuid() at
# shell startup, not an external lookup, so it can't be shadowed; getent
# is invoked by its fixed absolute path to map that numeric UID to a name
# via the real NSS/passwd database.
invoking_user=$(/usr/bin/getent passwd "$EUID" | /usr/bin/cut -d: -f1)
if [[ ! "$invoking_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Refusing to write sudoers policy: unexpected username '$invoking_user'" >&2
  exit 1
fi
# Fingerprint the bundled helper now; root re-checks the installed copy
# against it, so a copy that changed in between is refused, not authorized.
want_sha=$(/usr/bin/sha256sum "$HELPER_SRC" | /usr/bin/cut -d' ' -f1)
echo "    bundled helper sha256 $want_sha"

# One root step installs the helper, verifies it, and only then writes the
# rule — the rule can never point at a file this run didn't put there.
#
# The policy bytes go to root over a pipe instead of a caller-owned temp
# file that root then reopens by path (a TOCTOU window: a same-UID process
# could swap in different-but-valid sudoers syntax, and visudo only checks
# grammar, not intent). Root creates the staged file itself, so it is
# root:root and unwritable by the caller from its first byte; visudo checks
# that exact file and a same-filesystem `mv` makes it live atomically.
policy_line=$(printf '%s ALL=(root) NOPASSWD: %s\n' "$invoking_user" "$HELPER")
printf '%s' "$policy_line" | sudo /usr/bin/bash -c '
  set -euo pipefail
  src=$1 dest=$2 want=$3
  fail() { echo "Refusing to grant passwordless sudo: $*" >&2; rm -f "$dest.new" "$rule.new"; exit 1; }
  rule=/etc/sudoers.d/battery-plus

  # Every directory sudo resolves the helper through must be root-owned and
  # not writable by anyone else, or the file could be swapped after the fact.
  for d in / /usr /usr/local /usr/local/bin; do
    [ -d "$d" ] && [ ! -L "$d" ] || fail "$d is not a real directory"
    [ "$(stat -c %u "$d")" = 0 ] || fail "$d is not owned by root"
    [ $(( 0$(stat -c %a "$d") & 022 )) = 0 ] || fail "$d is group/other-writable"
  done

  install -m 755 -o root -g root "$src" "$dest.new"
  [ "$(sha256sum "$dest.new" | cut -d" " -f1)" = "$want" ] \
    || fail "the bundled helper changed while installing"
  mv -f "$dest.new" "$dest"

  [ -f "$dest" ] && [ ! -L "$dest" ] || fail "$dest is not a regular file"
  [ "$(stat -c %u:%g:%a "$dest")" = 0:0:755 ] || fail "$dest is not root:root 0755"
  [ "$(sha256sum "$dest" | cut -d" " -f1)" = "$want" ] || fail "$dest does not match the bundled helper"
  echo "    installed and verified $dest"

  umask 077
  cat > "$rule.new"
  chown root:root "$rule.new"
  chmod 440 "$rule.new"
  visudo -cf "$rule.new" >/dev/null || fail "sudoers syntax check failed"
  mv -f "$rule.new" "$rule"
  echo "    wrote $rule"
' _ "$HELPER_SRC" "$HELPER" "$want_sha"

echo "==> RAPL counters root-only"
# Earlier versions made energy_uj group-readable so the panel could sample
# it directly. That reopened the PLATYPUS power side channel
# (CVE-2020-8694/8695) to every process the user runs; the kernel made these
# counters root-only on purpose. The panel now asks battery-plus-priv for
# coarse watts instead. Undo the old rule and restore the kernel default.
if [ -e /etc/udev/rules.d/99-rapl-readable.rules ]; then
  sudo rm -f /etc/udev/rules.d/99-rapl-readable.rules
  sudo udevadm control --reload
  echo "    removed the old 99-rapl-readable.rules"
fi
for d in /sys/class/powercap/intel-rapl*/energy_uj; do
  [ -e "$d" ] && sudo chgrp root "$d" && sudo chmod 0400 "$d"
done

echo "==> restart shell"
omarchy restart shell 2>/dev/null || echo "    (couldn't restart the shell — run: omarchy restart shell)"

cat <<EOF

Done.
  • Verify tunables:   sudo tlp-stat -s   /   tlp-stat -b   /   tlp-stat -p
                       (these will prompt for your password — only
                       battery-plus-priv is passwordless)
  • Click the Battery+ widget — the Power mode / CPU / device toggles are now live.
  • Baseline your idle draw for a few minutes on battery, screen at a fixed
    brightness, then compare after a reboot (kernel params in README.md).
EOF
