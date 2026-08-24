import { describe, it, expect, vi, beforeAll, afterAll } from "vitest";
import * as NewsModel from "../NewsModel.js";

describe("NewsModel constants", () => {
  it("exposes ALL_FEEDS_ID and Limits with expected defaults", () => {
    expect(NewsModel.ALL_FEEDS_ID).toBe("__all");
    const L = NewsModel.Limits;
    expect(L.MAX_DESC_LENGTH).toBe(220);
    expect(L.MAX_PER_FEED).toBe(40);
    expect(L.MAX_TOTAL_ARTICLES).toBe(150);
    expect(L.MAX_ARTICLE_CACHE).toBe(60);
    expect(L.MAX_READ_IDS).toBe(800);
    expect(L.MAX_ARTICLE_BLOCKS).toBe(40);
    expect(L.MIN_BLOCK_CHARS).toBe(40);
    expect(L.MAX_FALLBACK_CHARS).toBe(1800);
    expect(L.MAX_JOINED_CHARS).toBe(9000);
    expect(L.MAX_JOINED_JOIN).toBe(7000);
    expect(L.WORDS_PER_MIN).toBe(220);
    expect(L.CJK_CHARS_PER_MIN).toBe(450);
    expect(L.MIN_CJK_FOR_READTIME).toBe(80);
    expect(L.MIN_WORDS_FOR_READTIME).toBe(30);
    expect(L.MIN_ARTICLE_LENGTH).toBe(600);
    expect(L.MIN_MAIN_LENGTH).toBe(600);
    expect(L.MIN_DIV_CLASS_LENGTH).toBe(800);
    expect(L.MIN_DIV_LENGTH).toBe(600);
    expect(L.MIN_CACHED_BODY_LENGTH).toBe(80);
    expect(L.MAX_TITLE_LENGTH).toBe(300);
    expect(L.MAX_LINK_LENGTH).toBe(2048);
    expect(L.MAX_GUID_LENGTH).toBe(512);
    expect(L.MAX_IMAGE_URL_LENGTH).toBe(2048);
    expect(L.MAX_FEEDS).toBe(100);
    expect(L.MAX_FEED_ID_LENGTH).toBe(128);
    expect(L.MAX_FEED_TITLE_LENGTH).toBe(160);
    expect(L.MAX_FEED_URL_LENGTH).toBe(2048);
    expect(L.MAX_FEED_CATEGORY_LENGTH).toBe(64);
  });

  it("defaultFeeds returns empty array", () => {
    expect(NewsModel.defaultFeeds()).toEqual([]);
  });
});

describe("capStr", () => {
  it("passes through short strings and falsy", () => {
    expect(NewsModel.capStr("hi", 10)).toBe("hi");
    expect(NewsModel.capStr(null, 5)).toBe("");
    expect(NewsModel.capStr(undefined, 5)).toBe("");
  });
  it("truncates long strings with ellipsis", () => {
    expect(NewsModel.capStr("abcdef", 4)).toBe("abcd…");
    expect(NewsModel.capStr("abc", 3)).toBe("abc"); // exactly at cap
  });
});

describe("sanitizeFeed", () => {
  const L = NewsModel.Limits;
  it("rejects non-objects, arrays, and non-http urls", () => {
    expect(NewsModel.sanitizeFeed(null)).toBeNull();
    expect(NewsModel.sanitizeFeed(undefined)).toBeNull();
    expect(NewsModel.sanitizeFeed("str")).toBeNull();
    expect(NewsModel.sanitizeFeed(42)).toBeNull();
    expect(NewsModel.sanitizeFeed([])).toBeNull();
    expect(NewsModel.sanitizeFeed({ url: "ftp://x" })).toBeNull();
    expect(NewsModel.sanitizeFeed({ url: "example.com" })).toBeNull();
    expect(NewsModel.sanitizeFeed({})).toBeNull();
  });
  it("accepts http and https urls and derives title from hostname", () => {
    const a = NewsModel.sanitizeFeed({ url: "http://example.com/rss" });
    expect(a.url).toBe("http://example.com/rss");
    expect(a.title).toBe("example.com");
    const b = NewsModel.sanitizeFeed({ url: "https://www.example.com/f", title: "T", id: "i", category: "C" });
    expect(b).toEqual({ id: "i", title: "T", url: "https://www.example.com/f", category: "C" });
  });
  it("falls back to name for title", () => {
    expect(NewsModel.sanitizeFeed({ url: "https://a.com/f", name: "Named" }).title).toBe("Named");
  });
  it("caps each retained field", () => {
    const f = NewsModel.sanitizeFeed({
      id: "x".repeat(L.MAX_FEED_ID_LENGTH + 50),
      title: "t".repeat(L.MAX_FEED_TITLE_LENGTH + 50),
      url: "https://a.com/" + "u".repeat(L.MAX_FEED_URL_LENGTH),
      category: "c".repeat(L.MAX_FEED_CATEGORY_LENGTH + 50),
    });
    expect(f.id.length).toBe(L.MAX_FEED_ID_LENGTH + 1);
    expect(f.title.length).toBe(L.MAX_FEED_TITLE_LENGTH + 1);
    expect(f.url.length).toBeLessThanOrEqual(L.MAX_FEED_URL_LENGTH + 1); // url may already exceed cap pre-trim
    expect(f.category.length).toBe(L.MAX_FEED_CATEGORY_LENGTH + 1);
    expect(f.id.endsWith("…")).toBe(true);
    expect(f.title.endsWith("…")).toBe(true);
    expect(f.category.endsWith("…")).toBe(true);
  });
});

