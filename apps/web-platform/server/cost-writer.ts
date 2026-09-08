// Shared per-turn cost writer used by both the legacy agent-runner.ts
// path and the cc-soleur-go dispatcher path. Centralizes the four
// side-effects that close the "API Usage" undercount loop:
//
//   1. Atomically increment `conversations.{total_cost_usd,
//      input_tokens, output_tokens, cache_read_input_tokens,
//      cache_creation_input_tokens}` via the v2 RPC.
//   2a. Solo path — append a forensic row to `audit_byok_use` via the
//      existing `write_byok_audit` RPC (migration 037).
//   2b. BYOK Delegations PR-A (#4232) — when `delegationId` is set,
//      route the audit through the merged atomic RPC
//      `check_and_record_byok_delegation_use` (migration 064, converted
//      to a return-status contract by migration 137) which performs
//      grace + consent + expired + hourly + daily checks under a single
//      FOR UPDATE row lock and INSERTs the audit row on EVERY outcome.
//   3. Fan out a `usage_update` WS event to the client (widened with
//      cache tokens).
//   4. Mirror all silent fallbacks to Sentry per
//      `cq-silent-fallback-must-mirror-to-sentry`.
//
// Fire-and-forget: turn termination must not block on DB writes. Per the
// plan's R3, the v2 RPC preserves the atomic UPDATE pattern from
// migration 017, so concurrent multi-leader turns remain race-safe.
import { randomUUID } from "node:crypto";

import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback, mirrorP0Deduped } from "@/server/observability";
import { sendToClient } from "@/server/ws-handler";
import { createChildLogger } from "@/server/logger";
import {
  emitClaudeCostMarker,
  type ClaudeCostSource,
} from "@/server/claude-cost-marker";
import {
  type ByokDelegationError,
  ByokDelegationRevokedError,
  ByokDelegationConsentWithdrawnError,
  ByokDelegationExpiredError,
  ByokDelegationHourlyCapError,
  ByokDelegationDailyCapError,
  ByokDelegationCrossTenantError,
} from "./byok-resolver";

const log = createChildLogger("cost-writer");

let _supabase: ReturnType<typeof createServiceClient> | null = null;
function supabase() {
  return (_supabase ??= createServiceClient());
}

// ─── Delegated-turn refusal contract (migration 137, #7829) ─────────────
//
// `check_and_record_byok_delegation_use` signals a refusal by RETURNING a
// reason, never by raising one. Refusal had to stop being an exception
// because an unhandled plpgsql RAISE aborts its own transaction and discards
// the `audit_byok_use` row the branch inserted immediately before it — which
// is why NO refusal has ever been ledgered, including the three branches that
// visibly INSERT first. `refusal_reason === null` means the turn was admitted
// and the grantor-attributed row was written.
//
// This union IS the contract. Coupling a TS error hierarchy to a plpgsql
// RAISE message substring was the leaky abstraction underneath the bug: the
// refusal had no typed carrier, so its only carrier was an exception, and the
// exception is what destroyed the row.
//
// Underscored literals — these are the `audit_byok_use.attribution_shift_reason`
// column values, NOT the hyphenated Sentry `op` slugs. Migration 064
// establishes that only `cross-tenant` is hyphenated; do not harmonise the two
// vocabularies (mig 137 §1).
type ByokRefusalReason =
  | "revoked_post_grace"
  | "consent_withdrawn"
  | "expired"
  | "hourly_cap_exceeded"
  | "daily_cap_exceeded";

/**
 * Refusal reason → the ADR-040 D10 error class and the Sentry `op` slug. The
 * `op` values are the hyphenated slugs the `byok_cap_exceeded` issue-alert rule
 * filters on (`apps/web-platform/infra/sentry/issue-alerts.tf`) — they are
 * deliberately NOT the underscored SQL literals.
 */
const REFUSAL_DISPATCH: Record<
  ByokRefusalReason,
  { op: string; error: (delegationId: string) => ByokDelegationError }
