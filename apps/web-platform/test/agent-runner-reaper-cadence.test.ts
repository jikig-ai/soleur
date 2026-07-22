import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Disk-IO remediation (2026-06-02): the stuck-active reaper poll cadence was
// widened 60s → 300s to cut the `find_stuck_active_conversations` RPC volume 5×
// — it was the #2 prod Supabase Disk-IO write consumer (760k ms / 38k calls
// over a 27-day window). The staleness window is INDEPENDENT of poll cadence.
// 2026-07-18 Disk-IO backoff: the local STUCK_ACTIVE_THRESHOLD_SECONDS literal
// was structurally de-duplicated into the shared SLOT_STALENESS_THRESHOLD_SECONDS
// const (server/concurrency.ts, now 240s) — agent-runner imports it and passes
// it as the RPC threshold arg, so it can no longer drift from the ws-handler
// read-side or the SQL sweep (mig 133). This test pins the poll cadence AND the
// shared-const wiring so a future edit cannot silently re-couple them, revert the
// cadence, or re-introduce a divergent local threshold literal.
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

  it("uses the shared SLOT_STALENESS_THRESHOLD_SECONDS as the RPC threshold (no local literal)", () => {
    // Imports the shared const...
    expect(SRC).toMatch(
      /import\s*\{[^}]*\bSLOT_STALENESS_THRESHOLD_SECONDS\b[^}]*\}\s*from\s*["']\.\/concurrency["']/,
    );
    // ...and passes it as the find_stuck_active_conversations threshold arg.
    expect(SRC).toMatch(
      /p_threshold_seconds:\s*SLOT_STALENESS_THRESHOLD_SECONDS/,
    );
    // The old divergent local literal is gone (structural de-dup, not a copy).
    expect(SRC).not.toMatch(/STUCK_ACTIVE_THRESHOLD_SECONDS\s*=\s*120/);
  });

  it("does NOT retain the old 60s poll cadence", () => {
    expect(SRC).not.toMatch(
      /STUCK_ACTIVE_CHECK_INTERVAL_MS\s*=\s*60\s*\*\s*1_000\s*;/,
    );
  });
});
