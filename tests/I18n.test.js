import { describe, it, expect } from "vitest";
import * as I18n from "../I18n.js";

describe("Locales / LocaleNames", () => {
  it("lists the 11 supported locales with a display name each", () => {
    expect(I18n.Locales).toEqual(["en", "es", "de", "zh", "ar", "hi", "fr", "bn", "ru", "pt", "ur"]);
    for (const loc of I18n.Locales) {
      expect(typeof I18n.LocaleNames[loc]).toBe("string");
      expect(I18n.LocaleNames[loc].length).toBeGreaterThan(0);
    }
  });
});

describe("isRtl", () => {
  it("is true only for Arabic and Urdu", () => {
    expect(I18n.isRtl("ar")).toBe(true);
    expect(I18n.isRtl("ur")).toBe(true);
    expect(I18n.isRtl("en")).toBe(false);
    expect(I18n.isRtl("es")).toBe(false);
    expect(I18n.isRtl("de")).toBe(false);
    expect(I18n.isRtl("zh")).toBe(false);
    expect(I18n.isRtl("hi")).toBe(false);
    expect(I18n.isRtl("fr")).toBe(false);
    expect(I18n.isRtl("bn")).toBe(false);
    expect(I18n.isRtl("ru")).toBe(false);
    expect(I18n.isRtl("pt")).toBe(false);
    expect(I18n.isRtl("")).toBe(false);
    expect(I18n.isRtl(undefined)).toBe(false);
  });
});

describe("resolveLocale", () => {
  it("matches the primary language subtag against supported locales", () => {
    expect(I18n.resolveLocale(["es-ES", "en"], I18n.Locales)).toBe("es");
    expect(I18n.resolveLocale(["de-DE"], I18n.Locales)).toBe("de");
    expect(I18n.resolveLocale(["zh-Hans-CN"], I18n.Locales)).toBe("zh");
    expect(I18n.resolveLocale(["ar-EG"], I18n.Locales)).toBe("ar");
    expect(I18n.resolveLocale(["hi-IN"], I18n.Locales)).toBe("hi");
    expect(I18n.resolveLocale(["fr-FR"], I18n.Locales)).toBe("fr");
    expect(I18n.resolveLocale(["bn-BD"], I18n.Locales)).toBe("bn");
    expect(I18n.resolveLocale(["ru-RU"], I18n.Locales)).toBe("ru");
    expect(I18n.resolveLocale(["pt-BR"], I18n.Locales)).toBe("pt");
    expect(I18n.resolveLocale(["ur-PK"], I18n.Locales)).toBe("ur");
  });

  it("falls through to the next tag when the first isn't supported", () => {
    expect(I18n.resolveLocale(["it-IT", "es-MX"], I18n.Locales)).toBe("es");
  });

  it("defaults to en when nothing matches or supported not passed", () => {
    expect(I18n.resolveLocale(["it-IT", "ja-JP"], I18n.Locales)).toBe("en");
    expect(I18n.resolveLocale(["en-US"])).toBe("en");
  });

  it("handles falsy/non-array input", () => {
    expect(I18n.resolveLocale(null, I18n.Locales)).toBe("en");
    expect(I18n.resolveLocale(undefined, I18n.Locales)).toBe("en");
    expect(I18n.resolveLocale([undefined, "de"], I18n.Locales)).toBe("de");
  });

  it("is case-insensitive and handles underscore separators", () => {
    expect(I18n.resolveLocale(["DE_DE"], I18n.Locales)).toBe("de");
  });
});

describe("t", () => {
  it("returns the English string for a plain key", () => {
    expect(I18n.t("en", "toolbar.title")).toBe("News Reader");
  });

  it("returns the localized string for each locale", () => {
    expect(I18n.t("es", "toolbar.title")).toBe("Lector de Noticias");
    expect(I18n.t("de", "toolbar.title")).toBe("Nachrichtenleser");
    expect(I18n.t("zh", "toolbar.title")).toBe("新闻阅读器");
    expect(I18n.t("ar", "toolbar.title")).toBe("قارئ الأخبار");
    expect(I18n.t("hi", "toolbar.title")).toBe("न्यूज़ रीडर");
    expect(I18n.t("fr", "toolbar.title")).toBe("Lecteur d'actualités");
    expect(I18n.t("bn", "toolbar.title")).toBe("নিউজ রিডার");
    expect(I18n.t("ru", "toolbar.title")).toBe("Читалка новостей");
    expect(I18n.t("pt", "toolbar.title")).toBe("Leitor de Notícias");
    expect(I18n.t("ur", "toolbar.title")).toBe("نیوز ریڈر");
  });

  it("falls back to English for an unsupported locale", () => {
    expect(I18n.t("it", "toolbar.title")).toBe("News Reader");
    expect(I18n.t(undefined, "toolbar.title")).toBe("News Reader");
  });

  it("falls back to the key itself when missing from every table", () => {
    expect(I18n.t("en", "no.such.key")).toBe("no.such.key");
    expect(I18n.t("es", "no.such.key")).toBe("no.such.key");
  });

  it("interpolates {placeholder} vars", () => {
    expect(I18n.t("en", "toast.feedAddedNamed", { title: "Example" })).toBe('Added "Example"');
    expect(I18n.t("en", "error.feedLimit", { max: 100 })).toBe("Feed limit reached (100)");
  });

  it("leaves an unmatched placeholder untouched when its var is missing", () => {
    expect(I18n.t("en", "toast.feedAddedNamed", {})).toBe('Added "{title}"');
    expect(I18n.t("en", "toast.feedAddedNamed")).toBe('Added "{title}"');
  });

  it("returns the raw string unchanged when no vars object is given", () => {
    expect(I18n.t("en", "toolbar.title", null)).toBe("News Reader");
  });
});

