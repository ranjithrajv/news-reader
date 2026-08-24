import { describe, it, expect } from "vitest";
import * as Config from "../Config.js";

describe("Config", () => {
  it("exposes suffix constants and sentinel", () => {
    expect(Config.stateDirSuffix).toBe("/.local/state/omarchy/");
    expect(Config.downloadsSuffix).toBe("/Downloads/");
    expect(Config.allFeedsId).toBe("__all");
  });

  it("stateDir joins home correctly", () => {
    expect(Config.stateDir("/home/alice")).toBe("/home/alice/.local/state/omarchy/");
    expect(Config.stateDir("")).toBe("/.local/state/omarchy/");
    expect(Config.stateDir(null)).toBe("/.local/state/omarchy/");
    expect(Config.stateDir(undefined)).toBe("/.local/state/omarchy/");
    expect(Config.stateDir()).toBe("/.local/state/omarchy/");
  });

  it("statePath builds full path", () => {
    expect(Config.statePath("/home/bob", "news-reader-read.json")).toBe(
      "/home/bob/.local/state/omarchy/news-reader-read.json"
    );
    expect(Config.statePath("", "x.json")).toBe("/.local/state/omarchy/x.json");
    expect(Config.statePath(null, "a")).toBe("/.local/state/omarchy/a");
  });

  it("downloadsDir joins home correctly", () => {
    expect(Config.downloadsDir("/home/alice")).toBe("/home/alice/Downloads/");
    expect(Config.downloadsDir("")).toBe("/Downloads/");
    expect(Config.downloadsDir(null)).toBe("/Downloads/");
    expect(Config.downloadsDir(undefined)).toBe("/Downloads/");
    expect(Config.downloadsDir()).toBe("/Downloads/");
  });
});
