import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// route-list-prereqs.test.ts — enforcement for #2362.2.
//
// Every `fixture_prereqs:` entry in route-list.yaml must appear in the
// documented `allowed_prereqs:` allowlist at the top of the file. The
// YAML is stable and flat, so a regex extractor is cheaper than adding
// a yaml-parser dependency.

const YAML_PATH = resolve(
  import.meta.dir,
  "../../skills/ux-audit/references/route-list.yaml",
);

const YAML = readFileSync(YAML_PATH, "utf8");

function parseAllowedPrereqs(src: string): string[] {
  const block = src.match(/^allowed_prereqs:\s*\n((?:[ \t]*-\s+\w+\s*\n?)+)/m);
  if (!block) return [];
  return [...block[1].matchAll(/-\s+(\w+)/g)].map((m) => m[1]);
}

function parseFixturePrereqs(src: string): string[][] {
  // Matches `    fixture_prereqs: [a, b, c]` (flow style).
  return [...src.matchAll(/fixture_prereqs:\s*\[([^\]]*)\]/g)].map((m) =>
    m[1]
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0),
  );
}

describe("route-list.yaml allowed_prereqs enforcement (#2362.2)", () => {
  test("allowed_prereqs block exists and is non-empty", () => {
    const allowed = parseAllowedPrereqs(YAML);
    expect(allowed.length).toBeGreaterThan(0);
  });

  test("every fixture_prereqs value is in allowed_prereqs", () => {
    const allowed = new Set(parseAllowedPrereqs(YAML));
    const fixtureLists = parseFixturePrereqs(YAML);
    expect(fixtureLists.length).toBeGreaterThan(0);

    for (const list of fixtureLists) {
      for (const entry of list) {
        expect(allowed.has(entry)).toBe(true);
      }
    }
  });

  test("allowed_prereqs includes the markers named in SKILL.md", () => {
    const allowed = new Set(parseAllowedPrereqs(YAML));
    for (const marker of [
      "tcs_accepted",
      "billing_active",
      "chat_conversations",
      "kb_workspace_deferred",
    ]) {
      expect(allowed.has(marker)).toBe(true);
    }
  });
});