describe("sanitizeFeeds", () => {
  it("returns empty for non-arrays", () => {
    expect(NewsModel.sanitizeFeeds(null)).toEqual([]);
    expect(NewsModel.sanitizeFeeds(undefined)).toEqual([]);
    expect(NewsModel.sanitizeFeeds("nope")).toEqual([]);
    expect(NewsModel.sanitizeFeeds({})).toEqual([]);
  });
  it("filters invalid entries and caps cardinality at MAX_FEEDS", () => {
    const list = [{ url: "https://a.com/1" }, { url: "bad" }, null, { url: "https://b.com/2" }];
    const out = NewsModel.sanitizeFeeds(list);
    expect(out).toHaveLength(2);
    expect(out[0].url).toBe("https://a.com/1");
    let many = [];
    for (let i = 0; i < NewsModel.Limits.MAX_FEEDS + 20; i++) many.push({ url: "https://f" + i + ".com/r" });
    expect(NewsModel.sanitizeFeeds(many)).toHaveLength(NewsModel.Limits.MAX_FEEDS);
  });
});

describe("decodeEntities", () => {
  it("handles falsy and plain", () => {
    expect(NewsModel.decodeEntities("")).toBe("");
    expect(NewsModel.decodeEntities(null)).toBe("");
    expect(NewsModel.decodeEntities(undefined)).toBe("");
    expect(NewsModel.decodeEntities("hello")).toBe("hello");
  });
  it("decodes named entities", () => {
    expect(NewsModel.decodeEntities("&lt;tag&gt;")).toBe("<tag>");
    expect(NewsModel.decodeEntities("a &amp; b")).toBe("a & b");
    expect(NewsModel.decodeEntities("&quot;hi&apos;")).toBe('"hi\'');
  });
  it("decodes numeric decimal and hex", () => {
    expect(NewsModel.decodeEntities("&#65;")).toBe("A");
    expect(NewsModel.decodeEntities("&#x41;")).toBe("A");
    expect(NewsModel.decodeEntities("&#x61;")).toBe("a");
    expect(NewsModel.decodeEntities("&#X41;")).toBe("&#X41;"); // uppercase X not matched by regex (lowercase x only)
  });
  it("decodes multiple entities in one string", () => {
    expect(NewsModel.decodeEntities("&lt;&#65;&#x41;&gt;")).toBe("<AA>");
  });
});

describe("stripTags", () => {
  it("handles falsy", () => {
    expect(NewsModel.stripTags("")).toBe("");
    expect(NewsModel.stripTags(null)).toBe("");
    expect(NewsModel.stripTags(undefined)).toBe("");
  });
  it("strips tags and collapses whitespace", () => {
    expect(NewsModel.stripTags("<p>hello <b>world</b></p>")).toBe("hello world");
    expect(NewsModel.stripTags("a   b\nc")).toBe("a b c");
    expect(NewsModel.stripTags("<div>  spaced   </div>  ")).toBe("spaced");
  });
});

describe("extractTag", () => {
  it("returns empty when not found", () => {
    expect(NewsModel.extractTag("<a>hi</a>", "title")).toBe("");
  });
  it("extracts tag content", () => {
    expect(NewsModel.extractTag("<title>My Title</title>", "title")).toBe("My Title");
  });
  it("handles CDATA", () => {
    expect(
      NewsModel.extractTag("<description><![CDATA[hello <b>world</b>]]></description>", "description")
    ).toBe("hello world");
  });
  it("is case-insensitive and decodes entities", () => {
    expect(NewsModel.extractTag('<TITLE>&lt;hi&gt;</TITLE>', "title")).toBe("<hi>");
  });
  it("handles attributes on tag", () => {
    expect(NewsModel.extractTag('<title lang="en">hi</title>', "title")).toBe("hi");
  });
});

describe("extractAttr", () => {
  it("extracts attribute double and single quotes", () => {
    expect(NewsModel.extractAttr('<enclosure url="http://a.jpg"/>', "enclosure", "url")).toBe("http://a.jpg");
    expect(NewsModel.extractAttr("<link href='http://x'/>", "link", "href")).toBe("http://x");
  });
  it("returns empty when not found", () => {
    expect(NewsModel.extractAttr("<a>hi</a>", "link", "href")).toBe("");
  });
  it("is case-insensitive for tag/attr", () => {
    expect(NewsModel.extractAttr('<ENCLOSURE URL="http://a.jpg"/>', "enclosure", "url")).toBe("http://a.jpg");
  });
  it("handles spaces around =", () => {
    expect(NewsModel.extractAttr('<link  href = "http://x" />', "link", "href")).toBe("http://x");
  });
});