> = {
  revoked_post_grace: {
    op: "revoke-past-grace",
    error: (id) => new ByokDelegationRevokedError(id),
  },
  consent_withdrawn: {
    op: "consent-withdrawn",
    error: (id) => new ByokDelegationConsentWithdrawnError(id),
  },
  expired: {
    op: "expired",
    error: (id) => new ByokDelegationExpiredError(id),
  },
  hourly_cap_exceeded: {
    op: "hourly-cap-exceeded",
    error: (id) => new ByokDelegationHourlyCapError(id),
  },
  daily_cap_exceeded: {
    op: "daily-cap-exceeded",
    error: (id) => new ByokDelegationDailyCapError(id),
  },
};

/**
 * The RPC's reply, classified. `admitted` is established POSITIVELY — it is
 * never the fallback for a shape we failed to parse.
 *
 * MEASURED, not assumed (2026-09-07, supabase-js 2.99.2, dev PostgREST, both
 * modes, via a throwaway function of the identical return signature):
 *
 *     refused  -> [{"refusal_reason":"hourly_cap_exceeded"}]
 *     admitted -> [{"refusal_reason":null}]
 *
 * Both are a ONE-ELEMENT ARRAY. An earlier revision also accepted a bare
 * scalar and a bare object, which was dead code AND asymmetric: it took a bare
 * `"reason"` as a refusal while taking a bare `null` as unreadable. Non-array
 * replies are now rejected symmetrically, because a bare `null` on the data arm
 * cannot be distinguished from "the RPC returned nothing" — that is a broken
 * contract, not an admission.
 *
 * Anything unrecognised is `unreadable`, never `admitted`: reading an unparsed
 * shape as "the turn was fine" would silence every refusal on this path, which
 * is precisely the silent-ledger failure #7829 exists to remove. Fail CLOSED.
 *
 * NOTE ON ROUTING, so this comment does not overstate itself: failing closed
 * RECORDS, it does not page. `unreadable-refusal-shape` matches no rule in
 * issue-alerts.tf, and the two cap slugs that do match route through
 * `issue_owners` with `fallthrough_type = "NoOne"` on a project with no
 * ownership rule — i.e. nobody. That routing question is #7829's other half and
 * is deliberately untouched here (see the standing note in issue-alerts.tf).
 */
export type RefusalRead =
  | { kind: "admitted" }
  | { kind: "refused"; reason: string }
  | { kind: "unreadable"; detail: string };

function readCell(cell: unknown): RefusalRead {
  // An explicit SQL NULL in the one column IS the admitted signal.
  if (cell === null) return { kind: "admitted" };
  if (typeof cell === "string") return { kind: "refused", reason: cell };
  if (typeof cell === "object" && "refusal_reason" in cell) {
    const value = (cell as { refusal_reason: unknown }).refusal_reason;
    if (value === null) return { kind: "admitted" };
    if (typeof value === "string") return { kind: "refused", reason: value };
    return { kind: "unreadable", detail: `refusal_reason is ${typeof value}` };
  }
  // Column NAMES only — never values. The one event whose whole job is "the
  // wire shape changed" is useless if it does not say what the shape was.
  const keys =
    cell && typeof cell === "object" ? Object.keys(cell).slice(0, 5).join(",") : "";
  return { kind: "unreadable", detail: `row is ${typeof cell}${keys ? ` keys=[${keys}]` : ""}` };
}

export function readRefusalReason(data: unknown): RefusalRead {
  // The function returns exactly one row on every path, so "no row at all"
  // is a broken contract, not an admission.
  if (data === undefined) return { kind: "unreadable", detail: "data is undefined" };
  if (Array.isArray(data)) {
    if (data.length !== 1) {
      return { kind: "unreadable", detail: `expected 1 row, got ${data.length}` };
    }
    return readCell(data[0]);
  }
  return {
    kind: "unreadable",
    detail: `expected a one-element array, got ${data === null ? "null" : typeof data}`,
  };
}

