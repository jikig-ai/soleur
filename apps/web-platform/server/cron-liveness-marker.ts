// Structured, WARN-level, fail-open cron-liveness markers (#6714, ADR-108 form).
//
// WHY THIS FILE EXISTS. The community-monitor persistence path emitted ZERO
// `SOLEUR_*` markers, which is precisely why H9 — "which internal branch
// swallowed persistence on the GREEN days of 2026-07-14 → 07-19" — could not be
// decided during the investigation. The deciding datum lived only in Inngest's
// step-level run history, which is host-local by design (ADR-030 binds the
// server to 127.0.0.1:8288) and therefore unreachable without SSH. These markers
// move that datum into Better Stack, where it is queryable with
// `scripts/betterstack-query.sh --grep SOLEUR_… --since <N>d`.
//
// Four properties below are load-bearing. A naive `console.log("SOLEUR_X …")`
// would compile, read as correct, and be SILENTLY INVISIBLE in production:
//
//  1. pino **WARN** level (>= 40), never info. The Vector `app_container_warn_
//     filter` ships only pino level >= 40 to Better Stack (runbook
//     `betterstack-log-query.md`). An info-level marker never leaves the host.
//  2. A **top-level boolean discriminator** plus spread fields, so
//     `betterstack-query.sh --grep SOLEUR_X` matches via its `raw LIKE '%…%'`
//     filter with no script change.
//  3. **Fail-open** — every emit is wrapped so an emit failure can never
//     propagate. Observability must never break the run it observes.
//  4. A **dedicated pino instance with NO `hooks.logMethod`** (logger.ts:123-125
//     auto-mirrors every WARN+ line to a Sentry breadcrumb; a steady daily
//     marker stream would evict genuine diagnostics from the shared-scope ring
//     buffer).
//
// The silent `catch` blocks are the sanctioned observability-of-observability
// exemption to `cq-silent-fallback-must-mirror-to-sentry` (documented in
// ADR-108): a logging failure must NEVER red a cron, and mirroring the failure
// to Sentry would re-enter the same broken path.
import pino from "pino";

// Dedicated instance — NO `hooks.logMethod` (so no Sentry breadcrumb mirror).
// The default pino level is `info`, so `warn` lines always emit.
//
// ‼️ BOUNDARY: this instance has NO `formatters.log` renameUserIdToHash
// (ADR-029 PII pseudonymization) and NO `redact` paths — both are
// shared-logger-only. The marker interfaces below MUST therefore stay free of
// any user id, email, secret, or other regulated field. They carry only a cron
// name, a status enum, counts, a PR/issue number, a date, and a repo-relative
// path.
//
// Be precise about WHICH half is uncovered, or the next author guards the wrong
// thing. Vector's `pii_scrub_structured` re-applies the ADR-029 HMAC rename in
// VRL to EVERY line reaching Better Stack, so a top-level `userId` would still
// be pseudonymized downstream. What is genuinely unprotected is the `redact`
// KEY SET: a top-level `token`/`secret`/`password`/`authorization` ships
// VERBATIM, because `pii_scrub_drop_userdata` drops only Art-9 content keys
// (body/content/message/prompt/…) and `pii_scrub_string` — which holds the
// credential and email regexes — SKIPS ENTIRELY once a line has parsed as JSON.
// Credential-shaped KEYS are the real residual risk here, not user ids.
//
// Note also why `stage` is safe and must stay so: it is typed as a closed union
// of 11 literals, and the UNBOUNDED `message` (raw git/GitHub error text, which
// can embed remote URLs carrying credentials) is deliberately NOT forwarded to
// the marker. Adding `message` here would be one line from shipping unredacted
// upstream errors through a logger with no `redact`.
const log = pino({ base: { component: "cron-liveness" } });

// ---------------------------------------------------------------------------
// Marker 1 — SOLEUR_CRON_PERSIST_RESULT
// ---------------------------------------------------------------------------
// The outcome of safeCommitAndPr, emitted on ALL THREE terminal paths
// (`failure()`, the `no-changes` return, and the `committed` return). Before
// this marker the outcome was `logger.info`-only and therefore unmonitored —
// `no-changes` and `failed` were indistinguishable from a healthy commit in
// every operator-reachable surface.

