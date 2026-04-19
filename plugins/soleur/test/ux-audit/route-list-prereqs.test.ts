import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// route-list-prereqs.test.ts — enforcement for #2362.2.
//
// Every `fixture_prereqs:` entry in route-list.yaml must appear in the
// documented `allowed_prereqs:` allowlist at the top of the file. The
// YAML is stable and flat, so a regex extractor is cheaper than adding
// a yaml-parser dependency. Parser covers both flow style
// (`fixture_prereqs: [a, b]`) and block style (`fixture_prereqs:\n  - a`)
// so switching a single route to block form does NOT silently drop it
// from the check.

const YAML_PATH = resolve(
  import.meta.dir,
  "../../skills/ux-audit/references/route-list.yaml",
);

const YAML = readFileSync(YAML_PATH, "utf8");

// Sync-counter: must equal the number of `fixture_prereqs:` keys in
// route-list.yaml. Pins the parser against silent underread — if a
// future route uses a style the regex doesn't cover, the count drops.
const EXPECTED_FIXTURE_LISTS = 11;

function parseAllowedPrereqs(src: string): string[] {
  const block = src.match(/^allowed_prereqs:\s*\n((?:[ \t]*-\s+\w+\s*\n?)+)/m);
  if (!block) return [];
  return [...block[1].matchAll(/-\s+(\w+)/g)].map((m) => m[1]);
}

function parseFixturePrereqs(src: string): string[][] {
  const out: string[][] = [];
  // Iterate every `fixture_prereqs:` key and inspect what follows, so
  // every key contributes exactly one entry to `out` regardless of
  // flow vs block style. Underread surfaces as a count mismatch
  // against EXPECTED_FIXTURE_LISTS.
  const keyRegex = /fixture_prereqs:[ \t]*(.*)(?:\n((?:[ \t]*-[^\n]*\n?)*))?/g;
  for (const m of src.matchAll(keyRegex)) {
    const inline = m[1] ?? "";
    const blockBody = m[2] ?? "";
    const flowMatch = inline.match(/^\[([^\]]*)\]\s*$/);
    if (flowMatch) {
      out.push(
        flowMatch[1]
          .split(",")
          .map((s) => s.trim())
          .filter((s) => s.length > 0),
      );
      continue;
    }
    if (blockBody.trim().length > 0) {
      out.push(
        [...blockBody.matchAll(/-\s+(\w+)/g)].map((bm) => bm[1]),
      );
      continue;
    }
    // Empty-list key (`fixture_prereqs: []` or `fixture_prereqs:`).
    out.push([]);
  }
  return out;
}

describe("route-list.yaml allowed_prereqs enforcement (#2362.2)", () => {
  test("allowed_prereqs block exists and is non-empty", () => {
    const allowed = parseAllowedPrereqs(YAML);
    expect(allowed.length).toBeGreaterThan(0);
  });

  test("parser reads every fixture_prereqs key (flow + block styles)", () => {
    const lists = parseFixturePrereqs(YAML);
    // Exact count so underread (e.g. a block-style list skipped by
    // the regex) fails loudly rather than silently passing with a
    // smaller set.
    expect(lists.length).toBe(EXPECTED_FIXTURE_LISTS);
  });

  test("every fixture_prereqs value is in allowed_prereqs", () => {
    const allowed = new Set(parseAllowedPrereqs(YAML));
    const fixtureLists = parseFixturePrereqs(YAML);
    expect(fixtureLists.length).toBe(EXPECTED_FIXTURE_LISTS);

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
