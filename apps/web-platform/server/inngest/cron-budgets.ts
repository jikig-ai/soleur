// Per-run dollar ceiling for every Claude spawn site (#8611 Fix 3; ADR-241).
//
// Passed to the `claude` CLI as `--max-budget-usd` (verified on the pinned
// @anthropic-ai/claude-code@2.1.219, `--print` mode only — every site runs --print). A run that
// reaches its cap ends with an `is_error` result whose `subtype` is `error_max_budget_usd`
// (string taken from the 2.1.219 binary), which the cost marker surfaces.
//
// Rule: cap = ceil(max(3 × median single-session cost, 1.25 × largest observed, $2)), from the
// SOLEUR_CLAUDE_COST markers' own `cost_usd` over 2026-08-24..09-23, one session per run, with
// Opus 5 sessions re-priced to Opus 5.5 (AUDIT_MODEL). Sites with no funded run in that window
// take a tier default — $10 audit tier, $5 execution tier — until they have data. The table and
// its worst-case-daily column live in ADR-241; recalibration is tracked on #8613.
//
// A per-run cap does not bound the daily total — the Better Stack daily burn alert does.
export const CLAUDE_BUDGET_USD: Readonly<Record<string, number>> = Object.freeze({
  // Audit tier (AUDIT_MODEL).
  "cron-agent-native-audit": 2, //         n=1, median $0.21
  "cron-architecture-diagram-sync": 9, //  n=2, median $2.91
  "cron-competitive-analysis": 10, //      no funded run — audit-tier default
  "cron-growth-audit": 16, //              n=2, median $5.27
  "cron-legal-audit": 10, //               no funded run — audit-tier default
  "cron-ux-audit": 10, //                  no funded run — audit-tier default
  // Execution tier (EXECUTION_MODEL).
  "cron-bug-fixer": 4, //                  n=10, median $0.75, max $3.06
  "cron-campaign-calendar": 4, //          n=2, median $1.27
  "cron-community-monitor": 6, //          n=9, median $1.75
  "cron-content-generator": 14, //         n=2, median $4.62
  "cron-daily-triage": 5, //               unmetered until #8611 — execution-tier default
  "cron-follow-through-monitor": 5, //     unmetered until #8611 — execution-tier default
  "cron-growth-execution": 4, //           n=1, median $1.02
  "cron-roadmap-review": 4, //             n=2, median $1.01
  "cron-seo-aeo-audit": 10, //             n=2, median $3.13, max $4.61
  "event-ship-merge": 5, //                no funded run — execution-tier default
  "oneshot-f2-defer-gate-review": 5, //    no funded run — execution-tier default
  "oneshot-recheck-4217-calibration": 5, // no funded run — execution-tier default
});

/** The CLI flag pair for one spawn site. Throws on an unknown site rather than running uncapped. */
export function budgetFlags(site: string): string[] {
  const usd = CLAUDE_BUDGET_USD[site];
  if (usd === undefined) throw new Error(`cron-budgets: no budget for "${site}"`);
  return ["--max-budget-usd", String(usd)];
}

// Manual-fire bound (#8611 Fix 3): every `soleur:trigger-cron` fire is a new run with a fresh
// per-run cap, which is how the 2026-09-19/20 extra runs happened. At most 2 starts per function
// per hour; Inngest queues (does not drop) the excess. Verified honored by the pinned self-hosted
// server in the #8611 streaming spike (2 ran, 2 queued). Spread into every spawn site's config.
export const CLAUDE_EVAL_THROTTLE = Object.freeze({ limit: 2, period: "1h" } as const);