export interface CronPersistResultMarker {
  cron: string;
  status: "committed" | "no-changes" | "failed";
  /** Committed file count; 0 on no-changes/failed and on a replay-resume. */
  files: number;
  /** PR number when one was opened, else null. */
  pr: number | null;
  /** `failure()` stage on the failed arm, else null. */
  stage: string | null;
}

/** Emit one `SOLEUR_CRON_PERSIST_RESULT` WARN marker. NEVER throws. */
export function emitCronPersistResult(m: CronPersistResultMarker): void {
  try {
    log.warn({ SOLEUR_CRON_PERSIST_RESULT: true, ...m }, "cron persist result");
  } catch {
    // fail-open: a marker-emit failure must never propagate into the cron.
  }
}

// ---------------------------------------------------------------------------
// Marker 2 — SOLEUR_CRON_PERSIST_SKIPPED
// ---------------------------------------------------------------------------
// The persistence gate (`heartbeatOk && !abortedByTimeout`) had no `else`, so a
// RED or timed-out run skipped persistence with no trace at all. `reason`
// discriminates the two arms in one event.

export interface CronPersistSkippedMarker {
  cron: string;
  reason: "red" | "timeout";
}

/** Emit one `SOLEUR_CRON_PERSIST_SKIPPED` WARN marker. NEVER throws. */
export function emitCronPersistSkipped(m: CronPersistSkippedMarker): void {
  try {
    log.warn({ SOLEUR_CRON_PERSIST_SKIPPED: true, ...m }, "cron persist skipped");
  } catch {
    // fail-open.
  }
}

// ---------------------------------------------------------------------------
// Marker 3 — SOLEUR_COMMUNITY_DIGEST_FILE
// ---------------------------------------------------------------------------
// THIS IS THE SIGNAL THAT WOULD HAVE DECIDED H9 ON DAY ONE. Stat'ing the dated
// digest in the workspace immediately before the persistence gate splits
// "the agent never wrote the file" from "the file was written but never entered
// the commit" — the exact discrimination the investigation could not make.
// Workspace presence alone is NOT proof of persistence (that is marker 1's
// job); it is the other half of the pair.

export interface CommunityDigestFileMarker {
  cron: string;
  /**
   * Inngest attempt index. LOAD-BEARING for this marker specifically: the stat
   * runs OUTSIDE step.run, so it re-emits on every replay — and by then the
   * handler's `finally` has deleted the workspace, forcing `present: 0`. Without
   * this field a healthy run that replayed is indistinguishable from an agent
   * that never wrote the file, which is the exact discrimination this marker
   * exists to provide. Consumers should filter to `attempt=0`.
   */
  attempt: number;
  /** Repo-relative digest path that was stat'ed. */
  digest_path: string;
  /** 1 when the file exists in the spawn workspace, 0 otherwise. */
  present: 0 | 1;
}

/** Emit one `SOLEUR_COMMUNITY_DIGEST_FILE` WARN marker. NEVER throws. */
export function emitCommunityDigestFile(m: CommunityDigestFileMarker): void {
  try {
    log.warn({ SOLEUR_COMMUNITY_DIGEST_FILE: true, ...m }, "community digest file");
  } catch {
    // fail-open.
  }
}

// ---------------------------------------------------------------------------
// Marker 4 — SOLEUR_CRON_TIER2_DEFERRED
// ---------------------------------------------------------------------------
// The Tier-2 defer posts a GREEN check-in and skips the spawn entirely, so it is
// indistinguishable from a healthy run in Sentry — that blind spot accounted for
// 4 of the 41 gap days (2026-06-09 → 06-12). `TIER2_DEFERRED_CRONS` is empty at
// HEAD, so this instruments a condition not currently occurring; it is retained
// deliberately (DC-1 in decision-challenges.md) because ADR-126 requires every
// GREEN check-in path to be enumerable, and the cost is one line at one site.

export interface CronTier2DeferredMarker {
  cron: string;
}

/** Emit one `SOLEUR_CRON_TIER2_DEFERRED` WARN marker. NEVER throws. */
export function emitCronTier2Deferred(m: CronTier2DeferredMarker): void {
  try {
    log.warn({ SOLEUR_CRON_TIER2_DEFERRED: true, ...m }, "cron tier2 deferred");
  } catch {
    // fail-open.
  }
}