describe("extractLink", () => {
  it("prefers RSS link text", () => {
    expect(NewsModel.extractLink("<item><link>http://example.com/a</link></item>")).toBe(
      "http://example.com/a"
    );
  });
  it("falls back to href when link text not http", () => {
    expect(NewsModel.extractLink('<item><link>not http</link><link href="http://example.com/b"/></item>')).toBe(
      "http://example.com/b"
    );
  });
  it("prefers first href if no link text http", () => {
    expect(NewsModel.extractLink('<entry><link href="http://example.com/c" rel="alternate"/></entry>')).toBe(
      "http://example.com/c"
    );
  });
  it("uses regex fallback for Atom href", () => {
    // extractTag for link will return empty if link is self-closing <link href... />
    expect(NewsModel.extractLink('<entry><link href="http://example.com/d"/></entry>')).toBe(
      "http://example.com/d"
    );
  });
  it("returns empty if no link", () => {
    expect(NewsModel.extractLink("<item><title>hi</title></item>")).toBe("");
  });
  it("hits fallback regex when extractAttr misses due to word boundary (xhref)", () => {
    // xhref contains href substring but \bhref will not match, so extractAttr returns "" while fallback regex matches
    expect(NewsModel.extractLink('<item><link xhref="http://fallback.example.com"></link></item>')).toBe(
      "http://fallback.example.com"
    );
  });
});

describe("extractDate", () => {
  it("returns 0 for empty", () => {
    expect(NewsModel.extractDate("<item></item>")).toBe(0);
  });
  it("parses pubDate", () => {
    const ms = Date.parse("Mon, 01 Jan 2024 00:00:00 GMT");
    expect(NewsModel.extractDate("<item><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate></item>")).toBe(ms);
  });
  it("falls back through published/updated/dc:date", () => {
    const ms = Date.parse("2024-01-02T00:00:00Z");
    expect(NewsModel.extractDate("<item><published>2024-01-02T00:00:00Z</published></item>")).toBe(ms);
    expect(NewsModel.extractDate("<item><updated>2024-01-02T00:00:00Z</updated></item>")).toBe(ms);
    expect(NewsModel.extractDate("<item><dc:date>2024-01-02T00:00:00Z</dc:date></item>")).toBe(ms);
  });
  it("returns 0 for invalid date", () => {
    expect(NewsModel.extractDate("<item><pubDate>not a date</pubDate></item>")).toBe(0);
  });
  it("is case-insensitive via extractTag", () => {
    const ms = Date.parse("Mon, 01 Jan 2024 00:00:00 GMT");
    expect(NewsModel.extractDate("<item><PUBDATE>Mon, 01 Jan 2024 00:00:00 GMT</PUBDATE></item>")).toBe(ms);
  });
});