describe("translation completeness", () => {
  it("every locale resolves every en. key to a non-empty, non-fallback string", () => {
    // Exercise the full key surface through the public t() API so this test
    // also acts as the "100% translation coverage" check: any locale table
    // missing a key falls back to en and would still pass shape checks, so
    // compare each locale's value against en's key literal (which t() would
    // return only on a genuine miss) to catch accidental omissions.
    const sampleKeys = [
      "bar.tooltipUnread", "bar.tooltipSummon",
      "toolbar.title", "toolbar.statusRefreshing", "toolbar.statusStory", "toolbar.statusStories",
      "toolbar.statusUnread", "toolbar.tooltipRefresh", "toolbar.markRead", "toolbar.tooltipSettings",
      "toolbar.tooltipFullscreenEnter", "toolbar.tooltipFullscreenExit", "toolbar.tooltipClose",
      "search.placeholder", "chips.all", "chips.unread", "chips.unreadOn",
      "toast.unreadOnlyOn", "toast.unreadOnlyOff",
      "list.loading", "list.noMatch", "list.tryAnother", "list.clearFilters", "list.retry", "list.footerHint",
      "detail.markUnreadTooltip", "detail.read", "detail.retry", "detail.min", "detail.loadingArticle",
      "detail.noSummary", "detail.openStory", "detail.copyLink", "detail.share", "detail.shareTooltip",
      "detail.footerNote", "detail.noneSelected", "detail.fetchOrAdjust", "detail.selectStory",
      "settings.titlePrefix", "settings.feeds", "settings.feedsCount", "settings.folderTooltip", "settings.remove", "settings.noFeeds",
      "settings.suggested", "settings.addFeed", "settings.titlePlaceholder", "settings.add",
      "settings.importExport", "settings.importPlaceholder", "settings.import", "settings.exportJson",
      "settings.exportOpml", "settings.preferences", "settings.autoRefreshInterval", "settings.readingTheme",
      "settings.fontSize", "settings.fontSizeNote", "settings.tipImportExport", "settings.language",
      "interval.hourly", "interval.daily", "interval.weekly",
      "theme.auto", "theme.contrast", "theme.light", "theme.dark", "theme.sepia", "theme.grey",
      "fontctl.reset",
      "shortcuts.title", "shortcuts.nextStory", "shortcuts.prevStory", "shortcuts.openStory",
      "shortcuts.focusSearch", "shortcuts.refresh", "shortcuts.toggleUnread", "shortcuts.fontAdjust",
      "shortcuts.fullscreen", "shortcuts.toggleHelp", "shortcuts.closeOrExit", "shortcuts.tip", "shortcuts.gotIt",
      "error.urlRequired", "error.invalidUrl", "error.feedExists", "error.feedLimit", "error.feedLimitPlain",
      "error.invalidFeed", "error.keepAtLeastOne", "error.pasteFirst", "error.noFeedsFound", "error.noNewFeeds",
      "error.noFeedsConfigured", "error.noArticles", "error.couldNotFetch", "error.parseErrorFeed",
      "error.couldNotLoadArticle", "error.parseError", "error.saveFailed",
      "toast.feedsSaved", "toast.feedAdded", "toast.feedAddedNamed", "toast.feedRestored", "toast.feedRemovedNamed", "toast.importedCount",
      "toast.importedSkipped", "toast.exportedJsonInfo", "toast.exportedJson", "toast.exportedOpmlInfo",
      "toast.exportedOpml", "toast.noHardcodedTestData", "toast.markedUnread", "toast.markedNRead",
      "toast.linkCopied", "toast.sharedLinkCopied", "toast.markedRead", "toast.undo", "toast.fontSize",
      "toast.fontReset", "toast.readingTheme", "toast.autoRefresh", "toast.languageChanged",
    ];
    // Legitimately identical across locales (e.g. "min" is also the Spanish
    // abbreviation for minutos) — not a missed translation.
    const allowedCoincidence = {
      "es:detail.min": true, // "min" is also the Spanish abbreviation for minutos
      "es:settings.feeds": true, // "Feeds" is used as a loanword in Spanish tech UI
      "es:settings.feedsCount": true, // same loanword ("{n} feeds")
      "de:settings.feeds": true, // same loanword in German tech UI
      "es:theme.sepia": true, // "Sepia" is the same word in Spanish
      "de:theme.sepia": true, // "Sepia" is the same word in German
      "fr:detail.min": true, // "min" is also the French abbreviation for minute
      "pt:detail.min": true, // "min" is also the Portuguese abbreviation for minuto
      "pt:settings.feeds": true, // "Feeds" is used as a loanword in Portuguese tech UI
      "pt:settings.feedsCount": true, // same loanword ("{n} feeds")
    };
    for (const loc of I18n.Locales) {
      for (const key of sampleKeys) {
        const value = I18n.t(loc, key);
        expect(value, `${loc} missing translation for ${key}`).not.toBe(key);
        expect(value.length).toBeGreaterThan(0);
        if (loc !== "en" && !allowedCoincidence[loc + ":" + key]) {
          expect(value, `${loc} silently falls back to English for ${key}`).not.toBe(I18n.t("en", key));
        }
      }
    }
  });
});
