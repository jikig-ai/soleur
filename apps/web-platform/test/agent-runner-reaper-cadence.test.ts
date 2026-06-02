import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Disk-IO remediation (2026-06-02): the stuck-active reaper poll cadence was
// widened 60s → 300s to cut the `find_stuck_active_conversations` RPC volume 5×
// — it was the #2 prod Supabase Disk-IO write consumer (760k ms / 38k calls
// over a 27-day window). The 120s STUCK_ACTIVE_THRESHOLD_SECONDS staleness
// window is INDEPENDENT of poll cadence and MUST stay 120s (it is co-locked
// across four sources per the agent-runner.ts:726 comment). This test pins
// BOTH so a future edit cannot silently re-couple them or revert the cadence.
//
// Source-reading regex test: the constants are module-private (not exported),
// so this asserts on the file text. Standalone file per the work-skill guidance
// — never colocate readFileSync source asserts with a file that mocks node:fs.
//
// Plan: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 1.

const SRC = readFileSync(
  path.join(__dirname, "../server/agent-runner.ts"),
  "utf8",
);

describe("stuck-active reaper cadence (disk-IO remediation)", () => {
  it("polls every 300s (widened from 60s to cut RPC volume 5×)", () => {
    expect(SRC).toMatch(
      /STUCK_ACTIVE_CHECK_INTERVAL_MS\s*=\s*300\s*\*\s*1_000\s*;/,
    );
  });

  it("keeps the staleness threshold at 120s (independent of poll cadence)", () => {
    expect(SRC).toMatch(/STUCK_ACTIVE_THRESHOLD_SECONDS\s*=\s*120\s*;/);
  });

  it("does NOT retain the old 60s poll cadence", () => {
    expect(SRC).not.toMatch(
      /STUCK_ACTIVE_CHECK_INTERVAL_MS\s*=\s*60\s*\*\s*1_000\s*;/,
    );
  });
});
