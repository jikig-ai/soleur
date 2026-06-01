// #4689/#4686/#4684 — un-wiring guard for the output-aware heartbeat.
//
// The behavioral contract of resolveOutputAwareOk lives in cron-shared.test.ts.
// THIS file guards the integration points the helper was built for: the three
// always-create producer handlers must feed the OUTPUT-aware result
// (`heartbeatOk`) to postSentryHeartbeat — NOT the bare spawn exit code
// (`ok: spawnResult.ok`), which is the exact pre-fix line the PR replaces.
//
// Without this guard a revert of just the handler wiring (leaving the helper
// intact and green) would pass the entire suite — the helper unit tests can't
// see the call sites. Per cq-test-fixtures-synthesized-only we read the
// production source via readFileSync (the wiring IS the artifact under test)
// and assert the established source-shape anchors, mirroring the convention in
// cron-roadmap-review.test.ts.

import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const FN_DIR = resolve(__dirname, "../../../server/inngest/functions");

const WIRED_PRODUCERS = [
  "cron-roadmap-review.ts",
  "cron-content-generator.ts",
  "cron-competitive-analysis.ts",
] as const;

describe("output-aware heartbeat wiring (always-create producers)", () => {
  it.each(WIRED_PRODUCERS)(
    "%s gates its heartbeat on output, not the bare spawn exit code",
    (file) => {
      const src = readFileSync(resolve(FN_DIR, file), "utf-8");

      // Calls the output-aware resolver…
      expect(src).toContain("resolveOutputAwareOk(");
      // …captures a replay-stable run window…
      expect(src).toContain('"run-started-at"');
      expect(src).toContain("runStartedAt");
      // …and feeds the RESOLVED result to the heartbeat. The pre-fix line was
      // `postSentryHeartbeat({ ok: spawnResult.ok, ...})`; the success-path
      // heartbeat must now read heartbeatOk.
      expect(src).toContain("ok: heartbeatOk");
      // The success path must NOT still pass the raw spawn result. (The
      // setup-failure early-exit legitimately passes `ok: false`, so we only
      // forbid the spawnResult.ok form specifically.)
      expect(src).not.toContain("ok: spawnResult.ok");
    },
  );

  it("cron-strategy-review is intentionally NOT wired (pure-TS, already output-aware)", () => {
    // strategy-review derives ok from `review.errors === 0` and legitimately
    // creates zero issues on an all-clean run; wiring resolveOutputAwareOk
    // would false-red those healthy runs. Guard the deliberate exclusion so a
    // future "wire all four for symmetry" change has to confront this comment.
    const src = readFileSync(resolve(FN_DIR, "cron-strategy-review.ts"), "utf-8");
    expect(src).not.toContain("resolveOutputAwareOk");
    expect(src).toContain("ok: result.ok");
  });
});
