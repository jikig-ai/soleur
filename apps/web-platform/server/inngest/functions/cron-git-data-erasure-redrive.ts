// cron-git-data-erasure-redrive — re-drives pending git-data bare-repo erasures (#8211, PR-B2).
//
// WHY: account deletion calls removeGitDataRepo once. Any outcome other than `erased` (refused,
// unreachable, unauthorized, unconfigured, host_key_mismatch, a throw) used to exist only as a Sentry
// event, and the re-drive was a manual sweep. The LUKS cutover runbook lists "the per-id re-erasure
// path for a populated store" as a hard precondition of the real flip. account-delete.ts now records
// each such id in git_data_erasure_pending (migration 182); this cron claims due rows and calls
// removeGitDataRepo per id until the host reports `erased`.
//
// SHAPE
//   - The cron fires every 15 minutes (and on `cron/git-data-erasure-redrive.manual-trigger`). Each
//     ROW is retried at most once per CLAIM_MIN_INTERVAL (one hour): the claim RPC stamps
//     last_attempt_at at CLAIM time (a few seconds after the tick), so a row claimed at :00 is not yet
//     due again at the next hour's :00 tick and is usually retried at the :15 tick, 60-75 minutes
//     later. Each run handles at most CLAIM_LIMIT rows.
//   - One step.run per row, and the row is claimed INSIDE that step (p_limit 1, FOR UPDATE SKIP
//     LOCKED, stamped in the same statement). The workspace id therefore never leaves the step: it is
//     not a step output and so not Inngest run state, and the step is named by index, never by id.
//     A double run never hands one row to two callers.
//   - The ledger is NOT proof that an account is gone. Before ANY host call the row's owner is checked
//     with git_data_erasure_owner_gone (no auth/membership row still keys on the id). A seeded wrong
//     id, or a deletion that aborted after the ledger write, therefore keeps its row and its
//     repository: nothing is erased, nothing is resolved, the claim stamp is the backoff. Counted, and
//     warned once per run as `owner_still_exists` (no ids). An owner-check ERROR is "not gone".
//   - `erased` => resolve_git_data_erasure_pending (delete the row, bump the non-identifying counter,
//     one statement). The host wrapper treats an absent repo as rc 0, so confirmed-absent == erased.
//     Any other outcome leaves the row; a refusal during a freeze or rotate window simply waits.
//     `skipped` (no REMOVE key and no sibling git-data inputs) is NOT confirmation and leaves the row.
//   - A stuck row is NEVER purged on a timer. The oldest pending age is gauged every run, SPLIT by
//     owner: the 20/28-day escalation looks ONLY at rows whose owner is gone (git_data_erasure_pending_ages),
//     because a row whose owner still exists is an aborted deletion that must NOT be erased: it gets its
//     own warn after LIVE_OWNER_WARN_AFTER_SECONDS ("deletion aborted? owner still exists, do not
//     erase"). At 20 days a Sentry
//     ERROR issue is raised (escalation=20d), at 28 days a second one (escalation=28d). A sentry_alert,
//     git_data_erasure_redrive_escalation (feature=cron-git-data-erasure-redrive AND escalation in
//     20d,28d, infra/sentry/issue-alerts.tf, #10914), emails them; it is a hard
//     precondition of the real flip. Until that rule is applied and sentry-alert-live-fidelity.sh passes,
//     they are only Sentry issues someone must look at. Art. 12(3) allows one calendar month, which can be
//     as short as 28 days (February): the 28-day event is therefore the LAST warning, not a margin.
//     Each tier re-emits at most once per hour per process, not on every 15-minute run.
//   - The claimed id needs no shape check: git_data_erasure_pending.workspace_id is a `uuid` primary key
//     and claim_git_data_erasure_pending RETURNS TABLE (workspace_id uuid, ...), so Postgres can only hand
//     back a canonical UUID. (The host wrapper and the owner-check RPC re-validate the id regardless.)
//   - A row the claim returns with last_outcome = 'seeded' is NOT refreshed with the host outcome:
//     overwriting it would erase the seed provenance git_data_erasure_owner_gone uses to keep the
//     workspace_members check for operator-supplied ids.
//   - A manual event may carry `data.ids` (UUIDs) AND `data.requested_at` (ISO time, not in the
//     future) to seed ids swept from a freeze/rotate window. requested_at is REQUIRED with ids so the
//     Art. 12(3) clock keeps the ORIGINAL request time instead of restarting at age 0. Every id is
//     validated as a UUID and owner-checked like a claimed row; a live id is not seeded.
//
// PRIVACY: this module never logs, tags or step-names a workspace id. Sentry events carry counts, ages,
// status words and scrubbed host detail only; the ids live in the ledger, reachable by service role only.
// The Inngest sentry-correlation middleware attaches the whole event payload to every Sentry event of a
// run as `inngest.event_data`; the Sentry scrubber redacts the `ids` key (server/sensitive-keys.ts), so a
// manual seed's id list does not ride along (`requested_at` does; it is not an identifier). Residual
// (unmeasured, for the Art. 30 entry): the manual event's `data.ids` are persisted in Inngest's event
// store and run state.
//
// ADR-033 invariants: all IO inside step.run (I1); no claude / BYOK (I2); each host call is bounded by
// removeGitDataRepo's own timeout (I3); deterministic step returns (I5); emits no Inngest events (I6).
//
// Residual (unverified): a process death between the account-delete host call and the ledger insert
// loses the id to everything except the Sentry event.

