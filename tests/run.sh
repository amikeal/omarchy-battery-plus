#!/usr/bin/env bash
# Battery+ security / regression checks. Run as your normal user, from anywhere:
#   bash tests/run.sh
# Needs nothing beyond what the plugin already uses (bash, jq, coreutils).
# Nothing here needs root or changes system state; the privileged helper is
# exercised as a copy that writes to a scratch file.
set -uo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'pkill -P $$ 2>/dev/null; rm -rf -- "$TMP"' EXIT

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
# jq -e against a JSON string, quietly (redirecting a whole `check` call
# would also swallow its ok/FAIL line).
jqe() { jq -e "$1" <<<"$2" >/dev/null 2>&1; }

echo "Panel text rendering"
# QML Text defaults to AutoText, which renders markup. Process names are
# chosen by whatever process it is, so every Text must be PlainText.
texts=$(grep -cE '^\s*Text \{$' "$ROOT/Panel.qml")
plain=$(grep -cE '^\s*textFormat: Text\.PlainText$' "$ROOT/Panel.qml")
check "every Text item is PlainText ($plain/$texts)" [ "$texts" -gt 0 ] && [ "$texts" = "$plain" ]
check "no RichText/StyledText/AutoText sinks" \
  bash -c '! grep -qE "Text\.(RichText|StyledText|AutoText|MarkdownText)" "$1"' _ "$ROOT/Panel.qml"

echo "Data feed"
# A busy process with a markup-shaped name must reach the panel as exactly
# that literal string (escaped by jq, not mangled, not breaking the JSON).
evil="$TMP/<u>EVIL"
cp /usr/bin/yes "$evil"
timeout 5 "$evil" >/dev/null &
sleep 1.5
out=$("$ROOT/bin/battery-plus-data" --no-rapl)
check "data helper emits valid JSON with a markup-named process" jqe . "$out"
check "markup-named process passes through as a literal string" \
  jqe '.top | any(.name == "<u>EVIL")' "$out"

# The sleep log is user-writable: junk in it must not break the feed or
# reach the panel as anything but numbers and an ISO time.
mkdir -p "$TMP/state/battery-plus"
printf '%s\n' '<img src=x> duration=1.2.3 pre_cap=x watts=<b>9 pct_per_hour=--1' \
  > "$TMP/state/battery-plus/sleep.log"
out=$(XDG_STATE_HOME="$TMP/state" "$ROOT/bin/battery-plus-data" --no-rapl)
check "malformed sleep log still gives valid JSON" jqe '.battery' "$out"
check "malformed sleep log yields only numbers (time dropped)" \
  jqe '.sleep.lastAt == "" and .sleep.lastWatts == 0 and ([.sleep[] | select(type == "string")] == [""])' "$out"

echo "Privileged helper input validation"
# Run a copy as the current user, with its TLP drop-in redirected to a
# scratch file. Every rejected call must exit 2 before touching anything.
PRIV="$TMP/priv"
sed -e "s|^PERSIST=.*|PERSIST=$TMP/persist.conf|" \
    -e 's|tlp start >/dev/null 2>&1 \|\| true|true|' "$ROOT/bin/battery-plus-priv" > "$PRIV"
rejects() { bash "$PRIV" "$@" >/dev/null 2>&1; [ $? = 2 ]; }
check "rejects unknown verb"                rejects frobnicate
check "rejects persist with unknown tweak"  rejects persist bogus on
check "rejects persist with bad value"      rejects persist wifi maybe
check "rejects unpersist with unknown tweak" rejects unpersist bogus
check "rejects shell-shaped tweak"          rejects persist '$(id)' on
check "rejects bad epp value"               rejects epp '../../etc/passwd'
check "rejects bad turbo value"             rejects turbo yes
check "rejected calls left no TLP drop-in"  [ ! -e "$TMP/persist.conf" ]
bash "$PRIV" persist wifi on >/dev/null 2>&1
check "valid persist writes exactly one key line" \
  bash -c '[ "$(grep -cE "^[A-Z_]+=" "$1")" = 1 ] && grep -qx "WIFI_PWR_ON_BAT=on" "$1" && ! grep -q "^=" "$1"' _ "$TMP/persist.conf"

echo "RAPL side channel (CVE-2020-8694)"
check "installer never opens energy_uj to a group" \
  bash -c '! grep -qE "chmod (g|o|a)\+r|chgrp wheel" "$1"' _ "$ROOT/extras/power-tuning/apply.sh"
check "data helper never reads energy_uj itself" \
  bash -c '! grep -q "energy_uj" "$1"' _ "$ROOT/bin/battery-plus-data"
check "helper rounds RAPL output to 0.1 W" grep -q 'printf "%.1f", d/1e6/0.4' "$ROOT/bin/battery-plus-priv"
check "background polls skip RAPL" grep -q '"--no-rapl"' "$ROOT/PowerService.qml"
if [ -x /usr/local/bin/battery-plus-priv ] && r=$(sudo -n /usr/local/bin/battery-plus-priv rapl 2>/dev/null); then
  check "installed helper returns three coarse numbers" \
    bash -c '[[ $1 =~ ^[0-9]+\.[0-9]\ [0-9]+\.[0-9]\ [0-9]+\.[0-9]$ ]]' _ "$r"
else
  echo "  skip  installed helper rapl output (helper not installed or no RAPL)"