/**
 * Did the refusal actually persist its ledger row?
 *
 * The highest-probability post-merge failure mode is "137 applies but writes no
 * row" — invisible without this read-back, because the Sentry event derives
 * from the refusal, which fires whether or not the INSERT survived.
 *
 * THIS IS A DIAGNOSTIC AND MUST NEVER GATE THE REPORT IT ANNOTATES. An earlier
 * revision wrote `tags: { ledger_row_written: await ledgerRowWrittenTag(...) }`,
 * which evaluates the await BEFORE reportSilentFallback runs — sequencing the
 * mandatory signal behind an optional, untimed round-trip whose failure modes
 * are CORRELATED with it (a database that just failed to write the row is the
 * one that will not answer the read-back). On a degraded database the breach
 * was then never reported at all: #7829's silent failure, relocated into the
 * reporting path. Callers now emit first and annotate second.
 *
 * Never throws, and never blocks for long: bounded so a stalled connection
 * cannot hold a fire-and-forget path open past a rollout.
 */
async function ledgerRowWrittenTag(
  invocationId: string,
  ctx: { conversationId: string; userId: string; delegationId: string },
): Promise<string> {
  try {
    const { data, error } = await supabase()
      .from("audit_byok_use")
      .select("invocation_id")
      .eq("invocation_id", invocationId)
      .abortSignal(AbortSignal.timeout(LEDGER_READBACK_TIMEOUT_MS))
      .maybeSingle();
    if (error) {
      // "unknown" alone is a dead end: it cannot distinguish a 42501 grant
      // regression from a timeout from a shape change. Carry the cause.
      log.error({ err: error, ...ctx }, "byok ledger read-back failed");
      return "unknown";
    }
    return data ? "true" : "false";
  } catch (err) {
    log.error({ err, ...ctx }, "byok ledger read-back threw");
    return "unknown";
  }
}

/**
 * Emit the ledger-verdict annotation as its OWN event, after the mandatory one.
 * Fire-and-forget by construction: a caller cannot accidentally await it back
 * into the gating position that C1 removed.
 */
function annotateLedger(
  op: string,
  invocationId: string,
  ctx: { conversationId: string; userId: string; delegationId: string },
  extra: Record<string, unknown>,
): void {
  void ledgerRowWrittenTag(invocationId, ctx).then((tag) => {
    // CONSIDERED AND REJECTED (#7914 ship consult): suppressing the `true`
    // verdict to keep a routine outcome out of the error stream. It does not
    // apply here. `annotateLedger` is reached ONLY from a refusal branch — a
    // cap breach or a revoked/expired/withdrawn delegation — so the verdict
    // annotates an event that is already exceptional; it is not one-per-turn
    // and cannot bury anything. Emitting on every outcome also keeps the
    // positive confirmation robust under Sentry sampling, where inferring
    // health from the ABSENCE of a sibling event is not: a dropped `false`
    // event would read as a healthy ledger. That inversion is the failure this
    // whole PR exists to remove, so the verdict is stated, never inferred.
    reportSilentFallback(new Error(`byok ledger verdict for ${op}: ${tag}`), {
      feature: "byok-delegations",
      op: `${op}.ledger`,
      tags: { ledger_row_written: tag },
      extra,
    });
  });
}

/** Bounded so a stalled read-back cannot outlive the turn it annotates. */
const LEDGER_READBACK_TIMEOUT_MS = 2_000;

// SDK exposes nullable cache fields per
// `node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:69-70`.
// Coerce with `?? 0` at this boundary so DB writes never see NULL on a
// NOT NULL column. `input_tokens` is the SDK's uncached-input count —
// the "true" total input (matching the Anthropic Console headline) is
// `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
// (R8 mitigation; see plan §Risks).
export interface UsageDeltas {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens: number;
  cache_creation_input_tokens: number;
}

export interface TurnCostInput {
  totalCostUsd: number;
  usage: UsageDeltas;
}