import { createHash } from "node:crypto";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback, warnSilentFallback, infoSilentFallback } from "@/server/observability";
import { removeGitDataRepo } from "@/server/git-data-replication";
import { isUuid } from "@/lib/is-uuid";
import {
  GIT_DATA_ERASURE_HOST_OUTCOMES,
  gitDataErasureOwnerGone,
  recordGitDataErasurePending,
  type GitDataErasureLedgerOutcome,
  type Rpc,
} from "@/server/git-data-erasure-ledger";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

export const SENTRY_MONITOR_SLUG = "scheduled-git-data-erasure-redrive";
const CRON_NAME = "cron-git-data-erasure-redrive";
/** Sentry op of every event this cron raises (the ruling's new op). */
export const REDRIVE_OP = "git-data-erasure-redrive";

/** Rows handled per run (one claim step each). */
export const CLAIM_LIMIT = 25;
/** Per-row backoff: a claimed row is not handed out again for this long. Must be >= 1 minute (RPC floor). */
export const CLAIM_MIN_INTERVAL = "1 hour";
/** Upper bound on ids accepted from one manual event. */
export const MAX_SEED_IDS = 500;

const DAY_S = 86_400;
/** Sentry ERROR issue (routed by sentry_alert git_data_erasure_redrive_escalation once applied, #10914): well ahead of the Art. 12(3) one-month limit. */
export const ESCALATE_AFTER_SECONDS = 20 * DAY_S;
/** Second, louder Sentry ERROR issue (same alert, #10914): the shortest calendar month. */
export const HARD_STOP_AFTER_SECONDS = 28 * DAY_S;
/** A row whose owner STILL EXISTS this long is an aborted deletion worth a human look (never erased). */
export const LIVE_OWNER_WARN_AFTER_SECONDS = 3 * DAY_S;
/** Each escalation tier re-emits at most this often per process (the cron itself runs every 15 minutes). */
export const ESCALATION_REPEAT_MS = 60 * 60 * 1000;

const MEMO_MAX = 1_000;
const quarantineMemo = new Set<string>();
const lastEscalationAt: Record<"20d" | "28d" | "live" | "noprogress", number> = {
  "20d": 0,
  "28d": 0,
  live: 0,
  noprogress: 0,
};
/** Test seam: the report-once and escalation-throttle memos are process-local. */
export function _resetProcessMemosForTest(): void {
  quarantineMemo.clear();
  lastEscalationAt["20d"] = 0;
  lastEscalationAt["28d"] = 0;
  lastEscalationAt.live = 0;
  lastEscalationAt.noprogress = 0;
}

// =============================================================================
// Helpers
// =============================================================================

async function getService(): Promise<Rpc> {
  const { createServiceClient } = await import("@/lib/supabase/service");
  return createServiceClient();
}

interface ClaimedRow {
  workspace_id: string;
  last_outcome?: string | null;
}

