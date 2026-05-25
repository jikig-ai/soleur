/**
 * PR-A (#4124) — knowledge.kb_drift tier bump sentinel.
 *
 * The plan's CPO threshold AC3 requires `ACTION_CLASS_DEFAULTS[
 * "knowledge.kb_drift"]` to be `"draft_one_click"` (NOT `"auto"`) so the
 * KbDriftCard "Fix link" / "Update anchor" button reaches a non-400 path
 * on `/api/dashboard/today/[id]/send`. The plan trims spec-flow-analyzer
 * GAP #5 (CRITICAL) via tier-option (A) — single-row bump, no producer
 * branching, no new route surface.
 *
 * Two-layer enforcement:
 *   (a) Map-value assertion — runtime confirmation that the registry
 *       carries the bumped value.
 *   (b) Producer-side cascade grep — no other site in `server/` or `app/`
 *       under apps/web-platform/ couples kb_drift to the literal `"auto"`
 *       tier. A drift commit that splits the kb_drift handling into a
 *       producer-side hard-coded "auto" path would re-introduce the
 *       400 dead-letter and is caught here.
 */

import { describe, expect, test } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, join } from "node:path";

import { ACTION_CLASS_DEFAULTS } from "@/server/scope-grants/action-class-map";

const APP_ROOT = resolve(__dirname, "../../..");

/**
 * Recursive directory walk that yields every regular file path. Avoids a
 * shell-invoking grep so the test is portable and free of shell-injection
 * surface.
 */
function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (entry === "node_modules" || entry === ".next") continue;
      yield* walk(full);
      continue;
    }
    if (st.isFile()) yield full;
  }
}

const KB_DRIFT_AUTO_COUPLING =
  /kb_drift[^\n]{0,80}['"]auto['"]|['"]auto['"][^\n]{0,80}kb_drift/;

describe("knowledge.kb_drift tier bump (PR-A AC3)", () => {
  test("ACTION_CLASS_DEFAULTS['knowledge.kb_drift'] === 'draft_one_click'", () => {
    expect(ACTION_CLASS_DEFAULTS["knowledge.kb_drift"]).toBe("draft_one_click");
  });

  test("the action-class-map.ts source carries the bumped literal at the kb_drift entry", () => {
    const src = readFileSync(
      resolve(__dirname, "../../../server/scope-grants/action-class-map.ts"),
      "utf8",
    );
    const defaultsBlock = src.match(
      /export\s+const\s+ACTION_CLASS_DEFAULTS\b[^=]*=\s*\{([\s\S]*?)\n\};/,
    );
    expect(defaultsBlock).not.toBeNull();
    const kbLine = (defaultsBlock![1] ?? "")
      .split("\n")
      .find((l) => l.includes('"knowledge.kb_drift"'));
    expect(kbLine).toBeDefined();
    expect(kbLine).toMatch(/"draft_one_click"/);
    expect(kbLine).not.toMatch(/:\s*"auto"\s*[,}]/);
  });

  test("producer-side cascade: no server/ or app/ file couples kb_drift to the literal 'auto' tier", () => {
    const hits: string[] = [];
    for (const subdir of ["server", "app"]) {
      const dir = resolve(APP_ROOT, subdir);
      try {
        statSync(dir);
      } catch {
        continue;
      }
      for (const f of walk(dir)) {
        if (!/\.(ts|tsx)$/.test(f)) continue;
        const src = readFileSync(f, "utf8");
        // Strip comments (line + block) so docstrings explaining the
        // historical "auto" tier don't false-positive.
        const code = src
          .replace(/\/\*[\s\S]*?\*\//g, "")
          .replace(/(^|\n)\s*\/\/[^\n]*/g, "$1");
        if (KB_DRIFT_AUTO_COUPLING.test(code)) {
          hits.push(f.slice(APP_ROOT.length + 1));
        }
      }
    }
    expect(
      hits,
      `Producer-side kb_drift+auto coupling found in: ${hits.join(", ")}`,
    ).toEqual([]);
  });
});
