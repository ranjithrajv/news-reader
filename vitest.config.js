import { defineConfig } from "vitest/config";

const newsModelExports = `
export {
  ALL_FEEDS_ID,
  Limits,
  decodeEntities,
  stripTags,
  extractTag,
  extractAttr,
  extractLink,
  extractDate,
  capStr,
  sanitizeFeed,
  sanitizeFeeds,
  parseRss,
  timeAgo,
  filterArticles,
  extractArticle,
  readTimeMins,
  escapeHtml,
  highlightHtml,
  feedUnreadCount,
  categoryColor,
  hslToHex,
  groupFeedsByCategory,
  defaultFeeds,
};
`;

const configExports = `
export {
  stateDirSuffix,
  downloadsSuffix,
  allFeedsId,
  stateMaxBytes,
  stateDir,
  statePath,
  downloadsDir,
  shellQuote,
  stateReadCmd,
};
`;

const i18nExports = `
export {
  Locales,
  LocaleNames,
  isRtl,
  resolveLocale,
  t,
};
`;

export default defineConfig({
  plugins: [
    {
      name: "pragma-strip-and-export",
      transform(code, id) {
        if (id.endsWith("NewsModel.js")) {
          const stripped = code.replace(/^\s*\.pragma library\s*\n/, "");
          return stripped + newsModelExports;
        }
        if (id.endsWith("Config.js")) {
          const stripped = code.replace(/^\s*\.pragma library\s*\n/, "");
          return stripped + configExports;
        }
        if (id.endsWith("I18n.js")) {
          const stripped = code.replace(/^\s*\.pragma library\s*\n/, "");
          return stripped + i18nExports;
        }
        return null;
      },
    },
  ],
  test: {
    include: ["tests/**/*.test.js"],
    environment: "node",
    coverage: {
      provider: "v8",
      include: ["NewsModel.js", "Config.js", "I18n.js"],
      exclude: ["tests/**", "vitest.config.js"],
      reportsDirectory: "./coverage",
      reporter: ["text", "lcov", "html"],
      thresholds: {
        lines: 100,
        branches: 100,
        functions: 100,
        statements: 100,
      },
    },
  },
});
