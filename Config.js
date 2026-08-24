.pragma library

// Shared path + sentinel config — single source for both Overlay.qml and BarWidget.qml.
// QML callers must pass Quickshell.env("HOME") because .pragma library has no Quickshell import.

var stateDirSuffix = "/.local/state/omarchy/"
var downloadsSuffix = "/Downloads/"
var allFeedsId = "__all"

function stateDir(home) {
    return (home || "") + stateDirSuffix
}
function statePath(home, name) {
    return stateDir(home) + name
}
function downloadsDir(home) {
    return (home || "") + downloadsSuffix
}