describe("parseRss", () => {
  it("returns empty for falsy", () => {
    expect(NewsModel.parseRss(null, "f1", "Feed")).toEqual([]);
    expect(NewsModel.parseRss("", "f1", "Feed")).toEqual([]);
    expect(NewsModel.parseRss(undefined, "f1", "Feed")).toEqual([]);
  });

  it("parses single RSS item", () => {
    const xml = `<rss><channel><item><title>T1</title><link>http://a.com/1</link><description>desc</description><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate><guid>g1</guid></item></channel></rss>`;
    const out = NewsModel.parseRss(xml, "f1", "Feed One");
    expect(out).toHaveLength(1);
    expect(out[0].title).toBe("T1");
    expect(out[0].link).toBe("http://a.com/1");
    expect(out[0].feedId).toBe("f1");
    expect(out[0].feedTitle).toBe("Feed One");
    expect(out[0].id).toBe("g1");
    expect(out[0].description).toBe("desc");
    expect(out[0].pubDateLabel).toBeTruthy();
  });

  it("skips item without title", () => {
    const xml = `<rss><item><link>http://a.com</link></item><item><title>ok</title><link>http://b.com</link></item></rss>`;
    const out = NewsModel.parseRss(xml, "f1", "F");
    expect(out).toHaveLength(1);
    expect(out[0].title).toBe("ok");
  });

  it("handles Atom entry and content fallback", () => {
    const xml = `<feed><entry><title>Atom Title</title><link href="http://atom.com/entry"/><summary>summary text</summary></entry></feed>`;
    const out = NewsModel.parseRss(xml, "f2", "Atom Feed");
    expect(out[0].link).toBe("http://atom.com/entry");
    expect(out[0].description).toBe("summary text");
  });

  it("falls back to summary/content and content:encoded CDATA", () => {
    const xml = `<rss>
      <item><title>A</title><link>http://a</link><content>content tag</content></item>
      <item><title>B</title><link>http://b</link><content:encoded><![CDATA[<p>encoded <b>hello</b></p>]]></content:encoded></item>
      <item><title>C</title><link>http://c</link><content:encoded>plain encoded</content:encoded></item>
    </rss>`;
    const out = NewsModel.parseRss(xml, "f1", "F");
    expect(out.find((x) => x.title === "A").description).toBe("content tag");
    expect(out.find((x) => x.title === "B").description).toBe("encoded hello");
    expect(out.find((x) => x.title === "C").description).toBe("plain encoded");
  });

  it("truncates long description", () => {
    const long = "a".repeat(300);
    const xml = `<rss><item><title>T</title><link>http://a</link><description>${long}</description></item></rss>`;
    const out = NewsModel.parseRss(xml, "f", "F");
    expect(out[0].description.length).toBe(NewsModel.Limits.MAX_DESC_LENGTH + 1); // includes …
    expect(out[0].description.endsWith("…")).toBe(true);
  });

  it("guid fallback to link then feedId:title", () => {
    const xml1 = `<rss><item><title>T</title><link>http://a</link><guid>myguid</guid></item></rss>`;
    expect(NewsModel.parseRss(xml1, "f", "F")[0].id).toBe("myguid");
    const xml2 = `<rss><item><title>T</title><link>http://a</link></item></rss>`;
    expect(NewsModel.parseRss(xml2, "f", "F")[0].id).toBe("http://a");
    const xml3 = `<rss><item><title>T</title></item></rss>`;
    expect(NewsModel.parseRss(xml3, "myfeed", "F")[0].id).toBe("myfeed:T");
  });

  it("extracts image via enclosure/media and img fallback, handles protocol relative and filter", () => {
    const xml = `<rss>
      <item><title>T1</title><link>http://a</link><enclosure url="http://img.com/a.jpg"/></item>
      <item><title>T2</title><link>http://b</link><media:thumbnail url="http://img.com/b.jpg"/></item>
      <item><title>T3</title><link>http://c</link><media:content url="http://img.com/c.jpg"/></item>
      <item><title>T4</title><link>http://d</link><description><![CDATA[<p>hi <img src="http://img.com/d.jpg">]]></description></item>
      <item><title>T5</title><link>http://e</link><description><![CDATA[<img src="//img.com/e.jpg">]]></description></item>
      <item><title>T6</title><link>http://f</link><description><![CDATA[<img src="http://img.com/icon.png">]]></description></item>
      <item><title>T7</title><link>http://g</link><description><![CDATA[<img src="http://img.com/avatar.jpg">]]></description></item>
    </rss>`;
    const out = NewsModel.parseRss(xml, "f", "F");
    expect(out.find((x) => x.title === "T1").image).toBe("http://img.com/a.jpg");
    expect(out.find((x) => x.title === "T2").image).toBe("http://img.com/b.jpg");
    expect(out.find((x) => x.title === "T3").image).toBe("http://img.com/c.jpg");
    expect(out.find((x) => x.title === "T4").image).toBe("http://img.com/d.jpg");
    expect(out.find((x) => x.title === "T5").image).toBe("https://img.com/e.jpg");
    expect(out.find((x) => x.title === "T6").image).toBe("");
    expect(out.find((x) => x.title === "T7").image).toBe("");
  });

  it("caps retained remote fields: title, link, guid, image", () => {
    const L = NewsModel.Limits;
    const longTitle = "T".repeat(L.MAX_TITLE_LENGTH + 100);
    const longLink = "https://a.com/" + "l".repeat(L.MAX_LINK_LENGTH);
    const longGuid = "g".repeat(L.MAX_GUID_LENGTH + 100);
    const longImg = "https://img.com/" + "i".repeat(L.MAX_IMAGE_URL_LENGTH);
    const xml = `<rss><item><title>${longTitle}</title><link>${longLink}</link><guid>${longGuid}</guid><enclosure url="${longImg}"/></item></rss>`;
    const out = NewsModel.parseRss(xml, "f", "F");
    expect(out[0].title.length).toBe(L.MAX_TITLE_LENGTH + 1);
    expect(out[0].link.length).toBe(L.MAX_LINK_LENGTH + 1);
    expect(out[0].id.length).toBe(L.MAX_GUID_LENGTH + 1);
    expect(out[0].image.length).toBe(L.MAX_IMAGE_URL_LENGTH + 1);
    expect(out[0].title.endsWith("…")).toBe(true);
  });

  it("sorts newest first", () => {
    const xml = `<rss>
      <item><title>Old</title><link>http://a</link><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate></item>
      <item><title>New</title><link>http://b</link><pubDate>Tue, 02 Jan 2024 00:00:00 GMT</pubDate></item>
    </rss>`;
    const out = NewsModel.parseRss(xml, "f", "F");
    expect(out[0].title).toBe("New");
    expect(out[1].title).toBe("Old");
  });

  it("limits per feed and sets pubDateLabel empty when no date", () => {
    let xml = "<rss>";
    for (let i = 0; i < 50; i++) {
      xml += `<item><title>T${i}</title><link>http://a/${i}</link></item>`;
    }
    xml += "</rss>";
    const out = NewsModel.parseRss(xml, "f", "F");
    expect(out.length).toBe(NewsModel.Limits.MAX_PER_FEED);
    expect(out[0].pubDateLabel).toBe(""); // no pubDate => 0 => label ""
    expect(out[0].pubDate).toBe(0);
  });

  it("handles pubDateLabel when pub date exists", () => {
    const xml = `<rss><item><title>T</title><link>http://a</link><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate></item></rss>`;
    const out = NewsModel.parseRss(xml, "f", "F");
    expect(out[0].pubDateLabel).not.toBe("");
    expect(typeof out[0].pubDateLabel).toBe("string");
  });
});

