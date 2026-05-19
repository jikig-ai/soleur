// PR-G (#3947) — TR7 lint test. INNGEST_SIGNING_KEY MUST NOT appear in
// any file under app/(dashboard)/ or components/. The Inngest API
// credential is server-only; a client-bundle reference would expose the
// signing key to the browser.

import { describe, expect, test } from "vitest";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { sync as globSync } from "fast-glob";

const ROOTS = ["app/(dashboard)", "components"];

function listSourceFiles(): string[] {
  const cwd = process.cwd();
  const patterns = ROOTS.map((r) => `${r}/**/*.{ts,tsx}`);
  return globSync(patterns, { cwd, absolute: true });
}

describe("INNGEST_SIGNING_KEY server-only enforcement", () => {
  test("does not appear in client-bundle paths (app/(dashboard)/** or components/**)", async () => {
    const files = listSourceFiles();
    expect(files.length).toBeGreaterThan(0); // sanity: globbed something

    const violations: string[] = [];
    for (const file of files) {
      const content = await readFile(file, "utf8");
      // Strip line-comment annotations so the lint guard itself doesn't
      // false-positive when documentation mentions the env var name.
      const stripped = content
        .split("\n")
        .filter((line) => !/^\s*\/\//.test(line))
        .join("\n");
      if (stripped.includes("INNGEST_SIGNING_KEY")) {
        violations.push(path.relative(process.cwd(), file));
      }
    }

    expect(violations).toEqual([]);
  });
});
