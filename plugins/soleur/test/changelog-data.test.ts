import { describe, test, expect } from "bun:test";
import { resolve } from "path";
import { existsSync } from "fs";

// The changelog data file resolves relative to CWD, so we need to run
// from the repo root (or worktree root). Bun test runs from package.json dir.
const CHANGELOG_DATA = resolve(import.meta.dir, "../docs/_data/changelog.js");

describe("changelog.js data file", () => {
  test("file exists", () => {
    expect(existsSync(CHANGELOG_DATA)).toBe(true);
  });

  test("returns html when CHANGELOG.md exists", async () => {
    // Dynamic import to execute the data file
    const mod = await import(CHANGELOG_DATA);
    const data = mod.default();
    expect(data).toHaveProperty("html");
    expect(data.html.length).toBeGreaterThan(0);
    // Should contain rendered HTML tags from the changelog
    expect(data.html).toContain("<h2>");
  });

  test("rendered html strips the top-level heading", async () => {
    const mod = await import(CHANGELOG_DATA);
    const data = mod.default();
    // The CHANGELOG.md starts with "# Changelog" which should be stripped
    expect(data.html).not.toContain(">Changelog</h1>");
  });
});