type RowStatus =
  | "empty"
  | "claim_failed"
  | "erased"
  | "pending"
  | "owner_present"
  | "owner_check_failed"
  | "resolve_failed"
  | "record_failed";

interface RowResult {
  status: RowStatus;
  /** Low-cardinality key for byStatus: a status word, `unconfigured:<reason>`, `threw:<ErrorName>`. */
  detail: string;
  /** Host `detail`, id-scrubbed (see scrubHostDetail); only for a driven row the host did not confirm. */
  hostDetail?: string;
  exitCode?: number;
}

/** Host statuses that map 1:1 onto a ledger word (derived from GitDataErasureOutcome, not restated). */
const LEDGER_STATUS = new Set<string>(GIT_DATA_ERASURE_HOST_OUTCOMES);

function shortHash(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 16);
}

/**
 * Report one failed stage of the run. `null` + a static message, NOT the Error: reportSilentFallback(Error)
 * is deduplicated against the pino mirror (#8629), which drops the op/stage tags and the extras. The
 * cause (a PostgREST message, never a row value) rides `extra`.
 */
function reportStageFailure(stage: string, message: string, err: unknown): void {
  reportSilentFallback(null, {
    feature: CRON_NAME,
    op: REDRIVE_OP,
    tags: { stage },
    message,
    extra: { fn: CRON_NAME, cause: err instanceof Error ? err.message : String(err) },
  });
}

/**
 * The one host status whose `detail` leads with a fixed reason word. Spelled as a template literal and
 * type-checked against the ledger enum (so a rename fails tsc) rather than restating a quoted word list
 * that test/git-data-erasure-outcome-parity.test.ts forbids.
 */
const UNCONFIGURED_STATUS = `unconfigured` as const satisfies GitDataErasureLedgerOutcome;
/** The fixed reason words `removeGitDataRepo` leads an `unconfigured` detail with (the rest is free text). */
const UNCONFIGURED_REASONS = ["remove_key_absent", "pin_absent", "pin_invalid", "ssh_client_absent"] as const;
function unconfiguredReason(detail: string): string {
  return UNCONFIGURED_REASONS.find((r) => detail.startsWith(r)) ?? "other";
}

const UUID_ANYWHERE_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g;
const HOST_DETAIL_MAX = 200;
/** removeGitDataRepo already scrubs ids and paths; scrub again by value and by shape before it rides an event. */
function scrubHostDetail(raw: string, id: string): string {
  return raw.split(id).join("WORKSPACE_ID_REDACTED").replace(UUID_ANYWHERE_RE, "UUID_REDACTED").slice(0, HOST_DETAIL_MAX);
}

function reportQuarantineOnce(kind: "invalid_seed_id", memoKey: string, message: string): void {
  if (quarantineMemo.has(memoKey)) return;
  if (quarantineMemo.size >= MEMO_MAX) quarantineMemo.clear();
  quarantineMemo.add(memoKey);
  // Deliberately no id, no hash of the id in the payload: the memo key stays process-local.
  reportSilentFallback(null, {
    feature: CRON_NAME,
    op: REDRIVE_OP,
    tags: { quarantine: kind },
    message,
    extra: { fn: CRON_NAME },
  });
}

/** Strict ISO-8601 instant (Date.parse alone accepts '1', 'Jan 1' and other non-ISO strings). */
const ISO_INSTANT_RE =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,3})?(?:Z|[+-](\d{2}):(\d{2}))$/;
/** The ledger refuses anything older (migration 182): reject early, with the rest of the batch. */
const SEED_EARLIEST_MS = Date.parse("2020-01-01T00:00:00Z");

/**
 * Parse a strict-ISO instant, rejecting calendar impossibilities that Date.parse silently rolls FORWARD
 * (2026-02-31 -> 03-03, T24:00:00Z -> next day): a rolled date understates the Art. 12(3) age, the unsafe
 * direction for the field this guard protects. Returns NaN for anything that is not a real instant.
 */
