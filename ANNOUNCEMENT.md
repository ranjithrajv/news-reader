<!-- Draft for Hyprland/Omarchy Discord or r/unixporn. Edit before posting. -->

**News Reader — an RSS overlay for Quickshell/Omarchy, not another terminal reader**

Been using Newsboat for years but wanted something that opens as a native
overlay on my Hyprland bar instead of a terminal split. Built a Quickshell
plugin for Omarchy:

- Fullscreen overlay, exclusive keyboard focus, `j/k` nav, `/` search, feed
  chips — feels like a TUI reader, looks native to the compositor
- Full in-panel article reading (extraction + cache), not just "open in
  browser"
- Bring-your-own feeds — OPML/JSON import-export, nothing hard-coded
- No daemon, no Python — fetches via `curl`, ~2200 lines of QML/JS, AGPLv3

Unsandboxed for now (see README § Security) — sandboxing is next up before
I'd call it 1.0. Feedback / bug reports welcome.

`omarchy plugin add https://github.com/ranjithrajv/news-reader --enable --yes`
