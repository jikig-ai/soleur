import { describe, test, expect } from "bun:test";
import { resolve } from "path";
import { existsSync } from "fs";

const CHANGELOG_DATA = resolve(import.meta.dir, "../docs/_data/changelog.js");

describe("changelog.js data file", () => {
  test("file exists", () => {
    expect(existsSync(CHANGELOG_DATA)).toBe(true);
  });

  test("returns html from GitHub Releases API", async () => {
    const mod = await import(CHANGELOG_DATA);
    const data = await mod.default();
    expect(data).toHaveProperty("html");
    expect(typeof data.html).toBe("string");
  });

  test("html contains release headings when releases exist", async () => {
    const mod = await import(CHANGELOG_DATA);
    const data = await mod.default();
    // If GitHub API returned releases, html should contain h2 tags
    if (data.html.length > 0) {
      expect(data.html).toContain("<h2>");
    }
  });
});
