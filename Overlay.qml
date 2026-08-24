import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "NewsModel.js" as NewsModel
import "Config.js" as Config

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // --- Centralized state paths (1) — shared via Config.js ---
  readonly property string stateDir: Config.stateDir(Quickshell.env("HOME"))
  readonly property string readIdsPath: stateDir + "news-reader-read.json"
  readonly property string unreadPath: stateDir + "news-reader-unread.json"
  readonly property string fontSizePath: stateDir + "news-reader-font.json"
  readonly property string feedsPath: stateDir + "news-reader-feeds.json"
  readonly property string readingThemePath: stateDir + "news-reader-reading-theme.json"
  readonly property string suggestedFeedsPath: Qt.resolvedUrl("suggested-feeds.json")

  // --- Fetch config (2) ---
  readonly property int feedFetchTimeoutSec: 8
  readonly property int articleFetchTimeoutSec: 10
  readonly property int feedMaxBytes: 500000
  readonly property int articleMaxBytes: 700000
  readonly property string curlUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
  readonly property string curlAccept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  readonly property string curlAcceptLang: "en-US,en;q=0.9"

  // --- Timing config (3) ---
  readonly property int autoRefreshIntervalMs: 10 * 60 * 1000
  readonly property int timeAgoIntervalMs: 60 * 1000
  readonly property int autoMarkDelayMs: 1500
  readonly property int toastDurationMs: 2200
  readonly property int toastWithActionMs: 4500
  readonly property int badgePollIntervalMs: 4000  // mirrored in BarWidget.qml

  // --- Sentinel (4) — single source for "all feeds" ---
  readonly property string allFeedsId: Config.allFeedsId  // mirrors NewsModel.ALL_FEEDS_ID

  // --- Font size config (5) ---
  readonly property int fontSizeDefault: 11
  readonly property int fontSizeMin: 9
  readonly property int fontSizeMax: 18

  // --- Layout config (6) ---
  readonly property int maxCardWidth: 1200
  readonly property int maxCardHeight: 760
  readonly property real defaultSplitRatio: 0.34
  readonly property real minSplitRatio: 0.22
  readonly property real maxSplitRatio: 0.5
  readonly property int cardOuterMargin: 32
  readonly property int cardTopMargin: 72

  // --- Paths (7) ---
  readonly property string downloadsDir: Config.downloadsDir(Quickshell.env("HOME"))
  readonly property string exportJsonPath: downloadsDir + "news-reader-feeds.json"
  readonly property string exportOpmlPath: downloadsDir + "news-reader-feeds.opml"

  property bool opened: false
  property bool loading: false
  property string errorText: ""
  property string filterText: ""
  property string selectedFeedId: allFeedsId
  property int selectedIndex: 0
  property var feeds: []
  property var suggestedFeeds: []
  property var articles: []
  property var readIds: ({})
  property int fetchCursor: 0
  property int fetchSerial: 0

  // full article cache + loading state
  property string articleBody: ""
  property bool articleLoading: false
  property string articleError: ""
  property var articleCache: ({})
  property string articleFetchId: ""

  // derived — respects search + feed + unread toggle
  readonly property var filtered: {
    var base = NewsModel.filterArticles(root.articles, root.filterText, root.selectedFeedId)
    if (!root.showUnreadOnly) return base
    var out = []
    for (var i = 0; i < base.length; i++) if (!root.readIds[base[i].id]) out.push(base[i])
    return out
  }
  readonly property var selectedArticle: {
    if (root.filtered.length === 0) return null
    var idx = Math.max(0, Math.min(root.selectedIndex, root.filtered.length - 1))
    return root.filtered[idx]
  }
  readonly property int unreadCount: {
    var c = 0
    for (var i = 0; i < root.articles.length; i++) {
      if (!root.readIds[root.articles[i].id]) c++
    }
    return c
  }

  onSelectedArticleChanged: {
    if (root.selectedArticle) {
      root.loadArticle(root.selectedArticle)
      // auto-mark read after dwell (1.5s) if still selected and unread
      if (!root.readIds[root.selectedArticle.id]) {
        autoMarkTimer.restart()
      } else autoMarkTimer.stop()
    } else {
      root.articleBody = ""; root.articleLoading = false; root.articleError = ""
      autoMarkTimer.stop()
    }
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property bool isFullScreen: false
  property int cardWidth: root.isFullScreen ? panel.width : Math.min(root.maxCardWidth, panel.width - root.cardOuterMargin)
  property int cardHeight: root.isFullScreen ? panel.height : Math.min(root.maxCardHeight, panel.height - root.cardOuterMargin)
  readonly property int cardRadius: root.isFullScreen ? 0 : Style.cornerRadius
  property bool useMockFallback: false
  property real splitRatio: root.defaultSplitRatio
  property string toastText: ""
  property string toastActionLabel: ""
  property var toastAction: null
  property bool toastVisible: false
  property bool helpVisible: false
  property bool showUnreadOnly: false
  property int articleFontSize: fontSizeDefault
  property string lightboxImage: ""
  property bool lightboxVisible: false
  property bool settingsVisible: false
  property string newFeedUrl: ""
  property string newFeedTitle: ""
  property string importText: ""
  property string settingsError: ""
  property string settingsInfo: ""
  property var pendingUndoFeed: null
  property var pendingUndoArticles: []
  property var pendingUndoCache: ({})

  // reading-area color theme — "auto" follows the app theme; others are fixed bg/fg pairs
  property string readingTheme: "auto"
  readonly property var readingPalette: ({
    contrast: { bg: "#000000", fg: "#ffffff" },
    light:    { bg: "#ffffff", fg: "#1c1c1c" },
    dark:     { bg: "#121212", fg: "#e6e6e6" },
    sepia:    { bg: "#f4ecd8", fg: "#5b4636" },
    grey:     { bg: "#d8d8d8", fg: "#2b2b2b" }
  })
  readonly property var readingPal: root.readingPalette[root.readingTheme] || null
  readonly property color readingBg: root.readingPal ? root.readingPal.bg : Util.alpha(root.foreground, 0.04)
  readonly property color readingFg: root.readingPal ? root.readingPal.fg : root.foreground

  function buildCurlCmd(url, timeoutSec, maxBytes) {
    return "curl -sL --max-time " + timeoutSec + " -A '" + root.curlUserAgent + "' -H 'Accept: " + root.curlAccept + "' -H 'Accept-Language: " + root.curlAcceptLang + "' " + Util.shellQuote(url) + " 2>&1 | head -c " + maxBytes
  }
  function feedCurlCmd(url) { return buildCurlCmd(url, root.feedFetchTimeoutSec, root.feedMaxBytes) }
  function articleCurlCmd(url) { return buildCurlCmd(url, root.articleFetchTimeoutSec, root.articleMaxBytes) }

  function showToast(msg, actionLabel, action) {
    root.toastText = msg
    root.toastActionLabel = actionLabel || ""
    root.toastAction = action || null
    root.toastVisible = true
    toastTimer.restart()
  }
  function toggleHelp() { root.helpVisible = !root.helpVisible }
  function feedTitle(id) {
    for (var i = 0; i < root.feeds.length; i++) if (root.feeds[i].id === id) return root.feeds[i].title
    return id
  }
  function adjustFont(delta) {
    var next = Math.max(root.fontSizeMin, Math.min(root.fontSizeMax, root.articleFontSize + delta))
    if (next !== root.articleFontSize) {
      root.articleFontSize = next
      fontSizeFile.setText(String(next))
      showToast("Font " + next + "px")
    }
  }
  function resetFont() { root.articleFontSize = root.fontSizeDefault; fontSizeFile.setText(String(root.fontSizeDefault)); showToast("Font reset") }
  function setReadingTheme(t) {
    if (root.readingTheme === t) return
    root.readingTheme = t
    readingThemeFile.setText(t)
    showToast("Reading theme: " + t.charAt(0).toUpperCase() + t.slice(1))
  }
  function openLightbox(url) { if (!url) return; root.lightboxImage = url; root.lightboxVisible = true }
  function closeLightbox() { root.lightboxVisible = false }
  function setImportText(t) { root.importText = t || "" }
  function debugAddFeed(url, title) { root.newFeedUrl = url || ""; root.newFeedTitle = title || ""; addFeed() }

  function toggleSettings() {
    root.settingsVisible = !root.settingsVisible
    root.settingsError = ""; root.settingsInfo = ""
    if (root.settingsVisible) feedsFileView.reload()
  }
  function saveFeeds() {
    try { feedsFile.setText(JSON.stringify(root.feeds, null, 2)); root.settingsInfo = "Feeds saved"; root.showToast("Feeds saved") } catch(e){ root.settingsError = "Save failed: " + e }
  }
  function addFeed() {
    var url = String(root.newFeedUrl||"").trim()
    var title = String(root.newFeedTitle||"").trim()
    root.settingsError = ""; root.settingsInfo = ""
    if (!url) { root.settingsError = "URL required"; return }
    if (url.indexOf("http") !== 0) url = "https://" + url
    try { var u = new URL(url); if (!u.hostname) throw "bad url" } catch(e){ root.settingsError = "Invalid URL"; return }
    for (var i=0;i<root.feeds.length;i++) if (root.feeds[i].url === url) { root.settingsError = "Feed already exists"; return }
    var id = url.replace(/[^a-zA-Z0-9]/g,"_").slice(0,24) + "_" + Date.now().toString(36)
    if (!title) {
      try { title = new URL(url).hostname.replace(/^www\./,"") } catch(e){ title = "Feed " + (root.feeds.length+1) }
    }
    var next = root.feeds.slice()
    next.push({ id: id, title: title, url: url, category: "Custom" })
    root.feeds = next
    saveFeeds()
    root.newFeedUrl = ""; root.newFeedTitle = ""
    root.settingsInfo = 'Added "' + title + '"'
    root.showToast("Feed added")
  }
  function addSuggestedFeed(feed) {
    root.settingsError = ""; root.settingsInfo = ""
    for (var i=0;i<root.feeds.length;i++) if (root.feeds[i].url === feed.url) { root.settingsError = "Feed already exists"; return }
    var id = feed.url.replace(/[^a-zA-Z0-9]/g,"_").slice(0,24) + "_" + Date.now().toString(36)
    var next = root.feeds.slice()
    next.push({ id: id, title: feed.title, url: feed.url, category: feed.category || "Custom" })
    root.feeds = next
    saveFeeds()
    root.settingsInfo = 'Added "' + feed.title + '"'
    root.showToast("Feed added")
  }
  function removeFeed(id) {
    var next = [], removed = null
    for (var i=0;i<root.feeds.length;i++) { if (root.feeds[i].id !== id) next.push(root.feeds[i]); else removed = root.feeds[i] }
    if (!removed) return
    if (next.length === 0) { root.settingsError = "Keep at least one feed"; return }
    root.feeds = next
    saveFeeds()
    if (root.selectedFeedId === id) root.selectedFeedId = root.allFeedsId
    // immediately purge articles from removed feed so UI reflects removal,
    // stashing what was removed so the toast's Undo can restore it
    var pruned = [], removedArticles = []
    for (var k=0;k<root.articles.length;k++) { if (root.articles[k].feedId !== id) pruned.push(root.articles[k]); else removedArticles.push(root.articles[k]) }
    root.articles = pruned
    // also drop cached bodies for those articles
    var prunedCache = {}, removedCache = {}
    var keptIds = {}
    for (var a=0;a<pruned.length;a++) keptIds[pruned[a].id] = true
    for (var key in root.articleCache) { if (keptIds[key]) prunedCache[key] = root.articleCache[key]; else removedCache[key] = root.articleCache[key] }
    root.articleCache = prunedCache
    if (root.selectedIndex >= root.filtered.length) root.selectedIndex = Math.max(0, root.filtered.length - 1)
    // if selected article was from removed feed, clear detail
    if (root.selectedArticle && root.selectedArticle.feedId === id) {
      root.articleBody = ""; root.articleLoading = false; root.articleError = ""
    }
    root.pendingUndoFeed = removed
    root.pendingUndoArticles = removedArticles
    root.pendingUndoCache = removedCache
    root.showToast('"' + removed.title + '" removed', "Undo", root.undoRemoveFeed)
  }
  function undoRemoveFeed() {
    if (!root.pendingUndoFeed) return
    var next = root.feeds.slice()
    next.push(root.pendingUndoFeed)
    root.feeds = next
    saveFeeds()
    var merged = root.articles.concat(root.pendingUndoArticles)
    merged.sort(function(a,b){ return b.pubDate - a.pubDate })
    root.articles = merged
    var nextCache = {}
    for (var k in root.articleCache) nextCache[k] = root.articleCache[k]
    for (var k2 in root.pendingUndoCache) nextCache[k2] = root.pendingUndoCache[k2]
    root.articleCache = nextCache
    root.pendingUndoFeed = null
    root.pendingUndoArticles = []
    root.pendingUndoCache = {}
    root.showToast("Feed restored")
  }
  function importFeeds() {
    var txt = String(root.importText||"").trim()
    root.settingsError = ""; root.settingsInfo = ""
    if (!txt) { root.settingsError = "Paste JSON or OPML first"; return }
    var list = null
    // try JSON array first
    try {
      var j = JSON.parse(txt)
      if (Array.isArray(j)) list = j
      else if (j && Array.isArray(j.feeds)) list = j.feeds
    } catch(e){}
    if (!list) {
      // try OPML — extract <outline ... xmlUrl/host ... title/text ...>
      var re = /<outline[^>]*>/gi
      var m, out=[]
      while ((m = re.exec(txt)) !== null) {
        var tag = m[0]
        var url = (tag.match(/xmlUrl\s*=\s*["']([^"']+)["']/i) || tag.match(/htmlUrl\s*=\s*["']([^"']+)["']/i) || [])[1]
        var t = (tag.match(/title\s*=\s*["']([^"']+)["']/i) || tag.match(/text\s*=\s*["']([^"']+)["']/i) || [])[1]
        if (url && url.indexOf("http")===0) out.push({ title: t || url.replace(/^https?:\/\//,"").slice(0,32), url: url, category: "Imported" })
      }
      if (out.length>0) list = out
    }
    if (!list || !Array.isArray(list) || list.length===0) { root.settingsError = "No feeds found — paste JSON array or OPML <outline> list"; return }
    var added=0, skipped=0
    var next = root.feeds.slice()
    var seen={}
    for (var i=0;i<next.length;i++) seen[next[i].url]=true
    for (var j=0;j<list.length;j++) {
      var e=list[j]; if (!e || !e.url) continue
      var u=String(e.url).trim(); if (u.indexOf("http")!==0) continue
      if (seen[u]) { skipped++; continue }
      var tid = String(e.id||"").trim() || u.replace(/[^a-zA-Z0-9]/g,"_").slice(0,24) + "_" + Date.now().toString(36) + j
      next.push({ id: tid, title: String(e.title|| e.name || u.replace(/^https?:\/\//,"").slice(0,32)), url: u, category: String(e.category||"Imported") })
      seen[u]=true; added++
    }
    if (added===0) { root.settingsError = "No new feeds (all duplicates)"; return }
    root.feeds = next
    saveFeeds()
    root.importText = ""
    root.settingsInfo = "Imported " + added + " feed(s)" + (skipped ? " · " + skipped + " skipped" : "")
    root.showToast("Imported " + added)
  }
  function exportFeedsJson() {
    var js = JSON.stringify(root.feeds, null, 2)
    var path = root.exportJsonPath
    exportFile.setText(js)
    // also copy to clipboard
    Quickshell.execDetached(["bash","-c","printf %s " + Util.shellQuote(js) + " | wl-copy; notify-send -a 'News Reader' 'Feeds exported' 'Downloads/news-reader-feeds.json' 2>/dev/null || true"])
    root.settingsInfo = "Exported JSON to Downloads/news-reader-feeds.json + clipboard"
    root.showToast("Exported JSON")
  }
  function exportFeedsOpml() {
    var xml = '<?xml version="1.0" encoding="UTF-8"?>\n<opml version="2.0"><head><title>News Reader feeds</title></head><body>\n'
    for (var i=0;i<root.feeds.length;i++) {
      var f=root.feeds[i]
      xml += '  <outline text="' + String(f.title).replace(/"/g,"&quot;") + '" title="' + String(f.title).replace(/"/g,"&quot;") + '" type="rss" xmlUrl="' + String(f.url).replace(/"/g,"&quot;") + '" htmlUrl="' + String(f.url).replace(/"/g,"&quot;") + '"/>\n'
    }
    xml += '</body></opml>\n'
    var path = root.exportOpmlPath
    exportFileOpml.setText(xml)
    Quickshell.execDetached(["bash","-c","printf %s " + Util.shellQuote(xml) + " | wl-copy; notify-send -a 'News Reader' 'OPML exported' 'Downloads/news-reader-feeds.opml' 2>/dev/null || true"])
    root.settingsInfo = "Exported OPML to Downloads/news-reader-feeds.opml + clipboard"
    root.showToast("Exported OPML")
  }

  function toggleFullScreen() { root.isFullScreen = !root.isFullScreen }

  function open(payloadJson) {
    root.opened = true
    root.settingsVisible = false
    root.helpVisible = false
    root.lightboxVisible = false
    root.errorText = ""
    try {
      var p = payloadJson ? JSON.parse(payloadJson) : {}
      if (p && typeof p.feed === "string" && p.feed) root.selectedFeedId = p.feed
      if (p && typeof p.search === "string") root.filterText = p.search
    } catch(e) {}
    readFileView.reload()
    feedsFileView.reload()
    // No hard-coded mock articles — fetch only user-configured feeds.
    if (root.articles.length === 0) {
      root.refresh()
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // IPC-callable helpers for visual validation
  function setFeed(id) { root.selectedFeedId = id || root.allFeedsId; root.selectedIndex = 0 }
  function setSearch(t) { root.filterText = t || ""; if (searchField) searchField.text = root.filterText; root.selectedIndex = 0 }
  function clearSearch() { setSearch("") }

  function close() {
    root.opened = false
    root.settingsVisible = false
    root.helpVisible = false
    root.lightboxVisible = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.ranjithraj.news-reader")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refresh() {
    if (root.loading) return
    root.loading = true
    root.errorText = ""
    root.fetchSerial += 1
    root.fetchCursor = 0
    root.selectedIndex = 0
    fetchNext()
  }

  function mockArticles() {
    // No hard-coded news — kept for API compat only.
    return []
  }

  function loadMultilingualTest() {
    // Removed: no hard-coded news. This previously injected multilingual mock stories.
    root.showToast("No hard-coded test data — add feeds in Settings")
  }

  function fetchNext() {
    if (root.feeds.length === 0) {
      root.loading = false
      if (!root.errorText) root.errorText = "No feeds configured — add one in Settings (⚙) or import OPML/JSON"
      return
    }
    if (root.fetchCursor >= root.feeds.length) {
      root.loading = false
      if (root.articles.length === 0 && !root.errorText) root.errorText = "No articles — check network or feed URLs"
      return
    }
    var feed = root.feeds[root.fetchCursor]
    fetchProc.command = ["bash", "-c", root.feedCurlCmd(feed.url)]
    fetchProc.running = true
  }

  function handleFetchResult(text) {
    var feed = root.feeds[root.fetchCursor]
    var serial = root.fetchSerial
    if (!text || text.trim().length === 0) {
      // keep error but continue to next feed
      if (root.fetchCursor === 0) root.errorText = "Could not fetch " + feed.title
    } else if (text.indexOf("<") === -1) {
      if (root.fetchCursor === 0) root.errorText = feed.title + ": " + text.slice(0, 120)
    } else {
      try {
        var parsed = NewsModel.parseRss(text, feed.id, feed.title)
        var base = root.fetchCursor > 0 ? root.articles.slice() : []
        var merged = base
        for (var i = 0; i < parsed.length; i++) merged.push(parsed[i])
        merged.sort(function(a,b){ return b.pubDate - a.pubDate })
        if (merged.length > NewsModel.Limits.MAX_TOTAL_ARTICLES) merged = merged.slice(0, NewsModel.Limits.MAX_TOTAL_ARTICLES)
        for (var k = 0; k < merged.length; k++) merged[k].pubDateLabel = merged[k].pubDate ? NewsModel.timeAgo(merged[k].pubDate) : ""
        if (serial === root.fetchSerial && merged.length > 0) root.articles = merged
      } catch(e) {
        if (root.fetchCursor === 0) root.errorText = "Parse error for " + feed.title + ": " + e
      }
    }
    root.fetchCursor += 1
    if (root.fetchCursor < root.feeds.length && serial === root.fetchSerial) {
      Qt.callLater(fetchNext)
    } else {
      root.loading = false
    }
  }

  function loadArticle(article) {
    if (!article || !article.link) {
      root.articleBody = article ? (article.description || "") : ""
      root.articleError = ""
      root.articleLoading = false
      return
    }
    var id = String(article.id)
    if (root.articleCache[id] !== undefined) {
      root.articleBody = root.articleCache[id]
      root.articleError = ""
      root.articleLoading = false
      root.articleFetchId = id
      return
    }
    root.articleBody = article.description || ""
    root.articleError = ""
    root.articleLoading = true
    root.articleFetchId = id
    articleProc.command = ["bash", "-c", root.articleCurlCmd(article.link)]
    articleProc.running = true
  }

  function handleArticleResult(text) {
    var fid = root.articleFetchId
    var article = root.selectedArticle
    // if selection changed, fid may not match current selectedArticle.id → keep cache but don't overwrite body unless still matching
    if (!text || text.trim().length === 0) {
      if (article && String(article.id) === fid) {
        root.articleError = "Could not load article"
        root.articleLoading = false
      } else root.articleLoading = false
      return
    }
    if (text.indexOf("<") === -1) {
      if (article && String(article.id) === fid) {
        root.articleError = text.slice(0,120)
        root.articleLoading = false
      } else root.articleLoading = false
      return
    }
    try {
      var body = NewsModel.extractArticle(text)
      var nextCache = {}
      for (var k in root.articleCache) nextCache[k] = root.articleCache[k]
      nextCache[fid] = body && body.length > NewsModel.Limits.MIN_CACHED_BODY_LENGTH ? body : (article ? article.description : "")
      root.articleCache = nextCache
      // trim cache to NewsModel.Limits.MAX_ARTICLE_CACHE entries
      var keys = Object.keys(root.articleCache)
      if (keys.length > NewsModel.Limits.MAX_ARTICLE_CACHE) {
        var trimmed = {}
        for (var i = keys.length - NewsModel.Limits.MAX_ARTICLE_CACHE; i < keys.length; i++) trimmed[keys[i]] = root.articleCache[keys[i]]
        root.articleCache = trimmed
      }
      if (article && String(article.id) === fid) {
        root.articleBody = root.articleCache[fid]
        root.articleError = ""
        root.articleLoading = false
      } else {
        root.articleLoading = false
      }
    } catch(e) {
      if (article && String(article.id) === fid) {
        root.articleError = "Parse error: " + e
        root.articleLoading = false
      } else root.articleLoading = false
    }
  }

  function markRead(article) {
    if (!article || !article.id) return
    if (root.readIds[article.id]) return
    var next = {}
    for (var k in root.readIds) next[k] = root.readIds[k]
    next[article.id] = true
    root.readIds = next
    persistReadIds()
  }

  function markUnread(article) {
    if (!article || !article.id) return
    if (!root.readIds[article.id]) return
    var next = {}
    for (var k in root.readIds) if (k !== article.id) next[k] = root.readIds[k]
    root.readIds = next
    persistReadIds()
    root.showToast("Marked unread")
  }
  function markAllRead() {
    var next = {}
    for (var k in root.readIds) next[k] = root.readIds[k]
    for (var i = 0; i < root.filtered.length; i++) next[root.filtered[i].id] = true
    root.readIds = next
    persistReadIds()
    root.showToast("Marked " + root.filtered.length + " stories read")
  }

  function persistReadIds() {
    // keep last NewsModel.Limits.MAX_READ_IDS
    var keys = Object.keys(root.readIds)
    if (keys.length > NewsModel.Limits.MAX_READ_IDS) {
      var trimmed = {}
      for (var i = keys.length - NewsModel.Limits.MAX_READ_IDS; i < keys.length; i++) trimmed[keys[i]] = true
      root.readIds = trimmed
      keys = Object.keys(trimmed)
    }
    readFile.setText(JSON.stringify(root.readIds))
  }

  function openExternal(article) {
    if (!article || !article.link) return
    root.markRead(article)
    Quickshell.execDetached(["xdg-open", article.link])
  }

  function copyLink(article) {
    if (!article || !article.link) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(article.link) + " | wl-copy"])
    root.showToast("Link copied")
  }

  function shareArticle(article) {
    if (!article || !article.link) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(article.link) + " | wl-copy; notify-send -a 'News Reader' 'Shared — link copied' " + Util.shellQuote(article.title) + " 2>/dev/null || true"])
    root.markRead(article)
    root.showToast("Shared — link copied")
  }

  function selectNext(delta) {
    if (root.filtered.length === 0) return
    var n = root.filtered.length
    root.selectedIndex = (root.selectedIndex + delta + n) % n
    articleList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // persistence for read ids
  FileView {
    id: readFileView
    path: root.readIdsPath
    onLoaded: {
      try {
        var t = text()
        if (t && t.trim().length > 0) {
          var obj = JSON.parse(t)
          if (obj && typeof obj === "object") root.readIds = obj
        }
      } catch(e) {}
    }
    onLoadFailed: {}
  }
  FileView {
    id: readFile
    path: root.readIdsPath
  }
  FileView {
    id: unreadFile
    path: root.unreadPath
  }
  FileView {
    id: fontSizeFile
    path: root.fontSizePath
    onLoaded: {
      var n = parseInt(String(text()||"").trim())
      if (isFinite(n) && n >= root.fontSizeMin && n <= root.fontSizeMax) root.articleFontSize = n
    }
  }
  FileView {
    id: feedsFile
    path: root.feedsPath
  }
  FileView {
    id: readingThemeFile
    path: root.readingThemePath
    onLoaded: {
      var t = String(text()||"").trim()
      if (t in root.readingPalette || t === "auto") root.readingTheme = t
    }
  }
  FileView {
    id: feedsFileView
    path: root.feedsPath
    onLoaded: {
      try { var j=JSON.parse(text()); if (Array.isArray(j) && j.length>0 && j[0].url) root.feeds = j } catch(e){}
    }
    onLoadFailed: {}
  }
  FileView { id: exportFile; path: root.exportJsonPath }
  FileView { id: exportFileOpml; path: root.exportOpmlPath }
  FileView {
    id: suggestedFeedsFileView
    path: root.suggestedFeedsPath
    onLoaded: {
      try { var j = JSON.parse(text()); if (Array.isArray(j)) root.suggestedFeeds = j } catch(e){}
    }
    onLoadFailed: {}
  }
  Component.onCompleted: { fontSizeFile.reload(); feedsFileView.reload(); readingThemeFile.reload(); suggestedFeedsFileView.reload() }
  onUnreadCountChanged: {
    if (unreadFile) unreadFile.setText(String(root.unreadCount))
  }

  // periodic refresh when open
  Timer {
    id: autoRefresh
    interval: root.autoRefreshIntervalMs
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  // keep time-ago labels fresh when opened
  Timer {
    id: timeAgoTimer
    interval: root.timeAgoIntervalMs
    repeat: true
    running: root.opened && root.articles.length > 0
    onTriggered: {
      var copy = root.articles.slice()
      for (var i = 0; i < copy.length; i++) copy[i].pubDateLabel = copy[i].pubDate ? NewsModel.timeAgo(copy[i].pubDate) : ""
      root.articles = copy
    }
  }
  Timer {
    id: toastTimer
    interval: root.toastActionLabel !== "" ? root.toastWithActionMs : root.toastDurationMs
    onTriggered: root.toastVisible = false
  }
  Timer {
    id: autoMarkTimer
    interval: root.autoMarkDelayMs
    onTriggered: {
      var a = root.selectedArticle
      if (a && !root.readIds[a.id]) {
        root.markRead(a)
        root.showToast("Marked read")
      }
    }
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleFetchResult(String(text || ""))
    }
    onExited: function(code) {
      if (code !== 0 && root.fetchCursor === 0 && !root.errorText) {
      }
    }
  }

  Process {
    id: articleProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleArticleResult(String(text || ""))
    }
    onExited: function(code) {
      if (code !== 0 && root.articleLoading) {
        // leave to handleArticleResult; ensure spinner clears on hard fail
        if (!root.articleCache[root.articleFetchId]) root.articleLoading = false
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-news-reader"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // scrim
    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
      // allow wheel to not propagate to behind? scrim consumes click
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: root.cardRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: 0

      // prevent click-through to scrim
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          // overlay priority: lightbox → help → settings
          if (root.lightboxVisible) { root.closeLightbox(); event.accepted = true; return }
          if (root.helpVisible) { root.helpVisible = false; event.accepted = true; return }
          if (root.settingsVisible) {
            if (event.key === Qt.Key_Escape) { root.settingsVisible = false; event.accepted = true; return }
            // block list navigation while settings open, let TextInputs handle typing
            if (event.key === Qt.Key_J || event.key === Qt.Key_K || event.key === Qt.Key_Down || event.key === Qt.Key_Up || event.key === Qt.Key_R || event.key === Qt.Key_Slash || event.key === Qt.Key_U) { event.accepted = true; return }
            return
          }
          if (event.text === "?" || event.key === Qt.Key_Question) { root.toggleHelp(); event.accepted = true; return }
          if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) { root.adjustFont(1); event.accepted = true; return }
          if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Minus) { root.adjustFont(-1); event.accepted = true; return }
          if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_0) { root.resetFont(); event.accepted = true; return }
          if (event.key === Qt.Key_U && !searchField.activeFocus) { root.showUnreadOnly = !root.showUnreadOnly; root.selectedIndex = 0; root.showToast(root.showUnreadOnly ? "Unread only" : "All stories"); event.accepted = true; return }
          if (event.key === Qt.Key_Escape) {
            if (root.isFullScreen) { root.isFullScreen = false; event.accepted = true }
            else { root.dismiss(); event.accepted = true }
          } else if (event.key === Qt.Key_F11) {
            root.toggleFullScreen(); event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            root.refresh()
            event.accepted = true
          } else if (event.key === Qt.Key_R) {
            // plain r to refresh when not typing
            if (!searchField.activeFocus) { root.refresh(); event.accepted = true }
          } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.selectNext(1); event.accepted = true
          } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.selectNext(-1); event.accepted = true
          } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            if (root.selectedArticle) root.openExternal(root.selectedArticle)
            event.accepted = true
          } else if (event.key === Qt.Key_Slash) {
            if (!searchField.activeFocus) { searchField.forceActiveFocus(); event.accepted = true }
          } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            if (root.selectedArticle) root.copyLink(root.selectedArticle)
            event.accepted = true
          } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            if (root.selectedArticle) root.shareArticle(root.selectedArticle)
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          anchors.margins: root.contentMargin
          spacing: Style.spacing.md

          // Header
          Row {
            width: parent.width
            spacing: Style.spacing.md

            Column {
              width: parent.width - headerActions.width - Style.spacing.md
              spacing: 2
              Text {
                text: "News Reader"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.loading ? "Refreshing…" : (root.filtered.length + " stories" + (root.unreadCount > 0 ? " · " + root.unreadCount + " unread" : "") + (root.selectedFeedId !== root.allFeedsId ? " · " + root.feedTitle(root.selectedFeedId) : ""))
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: headerActions
              spacing: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter

              // refresh
              Rectangle {
                width: 36; height: 30
                radius: Style.cornerRadius
                color: refreshHover.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1; border.color: root.foreground; opacity: 0.12
                Text {
                  anchors.centerIn: parent
                  text: root.loading ? "…" : "↻"
                  color: root.foreground
                  font.pixelSize: 16
                }
                MouseArea {
                  id: refreshHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refresh()
                }
                PanelToolTip { visible: refreshHover.containsMouse; text: "Refresh feeds (r)" }
              }

              // mark all read
              Rectangle {
                width: 72; height: 30
                radius: Style.cornerRadius
                color: markHover.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1; border.color: root.foreground; opacity: 0.12
                Text {
                  anchors.centerIn: parent
                  text: "Mark read"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: markHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.markAllRead()
                }
              }

              // settings
              Rectangle {
                width: 36; height: 30
                radius: Style.cornerRadius
                color: settingsHover.containsMouse || root.settingsVisible ? root.selectedBackground : "transparent"
                border.width: 1; border.color: root.foreground; opacity: root.settingsVisible ? 0.22 : 0.12
                Text {
                  anchors.centerIn: parent
                  text: "⚙"
                  color: root.foreground
                  font.pixelSize: 14
                }
                MouseArea {
                  id: settingsHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSettings()
                }
                PanelToolTip { visible: settingsHover.containsMouse; text: "Feed settings" }
              }

              // fullscreen — beside X
              Rectangle {
                width: 36; height: 30
                radius: Style.cornerRadius
                color: fsHover.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1; border.color: root.foreground; opacity: 0.12
                Text {
                  anchors.centerIn: parent
                  text: root.isFullScreen ? "🗗" : "⛶"
                  color: root.foreground
                  font.pixelSize: 13
                }
                MouseArea {
                  id: fsHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleFullScreen()
                }
                PanelToolTip { visible: fsHover.containsMouse; text: root.isFullScreen ? "Exit fullscreen (F11)" : "Fullscreen (F11)" }
              }

              // close
              Rectangle {
                width: 36; height: 30
                radius: Style.cornerRadius
                color: closeHover.containsMouse ? Util.alpha(Color.urgent, 0.15) : "transparent"
                border.width: 1; border.color: root.foreground; opacity: 0.12
                Text {
                  anchors.centerIn: parent
                  text: "✕"
                  color: root.foreground
                  font.pixelSize: 13
                }
                MouseArea {
                  id: closeHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.dismiss()
                }
                PanelToolTip { visible: closeHover.containsMouse; text: "Close (Esc)" }
              }
            }
          }

          // Search + filter row
          Row {
            width: parent.width
            spacing: Style.spacing.sm

            // search field
            Rectangle {
              id: searchBox
              width: Math.max(240, Math.min(460, parent.width * 0.32))
              height: 32
              radius: Style.cornerRadius
              color: Style.controlFill(searchField.activeFocus, searchHover.containsMouse, root.foreground, Color.accent)
              border.width: 1
              border.color: searchField.activeFocus ? Color.accent : Util.alpha(root.foreground, root.foreground === Color.foreground ? 0.18 : 0.28)

              Item {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "⌕"
                  color: root.foreground
                  opacity: 0.5
                  font.pixelSize: 13
                }

                TextInput {
                  id: searchField
                  anchors.left: parent.left
                  anchors.leftMargin: 16
                  anchors.right: clearBtn.left
                  anchors.rightMargin: 6
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  selectByMouse: true
                  selectionColor: Color.accent
                  selectedTextColor: root.background
                  text: root.filterText
                  onTextChanged: {
                    if (text !== root.filterText) {
                      root.filterText = text
                      root.selectedIndex = 0
                    }
                  }
                  Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Escape) {
                      if (root.filterText.length > 0) { root.filterText = ""; searchField.text = ""; e.accepted = true }
                      else { keyCatcher.forceActiveFocus(); e.accepted = true }
                    } else if (e.key === Qt.Key_Down) { keyCatcher.forceActiveFocus(); root.selectNext(1); e.accepted = true }
                    else if (e.key === Qt.Key_Up) { keyCatcher.forceActiveFocus(); root.selectNext(-1); e.accepted = true }
                    else if (e.key === Qt.Key_Enter || e.key === Qt.Key_Return) { keyCatcher.forceActiveFocus(); e.accepted = true }
                  }
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 16
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.filterText.length === 0 && !searchField.activeFocus
                  text: "Search headlines or source…  ( / )"
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  id: clearBtn
                  visible: root.filterText.length > 0
                  width: 18; height: 18; radius: 9
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  color: clearHover.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"
                  Text { anchors.centerIn: parent; text: "✕"; color: root.foreground; opacity: 0.7; font.pixelSize: 10 }
                  MouseArea {
                    id: clearHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.filterText = ""; searchField.text = ""; }
                  }
                }
              }

              HoverHandler { id: searchHover }
            }

            // feed chips
            Flickable {
              width: parent.width - searchBox.width - Style.spacing.sm
              height: 32
              clip: true
              contentWidth: chipRow.width
              boundsBehavior: Flickable.StopAtBounds
              Row {
                id: chipRow
                height: 32
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                // All chip — with unread count
                Rectangle {
                  height: 28; width: allChipText.implicitWidth + 18; radius: 14
                  color: root.selectedFeedId === root.allFeedsId ? Color.accent : (allHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06))
                  border.width: root.selectedFeedId === root.allFeedsId ? 0 : 1; border.color: Util.alpha(root.foreground, 0.14)
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    id: allChipText
                    anchors.centerIn: parent
                    text: {
                      var c = NewsModel.feedUnreadCount(root.articles, root.allFeedsId, root.readIds)
                      return c > 0 ? "All · " + c : "All"
                    }
                    color: root.selectedFeedId === root.allFeedsId ? root.background : root.foreground
                    font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: root.selectedFeedId === root.allFeedsId
                  }
                  MouseArea { id: allHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.selectedFeedId = root.allFeedsId; root.selectedIndex = 0 } }
                }

                // Unread toggle
                Rectangle {
                  height: 28; width: unreadChipText.implicitWidth + 18; radius: 14
                  color: root.showUnreadOnly ? Color.accent : (unreadHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06))
                  border.width: root.showUnreadOnly ? 0 : 1; border.color: Util.alpha(root.foreground, 0.14)
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    id: unreadChipText
                    anchors.centerIn: parent
                    text: root.showUnreadOnly ? "Unread ✓" : "Unread"
                    color: root.showUnreadOnly ? root.background : root.foreground
                    font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: root.showUnreadOnly
                  }
                  MouseArea { id: unreadHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.showUnreadOnly = !root.showUnreadOnly; root.selectedIndex = 0; root.showToast(root.showUnreadOnly ? "Unread only" : "All stories") } }
                }

                Repeater {
                  model: root.feeds
                  delegate: Rectangle {
                    required property var modelData
                    required property int index
                    property bool isSelected: root.selectedFeedId === modelData.id
                    height: 28
                    width: chipContent.implicitWidth + 24
                    radius: 14
                    color: isSelected ? Color.accent : (chipHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06))
                    border.width: isSelected ? 0 : 1
                    border.color: Util.alpha(root.foreground, 0.14)
                    anchors.verticalCenter: parent.verticalCenter

                    Row {
                      id: chipContent
                      anchors.centerIn: parent
                      spacing: 5
                      Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: NewsModel.categoryColor(modelData.category)
                      }
                      Text {
                        id: chipText
                        text: {
                          var c = NewsModel.feedUnreadCount(root.articles, modelData.id, root.readIds)
                          return c > 0 ? modelData.title + " · " + c : modelData.title
                        }
                        color: isSelected ? root.background : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: isSelected
                      }
                    }
                    MouseArea {
                      id: chipHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { root.selectedFeedId = modelData.id; root.selectedIndex = 0 }
                    }
                  }
                }
              }
            }
          }

          // Main split: list + detail
          Row {
            width: parent.width
            height: parent.height - 92
            spacing: 0

            // Article list — further reduced so reader dominates even fullscreen
            Rectangle {
              id: listPane
              width: Math.round(parent.width * root.splitRatio)
              height: parent.height
              radius: Style.cornerRadius
              color: Util.alpha(root.foreground, 0.04)
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.08)
              clip: true

              // skeleton loading — 6 shimmer rows
              Column {
                visible: root.loading && root.articles.length === 0
                anchors.fill: parent
                anchors.margins: 6
                spacing: 8
                Repeater {
                  model: 6
                  delegate: Rectangle {
                    width: parent.width
                    height: 68
                    radius: Style.cornerRadius - 2
                    color: Util.alpha(root.foreground, 0.04)
                    Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: 66
                      anchors.rightMargin: 10
                      spacing: 8
                      Rectangle { width: parent.width * 0.72; height: 12; radius: 3; color: Util.alpha(root.foreground, 0.07) }
                      Rectangle { width: parent.width * 0.5; height: 8; radius: 3; color: Util.alpha(root.foreground, 0.05) }
                    }
                    Rectangle {
                      width: 44; height: 44; radius: 6
                      anchors.left: parent.left
                      anchors.leftMargin: 10
                      anchors.verticalCenter: parent.verticalCenter
                      color: Util.alpha(root.foreground, 0.06)
                    }
                  }
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Fetching feeds…"
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              Column {
                anchors.centerIn: parent
                visible: !root.loading && root.filtered.length === 0
                spacing: 8
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.errorText ? "⚠  " + root.errorText : "No stories match"
                  color: root.errorText ? Color.urgent : root.foreground
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  width: 420
                  wrapMode: Text.WordWrap
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.errorText
                  text: "Try another feed or clear search"
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 8
                  visible: !root.loading
                  Rectangle {
                    width: 110; height: 28; radius: 14
                    color: clearSearchHover.containsMouse ? Color.accent : Util.alpha(Color.accent, 0.12)
                    border.width: 1; border.color: Util.alpha(Color.accent, 0.3)
                    visible: root.filterText.length > 0 || root.showUnreadOnly || root.selectedFeedId !== root.allFeedsId
                    Text { anchors.centerIn: parent; text: "Clear filters"; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    MouseArea { id: clearSearchHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.filterText = ""; if (searchField) searchField.text = ""; root.showUnreadOnly = false; root.selectedFeedId = root.allFeedsId; root.selectedIndex = 0 } }
                  }
                  Rectangle {
                    width: 90; height: 28; radius: 14
                    color: retryHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
                    border.width: 1; border.color: Util.alpha(root.foreground, 0.14)
                    visible: root.errorText !== ""
                    Text { anchors.centerIn: parent; text: "Retry"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    MouseArea { id: retryHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refresh() }
                  }
                }
              }

              ListView {
                id: articleList
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                model: root.filtered
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.selectedIndex
                highlightMoveDuration: 120

                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  property bool isSelected: index === root.selectedIndex
                  property bool isRead: root.readIds[modelData.id] === true
                  width: articleList.width
                  height: 72
                  radius: Style.cornerRadius - 2
                  color: isSelected ? root.selectedBackground : (delHover.containsMouse ? Util.alpha(root.foreground, 0.06) : "transparent")
                  border.width: isSelected ? 1 : 0
                  border.color: isSelected ? Util.alpha(Color.accent, 0.35) : "transparent"

                  // unread dot
                  Rectangle {
                    visible: !isRead
                    width: 6; height: 6; radius: 3
                    color: Color.accent
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  // thumbnail — shows feed image or initial
                  Rectangle {
                    id: thumbBox
                    width: 44; height: 44; radius: 6
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Util.alpha(Color.accent, isSelected ? 0.16 : 0.07)
                    clip: true
                    border.width: modelData.image ? 0 : 1
                    border.color: Util.alpha(Color.accent, 0.18)
                    Image {
                      anchors.fill: parent
                      source: modelData.image || ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: true
                      visible: modelData.image && modelData.image.length > 0
                      sourceSize.width: 88
                      sourceSize.height: 88
                    }
                    Text {
                      anchors.centerIn: parent
                      visible: !modelData.image || modelData.image.length === 0
                      text: modelData.feedTitle.charAt(0).toUpperCase()
                      color: Color.accent
                      font.pixelSize: 14
                      font.bold: true
                      font.family: root.fontFamily
                    }
                    MouseArea {
                      anchors.fill: parent
                      z: 2
                      cursorShape: modelData.image && modelData.image.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                      enabled: modelData.image && modelData.image.length > 0
                      onClicked: function(mouse) { root.selectedIndex = index; root.openLightbox(modelData.image); mouse.accepted = true }
                    }
                  }

                  Column {
                    anchors.left: thumbBox.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                      width: parent.width
                      text: root.filterText ? NewsModel.highlightHtml(modelData.title, root.filterText, Color.accent) : NewsModel.escapeHtml(modelData.title)
                      textFormat: Text.RichText
                      color: isSelected ? root.selectedText : root.foreground
                      opacity: isRead && !isSelected ? 0.75 : 1
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: !isRead
                      elide: Text.ElideRight
                      maximumLineCount: 2
                      wrapMode: Text.WordWrap
                    }
                    Row {
                      width: parent.width
                      spacing: 6
                      Text {
                        text: modelData.feedTitle
                        color: isSelected ? root.selectedText : Color.accent
                        opacity: isSelected ? 0.9 : 0.85
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      Text {
                        text: "· " + modelData.pubDateLabel
                        color: root.foreground
                        opacity: isSelected ? 0.7 : 0.5
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        text: "· " + NewsModel.readTimeMins(modelData.description) + "m"
                        color: root.foreground
                        opacity: isSelected ? 0.55 : 0.4
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        width: parent.width - 140
                        visible: modelData.description.length > 0
                        text: "· " + modelData.description
                        color: root.foreground
                        opacity: isSelected ? 0.6 : 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }

                  MouseArea {
                    id: delHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.selectedIndex = index; keyCatcher.forceActiveFocus() }
                    onDoubleClicked: root.openExternal(modelData)
                  }
                }

                // keyboard nav already handled via root.selectNext; also handle wheel
                onCurrentIndexChanged: root.selectedIndex = currentIndex
              }

              // footer actions hint
              Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 22
                color: Util.alpha(root.background, 0.78)
                visible: root.filtered.length > 0
                Text {
                  anchors.centerIn: parent
                  text: "j/k or ↑↓ navigate · Enter open · Ctrl+C copy link · r refresh · / search"
                  color: root.foreground
                  opacity: 0.35
                  font.family: root.fontFamily
                  font.pixelSize: 10
                }
              }
            }

            // draggable splitter handle
            Rectangle {
              id: splitter
              width: 8
              height: parent.height
              color: splitterDrag.drag.active ? Util.alpha(Color.accent, 0.18) : "transparent"
              radius: 4
              Rectangle {
                anchors.centerIn: parent
                width: 2; height: 32; radius: 1
                color: Util.alpha(root.foreground, splitterHover.containsMouse || splitterDrag.drag.active ? 0.28 : 0.14)
              }
              HoverHandler { id: splitterHover }
              MouseArea {
                id: splitterDrag
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.SizeHorCursor
                hoverEnabled: true
                property real startX: 0
                property real startRatio: 0
                onPressed: function(mouse) { startX = mouse.x; startRatio = root.splitRatio }
                onPositionChanged: function(mouse) {
                  if (!pressed) return
                  var dx = mouse.x - startX
                  var total = parent.width
                  var nr = startRatio + dx / total
                  root.splitRatio = Math.max(root.minSplitRatio, Math.min(root.maxSplitRatio, nr))
                }
              }
            }

            // Detail pane — dominates, especially in fullscreen
            Rectangle {
              id: detailPane
              width: parent.width - listPane.width - splitter.width
              height: parent.height
              radius: Style.cornerRadius
              color: root.readingBg
              border.width: 1
              border.color: root.readingPal ? Util.alpha(root.readingFg, 0.15) : Util.alpha(root.foreground, 0.08)
              clip: true

              Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                visible: root.selectedArticle !== null

                Row {
                  width: parent.width
                  spacing: 8
                  Text {
                    width: parent.width - themeSwatches.width - fontControls.width - 16
                    text: root.selectedArticle ? root.selectedArticle.feedTitle.toUpperCase() : ""
                    color: Color.accent
                    opacity: 0.9
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    elide: Text.ElideRight
                  }
                  Row {
                    id: themeSwatches
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                      model: [
                        {key:"auto", label:"Auto"}, {key:"contrast", label:"Contrast"}, {key:"light", label:"Light"},
                        {key:"dark", label:"Dark"}, {key:"sepia", label:"Sepia"}, {key:"grey", label:"Grey"}
                      ]
                      delegate: Rectangle {
                        required property var modelData
                        property bool isSel: root.readingTheme === modelData.key
                        property var pal: root.readingPalette[modelData.key] || null
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: pal ? pal.bg : root.background
                        border.width: isSel ? 2 : 1
                        border.color: isSel ? Color.accent : Util.alpha(root.foreground, 0.25)
                        Text {
                          visible: !pal
                          anchors.centerIn: parent
                          text: "A"
                          color: root.foreground
                          font.pixelSize: 7
                          font.bold: true
                          font.family: root.fontFamily
                        }
                        Rectangle {
                          visible: pal !== null
                          width: 6; height: 6; radius: 3
                          anchors.centerIn: parent
                          color: pal ? pal.fg : "transparent"
                        }
                        MouseArea {
                          id: themeHover
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.setReadingTheme(modelData.key)
                        }
                        PanelToolTip { visible: themeHover.containsMouse; text: "Reading theme: " + modelData.label + (isSel ? " (current)" : "") }
                      }
                    }
                  }
                  Row {
                    id: fontControls
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                      width: 22; height: 18; radius: 4
                      color: fontMinusHover.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"
                      border.width: 1; border.color: Util.alpha(root.foreground, 0.18)
                      Text { anchors.centerIn: parent; text: "A-"; color: root.foreground; opacity: 0.7; font.pixelSize: 9; font.family: root.fontFamily }
                      MouseArea { id: fontMinusHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustFont(-1) }
                      PanelToolTip { visible: fontMinusHover.containsMouse; text: "Smaller text (Ctrl -)" }
                    }
                    Rectangle {
                      width: 22; height: 18; radius: 4
                      color: fontPlusHover.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"
                      border.width: 1; border.color: Util.alpha(root.foreground, 0.18)
                      Text { anchors.centerIn: parent; text: "A+"; color: root.foreground; opacity: 0.7; font.pixelSize: 9; font.family: root.fontFamily }
                      MouseArea { id: fontPlusHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustFont(1) }
                      PanelToolTip { visible: fontPlusHover.containsMouse; text: "Larger text (Ctrl +)" }
                    }
                  }
                }

                Rectangle {
                  visible: root.selectedArticle && root.selectedArticle.image && root.selectedArticle.image.length > 0
                  width: parent.width
                  height: visible ? 160 : 0
                  radius: 6
                  clip: true
                  color: Util.alpha(root.readingFg, 0.04)
                  border.width: 1
                  border.color: Util.alpha(root.readingFg, 0.08)
                  Image {
                    anchors.fill: parent
                    source: root.selectedArticle ? root.selectedArticle.image : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 600
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openLightbox(root.selectedArticle.image)
                  }
                }

                Text {
                  width: parent.width
                  text: root.selectedArticle ? root.selectedArticle.title : ""
                  color: root.readingFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  wrapMode: Text.WordWrap
                }

                Row {
                  width: parent.width
                  spacing: 6
                  Text {
                    text: root.selectedArticle ? root.selectedArticle.pubDateLabel : ""
                    color: root.readingFg
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    text: "· " + NewsModel.readTimeMins(root.articleBody || (root.selectedArticle ? root.selectedArticle.description : "")) + " min"
                    color: root.readingFg
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    visible: root.selectedArticle && root.readIds[root.selectedArticle.id]
                    text: "· read"
                    color: root.readingFg
                    opacity: markUnreadHover.containsMouse ? 0.8 : 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: markUnreadHover.containsMouse
                    MouseArea {
                      id: markUnreadHover
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.selectedArticle) root.markUnread(root.selectedArticle)
                    }
                    PanelToolTip { visible: markUnreadHover.containsMouse; text: "Mark as unread" }
                  }
                  Text {
                    width: parent.width - 160
                    visible: root.selectedArticle && root.selectedArticle.link.length > 0
                    text: root.selectedArticle ? root.selectedArticle.link : ""
                    color: root.readingFg
                    opacity: 0.35
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(root.readingFg, 0.08) }

                // loading / error status for full article
                Row {
                  width: parent.width
                  visible: root.articleLoading || root.articleError !== ""
                  spacing: 6
                  Text {
                    text: root.articleLoading ? "⟳  Loading full article…" : (root.articleError ? "⚠  " + root.articleError : "")
                    color: root.articleError ? Color.urgent : root.readingFg
                    opacity: root.articleLoading ? 0.7 : 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width - (root.articleError ? 60 : 0)
                  }
                  Text {
                    visible: root.articleError !== ""
                    text: "Retry"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.selectedArticle) root.loadArticle(root.selectedArticle)
                    }
                  }
                }

                // read progress — top of article
                Rectangle {
                  width: parent.width
                  height: 2
                  radius: 1
                  color: Util.alpha(root.readingFg, 0.08)
                  visible: articleFlick.contentHeight > articleFlick.height
                  Rectangle {
                    width: parent.width * (articleFlick.contentHeight > articleFlick.height ? Math.min(1, articleFlick.contentY / Math.max(1, articleFlick.contentHeight - articleFlick.height)) : 0)
                    height: 2
                    radius: 1
                    color: Color.accent
                  }
                }

                Flickable {
                  id: articleFlick
                  width: parent.width
                  height: Math.max(180, parent.height - 300)
                  clip: true
                  contentHeight: descText.implicitHeight
                  boundsBehavior: Flickable.StopAtBounds
                  flickableDirection: Flickable.VerticalFlick
                  boundsMovement: Flickable.StopAtBounds
                  Text {
                    id: descText
                    width: parent.width
                    text: {
                      if (!root.selectedArticle) return ""
                      if (root.articleBody && root.articleBody.length > 40) return root.articleBody
                      return root.selectedArticle.description || "No summary available for this story. Open it to read the full article."
                    }
                    color: root.readingFg
                    opacity: root.articleLoading ? 0.6 : 0.85
                    font.family: root.fontFamily
                    font.pixelSize: root.articleFontSize
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    lineHeight: 1.35
                  }
                }

                Row {
                  width: parent.width
                  spacing: 8

                  Rectangle {
                    width: (parent.width - 16) / 2
                    height: 36
                    radius: Style.cornerRadius
                    color: openHover.containsMouse ? Color.accent : Util.alpha(Color.accent, 0.92)
                    Text {
                      anchors.centerIn: parent
                      text: "Open story  ↗"
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                    MouseArea {
                      id: openHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.selectedArticle) root.openExternal(root.selectedArticle)
                    }
                  }

                  Rectangle {
                    width: (parent.width - 16) / 4
                    height: 36
                    radius: Style.cornerRadius
                    color: copyHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
                    border.width: 1
                    border.color: Util.alpha(root.foreground, 0.12)
                    Text {
                      anchors.centerIn: parent
                      text: "Copy link"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      id: copyHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.selectedArticle) root.copyLink(root.selectedArticle)
                    }
                  }

                  Rectangle {
                    width: (parent.width - 16) / 4
                    height: 36
                    radius: Style.cornerRadius
                    color: shareHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
                    border.width: 1
                    border.color: Util.alpha(root.foreground, 0.12)
                    Text {
                      anchors.centerIn: parent
                      text: "Share"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      id: shareHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.selectedArticle) root.shareArticle(root.selectedArticle)
                    }
                    PanelToolTip { visible: shareHover.containsMouse; text: "Copy link + notify (Ctrl+Shift+S)" }
                  }
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(root.readingFg, 0.06) }

                Text {
                  width: parent.width
                  text: "Feeds are fetched live via RSS. Add feeds in Settings (⚙) or import OPML/JSON — see suggested-feeds.json for examples."
                  color: root.readingFg
                  opacity: 0.35
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  wrapMode: Text.WordWrap
                }
              }

              // empty detail
              Column {
                anchors.centerIn: parent
                spacing: 8
                visible: root.selectedArticle === null
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "No story selected"
                  color: root.readingFg
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.filtered.length === 0 ? "Fetch or adjust filters" : "Select a story on the left"
                  color: root.readingFg
                  opacity: 0.35
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
      // settings — feed manager (covers list/detail, keeps header/search visible underneath)
      Rectangle {
        visible: root.settingsVisible
        anchors.fill: parent
        anchors.topMargin: root.cardTopMargin
        color: Util.alpha(root.background, 0.98)
        radius: Style.cornerRadius
        clip: true
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.08)
        MouseArea { anchors.fill: parent; onClicked: {} } // block clicks to underlying list
        Column {
          anchors.fill: parent
          anchors.margins: 14
          spacing: 10
          // header
          Row {
            width: parent.width
            spacing: 8
            Text {
              width: parent.width - 40
              text: "Feed Settings · " + root.feeds.length + " feeds"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }
            Rectangle {
              width: 32; height: 28; radius: 6
              color: settingsCloseHover.containsMouse ? Util.alpha(Color.urgent, 0.12) : Util.alpha(root.foreground, 0.06)
              border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "✕"; color: root.foreground; font.pixelSize: 12 }
              MouseArea { id: settingsCloseHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleSettings() }
            }
          }
          Rectangle { width: parent.width; height: 1; color: Util.alpha(root.foreground, 0.08) }
          // current feeds — scrollable
          Flickable {
            width: parent.width
            height: Math.min(260, contentHeight)
            clip: true
            contentHeight: feedListCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            Column {
              id: feedListCol
              width: parent.width
              spacing: 6
              Repeater {
                model: root.feeds
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  width: feedListCol.width
                  height: 48
                  radius: 6
                  color: Util.alpha(root.foreground, 0.04)
                  border.width: 1; border.color: Util.alpha(root.foreground, 0.08)
                  Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8
                    Column {
                      width: parent.width - 80
                      spacing: 2
                      anchors.verticalCenter: parent.verticalCenter
                      Row {
                        width: parent.width
                        spacing: 6
                        Rectangle {
                          width: 6; height: 6; radius: 3
                          anchors.verticalCenter: parent.verticalCenter
                          color: NewsModel.categoryColor(modelData.category)
                        }
                        Text {
                          width: parent.width - 12
                          text: modelData.title
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                          elide: Text.ElideRight
                        }
                      }
                      Text {
                        width: parent.width
                        text: modelData.url + (modelData.category ? "  ·  " + modelData.category : "")
                        color: root.foreground
                        opacity: 0.5
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideMiddle
                      }
                    }
                    Rectangle {
                      width: 56; height: 28; radius: 6
                      anchors.verticalCenter: parent.verticalCenter
                      color: delHover.containsMouse ? Util.alpha(Color.urgent, 0.14) : Util.alpha(Color.urgent, 0.08)
                      border.width: 1; border.color: Util.alpha(Color.urgent, 0.2)
                      Text { anchors.centerIn: parent; text: "Remove"; color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                      MouseArea { id: delHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeFeed(modelData.id) }
                    }
                  }
                }
              }
            }
          }
          // suggested feeds — bundled starter list, hidden once fully added
          Text {
            visible: suggestedFeedsFlow.count > 0
            text: "Suggested feeds"
            color: root.foreground
            opacity: 0.9
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Flow {
            id: suggestedFeedsFlow
            width: parent.width
            spacing: 6
            property var unadded: root.suggestedFeeds.filter(function(s) {
              return !root.feeds.some(function(f) { return f.url === s.url })
            })
            property int count: unadded.length
            Repeater {
              model: suggestedFeedsFlow.unadded
              delegate: Rectangle {
                required property var modelData
                width: suggestedLabel.implicitWidth + 16
                height: 24
                radius: 12
                color: suggestedHover.containsMouse ? Util.alpha(Color.accent, 0.16) : Util.alpha(root.foreground, 0.06)
                border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
                Text {
                  id: suggestedLabel
                  anchors.centerIn: parent
                  text: "+ " + modelData.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: suggestedHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.addSuggestedFeed(modelData)
                }
                PanelToolTip { visible: suggestedHover.containsMouse; text: modelData.url }
              }
            }
          }
          // add new feed
          Text { text: "Add RSS feed"; color: root.foreground; opacity: 0.9; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
          Row {
            width: parent.width
            spacing: 8
            Rectangle {
              width: parent.width * 0.62
              height: 32
              radius: Style.cornerRadius
              color: Style.controlFill(addUrlField.activeFocus, addUrlHover.containsMouse, root.foreground, Color.accent)
              border.width: 1; border.color: addUrlField.activeFocus ? Color.accent : Util.alpha(root.foreground, 0.14)
              TextInput {
                id: addUrlField
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 10
                verticalAlignment: Text.AlignVCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                selectByMouse: true
                selectionColor: Color.accent
                text: root.newFeedUrl
                onTextChanged: root.newFeedUrl = text
                Keys.onReturnPressed: root.addFeed()
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: addUrlField.text.length === 0 && !addUrlField.activeFocus
                text: "https://example.com/rss.xml"
                color: root.foreground; opacity: 0.35
                font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
              HoverHandler { id: addUrlHover }
            }
            Rectangle {
              width: parent.width * 0.22
              height: 32
              radius: Style.cornerRadius
              color: Style.controlFill(addTitleField.activeFocus, addTitleHover.containsMouse, root.foreground, Color.accent)
              border.width: 1; border.color: addTitleField.activeFocus ? Color.accent : Util.alpha(root.foreground, 0.14)
              TextInput {
                id: addTitleField
                anchors.fill: parent
                anchors.leftMargin: 8; anchors.rightMargin: 8
                verticalAlignment: Text.AlignVCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                selectByMouse: true
                text: root.newFeedTitle
                onTextChanged: root.newFeedTitle = text
                Keys.onReturnPressed: root.addFeed()
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: addTitleField.text.length === 0 && !addTitleField.activeFocus
                text: "Title (optional)"
                color: root.foreground; opacity: 0.35
                font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
              HoverHandler { id: addTitleHover }
            }
            Rectangle {
              width: parent.width - (parent.width * 0.62 + parent.width * 0.22 + 16)
              height: 32
              radius: Style.cornerRadius
              color: addHover.containsMouse ? Color.accent : Util.alpha(Color.accent, 0.88)
              Text { anchors.centerIn: parent; text: "Add"; color: Color.background; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
              MouseArea { id: addHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addFeed() }
            }
          }
          // import / export
          Text { text: "Import / Export"; color: root.foreground; opacity: 0.9; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
          Rectangle {
            width: parent.width
            height: 72
            radius: 6
            color: Util.alpha(root.foreground, 0.04)
            border.width: 1; border.color: Util.alpha(root.foreground, 0.08)
            Flickable {
              anchors.fill: parent
              anchors.margins: 8
              clip: true
              contentHeight: importField.implicitHeight
              flickableDirection: Flickable.VerticalFlick
              TextEdit {
                id: importField
                width: parent.width
                wrapMode: TextEdit.Wrap
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                selectByMouse: true
                text: root.importText
                onTextChanged: root.importText = text
              }
            }
            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: 10
              visible: importField.text.length === 0
              text: "Paste JSON array or OPML <outline> here for import…"
              color: root.foreground; opacity: 0.3
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
          }
          Row {
            width: parent.width
            spacing: 8
            Rectangle {
              width: (parent.width - 16) / 3
              height: 30
              radius: Style.cornerRadius
              color: importHover.containsMouse ? Color.accent : Util.alpha(Color.accent, 0.88)
              Text { anchors.centerIn: parent; text: "Import"; color: Color.background; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
              MouseArea { id: importHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.importFeeds() }
            }
            Rectangle {
              width: (parent.width - 16) / 3
              height: 30
              radius: Style.cornerRadius
              color: exportJsonHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
              border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "Export JSON"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { id: exportJsonHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.exportFeedsJson() }
            }
            Rectangle {
              width: (parent.width - 16) / 3
              height: 30
              radius: Style.cornerRadius
              color: exportOpmlHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
              border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "Export OPML"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { id: exportOpmlHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.exportFeedsOpml() }
            }
          }
          Text {
            width: parent.width
            visible: root.settingsError !== "" || root.settingsInfo !== ""
            text: root.settingsError || root.settingsInfo
            color: root.settingsError ? Color.urgent : Color.accent
            opacity: 0.9
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Text {
            width: parent.width
            text: "Tip: JSON is an array of {title,url}. OPML from Feedly/Inoreader works too. Exports go to ~/Downloads + clipboard."
            color: root.foreground; opacity: 0.35
            font.family: root.fontFamily; font.pixelSize: 10; wrapMode: Text.WordWrap
          }
        }
      }
      // toast feedback — bottom-center of card
      Rectangle {
        visible: root.toastVisible
        width: Math.min(parent.width - root.cardOuterMargin, toastRow.implicitWidth + 28)
        height: 32
        radius: 16
        color: Color.foreground
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: visible ? 0.98 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Row {
          id: toastRow
          anchors.centerIn: parent
          spacing: 12
          Text {
            id: toastLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.toastText
            color: Color.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Text {
            visible: root.toastActionLabel !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.toastActionLabel
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.underline: toastActionHover.containsMouse
            MouseArea {
              id: toastActionHover
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (typeof root.toastAction === "function") root.toastAction()
                root.toastVisible = false
              }
            }
          }
        }
      }
    }
    // lightbox — fullscreen image viewer
    Rectangle {
      visible: root.lightboxVisible
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.92)
      MouseArea { anchors.fill: parent; onClicked: root.closeLightbox(); cursorShape: Qt.PointingHandCursor }
      Image {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, implicitWidth > 0 ? implicitWidth : parent.width - 64)
        height: Math.min(parent.height - 64, implicitHeight > 0 ? implicitHeight : parent.height - 64)
        source: root.lightboxImage
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: true
      }
      Rectangle {
        width: 36; height: 36; radius: 18
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        color: Util.alpha(Color.foreground, 0.12)
        Text { anchors.centerIn: parent; text: "✕"; color: Color.foreground; font.pixelSize: 16 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeLightbox() }
      }
    }
    // help overlay — press ? to toggle
    Rectangle {
      visible: root.helpVisible
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.72)
      MouseArea { anchors.fill: parent; onClicked: root.helpVisible = false }
      BorderSurface {
        width: Math.min(520, parent.width - root.cardOuterMargin)
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
        padding: 16
        Column {
          width: parent.width
          spacing: 12
          Text { text: "News Reader — Shortcuts"; color: Color.menu.text; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
          Grid {
            columns: 2
            columnSpacing: 16
            rowSpacing: 6
            width: parent.width
            Repeater {
              model: [
                {k:"j / ↓", v:"Next story"}, {k:"k / ↑", v:"Prev story"},
                {k:"Enter", v:"Open story"}, {k:"/", v:"Focus search"},
                {k:"Ctrl+C", v:"Copy link"}, {k:"Ctrl+Shift+S / Share", v:"Share"},
                {k:"r", v:"Refresh"}, {k:"u", v:"Toggle unread"},
                {k:"Ctrl + / - / 0", v:"Font + / - / reset"}, {k:"F11 / ⛶", v:"Fullscreen"},
                {k:"?", v:"Toggle help"}, {k:"Esc", v:"Close / exit fullscreen"}
              ]
              delegate: Row {
                required property var modelData
                spacing: 8
                width: parent.width / 2 - 8
                Text { width: 110; text: modelData.k; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; elide: Text.ElideRight }
                Text { text: modelData.v; color: Color.menu.text; opacity: 0.85; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; width: parent.width - 118 }
              }
            }
          }
          Text { width: parent.width; text: "Tip: Drag the center splitter to resize list vs reader. Click thumbnail to open image. Chip counts show unread."; color: Color.menu.text; opacity: 0.55; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Rectangle {
            width: parent.width; height: 32; radius: Style.cornerRadius
            color: Color.accent
            Text { anchors.centerIn: parent; text: "Got it — Esc to close"; color: Color.menu.background; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.helpVisible = false }
          }
        }
      }
    }
  }
}
