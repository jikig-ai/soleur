// Workflows the web server's watchdog dispatch clock fires via
// `workflow_dispatch` (#8495, ADR-246). Deliberately import-free so the Sentry
// parity test can read it as a pure module.
//
// ELIGIBILITY (ADR-246): a row belongs here ONLY if the workflow watches the
// scheduling substrate or something that substrate depends on, so it cannot be
// scheduled by that substrate (ADR-033 anti-circularity). Any other scheduled
// job uses the Inngest dispatch pattern (cron-main-health-monitor) instead.
//
// Adding a row: the workflow keeps `schedule:` (fallback) + `workflow_dispatch:`
// as its ONLY triggers and a `concurrency` group with `cancel-in-progress: false`;
// its Sentry monitor margin follows the budget in cron-monitors.tf. The checklist
// is in knowledge-base/engineering/operations/runbooks/inngest-server.md
// ("How the external watchdogs are triggered"); sentry-monitor-iac-parity.test.ts
// enforces it.

export interface WatchdogDispatchEntry {
  /** Workflow file basename; the dispatches endpoint accepts it as {workflow_id}. */
  readonly workflowFile: string;
  /** Sentry cron monitor slug the workflow's final heartbeat checks into. */
  readonly monitorSlug: string;
  /** Slot length; slots are UTC wall-clock multiples of this. */
  readonly intervalMinutes: number;
  /** Why this watcher cannot be scheduled by Inngest. Required, non-empty. */
  readonly eligibility: string;
}

export const WATCHDOG_DISPATCH_TABLE: ReadonlyArray<WatchdogDispatchEntry> = [
  {
    workflowFile: "scheduled-inngest-health.yml",
    monitorSlug: "scheduled-inngest-health",
    intervalMinutes: 15,
    eligibility:
      "Watches the Inngest scheduler itself; an Inngest cron cannot fire while Inngest is down (ADR-033 anti-circularity).",
  },
  {
    workflowFile: "scheduled-zot-restart-loop.yml",
    monitorSlug: "scheduled-zot-restart-loop",
    intervalMinutes: 60,
    eligibility:
      "Watches the zot registry the Inngest host pulls its image from at boot (#8539), so it shares Inngest's failure domain.",
  },
];
