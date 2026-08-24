import { describe, it, expect } from "vitest";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");

describe("static assets", () => {
  it("manifest.json is valid and has required fields", () => {
    const raw = fs.readFileSync(path.join(root, "manifest.json"), "utf-8");
    const m = JSON.parse(raw);
    expect(m.schemaVersion).toBe(1);
    expect(m.id).toBe("ranjithraj.news-reader");
    expect(m.kinds).toEqual(expect.arrayContaining(["overlay", "bar-widget"]));
    expect(m.entryPoints.overlay).toBe("Overlay.qml");
    expect(m.entryPoints.barWidget).toBe("BarWidget.qml");
    expect(m.keepLoaded).toBe(true);
  });

  it("suggested-feeds.json is valid array with url/category/title", () => {
    const raw = fs.readFileSync(path.join(root, "suggested-feeds.json"), "utf-8");
    const arr = JSON.parse(raw);
    expect(Array.isArray(arr)).toBe(true);
    expect(arr.length).toBeGreaterThan(0);
    for (const f of arr) {
      expect(typeof f.title).toBe("string");
      expect(typeof f.url).toBe("string");
      expect(f.url.startsWith("http")).toBe(true);
      expect(typeof f.category).toBe("string");
    }
  });

  it("Overlay.qml exposes centralized config properties", () => {
    const qml = fs.readFileSync(path.join(root, "Overlay.qml"), "utf-8");
    // centralized state paths via Config
    expect(qml).toContain('Config.stateDir');
    expect(qml).toContain('readonly property string allFeedsId: Config.allFeedsId');
    expect(qml).toContain('readonly property int autoRefreshIntervalMs');
    expect(qml).toContain('readonly property int timeAgoIntervalMs');
    expect(qml).toContain('readonly property int autoMarkDelayMs');
    expect(qml).toContain('readonly property int toastDurationMs');
    expect(qml).toContain('readonly property int toastWithActionMs');
    expect(qml).toContain('readonly property int cardOuterMargin');
    expect(qml).toContain('readonly property int cardTopMargin');
    expect(qml).toContain('readonly property string downloadsDir');
    expect(qml).toContain('exportJsonPath');
    expect(qml).toContain('exportOpmlPath');
    // ensure old hardcodes gone
    expect(qml).not.toMatch(/interval:\s*10 \* 60 \* 1000/);
    expect(qml).not.toMatch(/interval:\s*60 \* 1000[^;]*timeAgo/);
    expect(qml).not.toContain('"__all"');
    expect(qml).not.toMatch(/Quickshell\.env\("HOME"\) \+ "\/Downloads/);
  });

  it("BarWidget.qml uses Config and badgePollIntervalMs", () => {
    const qml = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf-8");
    expect(qml).toContain('import "Config.js" as Config');
    expect(qml).toContain('Config.stateDir');
    expect(qml).toContain('badgePollIntervalMs');
    expect(qml).toContain('interval: root.badgePollIntervalMs');
    expect(qml).not.toContain('interval: 4000;');
  });

  it("NewsModel.js uses Limits for article guards", () => {
    const js = fs.readFileSync(path.join(root, "NewsModel.js"), "utf-8");
    expect(js).toContain('MIN_ARTICLE_LENGTH');
    expect(js).toContain('MIN_MAIN_LENGTH');
    expect(js).toContain('MIN_DIV_CLASS_LENGTH');
    expect(js).toContain('MIN_DIV_LENGTH');
    expect(js).toContain('MIN_CACHED_BODY_LENGTH');
    expect(js).toContain('ALL_FEEDS_ID');
    // old literals should be gone (except Limits definitions)
    // ensure no bare > 600 inside extractArticle outside Limits block
    const afterLimits = js.split("MIN_DIV_LENGTH")[1];
    expect(afterLimits).not.toMatch(/> 600\)/);
    expect(afterLimits).not.toMatch(/> 800\)/);
  });
});
