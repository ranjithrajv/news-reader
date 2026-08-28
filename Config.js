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
// Bounded regular-file read. The path is opened exactly once with
// O_NOFOLLOW | O_NONBLOCK, so a same-user swap (symlink or FIFO) after the
// check cannot redirect the read — the descriptor is bound at open() time and
// never re-resolved. O_NONBLOCK keeps a FIFO swap from hanging the reader, and
// a post-open fstat (on the descriptor, not the name) rejects non-regular
// files. Output is capped at maxBytes; empty output means "no data".
function stateReadCmd(path, maxBytes) {
    var q = shellQuote(path)
    var cap = Math.max(1, maxBytes || stateMaxBytes)
    return "python3 -c 'import sys,os,stat\n"
        + "p=sys.argv[1]; n=int(sys.argv[2])\n"
        + "try:\n fd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)\n"
        + "except OSError:\n sys.exit(0)\n"
        + "st=os.fstat(fd)\n"
        + "if not stat.S_ISREG(st.st_mode):\n os.close(fd); sys.exit(0)\n"
        + "try:\n sys.stdout.buffer.write(os.read(fd,n))\n"
        + "finally:\n os.close(fd)' " + q + " " + cap
}