// ---------------------------------------------------------------------------
// Marker 5 — SOLEUR_CRON_DEDUP_SKIP
// ---------------------------------------------------------------------------
// The date-dedup early-return posts `ok:true` and returns before minting a token
// or spawning. Observed failure shape: run 1 files a genuine digest issue but
// fails to commit; run 2 dedups on that issue and posts GREEN with no artifact.
//
// `digest_committed` alone carries the discrimination. An earlier draft also
// carried a `deduped` boolean, on the theory that one event should distinguish
// "deduped on a genuinely-committed digest" from "issue exists, digest does not".
// It could not: the marker fires only inside `if (digestAlreadyExists)` and the
// gate below it is `if (digestAlreadyExists && digestCommitted)`, so the dedup
// decision IS `digest_committed` and the two fields were equal by construction.
// A second field that cannot disagree with the first tells a Better Stack reader
// they might — which is worse than not carrying it. What matters is the emit's
// PLACEMENT (before the gate, so it fires on both outcomes), not a second field.

export interface CronDedupSkipMarker {
  cron: string;
  /** Date anchor (`YYYY-MM-DD`) the dedup read was scoped to. */
  date: string;
  // NO `matched_issue`. The matched issue's NUMBER is not obtainable at the one
  // call site: `digestIssueExistsForDate` returns a bare boolean, and widening
  // it would break 9 production handlers, ~10 tests asserting its
  // `Promise<boolean>` shape, and the discovery-based cron-cohort-title-date-pin
  // guard — all for a diagnostic nicety. Emitting `null` instead was rejected as
  // a LIE: this marker fires only when an issue DID match, so a null would read
  // as "none matched". `date` + the cron name already locate the issue by search.
  /**
   * 1 when the dated digest is committed on the default branch. This is ALSO
   * the dedup decision: 1 => the run short-circuited, 0 => it fell through to
   * spawn (the recovery path).
   */
  digest_committed: 0 | 1;
}

/** Emit one `SOLEUR_CRON_DEDUP_SKIP` WARN marker. NEVER throws. */
export function emitCronDedupSkip(m: CronDedupSkipMarker): void {
  try {
    log.warn({ SOLEUR_CRON_DEDUP_SKIP: true, ...m }, "cron dedup skip");
  } catch {
    // fail-open.
  }
}

// ---------------------------------------------------------------------------
// Marker 6 — SOLEUR_CRON_DIGEST_LIVENESS
// ---------------------------------------------------------------------------
// The VERDICT, and the reason for it. Without this the five markers above make
// every GREEN-with-no-artifact path enumerable but leave the RED arms
// undiagnosable: marker 1 emits `status:"committed"` from inside safeCommitAndPr
// BEFORE the handler's liveness table runs, so an operator seeing
// `PERSIST_RESULT status=committed` next to a RED monitor cannot tell a drifted
// result contract from a commit that simply missed today's digest. That is the
// "RED with an undiagnosable cause" shape this whole module exists to close, so
// leaving it open would have been the same defect in a new place.
//
// `run_id` and `attempt` are the correlation fields the precedent
// (claude-cost-marker's `id`) carries and the five markers above lack. They
// matter more here than in the precedent because markers 2/3/5 sit OUTSIDE
// step.run and therefore RE-EMIT on every Inngest replay — most consequentially
// marker 3, whose `present` is necessarily 0 on a replay since the `finally`
// already deleted the workspace. Without `attempt`, a healthy run that replayed
// looks like an agent that failed to write the file.

export interface CronDigestLivenessMarker {
  cron: string;
  /** Inngest run id — correlates every marker from ONE logical run. */
  run_id: string;
  /** Inngest attempt index. Markers outside step.run re-emit per attempt. */
  attempt: number;
  /** 1 when the operator's artifact is proven landed. */
  ok: 0 | 1;
  /** Which arm of the liveness table decided it. */
  reason:
    | "digest-committed"
    | "persistence-not-committed"
    | "digest-absent-from-commit"
    | "undetermined-replay-resume"
    | "undetermined-contract-drift"
    | "persistence-skipped";
}

/** Emit one `SOLEUR_CRON_DIGEST_LIVENESS` WARN marker. NEVER throws. */
export function emitCronDigestLiveness(m: CronDigestLivenessMarker): void {
  try {
    log.warn({ SOLEUR_CRON_DIGEST_LIVENESS: true, ...m }, "cron digest liveness");
  } catch {
    // fail-open.
  }
}
