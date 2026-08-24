.pragma library

// Shared path + sentinel config — single source for both Overlay.qml and BarWidget.qml.
// QML callers must pass Quickshell.env("HOME") because .pragma library has no Quickshell import.

var stateDirSuffix = "/.local/state/omarchy/"
var downloadsSuffix = "/Downloads/"
var allFeedsId = "__all"

// Security baseline: writable state is read through bounded, regular-file,
// no-follow shell readers (see stateReadCmd) instead of whole-file loads.
var stateMaxBytes = 262144

function stateDir(home) {
    return (home || "") + stateDirSuffix
}
function statePath(home, name) {
    return stateDir(home) + name
}
function downloadsDir(home) {
    return (home || "") + downloadsSuffix
}
function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
}
// Bounded regular-file read: refuses symlinks and non-regular files, caps
// output at maxBytes. Empty output (missing/refused file) means "no data".
function stateReadCmd(path, maxBytes) {
    var q = shellQuote(path)
    var cap = Math.max(1, maxBytes || stateMaxBytes)
    return "p=" + q + '; [ -f "$p" ] && [ ! -L "$p" ] && head -c ' + cap + ' "$p"'
}
