// Pure helpers for the Appearance plugin (theme + wallpaper modes).

// "aether\nAlfisti Nocturne\n" -> ["aether", "Alfisti Nocturne"]
function parseLines(text) {
  return String(text || "")
    .split("\n")
    .map(function (line) { return line.trim() })
    .filter(function (line) { return line !== "" })
}

// theme.name stores the slug ("alfisti-nocturne"); theme list prints
// "Alfisti Nocturne". Match that casing so the picker highlights the
// current theme by name.
function themeNameFromState(text) {
  return String(text || "").trim().replace(/(^|-)([a-z])/g, function(m, a, b) { return a + b.toUpperCase() }).replace(/-/g, " ")
}

// NUL-delimited find -print0 output -> path list.
function parseNullList(text) {
  return String(text || "")
    .split("\u0000")
    .map(function (entry) { return entry.trim() })
    .filter(function (entry) { return entry !== "" })
}

// The exact discovery the packaged omarchy-theme-bg-next uses: user
// backgrounds for the current theme win on top of the stock theme set.
function backgroundsCommand() {
  return "find -L \"$HOME/.config/omarchy/backgrounds/$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null)\" "
    + "\"$HOME/.local/state/omarchy/current/theme/backgrounds/\" "
    + "-maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' "
    + "-o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \\) -print0 2>/dev/null | sort -z"
}

function basename(path) {
  var value = String(path || "")
  var idx = value.lastIndexOf("/")
  return idx >= 0 ? value.slice(idx + 1) : value
}

// "<path>/1-quadrifoglio-nocturne.jpg" -> "Quadrifoglio Nocturne"
function backgroundLabel(path) {
  var name = basename(path).replace(/\.[^.]+$/, "")
  name = name.replace(/^\d+[-_. ]+/, "")
  name = name.replace(/[-_.]+/g, " ").trim()
  return name || "Background"
}

// Workspace 1 -> backgrounds[0], workspace 2 -> backgrounds[1], wrapping.
function backgroundForWorkspace(backgrounds, workspaceId) {
  if (!backgrounds || backgrounds.length === 0) return ""
  var id = Number(workspaceId)
  if (!id || id < 1) return ""
  var image = backgrounds[(id - 1) % backgrounds.length]
  return image || ""
}

// Which workspace numbers use backgrounds[index] under the wrap mapping.
function workspacesForIndex(index, count) {
  var ids = []
  for (var ws = index + 1; ws <= 24; ws += count) ids.push(String(ws))
  return ids.join(", ")
}

function clampInterval(minutes) {
  var value = Math.round(Number(minutes))
  if (isNaN(value)) value = 5
  return Math.max(1, Math.min(60, value))
}

function isMode(value) {
  return ["single", "workspace", "cycle"].indexOf(String(value || "")) !== -1
}

function modeLabel(mode) {
  if (mode === "workspace") return "PER WORKSPACE"
  if (mode === "cycle") return "CYCLING"
  return "SINGLE"
}

function modeDescription(mode, intervalMinutes, backgroundCount) {
  if (mode === "workspace") {
    return backgroundCount > 1
      ? "WORKSPACE N USES BACKGROUND N"
      : "ADD MORE BACKGROUNDS TO VARY WORKSPACES"
  }
  if (mode === "cycle") return "EVERY " + clampInterval(intervalMinutes) + " MIN"
  return "ONE WALLPAPER EVERYWHERE"
}
