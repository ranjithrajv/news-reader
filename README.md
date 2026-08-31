# News Reader — Omarchy Overlay

Fullscreen overlay RSS reader for Omarchy Quattro. Lives in one `omarchy-shell` process as an `overlay` + `bar-widget` plugin.

Press the bar button (📰) or summon via IPC to open a centered card:

- **Live RSS** — no hard-coded feeds or articles; add your own RSS/Atom URLs in Settings (⚙) or import OPML/JSON — see `suggested-feeds.json` for examples
- **Search + feed chips** — `/` focuses search, matches title/description/feed name plus the full cached body of any story you've opened; chips filter by source and are grouped into folders by feed category, `j`/`k` or `↑`/`↓` navigate, `Enter` opens, `r` refreshes, `Ctrl+C` copies link
- **Feed folders** — feeds group under a category header (edit a feed's category inline in Settings) in both the chip bar and the Settings feed list
- **Scrim + keyboard layer** — `WlrLayershell.layer: Overlay`, `Exclusive` focus, `Esc` dismisses, click outside dismisses
- **Read tracking** — read ids persisted at `~/.local/state/omarchy/news-reader-read.json` (800-entry cap), unread dot + “Mark read”
- **Auto refresh** — configurable Hourly (default) / Daily / Weekly in Settings, persisted, + minute-granular “2h ago” labels

## Install

```sh
omarchy plugin add https://github.com/ranjithrajv/news-reader --enable --yes
# then add to bar if not auto-placed:
omarchy bar move ranjithraj.news-reader --section right
```

Local dev (this repo is a plugin checkout already):

```sh
mkdir -p ~/.config/omarchy/plugins/ranjithraj.news-reader
cp manifest.json Overlay.qml BarWidget.qml NewsModel.js Config.js suggested-feeds.json ~/.config/omarchy/plugins/ranjithraj.news-reader/
omarchy-shell shell rescanPlugins
omarchy plugin validate ~/.config/omarchy/plugins/ranjithraj.news-reader
qmllint -I /usr/share/omarchy/shell ~/.config/omarchy/plugins/ranjithraj.news-reader/Overlay.qml ~/.config/omarchy/plugins/ranjithraj.news-reader/BarWidget.qml
```

## Remove

```sh
omarchy plugin remove ranjithraj.news-reader
```

State (feeds, read ids, unread count, font size) is left at `~/.local/state/omarchy/news-reader-*.json`; delete those files to fully reset.

## Dependencies

External commands invoked at runtime: `curl` (feed/article fetch), `wl-copy` (`wl-clipboard`, copy link/export), `notify-send` (`libnotify`, export/share notifications), `xdg-open` (open story in browser). No daemons, no build step, no sudo.

## Summon / hide

```sh
omarchy-shell shell summon ranjithraj.news-reader '{}'
omarchy-shell shell hide ranjithraj.news-reader
omarchy-shell shell toggle ranjithraj.news-reader '{}'
# bar button also triggers summon
```

## Files

- `manifest.json` — `kinds: ["overlay","bar-widget"]`, `overlay: Overlay.qml`, `barWidget: BarWidget.qml`, `keepLoaded: true`
- `Overlay.qml` — `PanelWindow` overlay, fetches RSS via `curl` + `Process`, merges 150 newest, chips + search + split list/detail
- `BarWidget.qml` — `WidgetButton` (`\uF1EA`) → `shell summon`
- `NewsModel.js` — RSS/Atom parser (`<item>`/`<entry>`, CDATA, `content:encoded`, link href fallback), `timeAgo`, `filterArticles` (no hard-coded feeds)
- `Config.js` — shared state-dir/path/sentinel config single source for Overlay + BarWidget
- `suggested-feeds.json` — example feeds to import (not auto-loaded); paste a filtered JSON array into Settings → Import

## Theming

Uses shared tokens so themes style it automatically: `Color.menu.*` (`background/text/border/scrim/selectedBackground/selectedText`), `Style.*` (`cornerRadius`, `space`, `spacing`, `font`), `Border.surfaceSpec`. No hardcoded palette.

## Security

Runs unsandboxed inside `omarchy-shell` as your user. Fetch is `curl -sL --max-time 8` capped at 500 KB per feed, parsed as text in QML JS — no eval, no hooks, no sudo. Writable state files are read through bounded regular-file/no-follow readers (256 KiB ceiling) and all retained collections/field lengths are structurally capped before entering shell state. Review `Overlay.qml:fetchNext` + `NewsModel.js:parseRss` before enabling.

## License

AGPL-3.0-or-later — see [LICENSE](LICENSE).
