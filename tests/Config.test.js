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

  it("exposes stateMaxBytes ceiling", () => {
    expect(typeof Config.stateMaxBytes).toBe("number");
    expect(Config.stateMaxBytes).toBeGreaterThan(0);
  });

  it("shellQuote single-quotes and escapes embedded quotes", () => {
    expect(Config.shellQuote("/plain/path")).toBe("'/plain/path'");
    expect(Config.shellQuote("it's")).toBe("'it'\\''s'");
    expect(Config.shellQuote("")).toBe("''");
  });

  it("stateReadCmd builds a single descriptor-bound no-follow/nonblocking reader", () => {
    const cmd = Config.stateReadCmd("/home/a/file.json", 1000);
    expect(cmd).toContain("python3 -c");
    expect(cmd).toContain("O_NOFOLLOW");
    expect(cmd).toContain("O_NONBLOCK");
    expect(cmd).toContain("os.read(fd,");
    expect(cmd).toContain("'/home/a/file.json'");
    expect(cmd).toContain("1000");
  });

  it("stateReadCmd defaults to stateMaxBytes and floors invalid caps", () => {
    expect(Config.stateReadCmd("/x")).toContain(` ${Config.stateMaxBytes}`);
    expect(Config.stateReadCmd("/x", 0)).toContain(` ${Config.stateMaxBytes}`); // falsy -> default
    expect(Config.stateReadCmd("/x", -5)).toContain(" 1");
    expect(Config.stateReadCmd("/x", null)).toContain(` ${Config.stateMaxBytes}`);
  });

  it("stateReadCmd reads a regular file capped, and refuses a symlink", () => {
    const fs = require("fs");
    const os = require("os");
    const path = require("path");
    const { execFileSync } = require("child_process");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "nr-"));
    const real = path.join(dir, "real.txt");
    const link = path.join(dir, "link.txt");
    fs.writeFileSync(real, "0123456789");
    fs.symlinkSync(real, link);
    const read = (p) => execFileSync("bash", ["-c", Config.stateReadCmd(p, 4)]).toString();
    expect(read(real)).toBe("0123");   // capped at 4 bytes
    expect(read(link)).toBe("");       // symlink rejected -> no data
    fs.rmSync(dir, { recursive: true, force: true });
  });
});