/**
 * Persist a single turn's cost + usage deltas. Called from both
 * `agent-runner.ts` (legacy single-leader path) and `cc-dispatcher.ts`
 * `onResult` (cc-soleur-go path). Fire-and-forget: the function awaits
 * nothing the caller cares about; failures land in Sentry via
 * `reportSilentFallback`.
 *
 * Phase 3 (feat-team-workspace-multi-user) — `workspaceId` is the
 * `audit_byok_use.workspace_id` value (NOT NULL after migration 059).
 * Threads through `write_byok_audit`'s 6-arg signature (migration 061).
 *
 * @param userId         Authenticated founder UUID (BYOK key owner).
 * @param conversationId Conversation UUID the turn belongs to.
 * @param leaderId       Domain leader id (cc-soleur-go uses the router
 *                       leader; legacy uses the per-message leader).
 * @param workspaceId    Workspace UUID for cost attribution. Sourced from
 *                       `lease.workspaceContextUserId` under the N2
 *                       invariant; future non-solo callers resolve via
 *                       `workspace-resolver.getDefaultWorkspaceForUser`.
 * @param input          Cost + usage payload from the SDK result message.
 */
/**
 * BYOK Delegations PR-A (#4232). Optional delegation context. When
 * `delegationId` is set, the audit RPC routes to the merged atomic
 * `check_and_record_byok_delegation_use` (mig 064) which enforces
 * caps under a row lock + writes the audit row with attribution
 * shift on post-grace/expired paths. `callerUserId` is the actual
 * lease consumer (grantee under delegation, self under solo); see
 * the SS F3 invariant comment in `byok-resolver.ts`.
 */
export interface ByokDelegationContext {
  delegationId: string;
  callerUserId: string;
}

// Attribution marker context threaded from the 3 session call sites
// (`agent-runner`, `cc-dispatcher`, `agent-on-spawn-requested`; plan R2/R6).
// `TurnCostInput` carries neither `source` nor `model`, so we widen the
// signature rather than mutate the cost payload (hr-type-widening-cross-
// consumer-grep).
export interface TurnCostMarker {
  source: ClaudeCostSource;
  model: string | null;
}

