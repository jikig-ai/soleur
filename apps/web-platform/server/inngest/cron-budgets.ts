// Per-run dollar ceiling for every Claude spawn site (#8611 Fix 3; ADR-243).
//
// spawnClaudeEval passes `--max-budget-usd <CLAUDE_BUDGET_USD[cronName]>` to the `claude` CLI itself
// (sites do not pass it, and a caller-supplied one is refused). Verified on the pinned
// @anthropic-ai/claude-code (2.1.219 at design time, 2.1.280 now; `--print` mode only — every site
// runs --print). A run that reaches its cap ends with an `is_error` result whose `subtype` is
// `error_max_budget_usd`; classifyEvalFatal reports it as its own class (`budget-capped`).
//
// Rule: cap = ceil(max(3 × median single-session cost, 1.25 × largest observed, $2)), from the
// SOLEUR_CLAUDE_COST markers' own `cost_usd` over 2026-08-24..09-23, one session per run, with
// Opus 5 sessions re-priced to Opus 5.5 (AUDIT_MODEL). A single sample is not data (it is often a
// run cut short by credit exhaustion), so n=1 sites and sites with no funded run take a tier
// default: $15 audit tier (the ledger records ~$3–12 per ux-audit run and growth-audit's own data
// gives $16), $5 execution tier. The per-site table and the worst-case-day arithmetic live in
// ADR-243 §3; cap and alert-threshold recalibration is tracked on #8613.
//
// A per-run cap does not bound the daily total — the Better Stack daily burn alert does.
export const CLAUDE_BUDGET_USD: Readonly<Record<string, number>> = Object.freeze({
  // Audit tier (AUDIT_MODEL).
  "cron-agent-native-audit": 15, //        n=1 ($0.21, likely truncated) — audit-tier default
  "cron-architecture-diagram-sync": 9, //  n=2, median $2.91
  "cron-competitive-analysis": 15, //      no funded run — audit-tier default
  "cron-growth-audit": 16, //              n=2, median $5.27
  "cron-legal-audit": 15, //               no funded run — audit-tier default
  "cron-ux-audit": 15, //                  no funded run — audit-tier default
  // Execution tier (EXECUTION_MODEL).
  "cron-bug-fixer": 4, //                  n=10, median $0.75, max $3.06
  "cron-campaign-calendar": 4, //          n=2, median $1.27
  "cron-community-monitor": 6, //          n=9, median $1.75
  "cron-content-generator": 14, //         n=2, median $4.62
  "cron-daily-triage": 5, //               unmetered until #8611 — execution-tier default
  "cron-follow-through-monitor": 5, //     unmetered until #8611 — execution-tier default
  "cron-growth-execution": 5, //           n=1 ($1.02) — execution-tier default
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

// Manual-fire RATE limit (#8611 Fix 3), not a spend bound: every `soleur:trigger-cron` fire is a
// new run with a fresh per-run cap, which is how the 2026-09-19/20 extra runs happened. At most 2
// starts per function per hour; Inngest QUEUES the excess (still billed, just later), so a burst is
// spread out long enough for the hourly-evaluated burn alert to page before it compounds. The
// dollar bound is the burn alert and, ultimately, a Console spend limit (#8614). Verified honored
// by the pinned self-hosted server in the #8611 streaming spike (2 ran, 2 queued).
export const CLAUDE_EVAL_THROTTLE = Object.freeze({ limit: 2, period: "1h" } as const);
