// Structured, WARN-level, fail-open Anthropic cost marker (ADR-103).
//
// `SOLEUR_CLAUDE_COST` is the top-level discriminator so
// `scripts/betterstack-query.sh --grep SOLEUR_CLAUDE_COST` matches it via its
// `raw LIKE '%…%'` filter — no script change required (plan Scope 3). The marker
// is emitted at pino **WARN** (level 40) because the Vector `app_container_warn_
// filter` only ships pino level >= 40 to Better Stack (runbook betterstack-log-
// query.md; plan R4). An info-level marker would never leave the host.
//
// Uses a DEDICATED pino instance that does NOT install the mirrorToSentry
// logMethod hook (logger.ts:123-125 auto-mirrors every WARN+ line to a Sentry
// breadcrumb — a steady per-turn cost-marker stream would evict genuine
// diagnostics from the shared-scope ring buffer; plan R-H / arch P2-Q4). Level
// WARN is still required so the Vector filter ships it.
//
// The silent `catch` below is the sanctioned observability-of-observability
// exemption to `cq-silent-fallback-must-mirror-to-sentry` (documented in
// ADR-103): a logging failure must NEVER red a cron or fail a session, and
// mirroring the failure to Sentry would re-enter the same broken path.
import pino from "pino";

// Dedicated instance — NO `hooks.logMethod` (so no Sentry breadcrumb mirror).
// `base` tags every line with the component so a Better Stack query can scope to
// it. The default pino level is `info`, so `warn` lines always emit.
const log = pino({ base: { component: "claude-cost" } });

// Where the spend originated. Session paths are fixed strings; crons are
// `cron:<cronName>` so a Better Stack `GROUP BY source` ranks per-cron spend.
export type ClaudeCostSource =
  | "agent-runner"
  | "cc-soleur-go"
  | "leader-loop"
  | `cron:${string}`;

// Positive capture-status on EVERY substrate exit (plan obs P1): row-absence is
// NOT a probe. `ok` carries a parsed cost; the others carry `cost_usd:null` and
// disambiguate "capture broke" from "genuinely $0" from "cron never ran".
export type CaptureStatus =
  | "ok"
  | "no-result-event"
  | "parse-error"
  | "timeout";

export interface ClaudeCostMarker {
  source: ClaudeCostSource;
  model: string | null;
  input_tokens: number | null;
  output_tokens: number | null;
  cache_read_input_tokens: number | null;
  cache_creation_input_tokens: number | null;
  cost_usd: number | null;
  // Correlation id — `conversationId` for sessions, `runId ?? cronName` for crons.
  id: string;
  capture_status: CaptureStatus;
}

/**
 * Emit one `SOLEUR_CLAUDE_COST` WARN marker. NEVER throws — observability must
 * never break a run (the fail-open contract; plan User-Brand Impact).
 */
export function emitClaudeCostMarker(m: ClaudeCostMarker): void {
  try {
    log.warn({ SOLEUR_CLAUDE_COST: true, ...m }, "claude cost");
  } catch {
    // fail-open: a marker-emit failure must never propagate into the caller.
  }
}
