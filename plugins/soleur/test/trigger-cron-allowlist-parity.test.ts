import { describe, test, expect } from "bun:test";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// Parity guard (#4742): the trigger-cron skill's `--list` derives its allowlist
// by awk-parsing EXPECTED_CRON_FUNCTIONS in cron-manifest.ts, while the route's
// lib/inngest/manual-trigger-allowlist.ts derives the SAME set via a TS import
// + manualTriggerEventFor(). The two extraction mechanisms are independent;
// this test asserts they cannot silently drift. Mirrors the architectural
// intent of function-registry-count.test.ts (e) for the awk side.

const REPO_ROOT = resolve(import.meta.dir, "..", "..", "..");
const MANIFEST = resolve(
  REPO_ROOT,
  "apps/web-platform/server/inngest/cron-manifest.ts",
);
const SCRIPT = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/trigger-cron/scripts/trigger.sh",
);

// Re-implement the canonical manualTriggerEventFor transform in TS, sourced
// from the manifest array literal — the authoritative side of the parity.
function manifestEvents(): string[] {
  const src = readFileSync(MANIFEST, "utf8");
  const block = src.slice(
    src.indexOf("EXPECTED_CRON_FUNCTIONS"),
    src.indexOf("];", src.indexOf("EXPECTED_CRON_FUNCTIONS")),
  );
  const fns = [...block.matchAll(/"(cron-[a-z0-9-]+)"/g)].map((m) => m[1]);
  return fns
    .map((fn) => `cron/${fn.replace(/^cron-/, "")}.manual-trigger`)
    .sort();
}

describe("trigger-cron skill allowlist parity", () => {
  test("trigger.sh --list matches the manifest-derived manual-trigger events", () => {
    const expected = manifestEvents();
    expect(expected.length).toBeGreaterThan(0);

    const out = execFileSync("bash", [SCRIPT, "--list"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
    });
    const actual = out.split("\n").map((l) => l.trim()).filter(Boolean).sort();

    expect(actual).toEqual(expected);
  });
});