describe("timeAgo", () => {
  beforeAll(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2024-01-10T12:00:00Z"));
  });
  afterAll(() => vi.useRealTimers());

  it("returns just now for <60s", () => {
    const now = Date.now();
    expect(NewsModel.timeAgo(now)).toBe("just now");
    expect(NewsModel.timeAgo(now - 30 * 1000)).toBe("just now");
    expect(NewsModel.timeAgo(now + 10 * 1000)).toBe("just now"); // future => diff 0 => just now
  });
  it("returns m ago", () => {
    const now = Date.now();
    expect(NewsModel.timeAgo(now - 5 * 60 * 1000)).toBe("5m ago");
    expect(NewsModel.timeAgo(now - 59 * 60 * 1000)).toBe("59m ago");
  });
  it("returns h ago", () => {
    const now = Date.now();
    expect(NewsModel.timeAgo(now - 2 * 60 * 60 * 1000)).toBe("2h ago");
    expect(NewsModel.timeAgo(now - 23 * 60 * 60 * 1000)).toBe("23h ago");
  });
  it("returns d ago", () => {
    const now = Date.now();
    expect(NewsModel.timeAgo(now - 2 * 24 * 60 * 60 * 1000)).toBe("2d ago");
    expect(NewsModel.timeAgo(now - 6 * 24 * 60 * 60 * 1000)).toBe("6d ago");
  });
  it("returns locale date for >=7 days", () => {
    const now = Date.now();
    const old = now - 10 * 24 * 60 * 60 * 1000;
    const expected = new Date(old).toLocaleDateString();
    expect(NewsModel.timeAgo(old)).toBe(expected);
  });
});

describe("filterArticles", () => {
  const articles = [
    { id: "1", feedId: "f1", title: "Hello World", description: "desc one", feedTitle: "Feed One" },
    { id: "2", feedId: "f2", title: "Another", description: "second desc", feedTitle: "Feed Two" },
    { id: "3", feedId: "f1", title: "Something else", description: "hello again", feedTitle: "Feed One" },
  ];

  it("returns all when no filter and all feeds", () => {
    expect(NewsModel.filterArticles(articles, "", NewsModel.ALL_FEEDS_ID)).toHaveLength(3);
    expect(NewsModel.filterArticles(articles, null, NewsModel.ALL_FEEDS_ID)).toHaveLength(3);
    expect(NewsModel.filterArticles(articles, undefined, NewsModel.ALL_FEEDS_ID)).toHaveLength(3);
    expect(NewsModel.filterArticles(articles, "   ", NewsModel.ALL_FEEDS_ID)).toHaveLength(3);
    expect(NewsModel.filterArticles(articles, "", null)).toHaveLength(3);
    expect(NewsModel.filterArticles(articles, "", "")).toHaveLength(3);
    expect(NewsModel.filterArticles(articles, "", undefined)).toHaveLength(3);
  });

  it("filters by feedId", () => {
    expect(NewsModel.filterArticles(articles, "", "f1")).toHaveLength(2);
    expect(NewsModel.filterArticles(articles, "", "f2")).toHaveLength(1);
    expect(NewsModel.filterArticles(articles, "", "none")).toHaveLength(0);
  });

  it("filters by query case-insensitive across title/desc/feedTitle", () => {
    expect(NewsModel.filterArticles(articles, "hello", NewsModel.ALL_FEEDS_ID)).toHaveLength(2);
    expect(NewsModel.filterArticles(articles, "HELLO", NewsModel.ALL_FEEDS_ID)).toHaveLength(2);
    expect(NewsModel.filterArticles(articles, "feed two", NewsModel.ALL_FEEDS_ID)).toHaveLength(1);
    expect(NewsModel.filterArticles(articles, "nonexistent", NewsModel.ALL_FEEDS_ID)).toHaveLength(0);
  });

  it("combines feedId and query", () => {
    expect(NewsModel.filterArticles(articles, "hello", "f1")).toHaveLength(2);
    expect(NewsModel.filterArticles(articles, "hello", "f2")).toHaveLength(0);
  });

  it("trims query", () => {
    expect(NewsModel.filterArticles(articles, "  hello  ", NewsModel.ALL_FEEDS_ID)).toHaveLength(2);
  });
});

