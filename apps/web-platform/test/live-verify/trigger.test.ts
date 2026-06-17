// AC5 — the live-verification gate trigger is driven by the committed
// trigger-paths.txt source-of-truth, plus a drift canary that fails when a new
// realtime/WS/auth top-level dir is added without extending the trigger set.

import { readdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

const here = dirname(fileURLToPath(import.meta.url));
const APP_ROOT = resolve(here, "..", ".."); // apps/web-platform
const TRIGGER_FILE = resolve(
  APP_ROOT,
  "scripts/live-verify/trigger-paths.txt",
);

/** Parse the committed file: drop blank + `#`-comment lines, keep ERE patterns. */
function loadPatterns(): RegExp[] {
  return readFileSync(TRIGGER_FILE, "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l !== "" && !l.startsWith("#"))
    .map((p) => new RegExp(p));
}

/** Mirror the gate consumer: fire iff any changed path matches any pattern. */
function triggers(changedFiles: string[], patterns: RegExp[]): boolean {
  return changedFiles.some((f) => patterns.some((re) => re.test(f)));
}

describe("trigger-paths.txt (AC5)", () => {
  const patterns = loadPatterns();

  it("has at least one pattern", () => {
    expect(patterns.length).toBeGreaterThan(0);
  });

  it("SKIPS a docs/config/logic-only changed set", () => {
    const changed = [
      "docs/legal/terms-and-conditions.md",
      "README.md",
      "apps/web-platform/lib/format-currency.ts",
      "knowledge-base/project/plans/x.md",
    ];
    expect(triggers(changed, patterns)).toBe(false);
  });

  it("RUNS for a components/chat change", () => {
    expect(
      triggers(
        ["apps/web-platform/components/chat/conversations-rail.tsx"],
        patterns,
      ),
    ).toBe(true);
  });

  it("RUNS for a realtime/WS server change", () => {
    expect(triggers(["apps/web-platform/server/ws-handler.ts"], patterns)).toBe(
      true,
    );
    expect(triggers(["apps/web-platform/middleware.ts"], patterns)).toBe(true);
    expect(
      triggers(["apps/web-platform/app/(auth)/login/page.tsx"], patterns),
    ).toBe(true);
  });
});

describe("drift canary (AC5)", () => {
  const patterns = loadPatterns();

  // A new top-level dir under apps/web-platform/ whose name reads as a
  // realtime/WS/auth/hooks surface MUST be covered by a trigger pattern —
  // otherwise its changes would silently skip the live gate (fail-open).
  const HEURISTIC = /realtime|websocket|socket|(^|[-_])ws([-_]|$)|(^|[-_])auth([-_]|$)|^hooks?$/i;

  it("every heuristic-matching top-level dir is covered by trigger-paths.txt", () => {
    const topLevel = readdirSync(APP_ROOT, { withFileTypes: true })
      .filter((d) => d.isDirectory() && !d.name.startsWith("."))
      .map((d) => d.name);

    const uncovered = topLevel
      .filter((name) => HEURISTIC.test(name))
      .filter((name) => {
        const sample = `apps/web-platform/${name}/sample.ts`;
        return !patterns.some((re) => re.test(sample));
      });

    expect(
      uncovered,
      `New realtime/WS/auth top-level dir(s) absent from trigger-paths.txt: ${uncovered.join(
        ", ",
      )} — add a pattern or justify the skip.`,
    ).toEqual([]);
  });
});
