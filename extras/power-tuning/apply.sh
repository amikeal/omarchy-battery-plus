#!/usr/bin/env bash
# Omarchy power tuning for the MacBook Air 9,1 (T2, Ice Lake).
# Run as your normal user:   bash ~/.config/omarchy/power-tuning/apply.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=/etc/tlp.d/01-omarchy-macbookair.conf

[ "$EUID" -ne 0 ] || { echo "Run as your normal user, not root — it calls sudo itself."; exit 1; }

PLUGIN=$(cd "$HERE/../.." && pwd)

cat <<EOF
This will:
  • install   tlp  powertop  (pacman)
  • mask      power-profiles-daemon      → omarchy.power profile buttons go inert
  • write     $CONF
  • enable    tlp.service  and apply it now
  • install   /usr/local/bin/battery-plus-priv   (root-owned tuning helper)
  • add       /etc/sudoers.d/battery-plus   (passwordless: battery-plus-priv ONLY —
                its own allowlist covers every action the panel performs; running
                tlp/tlp-stat/powertop by hand still prompts for your password)
  • add       /etc/udev/rules.d/99-rapl-readable.rules  (RAPL stats without root)
  • restart   the Omarchy shell

thermald is left running. Undo anytime with ./revert.sh
EOF
read -rp $'\nProceed? [y/N] ' a
[[ ${a,,} == y ]] || { echo "aborted"; exit 0; }

echo "==> packages"
sudo pacman -S --needed --noconfirm tlp powertop

echo "==> TLP drop-in"
sudo install -Dm644 -o root -g root "$HERE/tlp-macbookair.conf" "$CONF"
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

echo "==> passwordless helper"
# NOPASSWD is scoped to battery-plus-priv ONLY. That helper validates a fixed
# verb/value allowlist against fixed sysfs paths and TLP keys (see its header
# comment) — no caller-supplied string is ever executed or used to build a
# path. Granting the same to the bare tlp/tlp-stat/powertop binaries would be
# broader than any panel action needs and would sit as permanent, unrestricted
# root access; run those by hand with `sudo` (a password prompt) instead —
# the "PowerTOP scan" and "Full dashboard" buttons already open an interactive
# terminal for exactly that.
if [ -f /usr/local/bin/battery-plus-priv ]; then
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

  # Hand the exact policy bytes to root over a pipe instead of writing them
  # to a caller-owned temp file that `sudo install` then reopens by path.
  # That file-based handoff is a TOCTOU window: another same-UID process
  # could swap its contents for different-but-still-valid sudoers syntax
  # between our check and root's read, and a later visudo on the installed
  # copy would accept it just as happily — visudo only checks grammar, not
  # intent. Piping to a root shell removes the window entirely: the staged
  # file is created by root, from root's own read of the pipe, so it is
  # already root:root and unwritable by the caller from its very first
  # byte. visudo validates that exact root-owned file, and only then does
  # an in-place `mv` (same filesystem, hence atomic) make it live.
  policy_line=$(printf '%s ALL=(root) NOPASSWD: /usr/local/bin/battery-plus-priv\n' "$invoking_user")
  printf '%s' "$policy_line" | sudo bash -c '
    set -euo pipefail
    dest=/etc/sudoers.d/battery-plus
    stage="$dest.new"
    umask 077
    cat > "$stage"
    chown root:root "$stage"
    chmod 440 "$stage"
    visudo -cf "$stage" || { rm -f "$stage"; exit 1; }
    mv -f "$stage" "$dest"
  '
else
  echo "    (battery-plus-priv not installed — skipping; tuning toggles will use pkexec prompts)"
fi

echo "==> RAPL readable by group wheel"
# install -o/-g asserts ownership explicitly, unlike tee (which, like touch,
# leaves an already-existing file's ownership untouched — see the sleep-
# tracking log fix for why that matters).
printf '%s\n' \
  'SUBSYSTEM=="powercap", ACTION=="add", RUN+="/bin/chgrp wheel /sys%p/energy_uj", RUN+="/bin/chmod g+r /sys%p/energy_uj"' \
  | sudo install -Dm644 -o root -g root /dev/stdin /etc/udev/rules.d/99-rapl-readable.rules
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
                       (these will prompt for your password — only
                       battery-plus-priv is passwordless)
  • Click the Battery+ widget — the Power mode / CPU / device toggles are now live.
  • Baseline your idle draw for a few minutes on battery, screen at a fixed
    brightness, then compare after a reboot (kernel params in README.md).
EOF