fi

echo "Power-tuning install / revert"
# Stub sudo/systemctl/udevadm on PATH: sudo only logs what it was asked to
# run (and fails on request), so nothing here touches the real system.
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/sudo" <<'EOF'
#!/bin/bash
echo "$*" >> "$SUDO_LOG"
[ -n "${SUDO_FAIL:-}" ] && [[ "$*" == *"$SUDO_FAIL"* ]] && exit 1
exit 0
EOF
cat > "$STUB/systemctl" <<'EOF'
#!/bin/bash
case $1 in list-unit-files) echo "$3 enabled enabled" ;; is-enabled) echo enabled ;; esac
EOF
printf '#!/bin/bash\nexit 0\n' > "$STUB/udevadm"
chmod +x "$STUB"/*
export SUDO_LOG="$TMP/sudo.log"

# Finding: with no bundled helper, apply.sh used to skip the install but
# still grant NOPASSWD to whatever already sat in /usr/local/bin.
mkdir -p "$TMP/nohelper/extras/power-tuning"
cp "$ROOT/extras/power-tuning/apply.sh" "$TMP/nohelper/extras/power-tuning/"
: > "$SUDO_LOG"
echo y | PATH="$STUB:$PATH" bash "$TMP/nohelper/extras/power-tuning/apply.sh" >/dev/null 2>&1
check "apply.sh without the bundled helper exits non-zero" [ $? != 0 ]
check "...before running anything as root" [ ! -s "$SUDO_LOG" ]
ap="$ROOT/extras/power-tuning/apply.sh"
verify=$(grep -n 'sha256sum "$dest"' "$ap" | tail -1 | cut -d: -f1)
visudo=$(grep -n 'visudo -cf' "$ap" | cut -d: -f1)
check "sudoers rule is written only after the installed helper is verified" \
  [ -n "$verify" ] && [ -n "$visudo" ] && [ "$verify" -lt "$visudo" ]
check "apply.sh no longer has a branch that trusts an existing helper" \
  bash -c '! grep -q "if \[ -f /usr/local/bin/battery-plus-priv \]" "$1"' _ "$ap"

# Finding: revert.sh used to swallow failures and still say "Reverted".
rv="$ROOT/extras/power-tuning/revert.sh"
check "revert.sh has no '|| true'" bash -c '! grep -q "|| true" "$1"' _ "$rv"
: > "$SUDO_LOG"
out=$(echo y | PATH="$STUB:$PATH" SUDO_FAIL="sudoers.d" bash "$rv" 2>&1); rc=$?
check "revert.sh exits non-zero when a step fails" [ "$rc" != 0 ]
check "...names the failed step and doesn't claim success" \
  bash -c '[[ $1 == *"FAIL  remove /etc/sudoers.d/battery-plus"* && $1 != *"Reverted."* ]]' _ "$out"
check "...still runs the steps after the failure" grep -q 'rm -f /usr/local/bin/battery-plus-priv' "$SUDO_LOG"
check "...and keeps the state record for a re-run" bash -c '! grep -q "rm -rf -- /var/lib" "$1"' _ "$SUDO_LOG"
: > "$SUDO_LOG"
out=$(echo y | PATH="$STUB:$PATH" bash "$rv" 2>&1); rc=$?
check "revert.sh with every step succeeding reports success" \
  bash -c '[ "$1" = 0 ] && [[ $2 == *"Reverted."* ]]' _ "$rc" "$out"
check "revert.sh removes the helper's 02-battery-plus.conf drop-in" \
  grep -q 'rm -f /etc/tlp.d/02-battery-plus.conf' "$SUDO_LOG"

echo "Root-written files"
check "PowerTOP report is written into a root-created directory" \
  grep -q 'sudo powertop --csv="$rootdir/powertop.csv"' "$ROOT/extras/battery-dashboard"

echo "Sleep watcher"
mkfifo "$TMP/ev"
BATTERY_PLUS_STATE_DIR="$TMP/sw" BATTERY_PLUS_SLEEP_EVENTS="$TMP/ev" \
  BATTERY_PLUS_NO_INHIBIT=1 BATTERY_PLUS_MIN_SLEEP_SEC=1 "$ROOT/bin/battery-plus-sleepwatch" &
sw=$!
exec 4>"$TMP/ev"
sleep 0.5
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)" >&4
sleep 1.2
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)" >&4
sleep 0.5
check "a sleep cycle appends one well-formed line" \
  grep -qE '^[0-9T:+-]+ duration=[0-9]+ pre_cap=[0-9]+ post_cap=[0-9]+ drop_wh=-?[0-9.]+ watts=-?[0-9.]+ pct_per_hour=-?[0-9.]+$' \
  "$TMP/sw/sleep.log"
echo "PrepareForSleep (true,) from a spoofed line without the login1 path" >&4
sleep 0.3
check "a second watcher exits instead of running twice" \
  bash -c 'BATTERY_PLUS_STATE_DIR="$1" timeout 3 "$2"; [ $? = 0 ]' _ "$TMP/sw" "$ROOT/bin/battery-plus-sleepwatch"
kill "$sw" 2>/dev/null; wait "$sw" 2>/dev/null
exec 4>&-
check "watcher removes its pidfile on exit" [ ! -e "$TMP/sw/sleepwatch.pid" ]

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
