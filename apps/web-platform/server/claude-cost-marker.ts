// Structured, WARN-level, fail-open Anthropic cost marker (ADR-108).
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
// ADR-108): a logging failure must NEVER red a cron or fail a session, and
// mirroring the failure to Sentry would re-enter the same broken path.
import pino from "pino";

// Dedicated instance — NO `hooks.logMethod` (so no Sentry breadcrumb mirror).
// `base` tags every line with the component so a Better Stack query can scope to
// it. The default pino level is `info`, so `warn` lines always emit.
//
// ‼️ BOUNDARY: this instance also has NO `formatters.log` renameUserIdToHash
// (ADR-029 PII pseudonymization) and NO `redact` paths — both are shared-logger-
// only. The marker interfaces below MUST therefore stay free of any user id,
// email, secret, or other regulated/sensitive field (they carry only source,
// model, token counts, cost, a conversationId/cron correlation id, and status).
// Adding such a field here would silently bypass ADR-029 + redaction.
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

// -----------------------------------------------------------------------------
// Daily Admin cost-report marker (plan Phase 3). Distinct `SOLEUR_CLAUDE_COST_
// DAILY` discriminator from the per-run marker so the runbook can rank either.
// The per-model entry is an EXPLICIT field-allowlist (named picks) — the cron
// MUST build it this way and NEVER `...row`-spread the Admin API response, whose
// rows carry `api_key_id`/`workspace_id` that must never reach Better Stack
// (security F2 / GDPR field-allowlist). The type is the enforcement surface.
export interface ClaudeCostDailyModelEntry {
  model: string;
  input_tokens: number | null;
  output_tokens: number | null;
  cache_read_input_tokens: number | null;
  cache_creation_input_tokens: number | null;
  cost_usd: number | null;
}

export interface ClaudeCostDailyMarker {
  // `key-missing` is the positively-dark signal emitted while the admin key is
  // unprovisioned (obs P4) — an absent row would be mis-triageable as a
  // regression during the code-merges-first → mint window.
  status: "ok" | "key-missing";
  // UTC date the report covers (`YYYY-MM-DD`), or null on the key-missing path.
  date: string | null;
  // Authoritative org total for the day, or null (key-missing / no data).
  cost_usd: number | null;
  models: ClaudeCostDailyModelEntry[];
  // Whole UTC days since the FIRST observed dark fire — key-missing path only,
  // absent on `status:"ok"`. Deliberately NOT "age of the current dark window":
  // it does not reset if the key is minted and later unset (ADR-108 names key
  // exposure a rotation trigger). Inert reporting data; nothing branches on it.
  // Complies with the ‼️ BOUNDARY above — an integer day count carries no user
  // id, email, secret, or regulated data. Prior art: `days_since_last` on
  // cron-skill-freshness.ts.
  days_since_first_dark?: number;
}

/**
 * Emit one `SOLEUR_CLAUDE_COST_DAILY` WARN marker. NEVER throws (fail-open).
 */
export function emitClaudeCostDailyMarker(m: ClaudeCostDailyMarker): void {
  try {
    log.warn({ SOLEUR_CLAUDE_COST_DAILY: true, ...m }, "claude cost daily");
  } catch {
    // fail-open: observability must never break the cost-report cron.
  }
}