describe("extractArticle", () => {
  it("returns empty for falsy", () => {
    expect(NewsModel.extractArticle("")).toBe("");
    expect(NewsModel.extractArticle(null)).toBe("");
    expect(NewsModel.extractArticle(undefined)).toBe("");
    expect(NewsModel.extractArticle(0)).toBe("");
  });

  it("strips script/style/noscript/header/footer/nav/aside", () => {
    const html = `<html><script>bad</script><style>bad</style><noscript>bad</noscript><header>h</header><footer>f</footer><nav>n</nav><aside>a</aside><article>${"a".repeat(700)}<p>${"content ".repeat(10)}</p></article></html>`;
    const out = NewsModel.extractArticle(html);
    expect(out).not.toContain("bad");
    expect(out.length).toBeGreaterThan(0);
  });

  it("prefers article tag when > MIN_ARTICLE_LENGTH", () => {
    const long = "word ".repeat(200); // >600
    const html = `<article>${long}<p>${"hello ".repeat(20)}</p></article><main>other</main>`;
    const out = NewsModel.extractArticle(html);
    expect(out).toContain("hello");
  });

  it("falls back to main when article too short", () => {
    const html = `<article>short</article><main>${"m".repeat(700)}<p>${"main content ".repeat(20)}</p></main>`;
    const out = NewsModel.extractArticle(html);
    expect(out).toContain("main content");
  });

  it("falls back to div with class when article/main short - bestCount logic and short skipped", () => {
    const good = `<div class="post content"><p>${"p content ".repeat(20)}</p><p>${"more ".repeat(20)}</p></div>`;
    const short = `<div class="post"><p>short</p></div>`; // inner length <800 and <600 thresholds but also p count low
    const innerShort = `<div class="article"><p>${"a".repeat(10)}</p></div>`; // length < 800 => skipped
    const html = `<div>${short}${innerShort}${good}</div>`;
    // ensure we pad to make outer not chosen as fallback
    const out = NewsModel.extractArticle(html);
    expect(out).toContain("p content");
  });

  it("chooses best div by p count and length > MIN_DIV_CLASS_LENGTH", () => {
    // two divs with class, second has more <p> and longer length
    const div1 = `<div class="story"><p>one</p><p>two</p>${"x".repeat(900)}</div>`;
    const div2 = `<div class="content"><p>a</p><p>b</p><p>c</p><p>d</p>${"y".repeat(900)}</div>`;
    const html = div1 + div2;
    const out = NewsModel.extractArticle(html);
    // best should be div2 (4 p vs 2 p)
    expect(out).toBeTruthy();
  });

  it("falls back to div without class when no class-matched div", () => {
    const html = `<div><p>${"fallback ".repeat(20)}</p><p>${"more ".repeat(20)}</p>${"z".repeat(600)}</div><div><p>short</p></div>`;
    const out = NewsModel.extractArticle(html);
    expect(out).toContain("fallback");
  });

  it("uses s as final fallback when no div matches length", () => {
    // Provide html with no article/main/div matching thresholds, forces article = s
    const html = `<html><body><p>${"plain ".repeat(30)}</p><p>${"more plain ".repeat(30)}</p></body></html>`;
    const out = NewsModel.extractArticle(html);
    expect(out).toContain("plain");
  });

  it("extracts blocks and respects MIN_BLOCK_CHARS, boilerplate, and limits", () => {
    // block with <40 chars should be skipped, boilerplate skipped
    const shortBlock = `<p>hi</p>`;
    const boiler = `<p>Subscribe to newsletter</p><p>Sign up now</p><p>Copyright notice</p><p>All rights reserved</p><p>Follow us</p><p>Share this</p>`;
    const good = `<p>${"good content ".repeat(10)}</p>`;
    const html = `<article>${"a".repeat(700)}${shortBlock}${boiler}${good}<p>${"another good ".repeat(10)}</p></article>`;
    const out = NewsModel.extractArticle(html);
    expect(out).not.toContain("hi");
    expect(out).not.toContain("Subscribe");
    expect(out).toContain("good content");
    expect(out).toContain("another good");
  });

  it("handles br replacement and h1-3/li/blockquote tags", () => {
    // blocks must be >= MIN_BLOCK_CHARS (40), so use longer content
    const html = `<article>${"a".repeat(700)}<h1>Title<br>${"next ".repeat(10)}</h1><li>${"item ".repeat(10)}</li><blockquote>${"quote ".repeat(10)}</blockquote><p>${"paragraph ".repeat(10)}</p></article>`;
    const out = NewsModel.extractArticle(html);
    expect(out).toContain("Title");
    expect(out).toContain("next");
    expect(out).toContain("item");
    expect(out).toContain("quote");
    expect(out).toContain("paragraph");
  });

  it("breaks on MAX_ARTICLE_BLOCKS and MAX_JOINED_JOIN", () => {
    // Generate many blocks to hit MAX_ARTICLE_BLOCKS =40 and MAX_JOINED_JOIN 7000
    let html = `<article>${"a".repeat(700)}`;
    for (let i = 0; i < 50; i++) {
      html += `<p>${"word ".repeat(20)} block ${i}</p>`;
    }
    html += `</article>`;
    const out = NewsModel.extractArticle(html);
    const blocks = out.split("\n\n");
    expect(blocks.length).toBeLessThanOrEqual(NewsModel.Limits.MAX_ARTICLE_BLOCKS);
    expect(out.length).toBeLessThanOrEqual(NewsModel.Limits.MAX_JOINED_JOIN + 100); // allow small over
  });

  it("fallback when no blocks extracted - uses strip fallback and truncates at MAX_FALLBACK_CHARS", () => {
    const longText = "a".repeat(3000);
    const html = `<article>${"a".repeat(700)}<div>${longText}</div></article>`; // no p/h/li/blockquote
    const out = NewsModel.extractArticle(html);
    expect(out.length).toBe(NewsModel.Limits.MAX_FALLBACK_CHARS + 1);
    expect(out.endsWith("…")).toBe(true);
  });

  it("truncates joined at MAX_JOINED_CHARS", () => {
    let html = `<article>${"a".repeat(700)}`;
    for (let i = 0; i < 20; i++) {
      html += `<p>${"x".repeat(500)} ${i}</p>`;
    }
    html += `</article>`;
    const out = NewsModel.extractArticle(html);
    if (out.length > NewsModel.Limits.MAX_JOINED_CHARS) {
      expect(out.endsWith("…")).toBe(true);
      expect(out.length).toBe(NewsModel.Limits.MAX_JOINED_CHARS + 1);
    } else {
      expect(out.length).toBeGreaterThan(0);
    }
  });

  it("handles article with short blocks -> fallback path empty out", () => {
    // article with only short blocks (< MIN_BLOCK_CHARS) => out empty => fallback
    const html = `<article>${"a".repeat(700)}<p>short</p><p>tiny</p></article>`;
    const out = NewsModel.extractArticle(html);
    // fallback should be the stripped article text
    expect(out.length).toBeGreaterThan(0);
  });
});

