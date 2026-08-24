# Changelog

All notable changes to `news-reader` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-24

First public release — fullscreen overlay RSS reader for Omarchy Quattro (`overlay` + `bar-widget`, `keepLoaded: true`).

### Added
- Overlay `PanelWindow` with scrim, `WlrLayershell.Overlay` + `WlrKeyboardFocus.Exclusive`, `Esc` dismiss, click-outside dismiss, search/filter, feed chips with unread counts, `j`/`k` navigation, `Enter` open, `r` refresh, `Ctrl+C` copy, `Ctrl+Shift+S` share, `u` unread toggle, `F11` fullscreen, `?` help, drag splitter — `Overlay.qml`.
- Bar widget `WidgetButton` (`\uF1EA`) toggling overlay via `omarchy-shell shell summon` and unread badge polling `~/.local/state/omarchy/news-reader-unread.json` — `BarWidget.qml`.
- RSS/Atom parser handling `<item>`/`<entry>`, CDATA, `content:encoded`, `link href` fallback, image extraction, HTML entity decoding, `timeAgo` and `filterArticles` — `NewsModel.js`.
- Read tracking persisted at `~/.local/state/omarchy/news-reader-read.json` (capped, 800-entry), `Mark read`/`Mark unread`, auto-mark dwell, `~/.local/state/omarchy/news-reader-unread.json` bridge for bar badge.
- Full article extraction + caching (60-entry) with `curl` fetch, read-time (`220`wpm / `450`cpm CJK), in-detail progress bar, lightbox for images — `Overlay.qml:loadArticle`.
- Feed management in Settings (⚙): add/remove, duplicate guard, import JSON array or OPML `<outline>`, export JSON/OPML to `~/Downloads` + clipboard, undo-remove toast — `Overlay.qml`.
- `suggested-feeds.json` — 7 example feeds (not auto-loaded).
- Vitest suite — 95 tests at 100% statements/branches/functions/lines on `NewsModel.js` + `Config.js` (enforced threshold), plus regression checks on `manifest.json`, `suggested-feeds.json`, and QML config wiring — `tests/`.
- `scripts/verify.sh` — local full pass: `qmllint` → `omarchy plugin validate` (staged copy) → `vitest`.
- `scripts/check-api-surface.sh` + documented Quickshell API surface — `API-SURFACE.md`.
- GitHub Actions CI workflow (inert until a remote is added) — `.github/workflows/ci.yml`.

### Changed
- Centralized hard-coded values into maintainable config: persistence paths (`stateDir` + derived `readIdsPath`/`unreadPath`/`fontSizePath`/`feedsPath`), fetch config (`feedFetchTimeoutSec`/`articleFetchTimeoutSec`/`feedMaxBytes`/`articleMaxBytes`/`curl*` + `buildCurlCmd()`), collection limits (`NewsModel.Limits`), highlight color param, font-size bounds (`fontSizeDefault`/`Min`/`Max`), layout (`maxCardWidth`/`maxCardHeight`/`defaultSplitRatio`/`min`/`maxSplitRatio`) — `NewsModel.js:4-18`, `Overlay.qml:22-48,108-120,132-136`.
- Shared paths/sentinel extracted to `Config.js` (`stateDir`/`downloadsDir`, `allFeedsId`), timer intervals grouped as Overlay config properties, article-extract size guards folded into `NewsModel.Limits`.

### Fixed
- `NewsModel.js:229` highlight now accepts theme accent (`Color.accent`) instead of hard-coded `#7daea3`; fallback preserved for direct calls.

### Security
- Fetches via `curl -sL --max-time 8|10` capped at `500KB`/`700KB` per feed/article, parsed as text in QML JS (no eval), unsandboxed `omarchy-shell` user context documented in `README.md:Security`.

[0.1.0]: https://github.com/ranjithrajv/news-reader/releases/tag/v0.1.0
