// Calibration baseline fixture for the tier1-scan self-test.
//
// This file deliberately contains a Tier 1 anti-pattern (`transition-all`) so
// the scanner's end-to-end wiring can be exercised against a "scanner-scoped"
// .tsx file without depending on production code being mid-calibration.
//
// History: PR #4265 originally pinned the calibration baseline to
// `apps/web-platform/components/connect-repo/setting-up-state.tsx`. Draining
// the production findings (PR #4292) removed the `transition-all` token from
// that file, invalidating the baseline. The fix-class is documented in
// `knowledge-base/project/learnings/best-practices/2026-05-21-calibration-fixture-probe-and-markdown-table-pipe-escapes.md`
// ("Pattern 1: A calibration fixture must trigger the active rule set").
//
// Decoupling the baseline from production code lets us drain findings without
// breaking the scanner's self-test. The "real project file" intent of the
// original AC4 is preserved by the per-rule positive fixtures (lines 50-200 of
// tier1-scan.test.ts) which exercise every rule against synthetic .tsx.
//
// Do NOT remove the `transition-all` token below — it is the load-bearing
// signal the scanner self-test asserts on. If a future v1.5 rule retires
// TRANSITION-ALL, swap the token for another active Tier 1 anti-pattern AND
// update the precondition assertion in tier1-scan.test.ts.

export function CalibrationBaseline() {
  return (
    <div className="rounded bg-zinc-800 transition-all duration-300">
      Calibration baseline — TRANSITION-ALL token is intentional.
    </div>
  );
}
