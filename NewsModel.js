.pragma library

// Sentinel for "all feeds" — single source instead of repeated "__all" strings
var ALL_FEEDS_ID = "__all"

// Centralized limits (3) — tune parser/collection without hunting literals
var Limits = {
    MAX_DESC_LENGTH: 220,
    MAX_PER_FEED: 40,
    MAX_TOTAL_ARTICLES: 150,
    MAX_ARTICLE_CACHE: 60,
    MAX_READ_IDS: 800,
    MAX_ARTICLE_BLOCKS: 40,
    MIN_BLOCK_CHARS: 40,
    MAX_FALLBACK_CHARS: 1800,
    MAX_JOINED_CHARS: 9000,
    MAX_JOINED_JOIN: 7000,
    WORDS_PER_MIN: 220,
    CJK_CHARS_PER_MIN: 450,
    MIN_CJK_FOR_READTIME: 80,
    MIN_WORDS_FOR_READTIME: 30,
    // article-extract size guards — previously inline 600/800 literals (Overlay extractArticle)
    MIN_ARTICLE_LENGTH: 600,
    MIN_MAIN_LENGTH: 600,
    MIN_DIV_CLASS_LENGTH: 800,
    MIN_DIV_LENGTH: 600,
    MIN_CACHED_BODY_LENGTH: 80,
    // retained-field caps — remote XML and user-writable state must not inflate
    // shell state unboundedly (security baseline finding, issue #2230)
    MAX_TITLE_LENGTH: 300,
    MAX_LINK_LENGTH: 2048,
    MAX_GUID_LENGTH: 512,
    MAX_IMAGE_URL_LENGTH: 2048,
    MAX_FEEDS: 100,
    MAX_FEED_ID_LENGTH: 128,
    MAX_FEED_TITLE_LENGTH: 160,
    MAX_FEED_URL_LENGTH: 2048,
    MAX_FEED_CATEGORY_LENGTH: 64
}