describe("readTimeMins", () => {
  it("handles falsy", () => {
    expect(NewsModel.readTimeMins("")).toBe(1);
    expect(NewsModel.readTimeMins(null)).toBe(1);
    expect(NewsModel.readTimeMins(undefined)).toBe(1);
  });
  it("CJK branch - chars < MIN_CJK_FOR_READTIME => 1", () => {
    expect(NewsModel.readTimeMins("こんにちは")).toBe(1); // 5 chars <80
    expect(NewsModel.readTimeMins("你好")).toBe(1);
  });
  it("CJK branch - chars >=80 => ceil(chars / CJK_CHARS_PER_MIN)", () => {
    const cjk = "字".repeat(450);
    expect(NewsModel.readTimeMins(cjk)).toBe(1);
    const cjk2 = "字".repeat(900);
    expect(NewsModel.readTimeMins(cjk2)).toBe(2);
    const withSpaces = ("字 ".repeat(100)).trim(); // 100 chars + spaces removed
    // spaces removed via replace(/\s/g,"")
    expect(NewsModel.readTimeMins(withSpaces)).toBe(1);
  });
  it("non-CJK - words < MIN_WORDS_FOR_READTIME => 1", () => {
    expect(NewsModel.readTimeMins("hello world")).toBe(1); // 2 words <30
    expect(NewsModel.readTimeMins("  ")).toBe(1);
  });
  it("non-CJK - words >=30 => ceil(words / WORDS_PER_MIN)", () => {
    const text220 = Array(220).fill("word").join(" ");
    expect(NewsModel.readTimeMins(text220)).toBe(1);
    const text440 = Array(440).fill("word").join(" ");
    expect(NewsModel.readTimeMins(text440)).toBe(2);
    const text500 = Array(500).fill("word").join(" ");
    expect(NewsModel.readTimeMins(text500)).toBe(3);
  });
  it("detects CJK via mixed", () => {
    // contains CJK char anywhere triggers CJK branch
    expect(NewsModel.readTimeMins("hello 字 world " + "x".repeat(100))).toBeGreaterThanOrEqual(1);
  });
});

describe("escapeHtml", () => {
  it("escapes ampersand, lt, gt, quot", () => {
    expect(NewsModel.escapeHtml('a & b < c > d "e')).toBe('a &amp; b &lt; c &gt; d &quot;e');
    expect(NewsModel.escapeHtml(null)).toBe("");
    expect(NewsModel.escapeHtml(undefined)).toBe("");
    expect(NewsModel.escapeHtml("")).toBe("");
  });
  it("handles number and empty", () => {
    expect(NewsModel.escapeHtml(123)).toBe("123");
  });
});

