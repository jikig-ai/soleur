// #8076 / ADR-216 addendum — the run-report population, in one leaf.
//
// A cron in this list MUST file a `scheduled-<task>` issue on every run: its
// handler verifies run completion by that issue's existence
// (`resolveOutputAwareOk` → `verifyScheduledIssueCreated` in `_cron-shared.ts`),
// and the persistence handshake refuses to commit the run's artifacts until it
// is seen. That makes the filing "mandated by construction" — the reasoning
// ADR-216 used to exempt workflow-YAML filings (class 2) — inside the cron
// substrate the filing gate covers (class 3). First live contact was #8059:
// eleven hours after the gate merged, cron-community-monitor was denied on its
// prescribed filing and complied by relabelling a community digest
// `meta/machinery`.
//
// Three consumers read this leaf and it imports nothing from any cron
// function, so the graph stays acyclic:
//   - `_cron-claude-eval-substrate.ts` derives the per-spawn
//     `run-report-label <label>` directive (exit 0 of the containment hook)
//     from `fn`/`label`;
//   - `cron-stale-deferred-scope-outs.ts` sweeps SUCCESS run-reports older
//     than `closeAfterDays` (rows with `null` are never queried);
//   - `scripts/issue-flow-measure.sh` mirrors the label set for its line 1c
//     (parity: `plugins/soleur/test/issue-flow-measure.test.sh`).
//
// The population key is "calls `resolveOutputAwareOk`", NOT the heartbeat's
// `TASK_INVENTORY` (`cron-cloud-task-heartbeat.ts`), which is the five-entry
// liveness subset — the brainstorm keyed on that and was wrong by four. The
// parity test `cron-run-report-labels-parity.test.ts` greps the call sites.
//
// `closeAfterDays` is a LITERAL per row: 3 × the heartbeat's `maxGapDays` where
// the heartbeat tracks the cron (parity row (iii) asserts it), else 3 × the
// schedule period + 2 d. `null` means never swept: campaign-calendar
// comment-bumps ONE standing issue ("Do NOT create a new issue",
// `_cron-shared.ts` "counts via updated_at"), and legal-audit's issues are
// per-gap findings, not reports — it is in the directive map by operator
// decision (D1, plan review 2026-09-11) and never in the sweep.

export const RUN_REPORT_TITLE_PREFIX = "[Scheduled] ";

export interface RunReportCron {
  /** Inngest function id (the `cronName` the substrate spawns under). */
  fn: string;
  /** The cron's `SENTRY_MONITOR_SLUG`, which is also its scheduled-issue label. */
  label: string;
  /** Sweep window for SUCCESS reports, or `null` for never swept. */
  closeAfterDays: number | null;
}

export const RUN_REPORT_CRONS: ReadonlyArray<RunReportCron> = [
  { fn: "cron-architecture-diagram-sync", label: "scheduled-architecture-diagram-sync", closeAfterDays: 27 },
  { fn: "cron-campaign-calendar", label: "scheduled-campaign-calendar", closeAfterDays: null },
  { fn: "cron-community-monitor", label: "scheduled-community-monitor", closeAfterDays: 9 },
  { fn: "cron-competitive-analysis", label: "scheduled-competitive-analysis", closeAfterDays: 120 },
  { fn: "cron-content-generator", label: "scheduled-content-generator", closeAfterDays: 27 },
  { fn: "cron-growth-audit", label: "scheduled-growth-audit", closeAfterDays: 27 },
  { fn: "cron-growth-execution", label: "scheduled-growth-execution", closeAfterDays: 51 },
  { fn: "cron-legal-audit", label: "scheduled-legal-audit", closeAfterDays: null },
  { fn: "cron-roadmap-review", label: "scheduled-roadmap-review", closeAfterDays: 27 },
  { fn: "cron-seo-aeo-audit", label: "scheduled-seo-aeo-audit", closeAfterDays: 27 },
];

/** The directive label for a cron, or `null` when the cron is not a run-reporter. */
export function runReportLabelFor(cronName: string): string | null {
  return RUN_REPORT_CRONS.find((r) => r.fn === cronName)?.label ?? null;
}

/** Rows the sweeper may close (never campaign-calendar, never legal-audit). */
export function sweepableRunReports(): ReadonlyArray<RunReportCron & { closeAfterDays: number }> {
  return RUN_REPORT_CRONS.filter(
    (r): r is RunReportCron & { closeAfterDays: number } => r.closeAfterDays !== null,
  );
}