function decodeEntities(s) {
    if (!s) return ""
    return String(s)
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&amp;/g, "&")
        .replace(/&quot;/g, "\"")
        .replace(/&apos;/g, "'")
        .replace(/&#(\d+);/g, function(_, n) { return String.fromCharCode(Number(n)) })
        .replace(/&#x([0-9a-fA-F]+);/g, function(_, n) { return String.fromCharCode(parseInt(n, 16)) })
}

function stripTags(s) {
    if (!s) return ""
    return String(s).replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim()
}

function extractTag(block, tag) {
    // Handles <tag>..</tag> and <tag><![CDATA[..]]></tag>, case-insensitive
    var re = new RegExp("<" + tag + "[^>]*>([\\s\\S]*?)<\\/" + tag + ">", "i")
    var m = block.match(re)
    if (!m) return ""
    var raw = m[1].trim()
    // CDATA
    var cdata = raw.match(/<!\[CDATA\[([\s\S]*?)\]\]>/i)
    if (cdata) raw = cdata[1]
    return decodeEntities(stripTags(raw))
}

function extractAttr(block, tag, attr) {
    var re = new RegExp("<" + tag + "[^>]*\\b" + attr + "\\s*=\\s*['\"]([^'\"]+)['\"]", "i")
    var m = block.match(re)
    return m ? m[1].trim() : ""
}

function extractLink(block) {
    // Prefer <link>text</link> (RSS) then <link href="..."> (Atom)
    var linkText = extractTag(block, "link")
    if (linkText && linkText.indexOf("http") === 0) return linkText
    var href = extractAttr(block, "link", "href")
    if (href) return href
    // Atom may have multiple links; grab first href
    var m = block.match(/<link[^>]*href\s*=\s*['"]([^'"]+)['"]/i)
    return m ? m[1] : ""
}

function extractDate(block) {
    var s = extractTag(block, "pubDate") || extractTag(block, "published") || extractTag(block, "updated") || extractTag(block, "dc:date") || ""
    if (!s) return 0
    var t = Date.parse(s)
    return isFinite(t) ? t : 0
}

function capStr(s, max) {
    var t = String(s || "")
    return t.length > max ? t.slice(0, max) + "…" : t
}

// Validate + bound one feed entry from user-writable state or user paste.
// Returns null when the entry is not a usable http(s) feed.
function sanitizeFeed(f) {
    if (!f || typeof f !== "object" || Array.isArray(f)) return null
    var url = String(f.url || "").trim()
    if (url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0) return null
    var id = String(f.id || "").trim()
    var title = String(f.title || f.name || "").trim()
    if (!title) {
        try { title = new URL(url).hostname.replace(/^www\./, "") } catch(e) { title = url }
    }
    return {
        id: capStr(id, Limits.MAX_FEED_ID_LENGTH),
        title: capStr(title, Limits.MAX_FEED_TITLE_LENGTH),
        url: capStr(url, Limits.MAX_FEED_URL_LENGTH),
        category: capStr(String(f.category || ""), Limits.MAX_FEED_CATEGORY_LENGTH)
    }
}

function sanitizeFeeds(list) {
    if (!Array.isArray(list)) return []
    var out = []
    for (var i = 0; i < list.length && out.length < Limits.MAX_FEEDS; i++) {
        var f = sanitizeFeed(list[i])
        if (f) out.push(f)
    }
    return out
}

function parseRss(xmlText, feedId, feedTitle) {
    var out = []
    if (!xmlText) return out
    var text = String(xmlText)

    // Find items: <item> (RSS) or <entry> (Atom)
    var itemRe = /<(item|entry)[\s>][\s\S]*?<\/\1>/gi
    var items
    var seen = 0
    while ((items = itemRe.exec(text)) !== null) {
        var block = items[0]
        var title = extractTag(block, "title")
        if (!title) continue
        var link = extractLink(block)
        var desc = extractTag(block, "description") || extractTag(block, "summary") || extractTag(block, "content") || ""
        // Fallback content:encoded
        if (!desc) {
            var ce = block.match(/<content:encoded[^>]*>([\s\S]*?)<\/content:encoded>/i)
            if (ce) {
                var c = ce[1].trim()
                var cd = c.match(/<!\[CDATA\[([\s\S]*?)\]\]>/i)
                if (cd) c = cd[1]
                desc = decodeEntities(stripTags(c))
            }
        }
        if (desc.length > Limits.MAX_DESC_LENGTH) desc = desc.slice(0, Limits.MAX_DESC_LENGTH) + "…"
        var pub = extractDate(block)
        var guid = extractTag(block, "guid") || link || (feedId + ":" + title)
        // image: enclosure / media:thumbnail / first img in description
        var img = extractAttr(block, "enclosure", "url") || extractAttr(block, "media:thumbnail", "url") || extractAttr(block, "media:content", "url") || ""
        if (!img) {
            var imgM = block.match(/<img[^>]+src\s*=\s*['"]([^'"]+)['"]/i)
            if (imgM) img = imgM[1]
        }
        if (img && img.indexOf("http") !== 0 && img.indexOf("//") === 0) img = "https:" + img
        // crude image filter: ignore icons / 1px
        if (img && (img.indexOf("icon") !== -1 || img.indexOf("avatar") !== -1)) img = ""
        out.push({
            id: capStr(guid, Limits.MAX_GUID_LENGTH),
            feedId: feedId,
            feedTitle: feedTitle,
            title: capStr(title, Limits.MAX_TITLE_LENGTH),
            link: capStr(link, Limits.MAX_LINK_LENGTH),
            description: desc,
            image: img ? capStr(img, Limits.MAX_IMAGE_URL_LENGTH) : "",
            pubDate: pub,
            pubDateLabel: pub ? timeAgo(pub) : ""
        })
        seen++
        if (seen >= Limits.MAX_PER_FEED) break
    }
    // Sort newest first
    out.sort(function(a, b) { return b.pubDate - a.pubDate })
    return out
}

function timeAgo(epochMs) {
    var now = Date.now()
    var diff = Math.max(0, now - epochMs)
    var sec = Math.floor(diff / 1000)
    if (sec < 60) return "just now"
    var min = Math.floor(sec / 60)
    if (min < 60) return min + "m ago"
    var hr = Math.floor(min / 60)
    if (hr < 24) return hr + "h ago"
    var days = Math.floor(hr / 24)
    if (days < 7) return days + "d ago"
    var d = new Date(epochMs)
    return d.toLocaleDateString()
}

function filterArticles(articles, filterText, feedId) {
    var out = []
    var q = String(filterText || "").trim().toLowerCase()
    for (var i = 0; i < articles.length; i++) {
        var a = articles[i]
        if (feedId && feedId !== ALL_FEEDS_ID && a.feedId !== feedId) continue
        if (q) {
            var hay = (a.title + " " + a.description + " " + a.feedTitle).toLowerCase()
            if (hay.indexOf(q) === -1) continue
        }
        out.push(a)
    }
    return out
}

function extractArticle(html) {
    if (!html) return ""
    var s = String(html)
    // strip scripts/styles/nav/header/footer quickly
    s = s.replace(/<script[\s\S]*?<\/script>/gi, " ")
         .replace(/<style[\s\S]*?<\/style>/gi, " ")
         .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
         .replace(/<header[\s\S]*?<\/header>/gi, " ")
         .replace(/<footer[\s\S]*?<\/footer>/gi, " ")
         .replace(/<nav[\s\S]*?<\/nav>/gi, " ")
         .replace(/<aside[\s\S]*?<\/aside>/gi, " ")
    var article = ""
    var m = s.match(/<article[^>]*>([\s\S]*?)<\/article>/i)
    if (m && m[1].length > Limits.MIN_ARTICLE_LENGTH) article = m[1]
    else {
        m = s.match(/<main[^>]*>([\s\S]*?)<\/main>/i)
        if (m && m[1].length > Limits.MIN_MAIN_LENGTH) article = m[1]
        else {
            var divRe = /<div[^>]*class="[^"]*(?:post|article|story|content|entry)[^"]*"[^>]*>([\s\S]*?)<\/div>/gi
            var best = ""; var bestCount = 0; var dm
            while ((dm = divRe.exec(s)) !== null) {
                var inner = dm[1]
                var c = (inner.match(/<p[^>]*>/gi) || []).length
                if (c > bestCount && inner.length > Limits.MIN_DIV_CLASS_LENGTH) { bestCount = c; best = inner }
            }
            if (best) article = best
            else {
                // fallback: try largest div by <p> count without class filter
                divRe = /<div[^>]*>([\s\S]*?)<\/div>/gi
                best = ""; bestCount = 0
                while ((dm = divRe.exec(s)) !== null) {
                    var inner2 = dm[1]
                    var c2 = (inner2.match(/<p[^>]*>/gi) || []).length
                    if (c2 > bestCount && inner2.length > Limits.MIN_DIV_LENGTH) { bestCount = c2; best = inner2 }
                }
                article = best || s
            }
        }
    }
    // extract block elements
    var out = []
    var pRe = /<(p|h[1-3]|li|blockquote)[^>]*>([\s\S]*?)<\/\1>/gi
    var pm
    while ((pm = pRe.exec(article)) !== null) {
        var raw = pm[2].replace(/<br\s*\/?>/gi, " ")
        var txt = decodeEntities(stripTags(raw)).replace(/\s+/g, " ").trim()
        if (txt.length < Limits.MIN_BLOCK_CHARS) continue
        // skip boilerplate
        if (/^(subscribe|sign up|copyright|all rights reserved|follow us|share this)/i.test(txt)) continue
        out.push(txt)
        if (out.length >= Limits.MAX_ARTICLE_BLOCKS) break
        if (out.join("\n\n").length > Limits.MAX_JOINED_JOIN) break
    }
    if (out.length === 0) {
        var fallback = decodeEntities(stripTags(article)).replace(/\s+/g, " ").trim()
        if (fallback.length > Limits.MAX_FALLBACK_CHARS) fallback = fallback.slice(0, Limits.MAX_FALLBACK_CHARS) + "…"
        return fallback
    }
    var joined = out.join("\n\n")
    if (joined.length > Limits.MAX_JOINED_CHARS) joined = joined.slice(0, Limits.MAX_JOINED_CHARS) + "…"
    return joined
}

function readTimeMins(text) {
    var t = String(text || "")
    // CJK (JP/CN/KR) has no spaces — count characters instead of words
    if (/[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af]/.test(t)) {
        var chars = t.replace(/\s/g, "").length
        if (chars < Limits.MIN_CJK_FOR_READTIME) return 1
        return Math.max(1, Math.ceil(chars / Limits.CJK_CHARS_PER_MIN))
    }
    var words = t.trim().split(/\s+/).filter(function(w){ return w.length>0 }).length
    if (words < Limits.MIN_WORDS_FOR_READTIME) return 1
    return Math.max(1, Math.ceil(words / Limits.WORDS_PER_MIN))
}

function escapeHtml(s) {
    return String(s||"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;")
}

function highlightHtml(title, query, accentColor) {
    var q = String(query||"").trim()
    if (!q) return escapeHtml(title)
    var esc = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    try {
        var re = new RegExp("(" + esc + ")", "ig")
        // QML RichText supports <font> and <b>; accent comes from theme (caller passes Color.accent)
        var color = accentColor || "#7daea3"
        return escapeHtml(title).replace(re, '<font color="' + color + '"><b>$1</b></font>')
    } catch(e) { return escapeHtml(title) }
}

function feedUnreadCount(articles, feedId, readIds) {
    var c=0
    for (var i=0;i<articles.length;i++) {
        var a=articles[i]
        if (feedId !== ALL_FEEDS_ID && a.feedId !== feedId) continue
        if (!readIds[a.id]) c++
    }
    return c
}

function categoryColor(category) {
    var c = String(category || "General")
    var hash = 0
    for (var i = 0; i < c.length; i++) hash = (hash * 31 + c.charCodeAt(i)) | 0
    var hue = Math.abs(hash) % 360
    return hslToHex(hue, 55, 55)
}

function hslToHex(h, s, l) {
    s /= 100; l /= 100
    var k = function(n) { return (n + h / 30) % 12 }
    var a = s * Math.min(l, 1 - l)
    var f = function(n) { return l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1))) }
    var toHex = function(x) { var v = Math.round(255 * x); var s = v.toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + toHex(f(0)) + toHex(f(8)) + toHex(f(4))
}

function defaultFeeds() {
    // No hard-coded feeds — user configures via Settings or
    // ~/.local/state/omarchy/news-reader-feeds.json .
    // See suggested-feeds.json for open source tech / open science examples.
    return []
}
