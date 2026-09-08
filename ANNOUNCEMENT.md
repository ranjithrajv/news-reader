<!-- Launch kit. Record the demo (§1), then post in the order in §2. -->

# Launch kit

## 1. The demo clip

Everything below is carried by one 12–15s loop. Record it before posting anywhere.

Shot list — rehearse once, record in a single take, no cursor hunting:

1. Bar, idle. Click 📰. (1s)
2. Overlay opens. Hold still one beat so the reader registers the layout. (1s)
3. `j j j` down the list — let the detail pane repaint each time. (3s)
4. `/` → type a short query → list narrows live. (3s)
5. `Esc` out of search, `Enter` on a story → **full article renders in the panel**. Scroll once. (4s)
6. `Esc`. Back to the bare desktop. (1s)

Rules that decide whether it lands: a high-contrast theme (Tokyo Night, Catppuccin
Mocha, Rose Pine), a clean wallpaper, no other windows, no notifications, 1080p or
better. Feeds should show real headlines — an empty or lorem list reads as a mockup.

```sh
omarchy capture screenrecording      # pick region; run again to stop
START=0 DURATION=15 scripts/make-demo.sh   # newest recording -> docs/demo.gif
```

Keep the source `.mp4` — Reddit and Discord take it directly and it looks better
than the GIF. The GIF is only for the README.

## 2. Where to post, in this order

**a. Omarchy Discord** — first, always. Smallest, friendliest audience; surfaces
the install-path bugs before a big crowd hits them. Wait for it to be quiet before
step (c).

**b. r/unixporn** — mark it OC. Title sells the *look and the place*, not the
feature list. Post the mp4. Awesome lists and the marketplace submission (§4) should already be
filed so the traffic has somewhere to land.

> `[OC] Hyprland — I got tired of alt-tabbing to read RSS, so it lives in my bar now`

First comment carries the rice details, because that is what the sub asks for:
distro (Arch + Omarchy Quattro), WM (Hyprland), bar/shell (Quickshell via
omarchy-shell), theme, font, wallpaper source, and the repo link last.

**c. r/hyprland** — same clip, more technical framing. Quickshell plugin, layershell
overlay, exclusive keyboard focus. This crowd will ask how the article extraction
works; have an answer ready.

**d. Show HN** — last, and only once the issue tracker is calm. HN judges the repo,
not the GIF: the README, the security section, and whether the thing installs in
one command. Title: `Show HN: News Reader – an RSS reader that lives in the Wayland compositor`.

Skip Twitter/X, Product Hunt, and a blog post. Wrong audiences, and none of them
outperform the clip.

## 3. Post body

Reusable for Discord and r/hyprland; trim to two lines for the unixporn comment.

> **News Reader — read the whole article without leaving the compositor**
>
> Every RSS reader I tried made me choose between a terminal split and a browser
> tab. This one is neither: press the bar button and a Quickshell overlay takes
> the screen with exclusive keyboard focus, `j`/`k` through the list, `Enter`, and
> the **full article body renders in the panel** — extracted and cached, no browser
> handoff. `Esc` and you are back on the desktop. It reads like a TUI and looks
> native to the compositor, because it is part of it.
>
> - Bring your own feeds — OPML/JSON import-export, nothing hard-coded
> - `/` searches titles, descriptions and the cached body of anything you've opened
> - Feed folders, read tracking, configurable auto-refresh, 11 languages
> - Themes itself from your Omarchy tokens — no palette of its own
> - No daemon, no Python, no build step. `curl` + QML. AGPLv3.
>
> Unsandboxed for now (README § Security) — sandboxing is the gate before 1.0.
> Bug reports and feedback welcome.
>
> ```
> omarchy plugin add https://github.com/ranjithrajv/news-reader --enable --yes
> ```

Deliberately cut: the line count (reads as "toy"), "not another terminal reader"
(defensive — lead with what it does, not what it isn't), and the feature dump that
used to open the post.

## 4. Free distribution

### Before posting

- [ ] **[Omarchy Plugin Marketplace](https://github.com/omacom/omarchy-plugin-marketplace)**
      — highest value: the official-org listing behind omarchyplugins.com. Goes in
      through the [submission issue form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml),
      not a PR. Read `SUBMISSION.md` and `SECURITY.md` first — listing needs an
      exact-commit security scan plus explicit maintainer approval, so submit well
      ahead of any post, pinned to a release tag. Field-by-field answers:

      | Field | Value |
      |---|---|
      | Repository URL | `https://github.com/ranjithrajv/news-reader` |
      | Category | **Productivity** (matches `manifest.json` `barWidget.category`) |
      | Tags | **Quickshell**, **Bar** — the vocabulary is a fixed dropdown; there is no RSS/news/overlay tag, and >3 tags is an automatic rejection. Two exact tags beat three with a filler. |
      | Suggest a missing tag | `RSS` |

      Maintainer notes — reviewers will look for exactly this, so don't make them
      dig for it:

      > Quickshell overlay + bar widget for Omarchy Quattro. Runs unsandboxed inside
      > `omarchy-shell` as the user (documented in README § Security). External
      > commands at runtime: `curl` (feeds `--max-time 8`, articles `--max-time 10`;
      > URLs shell-quoted, responses truncated with `head -c` at 500 KB/feed),
      > `wl-copy`, `notify-send`, `xdg-open`. No daemon, no build step, no sudo, no
      > eval. Writable state is re-read through bounded regular-file/no-follow
      > readers with a 256 KiB ceiling. Ships no feeds — the user supplies them via Settings or
      > OPML/JSON import. State is confined to `~/.local/state/omarchy/news-reader-*.json`;
      > nothing outside that is written, so no user configuration is touched.
      > Install/removal are both one command (README § Install / § Remove). AGPL-3.0-or-later.

- [ ] **GitHub topics** — the repo currently has none, so it is invisible to
      topic browsing. There is no `awesome-quickshell` list; the `quickshell`
      topic is how that ecosystem is discovered.

      ```sh
      gh repo edit ranjithrajv/news-reader --add-topic quickshell,omarchy,hyprland,rss,wayland
      ```

### After posting — both lists gate on 5+ stars

`news-reader` is at **0 stars**, so neither of these can be filed yet. Come back
once the Discord and unixporn posts have moved the counter.

- [ ] **[awesome-omarchy](https://github.com/aorumbayev/awesome-omarchy)** — a
      hard CI gate, not a guideline: `scripts/check-min-stars.py` (`MIN_STARS = 5`)
      runs in the `awesome.yml` workflow and fails any newly added listing under
      five stars. Filing early burns the maintainer's time and closes the PR.
      When eligible: fork → branch → one line in `## Plugins`, alphabetical,
      between *Mirador* and *Notification Center*. Descriptions must be one
      sentence, capitalised, ending in a period. Run `pre-commit run --all-files`
      first — CI is awesome-lint + link check + spell check + list order.
      There is still no RSS or news plugin anywhere on that list.

      ```markdown
      - [News Reader](https://github.com/ranjithrajv/news-reader) - Fullscreen RSS overlay with in-panel article reading, search, and feed folders.
      ```
- [ ] **[awesome-hyprland](https://github.com/hyprland-community/awesome-hyprland)**
      — secondary; broader audience, weaker fit (compositor-plugin oriented).
      Same one-liner, standard awesome-list entry.