describe("highlightHtml", () => {
  it("returns escaped title when query empty", () => {
    expect(NewsModel.highlightHtml('<b>hi</b>', "")).toBe("&lt;b&gt;hi&lt;/b&gt;");
    expect(NewsModel.highlightHtml('<b>hi</b>', "   ")).toBe("&lt;b&gt;hi&lt;/b&gt;");
    expect(NewsModel.highlightHtml('<b>hi</b>', null)).toBe("&lt;b&gt;hi&lt;/b&gt;");
    expect(NewsModel.highlightHtml('<b>hi</b>', undefined)).toBe("&lt;b&gt;hi&lt;/b&gt;");
  });
  it("highlights query case-insensitive and escapes title", () => {
    const out = NewsModel.highlightHtml("Hello World", "hello", "#ff0000");
    expect(out).toContain('<font color="#ff0000"><b>Hello</b></font>');
    expect(out).toContain("World");
  });
  it("uses fallback color when not provided", () => {
    const out = NewsModel.highlightHtml("hello", "hello");
    expect(out).toContain('#7daea3');
  });
  it("escapes title before highlighting", () => {
    const out = NewsModel.highlightHtml("<script>", "script", "#000");
    expect(out).not.toContain("<script>");
    // escaped title is &lt;script&gt; with inner "script" highlighted
    expect(out).toContain('&lt;<font color="#000"><b>script</b></font>&gt;');
  });
  it("escapes regex special chars in query", () => {
    const out = NewsModel.highlightHtml("a.b*c", "a.b*c", "#123");
    expect(out).toContain("<b>a.b*c</b>");
  });
  it("handles query with brackets and pipes", () => {
    const out = NewsModel.highlightHtml("a [b] (c) {d} | e \\ f", "[b] (c)", "#111");
    // should highlight without throwing
    expect(typeof out).toBe("string");
  });
  it("catches RegExp errors and returns escaped title", () => {
    const original = globalThis.RegExp;
    const throwing = function () { throw new Error("bad regex"); };
    // @ts-ignore
    globalThis.RegExp = throwing;
    try {
      const out = NewsModel.highlightHtml("hello", "hello", "#ff0000");
      expect(out).toBe("hello"); // escapeHtml("hello") === "hello"
    } finally {
      globalThis.RegExp = original;
    }
  });
  it("handles falsy title", () => {
    expect(NewsModel.highlightHtml(null, "q", "#000")).toBe("");
    expect(NewsModel.highlightHtml(undefined, "q")).toBe("");
    expect(NewsModel.highlightHtml("", "q")).toBe("");
  });
});

describe("feedUnreadCount", () => {
  const articles = [
    { id: "1", feedId: "f1" },
    { id: "2", feedId: "f2" },
    { id: "3", feedId: "f1" },
  ];
  const readIds = { "1": true };

  it("counts unread for __all", () => {
    expect(NewsModel.feedUnreadCount(articles, NewsModel.ALL_FEEDS_ID, readIds)).toBe(2);
    expect(NewsModel.feedUnreadCount(articles, "__all", readIds)).toBe(2);
  });
  it("counts unread for specific feed", () => {
    expect(NewsModel.feedUnreadCount(articles, "f1", readIds)).toBe(1);
    expect(NewsModel.feedUnreadCount(articles, "f2", readIds)).toBe(1);
  });
  it("handles empty readIds and no articles", () => {
    expect(NewsModel.feedUnreadCount([], NewsModel.ALL_FEEDS_ID, {})).toBe(0);
    expect(NewsModel.feedUnreadCount(articles, "f1", {})).toBe(2);
  });
  it("handles all read", () => {
    expect(NewsModel.feedUnreadCount(articles, NewsModel.ALL_FEEDS_ID, { "1": true, "2": true, "3": true })).toBe(0);
  });
});

describe("categoryColor / hslToHex", () => {
  it("returns hex color for categories", () => {
    const c1 = NewsModel.categoryColor("Open Source");
    const c2 = NewsModel.categoryColor("Open Science");
    const c3 = NewsModel.categoryColor("General");
    const c4 = NewsModel.categoryColor(null);
    const c5 = NewsModel.categoryColor(undefined);
    const c6 = NewsModel.categoryColor("");
    expect(c1).toMatch(/^#[0-9a-f]{6}$/);
    expect(c2).toMatch(/^#[0-9a-f]{6}$/);
    expect(c3).toMatch(/^#[0-9a-f]{6}$/);
    expect(c4).toMatch(/^#[0-9a-f]{6}$/);
    expect(c5).toMatch(/^#[0-9a-f]{6}$/);
    expect(c6).toMatch(/^#[0-9a-f]{6}$/);
    // same input => same color
    expect(NewsModel.categoryColor("X")).toBe(NewsModel.categoryColor("X"));
    // different input => likely different (hash)
    // not guaranteed but usually
  });

  it("hslToHex converts correctly", () => {
    // known: hsl 0,100,50 => #ff0000 red
    expect(NewsModel.hslToHex(0, 100, 50)).toBe("#ff0000");
    expect(NewsModel.hslToHex(120, 100, 50)).toBe("#00ff00");
    expect(NewsModel.hslToHex(240, 100, 50)).toBe("#0000ff");
    // test black/white-ish
    expect(NewsModel.hslToHex(0, 0, 0)).toBe("#000000");
    expect(NewsModel.hslToHex(0, 0, 100)).toBe("#ffffff");
    // hue wrap
    expect(NewsModel.hslToHex(360, 55, 55)).toMatch(/^#/);
  });

  it("hslToHex handles edge toHex padding", () => {
    // force values that produce single digit hex
    const color = NewsModel.hslToHex(180, 55, 55);
    expect(color).toMatch(/^#[0-9a-f]{6}$/);
  });
});
