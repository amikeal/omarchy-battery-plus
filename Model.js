.pragma library

// Nerd Font battery glyphs (Material Design set, matching the built-in power widget).
var DISCHARGE = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾",
                 "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
var CHARGE    = ["󰂜", "󰂆", "󰂇", "󰂈", "󰂝",
                 "󰂉", "󰂞", "󰂊", "󰂋", "󰂅"];
var FULL_ICON = "󰂅";       // 󰂅
var ALERT_ICON = "󰂃";      // 󰂃

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function batteryIcon(percent, status) {
  var i = clamp(Math.floor((Number(percent) || 0) / 10), 0, 9);
  if (status === "Full" || status === "FullyCharged") return FULL_ICON;
  if (status === "Charging") return CHARGE[i];
  if (status === "Discharging" && percent <= 10) return ALERT_ICON;
  return DISCHARGE[i];
}

function fmtWatts(w) {
  var n = Number(w) || 0;
  return (n >= 10 ? n.toFixed(1) : n.toFixed(2)) + " W";
}

function fmtDuration(mins) {
  var m = Math.max(0, Math.round(Number(mins) || 0));
  if (m === 0) return "—";
  var h = Math.floor(m / 60);
  var r = m % 60;
  return h > 0 ? (h + "h " + (r < 10 ? "0" : "") + r + "m") : (r + "m");
}

// Hero meta line, e.g. "ON BATTERY · 10.2 W" / "CHARGING · 22 W" / "FULLY CHARGED".
function modeLabel(b) {
  if (!b || !b.present) return "NO BATTERY";
  if (b.status === "Full" || (b.acOnline && b.percent >= 99)) return "FULLY CHARGED";
  if (b.status === "Charging") return "CHARGING · " + fmtWatts(b.watts);
  if (b.acOnline) return "ON AC";
  return "ON BATTERY · " + fmtWatts(b.watts);
}

function healthLabel(b) {
  if (!b || !b.whDesign) return "—";
  return b.health + "%   " + Number(b.whFull).toFixed(1) + " / " + Number(b.whDesign).toFixed(1) + " Wh";
}

// Which segmented power mode is active.
function activeMode(tlp) {
  if (!tlp || !tlp.installed || !tlp.active) return "";
  if (!tlp.manual) return "auto";
  return tlp.mode === "battery" ? "saver" : "full";
}

var EPP_OPTIONS = [
  { value: "power", label: "Power" },
  { value: "balance_power", label: "Balanced" },
  { value: "balance_performance", label: "Perf+" },
  { value: "performance", label: "Max" }
];

function eppValue(epp) {
  for (var i = 0; i < EPP_OPTIONS.length; i++)
    if (EPP_OPTIONS[i].value === epp) return epp;
  return "";
}

// Normalize the top-consumer list into { name, pct, frac } where frac is
// relative to the busiest entry, for drawing the mini bars.
function consumers(list) {
  var rows = Array.isArray(list) ? list.slice(0, 6) : [];
  var max = 0;
  for (var i = 0; i < rows.length; i++) max = Math.max(max, Number(rows[i].pct) || 0);
  if (max <= 0) max = 1;
  return rows.map(function(r) {
    return { name: String(r.name || "?"), pct: Number(r.pct) || 0, frac: (Number(r.pct) || 0) / max };
  });
}

function raplLabel(rapl) {
  if (!rapl || !rapl.available) return "";
  var parts = ["CPU " + Number(rapl.package).toFixed(1) + " W"];
  if (Number(rapl.gpu) > 0.05) parts.push("GPU " + Number(rapl.gpu).toFixed(1) + " W");
  return parts.join("  ·  ");
}

// Device-power-saving rows: what each toggle does, plus the tradeoff to weigh
// before turning it on. `blurb` shows under the label; `help` opens on the (i).
var TWEAK_INFO = [
  {
    key: "wifi",
    title: "Wi-Fi power saving",
    blurb: "Lets the Wi-Fi radio sleep between packets on battery.",
    help: "Saves roughly 0.5–1 W. Adds a few milliseconds of latency, and on some "
        + "Broadcom/Intel adapters can cause brief stalls or lower throughput on a "
        + "weak signal. Turn it off if you notice connection hiccups or video-call drops."
  },
  {
    key: "pcie",
    title: "PCIe runtime power",
    blurb: "Suspends idle PCIe devices until something needs them.",
    help: "One of the larger idle-power wins (~1–2 W) — SSD controller, card reader, "
        + "Thunderbolt/USB4. Rarely a device fails to resume and needs a reboot. The "
        + "installed TLP config already keeps the NVMe controller out of this."
  },
  {
    key: "usb",
    title: "USB autosuspend",
    blurb: "Powers down idle USB devices. Keyboards and mice are always excluded.",
    help: "Saves about 0.1–0.5 W per device. Some webcams, audio interfaces, DACs and "
        + "wireless dongles drop off or take a moment to wake. If a device misbehaves, "
        + "replug it or turn this off."
  },
  {
    key: "audio",
    title: "Audio codec power save",
    blurb: "Powers down the audio codec about a second after sound stops.",
    help: "Saves ~0.4 W. You may hear a faint pop, or lose the first fraction of a "
        + "second of playback, when it wakes. Harmless — disable it if the click bothers you."
  }
];