export function persistTurnCost(
  userId: string,
  conversationId: string,
  leaderId: string,
  workspaceId: string,
  input: TurnCostInput,
  marker: TurnCostMarker,
  delegation?: ByokDelegationContext,
): void {
  const costDelta = Number.isFinite(input.totalCostUsd) ? input.totalCostUsd : 0;
  const usage = input.usage;

  // Side-effect #5 (plan Phase 1): emit the queryable cost marker. Synchronous,
  // BEFORE the fire-and-forget RPCs (does not change turn timing). Fail-open —
  // `emitClaudeCostMarker` never throws.
  emitClaudeCostMarker({
    source: marker.source,
    model: marker.model,
    input_tokens: usage.input_tokens,
    output_tokens: usage.output_tokens,
    cache_read_input_tokens: usage.cache_read_input_tokens,
    cache_creation_input_tokens: usage.cache_creation_input_tokens,
    cost_usd: costDelta,
    id: conversationId,
    capture_status: "ok",
  });

  // (1) Atomic increment via v2 RPC (5 deltas).
  supabase()
    .rpc("increment_conversation_cost", {
      conv_id: conversationId,
      cost_delta: costDelta,
      input_delta: usage.input_tokens,
      output_delta: usage.output_tokens,
      cache_read_delta: usage.cache_read_input_tokens,
      cache_creation_delta: usage.cache_creation_input_tokens,
    })
    .then(({ error }) => {
      if (error) {
        log.error(
          { err: error, conversationId },
          "Failed to increment conversation cost",
        );
        reportSilentFallback(error, {
          feature: "agent-cost-tracking",
          op: "increment",
          extra: {
            conversationId,
            costDelta,
            inputDelta: usage.input_tokens,
            outputDelta: usage.output_tokens,
            cacheReadDelta: usage.cache_read_input_tokens,
            cacheCreationDelta: usage.cache_creation_input_tokens,
          },
        });
      }
    });

  // (2) Forensic audit row. WORM trigger raises on UPDATE/DELETE, so
  //     plain INSERT semantics. Sub-cent precision is lost intentionally
  //     — the cent-precision surface stays on
  //     `conversations.total_cost_usd`.
  //
  //     CORRECTION (#7829): the claim below is INERT on this path.
  //     `invocationId` is `randomUUID()` minted a few lines down, so the
  //     conflict target can never fire from here — an Inngest retry mints a
  //     fresh id and writes a SECOND row. Newly consequential now that refusal
  //     rows persist and both windows are deliberately unfiltered, so a retry
  //     storm inflates the window. `ON CONFLICT` dedupes only a replayed
  //     identical payload. Left for provenance: with `invocation_id` UNIQUE
  //     (mig 064Phase 0.9), the merged RPC's `ON CONFLICT
  //     (invocation_id) DO NOTHING` makes Inngest retries idempotent.
  const totalTokens =
    usage.input_tokens +
    usage.output_tokens +
    usage.cache_read_input_tokens +
    usage.cache_creation_input_tokens;
  const invocationId = randomUUID();
  const unitCostCents = Math.round(costDelta * 100);

  if (delegation) {
    // (2b) Delegated path — merged atomic RPC.
    //
    // Since migration 137 a REFUSAL IS A RETURNED VALUE, not an exception:
    // `data` carries `refusal_reason`, and every refusal branch has already
    // committed its `audit_byok_use` row (attributed to the grantee, carrying
    // `attribution_shift_reason`) inside the same FOR UPDATE lock before
    // returning. `refusal_reason === null` means the turn was admitted and the
    // grantor-attributed row was written.
    //
    // `error` is now reserved for the branches that still RAISE, and those are
    // caller bugs or anonymised state rather than accounted refusals — no
    // provider call is attributable to a delegation that does not resolve, so
    // no ledger row is owed: 22023 (null args), P0002 (delegation not found),
    // P0001 `byok_delegations:anonymised`, and 42501
    // `byok_delegations:caller_not_grantee` (the mig-137 caller identity pin).
    supabase()
      .rpc("check_and_record_byok_delegation_use", {
        p_delegation_id: delegation.delegationId,
        p_invocation_id: invocationId,
        p_token_count: totalTokens,
        p_unit_cost_cents: unitCostCents,
        // The RPC pins p_caller_user_id to the delegation's grantee (42501
        // otherwise). `resolveKeyOwnerThenLease` takes callerUserId and
        // workspaceContextUserId as SEPARATE parameters, and byok-lease.ts
        // explicitly plans for them to diverge for team workspaces — at which
        // point EVERY delegated turn 42501s and no ledger row is written. The
        // only guard today is three comments reading "invariant kept"; comments
        // do not fail CI.
        p_caller_user_id: delegation.callerUserId,
        p_agent_role: leaderId,
      })
      .then(({ data, error }) => {
        const baseExtra = {
          conversationId,
          delegationId: delegation.delegationId,
          totalTokens,
          costCents: unitCostCents,
        };

        if (!error) {
          // Admitted, or refused-and-ledgered. Read the typed discriminator.
          const read = readRefusalReason(data);
          if (read.kind === "unreadable") {
            // Fail CLOSED. We cannot tell admitted from refused, so we must
            // not assume the benign one.
            log.error(
              { conversationId, userId, delegationId: delegation.delegationId, detail: read.detail },
              "Unreadable delegation RPC reply shape — refusal reporting is not trustworthy",
            );
            reportSilentFallback(
              new Error(
                `check_and_record_byok_delegation_use returned an unreadable reply (${read.detail})`,
              ),
              {
                feature: "byok-delegations",
                op: "unreadable-refusal-shape",
                extra: baseExtra,
              },
            );
            annotateLedger("unreadable-refusal-shape", invocationId, { conversationId, userId, delegationId: delegation.delegationId }, baseExtra);
            return;
          }
          if (read.kind === "admitted") return;
          const reason = read.reason;
          const dispatch = REFUSAL_DISPATCH[reason as ByokRefusalReason];
          if (!dispatch) {
            // A migration added a refusal reason this build does not know.
            // Record LOUDLY rather than folding it into `merged-rpc-failure`,
            // which is what silently swallowed `consent_withdrawn` until
            // #7829 gave the refusals a typed contract.
            log.error(
              { conversationId, userId, delegationId: delegation.delegationId, reason },
              "Unrecognised delegation refusal_reason",
            );
            reportSilentFallback(
              new Error(
                `check_and_record_byok_delegation_use returned unrecognised refusal_reason "${reason}"`,
              ),
              {
                feature: "byok-delegations",
                op: "unknown-refusal-reason",
                extra: baseExtra,
              },
            );
            annotateLedger("unknown-refusal-reason", invocationId, { conversationId, userId, delegationId: delegation.delegationId }, baseExtra);
            return;
          }
          reportSilentFallback(dispatch.error(delegation.delegationId), {
            feature: "byok-delegations",
            op: dispatch.op,
            extra: baseExtra,
          });
          annotateLedger(dispatch.op, invocationId, { conversationId, userId, delegationId: delegation.delegationId }, baseExtra);
          return;
        }

        const message = error.message ?? "";
        if (message.includes("byok_delegations:caller_not_grantee")) {
          // 42501, added by mig 137. `founder_id` on a refusal row is now a
          // durable BILLING assertion that enters the named user's DSAR
          // export, so the RPC refuses to book one caller's refusal against
          // another's identity. Reaching here is a caller bug in
          // `byok-lease`/`byok-resolver`, not a user-visible refusal. NOTE
          // `pg_code:42501` alone does NOT discriminate this: a service_role
          // grant regression raises "permission denied for function ..." with
          // the same SQLSTATE and no marker, and lands in merged-rpc-failure.
          // The `op` slug is the discriminator; the SQLSTATE is corroboration.
          log.error(
            { err: error, conversationId, userId, delegationId: delegation.delegationId },
            "Delegation RPC rejected caller: p_caller_user_id is not the grantee",
          );
          reportSilentFallback(error, {
            feature: "byok-delegations",
            op: "caller-not-grantee",
            extra: baseExtra,
          });
        } else if (message.includes("byok_delegations:cross-tenant:")) {
          // GDPR Art. 33 breach surface: the grantee used the grantor's BYOK
          // key from outside the grantor's workspace. Route through
          // `mirrorP0Deduped` (#4656 items 2+3) — NOT `reportSilentFallback`:
          //   - FATAL severity (a cross-tenant key leak is a breach, not a
          //     degraded fallback) so it pages, not folds into noise. This is
          //     the load-bearing distinction from `reportSilentFallback`, which
          //     captures at default (error) severity with no clock anchor.
          //   - `first_seen_at` + `severity=breach_attempt` clock anchor for the
          //     Art. 33(1) 72h notification window (item 3), even when re-fires
          //     within the 1h dedup window are suppressed.
          //   - Pino mirror BEFORE the try/catch-guarded Sentry call, so a
          //     swallowed/rate-limited Sentry capture still leaves a durable
          //     stdout signal (item 2 — capture-swallow resilience).
          // The `feature` + `art33Breach` options carry the two tags the
          // `byok_art_33_breach` rule (#4364) filters on (filter_match="all"):
          // `feature=byok-delegations` AND `art_33_breach=true`. Raise string is
          // the HYPHEN form `byok_delegations:cross-tenant:` per mig 064
          // L214/220/227 (sibling reasons use underscores; only cross-tenant is
          // hyphenated in the migration).
          mirrorP0Deduped(
            new ByokDelegationCrossTenantError(delegation.delegationId),
            {
              op: "cross-tenant-violation",
              userId,
              conversationId,
              delegationId: delegation.delegationId,
              feature: "byok-delegations",
              art33Breach: true,
            },
          );
        } else {
          // LEGACY-CONTRACT SHIM. Deleting these four branches when refusal
          // became a returned value opened a real skew window: the release
          // workflow runs `migrate` BEFORE the container rollout, so for the
          // whole window the app is BEHIND the function — and after
          // 137.down.sql the app is AHEAD of it. In either state a refusal
          // arrives as a RAISE, and without this shim all five collapse into
          // `merged-rpc-failure`, so `byok_cap_exceeded`'s `op in (...)` filter
          // never matches and the cap signal simply stops existing. That is
          // strictly WORSE discrimination than before this PR, in exactly the
          // window where the fix is being verified. The skew is surfaced as a
          // first-class `rpc_contract` tag rather than left invisible.
          const legacy = (Object.keys(REFUSAL_DISPATCH) as ByokRefusalReason[]).find((r) =>
            message.includes(`byok_delegations:${r}`),
          );
          if (legacy) {
            const dispatch = REFUSAL_DISPATCH[legacy];
            log.error(
              { err: error, conversationId, userId, delegationId: delegation.delegationId, reason: legacy },
              "Delegation refusal arrived on the legacy RAISE contract (migration skew)",
            );
            reportSilentFallback(dispatch.error(delegation.delegationId), {
              feature: "byok-delegations",
              op: dispatch.op,
              tags: { rpc_contract: "raise-legacy" },
              extra: baseExtra,
            });
            return;
          }
          log.error(
            { err: error, conversationId, userId, delegationId: delegation.delegationId },
            "Failed to record delegation use",
          );
          reportSilentFallback(error, {
            feature: "byok-delegations",
            op: "merged-rpc-failure",
            extra: baseExtra,
          });
        }
      })
      // Terminate the chain explicitly. A throw in a SYNCHRONOUS `.then`
      // handler produces an unhandled rejection just as an async one does — an
      // earlier comment here justified this by the handler being async, which
      // was the wrong reason for a real requirement. Two-arg `.then` rather
      // than `.catch` because PostgrestBuilder types its `.then` as returning
      // `PromiseLike<void>`, which declares no `.catch`.
      .then(undefined, (err: unknown) => {
        log.error(
          { err, conversationId, userId, delegationId: delegation.delegationId },
          "Delegation cost-write handler threw",
        );
        reportSilentFallback(err instanceof Error ? err : new Error(String(err)), {
          feature: "byok-delegations",
          op: "delegation-cost-write-threw",
          extra: { conversationId, delegationId: delegation.delegationId },
        });
      });
  } else {
    // (2a) Solo path — existing migration-037 RPC (extended to 6 args
    // in mig 061 with p_workspace_id).
    supabase()
      .rpc("write_byok_audit", {
        p_invocation_id: invocationId,
        p_founder_id: userId,
        p_workspace_id: workspaceId,
        p_agent_role: leaderId,
        p_token_count: totalTokens,
        p_unit_cost_cents: unitCostCents,
      })
      .then(({ error }) => {
        if (error) {
          log.error(
            { err: error, conversationId, userId },
            "Failed to write byok audit row",
          );
          reportSilentFallback(error, {
            feature: "agent-cost-tracking",
            op: "audit-write",
            extra: { conversationId, totalTokens, costCents: unitCostCents },
          });
        }
      });
  }

  // (3) Fan out `usage_update` so the client cost badge reflects the
  //     just-billed turn. Widened with cache tokens so the chat-surface
  //     bubble can render the same Input semantics the dashboard does.
  sendToClient(userId, {
    type: "usage_update",
    conversationId,
    workspaceId,
    totalCostUsd: costDelta,
    inputTokens: usage.input_tokens,
    outputTokens: usage.output_tokens,
    cacheReadInputTokens: usage.cache_read_input_tokens,
    cacheCreationInputTokens: usage.cache_creation_input_tokens,
  });
}