function parseStrictInstant(raw: string): number {
  const m = ISO_INSTANT_RE.exec(raw);
  if (!m) return NaN;
  const [y, mo, d, h, mi, sec] = m.slice(1, 7).map(Number);
  const offH = m[7] === undefined ? 0 : Number(m[7]);
  const offM = m[8] === undefined ? 0 : Number(m[8]);
  if (h > 23 || mi > 59 || sec > 59 || offH > 23 || offM > 59) return NaN;
  const probe = new Date(Date.UTC(y, mo - 1, d));
  if (probe.getUTCFullYear() !== y || probe.getUTCMonth() !== mo - 1 || probe.getUTCDate() !== d) return NaN;
  return Date.parse(raw);
}

/**
 * Validate a manual seed request. Ids need a strict-ISO `requested_at` between 2020-01-01 and now (the
 * original request time); without one NOTHING is seeded, because a defaulted now() would restart the
 * Art. 12(3) clock.
 */
export function parseSeedRequest(
  rawIds: unknown,
  rawRequestedAt: unknown,
  nowMs: number = Date.now(),
): { ids: string[]; requestedAt: Date | null; rejected: number } {
  if (rawIds === undefined) return { ids: [], requestedAt: null, rejected: 0 };
  if (!Array.isArray(rawIds) || rawIds.length > MAX_SEED_IDS) {
    return { ids: [], requestedAt: null, rejected: Array.isArray(rawIds) ? rawIds.length : 1 };
  }
  const ids = new Set<string>();
  let rejected = 0;
  for (const v of rawIds) {
    if (isUuid(v)) ids.add(v.toLowerCase());
    else rejected += 1;
  }
  const ms = typeof rawRequestedAt === "string" ? parseStrictInstant(rawRequestedAt) : NaN;
  if (!Number.isFinite(ms) || ms > nowMs || ms < SEED_EARLIEST_MS) {
    return { ids: [], requestedAt: null, rejected: rejected + ids.size };
  }
  return { ids: [...ids], requestedAt: new Date(ms), rejected };
}

// =============================================================================
// Handler
// =============================================================================

export interface RedriveResult {
  /** False when any stage failed (seed, claim, owner check, resolve, record, age read). Read by the run-log middleware. */
  ok: boolean;
  /** Names the failed stages only (never an id or a row value). */
  errorSummary?: string;
  claimed: number;
  erased: number;
  pending: number;
  ownerPresent: number;
  seeded: number;
  rejectedIds: number;
  oldestPendingAgeSeconds: number;
}

/** Distinct scrubbed host details / exit codes kept for the no_erasure_progress warn. */
const HOST_DETAILS_MAX = 3;

export async function cronGitDataErasureRedriveHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<RedriveResult> {
  const failedStages = new Set<string>();
  let seededLive = 0; // seeded ids whose owner still exists: never claimed, never ledgered

  // Step 1 (manual event only): seed swept ids into the ledger. Returns counts only.
  let seeded = 0;
  let rejectedIds = 0;
  const data = event?.data;
  if (data && "ids" in data) {
    const seedResult = await step.run("seed-ids", async () => {
      const { ids, requestedAt, rejected } = parseSeedRequest(data.ids, data.requested_at);
      if (rejected > 0) {
        reportQuarantineOnce(
          "invalid_seed_id",
          `seed:${shortHash(JSON.stringify(data.ids ?? null))}`,
          "manual git-data erasure seed rejected ids that are not UUIDs, or lacked a valid past requested_at (or an oversized/malformed list)",
        );
      }
      let ok = 0;
      let live = 0;
      let failed = 0;
      if (requestedAt) {
        let service: Rpc | null = null;
        try {
          service = await getService();
        } catch (err) {
          failed = Math.max(ids.length, 1); // setup failure: counted, reported, and the claim loop still runs
          reportStageFailure("seed", "creating the service client to seed git-data erasure ids failed", err);
        }
        if (service) {
          for (const id of ids) {
            try {
              if (!(await gitDataErasureOwnerGone(service, id))) {
                live += 1; // a live account: never ledgered, so never erased
                continue;
              }
              await recordGitDataErasurePending(service, id, "seeded", requestedAt);
              ok += 1;
            } catch (err) {
              failed += 1;
              reportStageFailure("seed", "seeding a git-data erasure id into the ledger failed", err);
            }
          }
        }
      }
      return { seeded: ok, rejected, live, failed };
    });
    seeded = seedResult.seeded;
    rejectedIds = seedResult.rejected;
    seededLive = seedResult.live;
    if (seedResult.failed > 0) failedStages.add("seed");
  }

  // Step 2..N: one step per row; the row is claimed (and its id kept) inside the step.
  let claimed = 0;
  let erased = 0;
  let pending = 0;
  let claimedOwnerPresent = 0; // claimed rows whose owner still exists
  let driven = 0; // claimed rows the host wrapper actually answered for (erased or not)
  const byStatus: Record<string, number> = {};
  const hostDetails = new Set<string>();
  const exitCodes = new Set<number>();
  for (let i = 0; i < CLAIM_LIMIT; i += 1) {
    const res = await step.run(`redrive-${i}`, async (): Promise<RowResult> => {
      let service: Rpc;
      let id: string;
      let seededRow = false;
      try {
        service = await getService();
        const { data: rows, error } = await service.rpc("claim_git_data_erasure_pending", {
          p_limit: 1,
          p_min_interval: CLAIM_MIN_INTERVAL,
        });
        if (error) throw new Error(error.message);
        const first = Array.isArray(rows) ? (rows as ClaimedRow[])[0] : undefined;
        if (!first) return { status: "empty", detail: "empty" };
        id = first.workspace_id;
        seededRow = first.last_outcome === "seeded";
      } catch (err) {
        reportStageFailure("claim", "claiming a pending git-data erasure failed", err);
        return { status: "claim_failed", detail: "claim_failed" };
      }

      // The ledger is not proof the account is gone: ask the database before touching the host.
      try {
        if (!(await gitDataErasureOwnerGone(service, id))) {
          return { status: "owner_present", detail: "owner_present" };
        }
      } catch (err) {
        reportStageFailure(
          "owner-check",
          "checking whether a pending git-data erasure's owner is gone failed; treated as not gone",
          err,
        );
        return { status: "owner_check_failed", detail: "owner_check_failed" };
      }

      let word: GitDataErasureLedgerOutcome | null = null;
      let detail = "";
      let hostDetail: string | undefined;
      let exitCode: number | undefined;
      try {
        const outcome = await removeGitDataRepo(id);
        detail = outcome.status;
        if (outcome.status === "erased") {
          try {
            const { data: bucket, error } = await service.rpc("resolve_git_data_erasure_pending", { p_workspace_id: id });
            if (error) throw new Error(error.message);
            // NULL = no row existed (already resolved by a racing run): the host still confirmed the erasure.
            return { status: "erased", detail: bucket == null ? "already_resolved" : detail };
          } catch (err) {
            reportStageFailure(
              "resolve",
              "the host confirmed a git-data erasure but resolving the ledger row failed; it stays and is retried",
              err,
            );
            return { status: "resolve_failed", detail: "resolve_failed" };
          }
        }
        if (outcome.status === UNCONFIGURED_STATUS) {
          // The reason word only: the free text after it is not guaranteed scrubbed.
          detail = `unconfigured:${unconfiguredReason(outcome.detail)}`;
        } else if (outcome.status !== "skipped") {
          hostDetail = scrubHostDetail(outcome.detail, id);
          if ("exitCode" in outcome) exitCode = outcome.exitCode; // only the host's own refusal carries one
        }
        if (LEDGER_STATUS.has(outcome.status)) word = outcome.status as GitDataErasureLedgerOutcome;
        // `skipped` is not confirmation and has no ledger word: the row stays untouched.
      } catch (err) {
        word = "threw";
        // Only the error NAME: assertSafeWorkspaceId's message embeds the raw id.
        detail = `threw:${err instanceof Error ? err.name : typeof err}`;
      }
      // A row the claim returned as 'seeded' keeps that provenance: refreshing last_outcome would make
      // git_data_erasure_owner_gone skip the workspace_members check for an operator-supplied id.
      if (word && !seededRow) {
        try {
          await recordGitDataErasurePending(service, id, word);
        } catch (err) {
          reportStageFailure("record", "refreshing last_outcome on a pending git-data erasure row failed", err);
          return { status: "record_failed", detail, hostDetail, exitCode };
        }
      }
      return { status: "pending", detail, hostDetail, exitCode };
    });

    if (res.status === "empty") break;
    if (res.status === "claim_failed") {
      failedStages.add("claim");
      break;
    }
    claimed += 1;
    byStatus[res.detail] = (byStatus[res.detail] ?? 0) + 1;
    if (res.status === "erased") {
      erased += 1;
      driven += 1;
    } else if (res.status === "owner_present") claimedOwnerPresent += 1;
    else {
      pending += 1;
      // Driven but not confirmed. A resolve failure is NOT counted: the host DID confirm (the ledger write
      // failed, a different fault with its own stage=resolve event), and an owner-check failure never reached it.
      if (res.status === "pending" || res.status === "record_failed") {
        driven += 1;
        if (res.hostDetail && hostDetails.size < HOST_DETAILS_MAX) hostDetails.add(res.hostDetail);
        if (res.exitCode !== undefined && exitCodes.size < HOST_DETAILS_MAX) exitCodes.add(res.exitCode);
      }
      if (res.status === "resolve_failed") failedStages.add("resolve");
      else if (res.status === "record_failed") failedStages.add("record");
      else if (res.status === "owner_check_failed") failedStages.add("owner-check");
    }
  }

  // Fleet-level warns FIRST, in their own step: a failing age read must not suppress them.
  const ownerPresent = claimedOwnerPresent + seededLive;
  await step.run("fleet-warns", async () => {
    if (ownerPresent > 0) {
      warnSilentFallback(null, {
        feature: CRON_NAME,
        op: REDRIVE_OP,
        tags: { reason: "owner_still_exists" },
        message:
          "pending git-data erasure rows (or seeded ids) belong to accounts that still exist; nothing was erased — an aborted deletion or a wrong seeded id",
        extra: { fn: CRON_NAME, ownerPresent },
      });
    }
    // Fleet-wide refusal, visible long before day 20: rows were driven at the host and none erased.
    // `driven` counts claimed rows only: a seeded live id (never claimed) must not hide this signal.
    // Throttled like the other tiers: a freeze or rotate window refuses everything for hours.
    if (driven > 0 && erased === 0) {
      const nowMs = Date.now();
      if (nowMs - lastEscalationAt.noprogress >= ESCALATION_REPEAT_MS) {
        lastEscalationAt.noprogress = nowMs;
        warnSilentFallback(null, {
          feature: CRON_NAME,
          op: REDRIVE_OP,
          tags: { reason: "no_erasure_progress" },
          message: "git-data erasure re-drive attempted rows and the host confirmed none; check the host, the REMOVE key and the pin",
          extra: {
            fn: CRON_NAME,
            driven,
            byStatus,
            // id-scrubbed host detail (<= 3 distinct) and exit codes: which refusal, not just that one happened
            hostDetails: [...hostDetails],
            exitCodes: [...exitCodes],
          },
        });
      }
    }
  });

  // Gauge the oldest pending age (split by owner) and escalate. Never deletes anything. Only rows whose
  // owner is GONE can escalate to "erase by hand".
  const ages = await step.run("age-gauge", async (): Promise<{ gone: number; live: number } | null> => {
    let gone = 0;
    let live = 0;
    try {
      const service = await getService();
      const { data: ageData, error } = await service.rpc("git_data_erasure_pending_ages");
      if (error) throw new Error(error.message);
      const row = (Array.isArray(ageData) ? ageData[0] : ageData) as
        | { oldest_gone_seconds?: unknown; oldest_live_seconds?: unknown }
        | null
        | undefined;
      gone = Number(row?.oldest_gone_seconds ?? 0) || 0;
      live = Number(row?.oldest_live_seconds ?? 0) || 0;
    } catch (err) {
      reportStageFailure("age-gauge", "reading the oldest pending git-data erasure ages failed", err);
      return null;
    }
    // An idle run (nothing claimed, empty ledger) is the steady state: the monitor's check-in is its heartbeat.
    if (claimed > 0 || gone > 0 || live > 0) {
      infoSilentFallback(null, {
        feature: CRON_NAME,
        op: REDRIVE_OP,
        message: "git-data erasure re-drive run complete",
        extra: {
          fn: CRON_NAME,
          claimed,
          erased,
          pending,
          ownerPresent,
          driven,
          byStatus,
          oldestPendingAgeSeconds: gone,
          oldestLiveOwnerAgeSeconds: live,
        },
      });
    }
    const nowMs = Date.now();
    // An aborted deletion (owner still exists) is NOT erasable: a separate, differently worded warn.
    if (live >= LIVE_OWNER_WARN_AFTER_SECONDS && nowMs - lastEscalationAt.live >= ESCALATION_REPEAT_MS) {
      lastEscalationAt.live = nowMs;
      warnSilentFallback(null, {
        feature: CRON_NAME,
        op: REDRIVE_OP,
        tags: { reason: "live_owner_aged" },
        message:
          "deletion aborted? a pending git-data erasure row has an owner that still exists — do NOT erase; check why the account deletion did not finish",
        extra: { fn: CRON_NAME, oldestLiveOwnerAgeSeconds: live },
      });
    }
    const tier: "28d" | "20d" | null =
      gone >= HARD_STOP_AFTER_SECONDS ? "28d" : gone >= ESCALATE_AFTER_SECONDS ? "20d" : null;
    if (tier && nowMs - lastEscalationAt[tier] >= ESCALATION_REPEAT_MS) {
      lastEscalationAt[tier] = nowMs;
      reportSilentFallback(null, {
        feature: CRON_NAME,
        op: REDRIVE_OP,
        tags: { escalation: tier },
        message:
          tier === "28d"
            ? "a git-data erasure whose owner is gone has been pending for 28 days or more — the Art. 12(3) one-month limit can be only 28 days away; confirm git_data_erasure_owner_gone first, then erase by hand now (routed by the git-data-erasure-redrive-escalation Sentry alert once applied, #10914)"
            : "a git-data erasure whose owner is gone has been pending for 20 days or more — ahead of the Art. 12(3) one-month limit; confirm git_data_erasure_owner_gone first, then find out why the host refuses (routed by the git-data-erasure-redrive-escalation Sentry alert once applied, #10914)",
        extra: { fn: CRON_NAME, oldestPendingAgeSeconds: gone },
      });
    }
    return { gone, live };
  });
  if (ages === null) failedStages.add("age-gauge");

  // Heartbeat: ok = the run completed its bookkeeping. A host refusal is the ledger's normal state, but a
  // failed claim / resolve / record / owner check / age read means rows are NOT being driven or settled.
  const healthy = failedStages.size === 0;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: healthy,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: CRON_NAME,
      logger,
    });
  });

  return {
    ok: healthy,
    ...(healthy ? {} : { errorSummary: `failed stages: ${[...failedStages].join(", ")}` }),
    claimed,
    erased,
    pending,
    ownerPresent,
    seeded,
    rejectedIds,
    oldestPendingAgeSeconds: ages?.gone ?? 0,
  };
}

// =============================================================================
// Registration
// =============================================================================

export const cronGitDataErasureRedrive = inngest.createFunction(
  {
    id: CRON_NAME,
    concurrency: [
      { scope: "fn", limit: 1 },
      // Dedicated account lane (the lane key is the fn id itself), as cron-approval-expiry and
      // cron-bot-pr-reaper do: the shared `"cron-platform"` lane is held for 50-70 minutes by claude-eval,
      // which would delay this 15-minute re-drive past the 30-minute check-in margin of its Sentry monitor
      // and page it as a false "cron dead".
      { scope: "account", key: '"cron-git-data-erasure-redrive"', limit: 1 },
    ],
    retries: 1,
    triggers: [
      // Every 15 minutes. (Cron literal kept out of the header comment: a star-slash inside a
      // block comment would close it.)
      { cron: "*/15 * * * *" },
      // Manual run; may carry `data.ids` (UUIDs) plus `data.requested_at` to seed ids swept from a
      // freeze/rotate window.
      { event: "cron/git-data-erasure-redrive.manual-trigger" },
    ],
  },
  cronGitDataErasureRedriveHandler as unknown as Parameters<typeof inngest.createFunction>[1],
);
