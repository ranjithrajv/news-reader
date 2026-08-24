# Quickshell API surface

This plugin is coupled to a specific slice of the Quickshell framework. If
Quickshell renames or restructures any of these, this plugin breaks silently
until someone restarts the shell and notices. Documented here so a future
Quickshell upgrade can be diffed against this list instead of discovered by
a blank overlay.

Check with `scripts/check-api-surface.sh` (see below) after upgrading
Quickshell or `/usr/share/omarchy/shell`.

## Imports

| Module | Used for |
|---|---|
| `Quickshell` | `Quickshell.env()`, `Quickshell.execDetached()` |
| `Quickshell.Io` | `FileView`, `Process`, `StdioCollector` |
| `Quickshell.Wayland` | `WlrLayershell` attached properties, `WlrLayer`, `WlrKeyboardFocus` |
| `qs.Commons` | `Color`, `Style`, `Border`, `Util` — shared theme tokens (omarchy-shell, not upstream Quickshell) |
| `qs.Ui` | `WidgetButton`, `PanelToolTip` — shared widgets (omarchy-shell, not upstream Quickshell) |

## Types / properties relied on

- **`PanelWindow`** — the overlay's root surface.
- **`WlrLayershell.namespace`**, **`WlrLayershell.layer`** (`WlrLayer.Overlay`),
  **`WlrLayershell.keyboardFocus`** (`WlrKeyboardFocus.Exclusive`) — attached
  properties that make this an exclusive-focus overlay layer.
- **`FileView`** — `path`, `text()`, `setText()`, `reload()`, `onLoaded`,
  `onLoadFailed`. Used for all local persistence (read state, feed list,
  font size, reading theme, bundled `suggested-feeds.json`) — no other
  file-IO API is used.
- **`Process`** + **`StdioCollector`** — `stdout.waitForEnd`,
  `onStreamFinished`, `onExited(code)`. Used to shell out to `curl` for
  every network fetch — there is no QML-native network API in this plugin.
- **`Quickshell.execDetached(argv)`** — fire-and-forget shell commands
  (clipboard copy, notify-send, xdg-open).
- **`WidgetButton`** (`qs.Ui`) — the bar-widget entry point.

## Not used (do not add without checking sandboxing/security implications)

- No `XMLHttpRequest` / QML network API — everything network-bound is a
  `curl` subprocess with `--max-time` and a byte cap, by design (see
  README § Security).
- No `Qt.include` / `.pragma library` sharing beyond `Config.js`.
