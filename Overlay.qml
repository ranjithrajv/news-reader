import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "NewsModel.js" as NewsModel
import "Config.js" as Config
import "I18n.js" as I18n

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
  readonly property string autoRefreshPath: stateDir + "news-reader-autorefresh.json"
  readonly property string localePath: stateDir + "news-reader-locale.json"
  readonly property string suggestedFeedsPath: Qt.resolvedUrl("suggested-feeds.json").toString()
  // Embedded fallback — mirrors suggested-feeds.json so first run works even
  // if the bundled FileView load fails or races persisted-state loading.
  readonly property var defaultFeeds: [
    { id: "default_hackernews", title: "Hacker News", url: "https://news.ycombinator.com/rss", category: "Open Source" },
    { id: "default_lobsters", title: "Lobste.rs", url: "https://lobste.rs/rss", category: "Open Source" },
    { id: "default_phoronix", title: "Phoronix", url: "https://www.phoronix.com/rss.php", category: "Open Source" },
    { id: "default_itsfoss", title: "It's FOSS", url: "https://itsfoss.com/feed/", category: "Open Source" },
    { id: "default_arxiv_cs", title: "arXiv CS", url: "https://rss.arxiv.org/rss/cs", category: "Open Science" },
    { id: "default_plosone", title: "PLOS ONE", url: "https://journals.plos.org/plosone/feed/atom", category: "Open Science" },
    { id: "default_sciencedaily", title: "ScienceDaily", url: "https://www.sciencedaily.com/rss/all.xml", category: "Open Science" }
  ]

  // --- Auto-refresh interval options — hourly (60m) is the default ---
  readonly property var autoRefreshOptions: [
    { min: 60,       key: "hourly" },
    { min: 60 * 24,  key: "daily" },
    { min: 60 * 24 * 7, key: "weekly" }
  ]
  readonly property int autoRefreshDefaultMs: 60 * 60 * 1000

  // --- i18n — locale auto-detected from the system, overridable in Settings ---
  property string locale: I18n.resolveLocale(Qt.uiLanguages(), I18n.Locales)
  readonly property bool isRtl: I18n.isRtl(root.locale)
  function tr(key, vars) { return I18n.t(root.locale, key, vars) }

  // --- Fetch config (2) ---
  readonly property int feedFetchTimeoutSec: 8
  readonly property int articleFetchTimeoutSec: 10
  readonly property int feedMaxBytes: 500000
  readonly property int articleMaxBytes: 700000
  readonly property string curlUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
  readonly property string curlAccept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  readonly property string curlAcceptLang: "en-US,en;q=0.9"

  // --- Timing config (3) ---
  property int autoRefreshIntervalMs: autoRefreshDefaultMs
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
  property bool feedsLoaded: false
  property bool feedsSeeded: false
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
    var base = NewsModel.filterArticles(root.articles, root.filterText, root.selectedFeedId, root.articleCache)
    if (!root.showUnreadOnly) return base
    var out = []
    for (var i = 0; i < base.length; i++) if (!root.readIds[base[i].id]) out.push(base[i])
    return out
  }
  // feeds grouped into folders by category, for the chip bar and Settings
  readonly property var groupedFeeds: NewsModel.groupFeedsByCategory(root.feeds)
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
  property string addFeedError: ""
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
      showToast(root.tr("toast.fontSize", { n: next }))
    }
  }
  function resetFont() { root.articleFontSize = root.fontSizeDefault; fontSizeFile.setText(String(root.fontSizeDefault)); showToast(root.tr("toast.fontReset")) }
  function setReadingTheme(t) {
    if (root.readingTheme === t) return
    root.readingTheme = t
    readingThemeFile.setText(t)
    showToast(root.tr("toast.readingTheme", { theme: root.tr("theme." + t) }))
  }
  function setAutoRefresh(ms) {
    if (!isFinite(ms) || ms <= 0) return
    root.autoRefreshIntervalMs = ms
    autoRefreshFile.setText(String(ms))
    autoRefresh.restart()
    var opt = null
    for (var i = 0; i < root.autoRefreshOptions.length; i++) if (root.autoRefreshOptions[i].min * 60 * 1000 === ms) opt = root.autoRefreshOptions[i]
    var value = opt ? root.tr("interval." + opt.key) : Math.round(ms / 60000) + "m"
    showToast(root.tr("toast.autoRefresh", { value: value }))
  }
  function setLocale(loc) {
    var l = I18n.Locales.indexOf(loc) !== -1 ? loc : "en"
    if (root.locale === l) return
    root.locale = l
    localeFile.setText(l)
    showToast(root.tr("toast.languageChanged", { name: I18n.LocaleNames[l] }))
  }
  function openLightbox(url) { if (!url) return; root.lightboxImage = url; root.lightboxVisible = true }
  function closeLightbox() { root.lightboxVisible = false }
  function setImportText(t) { root.importText = t || "" }
  function debugAddFeed(url, title) { root.newFeedUrl = url || ""; root.newFeedTitle = title || ""; addFeed() }

  function toggleSettings() {
    root.settingsVisible = !root.settingsVisible
    root.settingsError = ""; root.settingsInfo = ""
    if (root.settingsVisible) root.reloadFeedsState()
  }
  function saveFeeds() {
    try { feedsFile.setText(JSON.stringify(root.feeds, null, 2)); root.settingsInfo = root.tr("toast.feedsSaved"); root.showToast(root.tr("toast.feedsSaved")) } catch(e){ root.settingsError = root.tr("error.saveFailed", { error: e }) }
  }
  function addFeed() {
    var url = String(root.newFeedUrl||"").trim()
    var title = String(root.newFeedTitle||"").trim()
    root.settingsError = ""; root.settingsInfo = ""; root.addFeedError = ""
    if (!url) { root.addFeedError = root.tr("error.urlRequired"); return }
    if (url.indexOf("http") !== 0) url = "https://" + url
    try { var u = new URL(url); if (!u.hostname) throw "bad url" } catch(e){ root.addFeedError = root.tr("error.invalidUrl"); return }
    for (var i=0;i<root.feeds.length;i++) if (root.feeds[i].url === url) { root.addFeedError = root.tr("error.feedExists"); return }
    if (root.feeds.length >= NewsModel.Limits.MAX_FEEDS) { root.addFeedError = root.tr("error.feedLimit", { max: NewsModel.Limits.MAX_FEEDS }); return }
    var id = url.replace(/[^a-zA-Z0-9]/g,"_").slice(0,24) + "_" + Date.now().toString(36)
    if (!title) {
      try { title = new URL(url).hostname.replace(/^www\./,"") } catch(e){ title = "Feed " + (root.feeds.length+1) }
    }
    var clean = NewsModel.sanitizeFeed({ id: id, title: title, url: url, category: "Custom" })
    if (!clean) { root.settingsError = root.tr("error.invalidUrl"); return }
    var next = root.feeds.slice()
    next.push(clean)
    root.feeds = next
    saveFeeds()
    root.newFeedUrl = ""; root.newFeedTitle = ""
    root.settingsInfo = root.tr("toast.feedAddedNamed", { title: clean.title })
    root.showToast(root.tr("toast.feedAdded"))
  }
  function addSuggestedFeed(feed) {
    root.settingsError = ""; root.settingsInfo = ""
    var clean = NewsModel.sanitizeFeed(feed)
    if (!clean || !clean.url) { root.settingsError = root.tr("error.invalidFeed"); return }
    for (var i=0;i<root.feeds.length;i++) if (root.feeds[i].url === clean.url) { root.settingsError = root.tr("error.feedExists"); return }
    if (root.feeds.length >= NewsModel.Limits.MAX_FEEDS) { root.settingsError = root.tr("error.feedLimit", { max: NewsModel.Limits.MAX_FEEDS }); return }
    var id = clean.url.replace(/[^a-zA-Z0-9]/g,"_").slice(0,24) + "_" + Date.now().toString(36)
    var next = root.feeds.slice()
    next.push({ id: id, title: clean.title, url: clean.url, category: clean.category || "Custom" })
    root.feeds = next
    saveFeeds()
    root.settingsInfo = root.tr("toast.feedAddedNamed", { title: clean.title })
    root.showToast(root.tr("toast.feedAdded"))
  }
  function setFeedCategory(id, category) {
    var cat = NewsModel.capStr(String(category || "").trim() || "General", NewsModel.Limits.MAX_FEED_CATEGORY_LENGTH)
    var next = root.feeds.slice()
    var changed = false
    for (var i = 0; i < next.length; i++) {
      if (next[i].id !== id || next[i].category === cat) continue
      next[i] = { id: next[i].id, title: next[i].title, url: next[i].url, category: cat }
      changed = true
      break
    }
    if (!changed) return
    root.feeds = next
    saveFeeds()
  }
  function removeFeed(id) {
    var next = [], removed = null
    for (var i=0;i<root.feeds.length;i++) { if (root.feeds[i].id !== id) next.push(root.feeds[i]); else removed = root.feeds[i] }
    if (!removed) return
    if (next.length === 0) { root.settingsError = root.tr("error.keepAtLeastOne"); return }
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
    root.showToast(root.tr("toast.feedRemovedNamed", { title: removed.title }), root.tr("toast.undo"), root.undoRemoveFeed)
  }
  function undoRemoveFeed() {
    if (!root.pendingUndoFeed) return
    if (root.feeds.length >= NewsModel.Limits.MAX_FEEDS) { root.showToast(root.tr("error.feedLimitPlain")); return }
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
    root.showToast(root.tr("toast.feedRestored"))
  }
  function importFeeds() {
    var txt = String(root.importText||"").trim()
    root.settingsError = ""; root.settingsInfo = ""
    if (!txt) { root.settingsError = root.tr("error.pasteFirst"); return }
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
    if (!list || !Array.isArray(list) || list.length===0) { root.settingsError = root.tr("error.noFeedsFound"); return }
    var added=0, skipped=0
    var next = root.feeds.slice()
    var seen={}
    for (var i=0;i<next.length;i++) seen[next[i].url]=true
    for (var j=0;j<list.length;j++) {
      if (next.length >= NewsModel.Limits.MAX_FEEDS) break
      var clean = NewsModel.sanitizeFeed(list[j])
      if (!clean) { skipped++; continue }
      if (seen[clean.url]) { skipped++; continue }
      var tid = clean.id || clean.url.replace(/[^a-zA-Z0-9]/g,"_").slice(0,24) + "_" + Date.now().toString(36) + j
      next.push({ id: tid, title: clean.title, url: clean.url, category: clean.category || "Imported" })
      seen[clean.url]=true; added++
    }
    if (added===0) { root.settingsError = root.tr("error.noNewFeeds"); return }
    root.feeds = next
    saveFeeds()
    root.importText = ""
    root.settingsInfo = root.tr("toast.importedCount", { n: added }) + (skipped ? root.tr("toast.importedSkipped", { n: skipped }) : "")
    root.showToast(root.tr("toast.importedCount", { n: added }))
  }
  function exportFeedsJson() {
    var js = JSON.stringify(root.feeds, null, 2)
    var path = root.exportJsonPath
    exportFile.setText(js)
    // also copy to clipboard
    Quickshell.execDetached(["bash","-c","printf %s " + Util.shellQuote(js) + " | wl-copy; notify-send -a 'News Reader' " + Util.shellQuote(root.tr("toast.exportedJson")) + " 'Downloads/news-reader-feeds.json' 2>/dev/null || true"])
    root.settingsInfo = root.tr("toast.exportedJsonInfo")
    root.showToast(root.tr("toast.exportedJson"))
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
    Quickshell.execDetached(["bash","-c","printf %s " + Util.shellQuote(xml) + " | wl-copy; notify-send -a 'News Reader' " + Util.shellQuote(root.tr("toast.exportedOpml")) + " 'Downloads/news-reader-feeds.opml' 2>/dev/null || true"])
    root.settingsInfo = root.tr("toast.exportedOpmlInfo")
    root.showToast(root.tr("toast.exportedOpml"))
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
    root.reloadReadIds()
    root.reloadFeedsState()
    // Retry bundled suggested feeds every open — startup FileView load may
    // have failed or raced, and seeding depends on it.
    suggestedFeedsFileView.reload()
    // Synchronous first-run seed from embedded defaults so the overlay never
    // idles on "no feeds" waiting for async callbacks.
    if (root.feeds.length === 0) root.maybeSeedDefaultFeeds()
    // Fetch only once feeds are known — applyFeedsState() triggers refresh
    // when feeds arrive. If feeds are already in memory, refresh now.
    if (root.feedsLoaded && root.feeds.length > 0) {
      if (root.articles.length === 0) root.refresh()
    } else if (root.feedsLoaded && root.feeds.length === 0) {
      root.maybeSeedDefaultFeeds()
      if (root.feeds.length > 0) { if (root.articles.length === 0) root.refresh() }
      else if (!root.errorText) root.errorText = root.tr("error.noFeedsConfigured")
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
      root.shell.hide((root.manifest && root.manifest.id) || "ranjithraj.news-reader")
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
    root.showToast(root.tr("toast.noHardcodedTestData"))
  }

  function fetchNext() {
    if (root.feeds.length === 0) {
      root.loading = false
      if (!root.errorText) root.errorText = root.tr("error.noFeedsConfigured")
      return
    }
    if (root.fetchCursor >= root.feeds.length) {
      root.loading = false
      if (root.articles.length === 0 && !root.errorText) root.errorText = root.tr("error.noArticles")
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
      if (root.fetchCursor === 0) root.errorText = root.tr("error.couldNotFetch", { feed: feed.title })
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
        if (root.fetchCursor === 0) root.errorText = root.tr("error.parseErrorFeed", { feed: feed.title, error: e })
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
        root.articleError = root.tr("error.couldNotLoadArticle")
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
        root.articleError = root.tr("error.parseError", { error: e })
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
    root.showToast(root.tr("toast.markedUnread"))
  }
  function markAllRead() {
    var next = {}
    for (var k in root.readIds) next[k] = root.readIds[k]
    for (var i = 0; i < root.filtered.length; i++) next[root.filtered[i].id] = true
    root.readIds = next
    persistReadIds()
    root.showToast(root.tr("toast.markedNRead", { n: root.filtered.length }))
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
    root.showToast(root.tr("toast.linkCopied"))
  }

  function shareArticle(article) {
    if (!article || !article.link) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(article.link) + " | wl-copy; notify-send -a 'News Reader' 'Shared — link copied' " + Util.shellQuote(article.title) + " 2>/dev/null || true"])
    root.markRead(article)
    root.showToast(root.tr("toast.sharedLinkCopied"))
  }

  function selectNext(delta) {
    if (root.filtered.length === 0) return
    var n = root.filtered.length
    root.selectedIndex = (root.selectedIndex + delta + n) % n
    articleList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // persistence for read ids — loaded through bounded regular-file/no-follow
  // readers (security baseline): user-writable state never reaches shell state
  // uncapped.
  function applyReadIds(t) {
    try {
      var o = JSON.parse(String(t || ""))
      if (!o || typeof o !== "object" || Array.isArray(o)) return
      var keys = Object.keys(o)
      var capped = {}
      var start = Math.max(0, keys.length - NewsModel.Limits.MAX_READ_IDS)
      for (var i = start; i < keys.length; i++) capped[keys[i]] = true
      root.readIds = capped
    } catch(e) {}
  }
  function applyFeedsState(t) {
    try {
      var clean = NewsModel.sanitizeFeeds(JSON.parse(String(t || "")))
      if (clean.length > 0) {
        var hadNone = root.feeds.length === 0
        root.feeds = clean
        root.feedsLoaded = true
        if (hadNone && root.opened && root.articles.length === 0 && !root.loading) root.refresh()
        return
      }
    } catch(e) {}
    // No persisted feeds (first run / empty state): seed from suggested feeds
    // so the plugin loads content by default instead of idling on "no feeds".
    root.maybeSeedDefaultFeeds()
    root.feedsLoaded = true
    if (root.feeds.length > 0 && root.opened && root.articles.length === 0 && !root.loading) root.refresh()
    else if (root.feeds.length === 0 && root.opened && root.articles.length === 0 && !root.loading) {
      // still nothing to fetch — surface the empty-state error
      if (!root.errorText) root.errorText = root.tr("error.noFeedsConfigured")
    }
  }
  function maybeSeedDefaultFeeds() {
    if (root.feeds.length > 0) return
    // Prefer loaded suggested feeds, fall back to embedded defaults so a
    // failed/racing FileView load can never leave first run with no feeds.
    var source = (root.suggestedFeeds && root.suggestedFeeds.length > 0) ? root.suggestedFeeds : root.defaultFeeds
    if (!source || source.length === 0) return
    var next = []
    for (var i = 0; i < source.length; i++) {
      var clean = NewsModel.sanitizeFeed(source[i])
      if (!clean || !clean.url) continue
      var tid = clean.id
      if (!tid) tid = clean.url.replace(/[^a-zA-Z0-9]/g, "_").slice(0, 24) + "_" + Date.now().toString(36) + i
      next.push({ id: tid, title: clean.title, url: clean.url, category: clean.category || "General" })
      if (next.length >= NewsModel.Limits.MAX_FEEDS) break
    }
    if (next.length === 0) return
    root.feeds = next
    try { feedsFile.setText(JSON.stringify(root.feeds, null, 2)) } catch(e) {}
  }
  function applyFontSize(t) {
    var n = parseInt(String(t || "").trim(), 10)
    if (isFinite(n) && n >= root.fontSizeMin && n <= root.fontSizeMax) root.articleFontSize = n
  }
  function applyReadingTheme(t) {
    var s = String(t || "").trim()
    if (s in root.readingPalette || s === "auto") root.readingTheme = s
  }
  function applyAutoRefresh(t) {
    var n = parseInt(String(t || "").trim(), 10)
    if (isFinite(n) && n > 0) root.autoRefreshIntervalMs = n
  }
  function applyLocale(t) {
    var l = String(t || "").trim()
    if (I18n.Locales.indexOf(l) !== -1) root.locale = l
  }

  // queued bounded reader for all writable state files — a single Process
  // can only serve one read at a time, so queue requests instead of sharing
  // one sink (which dropped all but the last callback on startup/open).
  property var stateReadQueue: []
  property bool stateReadBusy: false
  property var stateReadCurrent: null
  Process {
    id: stateReader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishStateRead(String(text || ""))
    }
  }
  function readStateFile(path, sink) {
    root.stateReadQueue.push({ path: path, sink: sink })
    root.pumpStateQueue()
  }
  function pumpStateQueue() {
    if (root.stateReadBusy || root.stateReadQueue.length === 0) return
    if (stateReader.running) return
    var next = root.stateReadQueue[0]
    root.stateReadCurrent = next
    root.stateReadBusy = true
    stateReader.command = ["bash", "-c", Config.stateReadCmd(next.path, Config.stateMaxBytes)]
    stateReader.running = true
  }
  function finishStateRead(text) {
    var cur = root.stateReadCurrent
    root.stateReadQueue.shift()
    root.stateReadCurrent = null
    root.stateReadBusy = false
    try { if (cur && cur.sink) cur.sink(text) } catch(e) {}
    // drain the queue on the next tick so Process has settled
    Qt.callLater(root.pumpStateQueue)
  }
  function reloadReadIds()      { root.readStateFile(root.readIdsPath, root.applyReadIds) }
  function reloadFontSize()     { root.readStateFile(root.fontSizePath, root.applyFontSize) }
  function reloadReadingTheme() { root.readStateFile(root.readingThemePath, root.applyReadingTheme) }
  function reloadAutoRefresh()  { root.readStateFile(root.autoRefreshPath, root.applyAutoRefresh) }
  function reloadLocale()       { root.readStateFile(root.localePath, root.applyLocale) }
  function reloadFeedsState()   { root.readStateFile(root.feedsPath, root.applyFeedsState) }

  FileView {
    id: readFile
    path: root.readIdsPath
    preload: false
  }
  FileView {
    id: unreadFile
    path: root.unreadPath
    preload: false
  }
  FileView {
    id: fontSizeFile
    path: root.fontSizePath
    preload: false
  }
  FileView {
    id: feedsFile
    path: root.feedsPath
    preload: false
  }
  FileView {
    id: readingThemeFile
    path: root.readingThemePath
    preload: false
  }
  FileView {
    id: autoRefreshFile
    path: root.autoRefreshPath
    preload: false
  }
  FileView {
    id: localeFile
    path: root.localePath
    preload: false
  }
  FileView { id: exportFile; path: root.exportJsonPath; preload: false }
  FileView { id: exportFileOpml; path: root.exportOpmlPath; preload: false }
  FileView {
    id: suggestedFeedsFileView
    path: root.suggestedFeedsPath
    onLoaded: {
      try { root.suggestedFeeds = NewsModel.sanitizeFeeds(JSON.parse(text())) } catch(e){}
      // First run: no persisted feeds yet — seed defaults so content loads.
      if (root.feedsLoaded && root.feeds.length === 0 && root.suggestedFeeds.length > 0) {
        root.maybeSeedDefaultFeeds()
        if (root.feeds.length > 0 && root.opened && root.articles.length === 0 && !root.loading) root.refresh()
      }
    }
    onLoadFailed: {
      // Bundled file unreadable — fall back to embedded defaults so first
      // run still loads feeds instead of idling empty.
      if (root.suggestedFeeds.length === 0) root.suggestedFeeds = NewsModel.sanitizeFeeds(root.defaultFeeds)
      if (root.feedsLoaded && root.feeds.length === 0) {
        root.maybeSeedDefaultFeeds()
        if (root.feeds.length > 0 && root.opened && root.articles.length === 0 && !root.loading) root.refresh()
      }
    }
  }
  Component.onCompleted: { root.reloadFontSize(); root.reloadFeedsState(); root.reloadReadingTheme(); root.reloadAutoRefresh(); root.reloadLocale(); suggestedFeedsFileView.reload(); if (root.feeds.length === 0) root.maybeSeedDefaultFeeds() }
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
        root.showToast(root.tr("toast.markedRead"))
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
          if (event.key === Qt.Key_U && !searchField.activeFocus) { root.showUnreadOnly = !root.showUnreadOnly; root.selectedIndex = 0; root.showToast(root.showUnreadOnly ? root.tr("toast.unreadOnlyOn") : root.tr("toast.unreadOnlyOff")); event.accepted = true; return }
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
                text: root.tr("toolbar.title")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.loading ? root.tr("toolbar.statusRefreshing") : (root.filtered.length + " " + root.tr(root.filtered.length === 1 ? "toolbar.statusStory" : "toolbar.statusStories") + (root.unreadCount > 0 ? " · " + root.unreadCount + " " + root.tr("toolbar.statusUnread") : "") + (root.selectedFeedId !== root.allFeedsId ? " · " + root.feedTitle(root.selectedFeedId) : ""))
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
                PanelToolTip { visible: refreshHover.containsMouse; text: root.tr("toolbar.tooltipRefresh") }
              }

              // mark all read
              Rectangle {
                width: 72; height: 30
                radius: Style.cornerRadius
                color: markHover.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1; border.color: root.foreground; opacity: 0.12
                Text {
                  anchors.centerIn: parent
                  text: root.tr("toolbar.markRead")
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
                PanelToolTip { visible: settingsHover.containsMouse; text: root.tr("toolbar.tooltipSettings") }
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
                PanelToolTip { visible: fsHover.containsMouse; text: root.isFullScreen ? root.tr("toolbar.tooltipFullscreenExit") : root.tr("toolbar.tooltipFullscreenEnter") }
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
                PanelToolTip { visible: closeHover.containsMouse; text: root.tr("toolbar.tooltipClose") }
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
                  text: root.tr("search.placeholder")
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
                      return c > 0 ? root.tr("chips.all") + " · " + c : root.tr("chips.all")
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
                    text: root.showUnreadOnly ? root.tr("chips.unreadOn") : root.tr("chips.unread")
                    color: root.showUnreadOnly ? root.background : root.foreground
                    font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: root.showUnreadOnly
                  }
                  MouseArea { id: unreadHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.showUnreadOnly = !root.showUnreadOnly; root.selectedIndex = 0; root.showToast(root.showUnreadOnly ? root.tr("toast.unreadOnlyOn") : root.tr("toast.unreadOnlyOff")) } }
                }

                Repeater {
                  model: root.groupedFeeds
                  delegate: Row {
                    id: folderChips
                    required property var modelData
                    height: 32
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      visible: root.groupedFeeds.length > 1
                      text: folderChips.modelData.category
                      color: root.foreground
                      opacity: 0.35
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Repeater {
                      model: folderChips.modelData.feeds
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
                  text: root.tr("list.loading")
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
                  text: root.errorText ? "⚠  " + root.errorText : root.tr("list.noMatch")
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
                  text: root.tr("list.tryAnother")
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
                    Text { anchors.centerIn: parent; text: root.tr("list.clearFilters"); color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    MouseArea { id: clearSearchHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.filterText = ""; if (searchField) searchField.text = ""; root.showUnreadOnly = false; root.selectedFeedId = root.allFeedsId; root.selectedIndex = 0 } }
                  }
                  Rectangle {
                    width: 90; height: 28; radius: 14
                    color: retryHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
                    border.width: 1; border.color: Util.alpha(root.foreground, 0.14)
                    visible: root.errorText !== ""
                    Text { anchors.centerIn: parent; text: root.tr("list.retry"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
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
                  text: root.tr("list.footerHint")
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
                    width: parent.width
                    text: root.selectedArticle ? root.selectedArticle.feedTitle.toUpperCase() : ""
                    color: Color.accent
                    opacity: 0.9
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    elide: Text.ElideRight
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
                    text: "· " + NewsModel.readTimeMins(root.articleBody || (root.selectedArticle ? root.selectedArticle.description : "")) + " " + root.tr("detail.min")
                    color: root.readingFg
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    visible: root.selectedArticle && root.readIds[root.selectedArticle.id]
                    text: "· " + root.tr("detail.read")
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
                    PanelToolTip { visible: markUnreadHover.containsMouse; text: root.tr("detail.markUnreadTooltip") }
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
                    text: root.articleLoading ? "⟳  " + root.tr("detail.loadingArticle") : (root.articleError ? "⚠  " + root.articleError : "")
                    color: root.articleError ? Color.urgent : root.readingFg
                    opacity: root.articleLoading ? 0.7 : 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width - (root.articleError ? 60 : 0)
                  }
                  Text {
                    visible: root.articleError !== ""
                    text: root.tr("detail.retry")
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
                      return root.selectedArticle.description || root.tr("detail.noSummary")
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
                      text: root.tr("detail.openStory")
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
                      text: root.tr("detail.copyLink")
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
                      text: root.tr("detail.share")
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
                    PanelToolTip { visible: shareHover.containsMouse; text: root.tr("detail.shareTooltip") }
                  }
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(root.readingFg, 0.06) }

                Text {
                  width: parent.width
                  text: root.tr("detail.footerNote")
                  color: root.readingFg
                  opacity: 0.35
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  wrapMode: Text.WordWrap
                  horizontalAlignment: root.isRtl ? Text.AlignRight : Text.AlignLeft
                }
              }

              // empty detail
              Column {
                anchors.centerIn: parent
                spacing: 8
                visible: root.selectedArticle === null
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.tr("detail.noneSelected")
                  color: root.readingFg
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.filtered.length === 0 ? root.tr("detail.fetchOrAdjust") : root.tr("detail.selectStory")
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
        Flickable {
          id: settingsFlick
          anchors.fill: parent
          anchors.margins: 14
          clip: true
          contentHeight: settingsCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          Column {
            id: settingsCol
            width: parent.width
            spacing: 10
            // header
            Row {
              width: parent.width
              spacing: 8
              Text {
                width: parent.width - 40
                text: root.tr("settings.titlePrefix") + " · " + root.tr("settings.feedsCount", { n: root.feeds.length })
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
            // ---- Feeds section ----
            Text { text: root.tr("settings.feeds"); color: root.foreground; opacity: 0.9; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
            // current feeds
            Column {
              id: feedListCol
              width: parent.width
              spacing: 10
              visible: root.feeds.length > 0
              Repeater {
                model: root.groupedFeeds
                delegate: Column {
                  id: folderGroup
                  required property var modelData
                  width: feedListCol.width
                  spacing: 6
                  Text {
                    text: folderGroup.modelData.category + " · " + folderGroup.modelData.feeds.length
                    color: root.foreground
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Repeater {
                    model: folderGroup.modelData.feeds
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
                          width: parent.width - 164
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
                            text: modelData.url
                            color: root.foreground
                            opacity: 0.5
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideMiddle
                          }
                        }
                        Rectangle {
                          width: 84; height: 22; radius: 4
                          anchors.verticalCenter: parent.verticalCenter
                          color: Util.alpha(root.foreground, folderField.activeFocus ? 0.10 : 0.05)
                          border.width: 1; border.color: Util.alpha(root.foreground, folderField.activeFocus ? 0.3 : 0.14)
                          TextInput {
                            id: folderField
                            anchors.fill: parent
                            anchors.margins: 4
                            text: modelData.category || "General"
                            color: root.foreground
                            opacity: 0.7
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            selectByMouse: true
                            clip: true
                            onEditingFinished: root.setFeedCategory(modelData.id, text)
                            Keys.onReturnPressed: folderField.focus = false
                          }
                          PanelToolTip { visible: folderField.activeFocus; text: root.tr("settings.folderTooltip") }
                        }
                        Rectangle {
                          width: 56; height: 28; radius: 6
                          anchors.verticalCenter: parent.verticalCenter
                          color: delHover.containsMouse ? Util.alpha(Color.urgent, 0.14) : Util.alpha(Color.urgent, 0.08)
                          border.width: 1; border.color: Util.alpha(Color.urgent, 0.2)
                          Text { anchors.centerIn: parent; text: root.tr("settings.remove"); color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                          MouseArea { id: delHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeFeed(modelData.id) }
                        }
                      }
                    }
                  }
                }
              }
            }
            // empty state
            Text {
              visible: root.feeds.length === 0
              width: parent.width
              text: root.tr("settings.noFeeds")
              color: root.foreground; opacity: 0.5
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: root.isRtl ? Text.AlignRight : Text.AlignLeft
            }
            // suggested feeds — bundled starter list, hidden once fully added
            Text {
              visible: suggestedFeedsFlow.count > 0
              text: root.tr("settings.suggested")
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
            Text { text: root.tr("settings.addFeed"); color: root.foreground; opacity: 0.9; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
            Row {
              width: parent.width
              spacing: 8
              Rectangle {
                width: parent.width * 0.62
                height: 32
                radius: Style.cornerRadius
                color: root.addFeedError ? Util.alpha(Color.urgent, 0.10) : Style.controlFill(addUrlField.activeFocus, addUrlHover.containsMouse, root.foreground, Color.accent)
                border.width: 1; border.color: root.addFeedError ? Color.urgent : (addUrlField.activeFocus ? Color.accent : Util.alpha(root.foreground, 0.14))
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
                  onTextChanged: { root.newFeedUrl = text; if (root.addFeedError) root.addFeedError = "" }
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
                  text: root.tr("settings.titlePlaceholder")
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
                Text { anchors.centerIn: parent; text: root.tr("settings.add"); color: Color.background; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                MouseArea { id: addHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addFeed() }
              }
            }
            // inline add-feed validation
            Text {
              visible: root.addFeedError !== ""
              width: parent.width
              text: root.addFeedError
              color: Color.urgent
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
            // import / export
            Text { text: root.tr("settings.importExport"); color: root.foreground; opacity: 0.9; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
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
                text: root.tr("settings.importPlaceholder")
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
                Text { anchors.centerIn: parent; text: root.tr("settings.import"); color: Color.background; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                MouseArea { id: importHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.importFeeds() }
              }
              Rectangle {
                width: (parent.width - 16) / 3
                height: 30
                radius: Style.cornerRadius
                color: exportJsonHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
                border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
                Text { anchors.centerIn: parent; text: root.tr("settings.exportJson"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                MouseArea { id: exportJsonHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.exportFeedsJson() }
              }
              Rectangle {
                width: (parent.width - 16) / 3
                height: 30
                radius: Style.cornerRadius
                color: exportOpmlHover.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.06)
                border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
                Text { anchors.centerIn: parent; text: root.tr("settings.exportOpml"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                MouseArea { id: exportOpmlHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.exportFeedsOpml() }
              }
            }
            Rectangle { width: parent.width; height: 1; color: Util.alpha(root.foreground, 0.08) }
            // ---- Preferences section ----
            Text { text: root.tr("settings.preferences"); color: root.foreground; opacity: 0.9; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
            // language
            Text { text: root.tr("settings.language"); color: root.foreground; opacity: 0.8; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width
              spacing: 6
              Repeater {
                model: I18n.Locales
                delegate: Rectangle {
                  required property var modelData
                  property bool isSel: root.locale === modelData
                  width: langLabel.implicitWidth + 18
                  height: 26
                  radius: 13
                  color: isSel ? Color.accent : (langHover.containsMouse ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.06))
                  border.width: 1
                  border.color: isSel ? Color.accent : Util.alpha(root.foreground, 0.12)
                  Text {
                    id: langLabel
                    anchors.centerIn: parent
                    text: I18n.LocaleNames[modelData]
                    color: isSel ? Color.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: isSel
                  }
                  MouseArea {
                    id: langHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setLocale(modelData)
                  }
                }
              }
            }
            // auto-refresh interval
            Text { text: root.tr("settings.autoRefreshInterval"); color: root.foreground; opacity: 0.8; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width
              spacing: 6
              Repeater {
                model: root.autoRefreshOptions
                delegate: Rectangle {
                  required property var modelData
                  property int ms: modelData.min * 60 * 1000
                  property bool isSel: root.autoRefreshIntervalMs === ms
                  width: arLabel.implicitWidth + 18
                  height: 26
                  radius: 13
                  color: isSel ? Color.accent : (arHover.containsMouse ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.06))
                  border.width: 1
                  border.color: isSel ? Color.accent : Util.alpha(root.foreground, 0.12)
                  Text {
                    id: arLabel
                    anchors.centerIn: parent
                    text: root.tr("interval." + modelData.key)
                    color: isSel ? Color.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: isSel
                  }
                  MouseArea {
                    id: arHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setAutoRefresh(ms)
                  }
                }
              }
            }
            // reading theme — consistent chip style (#8)
            Text { text: root.tr("settings.readingTheme"); color: root.foreground; opacity: 0.8; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width
              spacing: 6
              Repeater {
                model: [
                  {key:"auto"}, {key:"contrast"}, {key:"light"},
                  {key:"dark"}, {key:"sepia"}, {key:"grey"}
                ]
                delegate: Rectangle {
                  required property var modelData
                  property bool isSel: root.readingTheme === modelData.key
                  property var pal: root.readingPalette[modelData.key] || null
                  width: rtLabel.implicitWidth + 22
                  height: 26
                  radius: 13
                  color: isSel ? Color.accent : (rtHover.containsMouse ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.06))
                  border.width: 1
                  border.color: isSel ? Color.accent : Util.alpha(root.foreground, 0.12)
                  Row {
                    anchors.centerIn: parent
                    spacing: 5
                    Rectangle {
                      visible: pal !== null
                      width: 12; height: 12; radius: 6
                      anchors.verticalCenter: parent.verticalCenter
                      color: pal ? pal.bg : "#888"
                      border.width: 1; border.color: Util.alpha(root.foreground, 0.3)
                    }
                    Text {
                      id: rtLabel
                      text: root.tr("theme." + modelData.key)
                      color: isSel ? Color.background : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: isSel
                    }
                  }
                  MouseArea {
                    id: rtHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setReadingTheme(modelData.key)
                  }
                }
              }
            }
            // font size
            Text { text: root.tr("settings.fontSize"); color: root.foreground; opacity: 0.8; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Row {
              width: parent.width
              spacing: 8
              Rectangle {
                width: 30; height: 26; radius: 13
                color: fMinusHover.containsMouse ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.06)
                border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
                Text { anchors.centerIn: parent; text: "A−"; color: root.foreground; font.pixelSize: 10; font.family: root.fontFamily }
                MouseArea { id: fMinusHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustFont(-1) }
              }
              Text {
                width: parent.width - 2 * 30 - 54 - 3 * 8
                horizontalAlignment: Text.AlignHCenter
                text: root.articleFontSize + "px"
                color: root.foreground
                font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
              Rectangle {
                width: 30; height: 26; radius: 13
                color: fPlusHover.containsMouse ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.06)
                border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
                Text { anchors.centerIn: parent; text: "A+"; color: root.foreground; font.pixelSize: 10; font.family: root.fontFamily }
                MouseArea { id: fPlusHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustFont(1) }
              }
              Rectangle {
                width: 54; height: 26; radius: 13
                color: fResetHover.containsMouse ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.06)
                border.width: 1; border.color: Util.alpha(root.foreground, 0.12)
                Text { anchors.centerIn: parent; text: root.tr("fontctl.reset"); color: root.foreground; font.pixelSize: Style.font.caption; font.family: root.fontFamily }
                MouseArea { id: fResetHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resetFont() }
              }
            }
            Text {
              width: parent.width
              text: root.tr("settings.fontSizeNote")
              color: root.foreground; opacity: 0.35
              font.family: root.fontFamily; font.pixelSize: 10; wrapMode: Text.WordWrap
              horizontalAlignment: root.isRtl ? Text.AlignRight : Text.AlignLeft
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
              text: root.tr("settings.tipImportExport")
              color: root.foreground; opacity: 0.35
              font.family: root.fontFamily; font.pixelSize: 10; wrapMode: Text.WordWrap
              horizontalAlignment: root.isRtl ? Text.AlignRight : Text.AlignLeft
            }
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
          Text { text: root.tr("shortcuts.title"); color: Color.menu.text; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
          Grid {
            columns: 2
            columnSpacing: 16
            rowSpacing: 6
            width: parent.width
            Repeater {
              model: [
                {k:"j / ↓", vKey:"shortcuts.nextStory"}, {k:"k / ↑", vKey:"shortcuts.prevStory"},
                {k:"Enter", vKey:"shortcuts.openStory"}, {k:"/", vKey:"shortcuts.focusSearch"},
                {k:"Ctrl+C", vKey:"detail.copyLink"}, {k:"Ctrl+Shift+S / Share", vKey:"detail.share"},
                {k:"r", vKey:"shortcuts.refresh"}, {k:"u", vKey:"shortcuts.toggleUnread"},
                {k:"Ctrl + / - / 0", vKey:"shortcuts.fontAdjust"}, {k:"F11 / ⛶", vKey:"shortcuts.fullscreen"},
                {k:"?", vKey:"shortcuts.toggleHelp"}, {k:"Esc", vKey:"shortcuts.closeOrExit"}
              ]
              delegate: Row {
                required property var modelData
                spacing: 8
                width: parent.width / 2 - 8
                Text { width: 110; text: modelData.k; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; elide: Text.ElideRight }
                Text { text: root.tr(modelData.vKey); color: Color.menu.text; opacity: 0.85; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; width: parent.width - 118 }
              }
            }
          }
          Text { width: parent.width; text: root.tr("shortcuts.tip"); color: Color.menu.text; opacity: 0.55; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; horizontalAlignment: root.isRtl ? Text.AlignRight : Text.AlignLeft }
          Rectangle {
            width: parent.width; height: 32; radius: Style.cornerRadius
            color: Color.accent
            Text { anchors.centerIn: parent; text: root.tr("shortcuts.gotIt"); color: Color.menu.background; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.helpVisible = false }
          }
        }
      }
    }
  }
}