/**
 * Awaitable variant of `persistTurnCost` for the PR-B (#4379) Anthropic-SDK
 * leader loop. Resolves AFTER both the `increment_conversation_cost` RPC and
 * the `write_byok_audit` RPC settle (success or fail). Per AC12, the loop's
 * `step.run("turn-${n}-claude", ...)` MUST await this BEFORE the step
 * returns so the next `step.run("turn-${n}-progress-write", ...)` (which
 * triggers the Supabase Realtime fanout) reads a deterministically-updated
 * `audit_byok_use` row.
 *
 * Failure mode parity with `persistTurnCost`: errors are mirrored to
 * Sentry via `reportSilentFallback` (same `feature` / `op` tags) and
 * SWALLOWED — the lease scope must close cleanly even if the cost
 * write trips a transient DB error, otherwise Inngest would retry the
 * whole leader turn and re-issue the Anthropic call.
 */
export async function persistTurnCostAwaitable(
  userId: string,
  conversationId: string,
  leaderId: string,
  workspaceId: string,
  input: TurnCostInput,
  marker: TurnCostMarker,
): Promise<void> {
  const costDelta = Number.isFinite(input.totalCostUsd) ? input.totalCostUsd : 0;
  const usage = input.usage;

  // Cost marker (plan Phase 1 / leader-loop path). Fail-open, before the RPCs.
  emitClaudeCostMarker({
    source: marker.source,
    model: marker.model,
    input_tokens: usage.input_tokens,
    output_tokens: usage.output_tokens,
    cache_read_input_tokens: usage.cache_read_input_tokens,
    cache_creation_input_tokens: usage.cache_creation_input_tokens,
    cost_usd: costDelta,
    id: conversationId,
    capture_status: "ok",
  });

  const incrementResult = supabase().rpc("increment_conversation_cost", {
    conv_id: conversationId,
    cost_delta: costDelta,
    input_delta: usage.input_tokens,
    output_delta: usage.output_tokens,
    cache_read_delta: usage.cache_read_input_tokens,
    cache_creation_delta: usage.cache_creation_input_tokens,
  });

  const totalTokens =
    usage.input_tokens +
    usage.output_tokens +
    usage.cache_read_input_tokens +
    usage.cache_creation_input_tokens;

  const auditResult = supabase().rpc("write_byok_audit", {
    p_invocation_id: randomUUID(),
    p_founder_id: userId,
    p_workspace_id: workspaceId,
    p_agent_role: leaderId,
    p_token_count: totalTokens,
    p_unit_cost_cents: Math.round(costDelta * 100),
  });

  const [incr, audit] = await Promise.all([incrementResult, auditResult]);
  if (incr.error) {
    log.error(
      { err: incr.error, conversationId },
      "Failed to increment conversation cost",
    );
    reportSilentFallback(incr.error, {
      feature: "agent-cost-tracking",
      op: "increment",
      extra: {
        conversationId,
        costDelta,
        inputDelta: usage.input_tokens,
        outputDelta: usage.output_tokens,
        cacheReadDelta: usage.cache_read_input_tokens,
        cacheCreationDelta: usage.cache_creation_input_tokens,
      },
    });
  }
  if (audit.error) {
    log.error(
      { err: audit.error, conversationId, userId },
      "Failed to write byok audit row",
    );
    reportSilentFallback(audit.error, {
      feature: "agent-cost-tracking",
      op: "audit-write",
      extra: { conversationId, totalTokens, costCents: Math.round(costDelta * 100) },
    });
  }

  sendToClient(userId, {
    type: "usage_update",
    conversationId,
    workspaceId,
    totalCostUsd: costDelta,
    inputTokens: usage.input_tokens,
    outputTokens: usage.output_tokens,
    cacheReadInputTokens: usage.cache_read_input_tokens,
    cacheCreationInputTokens: usage.cache_creation_input_tokens,
  });
}
