// byok-resolver.ts
// BYOK Delegations PR-A (#4232; parent #4229). The TS-layer entry point
// that resolves "whose api_keys row should this run lease?" via the
// public.resolve_byok_key_owner SECURITY DEFINER RPC, then opens a
// `runWithByokLease` scope around `fn`.
//
// Behavior:
//   - Flag OFF: direct passthrough to runWithByokLease (zero overhead).
//   - Flag ON + caller has own api_keys row: resolver returns
//     (callerUserId, NULL) — solo behavior preserved bit-for-bit.
//   - Flag ON + caller has no own key + active delegation in workspace:
//     lease scope is opened with `keyOwnerUserId = grantor` and the
//     lease carries `delegationId` so the cost-writer routes the audit
//     through `check_and_record_byok_delegation_use`.
//
// SECURITY INVARIANT (SS F3, load-bearing).
//
//   `callerUserId` MUST be derived from authenticated session/JWT
//   context, NEVER from request body/params. Passing user-controlled
//   input here would let an attacker name an arbitrary user as caller
//   and harvest delegations targeted at that user. The 5 prod call
//   sites (agent-runner.ts:882, agent-runner.ts:2401, cc-dispatcher.ts
//   :890, cfo-on-payment-failed.ts:199, github-on-event.ts:208) pass
//   `args.userId` which IS server-derived; the PR body enumerates the
//   provenance of `callerUserId` at every call site. Future call sites
//   MUST preserve this invariant.

import {
  runWithByokLease,
  type ByokLease,
} from "./byok-lease";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";
import { isByokDelegationsEnabled, ANON_IDENTITY, type Identity } from "@/lib/feature-flags/server";
import { getDefaultWorkspaceForUser } from "./workspace-resolver";
import { resolveGranteeAcceptanceStatus } from "./byok-delegation-ui-resolver";

const log = createChildLogger("byok-resolver");

// ─── Error hierarchy ──────────────────────────────────────────────────
//
// Abstract `ByokDelegationError` base so catch sites can use a single
// `instanceof` clause + the `.reason` discriminator. Five thin sibling
// classes carry the same structured fields.

export type ByokDelegationErrorReason =
  | "revoked_post_grace"
  | "expired"
  | "hourly_cap_exceeded"
  | "daily_cap_exceeded"
  | "cross_tenant";

export abstract class ByokDelegationError extends Error {
  public abstract readonly reason: ByokDelegationErrorReason;
  public readonly delegationId?: string;
  public readonly workspaceIdHash?: string;

  constructor(message: string, delegationId?: string, workspaceIdHash?: string) {
    super(message);
    this.name = "ByokDelegationError";
    this.delegationId = delegationId;
    this.workspaceIdHash = workspaceIdHash;
  }
}

export class ByokDelegationRevokedError extends ByokDelegationError {
  public readonly reason = "revoked_post_grace" as const;
  constructor(delegationId?: string, workspaceIdHash?: string) {
    super("BYOK delegation revoked past 60s grace window", delegationId, workspaceIdHash);
    this.name = "ByokDelegationRevokedError";
  }
}

export class ByokDelegationExpiredError extends ByokDelegationError {
  public readonly reason = "expired" as const;
  constructor(delegationId?: string, workspaceIdHash?: string) {
    super("BYOK delegation expired", delegationId, workspaceIdHash);
    this.name = "ByokDelegationExpiredError";
  }
}

export class ByokDelegationHourlyCapError extends ByokDelegationError {
  public readonly reason = "hourly_cap_exceeded" as const;
  constructor(delegationId?: string, workspaceIdHash?: string) {
    super("BYOK delegation hourly cap exceeded", delegationId, workspaceIdHash);
    this.name = "ByokDelegationHourlyCapError";
  }
}

export class ByokDelegationDailyCapError extends ByokDelegationError {
  public readonly reason = "daily_cap_exceeded" as const;
  constructor(delegationId?: string, workspaceIdHash?: string) {
    super("BYOK delegation daily cap exceeded", delegationId, workspaceIdHash);
    this.name = "ByokDelegationDailyCapError";
  }
}

export class ByokDelegationCrossTenantError extends ByokDelegationError {
  public readonly reason = "cross_tenant" as const;
  constructor(delegationId?: string, workspaceIdHash?: string) {
    super("BYOK delegation crosses tenant boundary (Art. 33 territory)", delegationId, workspaceIdHash);
    this.name = "ByokDelegationCrossTenantError";
  }
}

// ─── Resolver ────────────────────────────────────────────────────────

type ResolveRow = {
  key_owner_user_id: string;
  delegation_id: string | null;
};

/**
 * Resolve the BYOK key owner and run `fn` inside a freshly bound
 * `ByokLease`. See module docstring for behavior + the security
 * invariant on `callerUserId`.
 */
export async function resolveKeyOwnerThenLease<T>(
  callerUserId: string,
  workspaceContextUserId: string,
  fn: (lease: ByokLease) => Promise<T>,
): Promise<T> {
  const supabase = createServiceClient();

  let workspaceId: string;
  try {
    workspaceId = await getDefaultWorkspaceForUser(workspaceContextUserId, supabase);
  } catch (err) {
    log.warn({ err, workspaceContextUserId }, "byok-resolver: workspace lookup failed; falling back to direct lease");
    return runWithByokLease(
      { workspaceContextUserId, keyOwnerUserId: callerUserId },
      fn,
    );
  }

  const orgId = await resolveOrgIdForWorkspace(workspaceId);
  const identity: Identity = { userId: callerUserId, role: "prd", orgId };
  if (!(await isByokDelegationsEnabled(orgId, identity))) {
    return runWithByokLease(
      { workspaceContextUserId, keyOwnerUserId: callerUserId },
      fn,
    );
  }

  // Flag fully on for this org. Consult the SQL resolver.
  const { data, error } = await supabase
    .rpc("resolve_byok_key_owner", {
      p_caller_user_id: callerUserId,
      p_workspace_id: workspaceId,
    })
    .maybeSingle<ResolveRow>();

  if (error) {
    log.warn(
      { err: error, callerUserId, workspaceId },
      "byok-resolver: resolve_byok_key_owner failed; falling back to direct lease",
    );
    return runWithByokLease(
      { workspaceContextUserId, keyOwnerUserId: callerUserId },
      fn,
    );
  }

  if (!data) {
    // No own-key AND no active delegation. The lease body will raise
    // `MissingByokKeyError` when getApiKey() is invoked, which is the
    // desired fail-closed UX.
    return runWithByokLease(
      { workspaceContextUserId, keyOwnerUserId: callerUserId },
      fn,
    );
  }

  return runWithByokLease(
    {
      workspaceContextUserId,
      keyOwnerUserId: data.key_owner_user_id,
      delegationId: data.delegation_id ?? undefined,
    },
    fn,
  );
}

// ─── Effective-key gate (feat-skip-api-key-onboarding #4642) ──────────
//
// Routing/UX-only mirror of the lease's own-key-first + flag-gated-delegation
// sequence. Used by the onboarding redirect gates (callback, accept-terms)
// and the degraded-state banner endpoint. The chat-time enforcement path
// (`getUserApiKey` → KeyInvalidError) is authoritative and untouched.

/**
 * Whether `callerUserId` has a USABLE BYOK key: an own VALID anthropic key
 * OR an active, accepted delegation. Usability ≠ presence — an own *invalid*
 * key does NOT count (the chat path would still reject it, so the user must
 * keep seeing /setup-key).
 *
 * Mirrors `resolveKeyOwnerThenLease`'s sequence intentionally:
 *   1. own VALID anthropic key (matches the lease's actual success
 *      requirement — the RPC's own-key short-circuit at mig 083 is UNFILTERED,
 *      so we must filter `is_valid=true` ourselves and NOT trust a
 *      `delegation_id === null` row to mean "usable key").
 *   2. else derive the SAME default workspace the runtime uses → org → flag.
 *      Flag off → false (never broaden the gate past enforcement).
 *   3. flag on → resolve_byok_key_owner; usable ONLY when `delegation_id`
 *      is a real delegation row (own-key rows were handled in step 1).
 *
 * On any thrown/error path: Sentry-mirror and return `opts.onErrorReturn`.
 * Callers pick direction — redirect gates pass `true` (fail-open: never trap
 * a possibly-delegated user at /setup-key; chat enforcement is authoritative),
 * the status endpoint passes `false` (fail-closed: show the banner rather than
 * hide it and lie to a keyless user). Never serializes a ByokDelegationError
 * subtype — the boolean carries no workspace/delegation identifiers.
 */
export async function userHasEffectiveByokKey(
  callerUserId: string,
  opts: { onErrorReturn: boolean },
): Promise<boolean> {
  try {
    const supabase = createServiceClient();

    // 1. Own VALID anthropic key — short-circuits regardless of the flag.
    const { data: keys, error: keysError } = await supabase
      .from("api_keys")
      .select("id")
      .eq("user_id", callerUserId)
      .eq("provider", "anthropic")
      .eq("is_valid", true)
      .limit(1);
    if (keysError) throw keysError;
    if (keys && keys.length > 0) return true;

    // 2. Derive workspace → org → flag (same default workspace as the lease).
    const workspaceId = await getDefaultWorkspaceForUser(callerUserId, supabase);
    const orgId = await resolveOrgIdForWorkspace(workspaceId);
    const identity: Identity = { userId: callerUserId, role: "prd", orgId };
    if (!(await isByokDelegationsEnabled(orgId, identity))) return false;

    // 3. Resolver row — usable ONLY for a real delegation (delegation_id != null).
    const { data, error } = await supabase
      .rpc("resolve_byok_key_owner", {
        p_caller_user_id: callerUserId,
        p_workspace_id: workspaceId,
      })
      .maybeSingle<ResolveRow>();
    if (error) throw error;
    return data?.delegation_id != null;
  } catch (err) {
    reportSilentFallback(err, {
      feature: "byok-resolver",
      op: "userHasEffectiveByokKey",
    });
    return opts.onErrorReturn;
  }
}

/**
 * Whether `callerUserId` has been GRANTED a BYOK delegation they have not yet
 * accepted at the current side-letter version (or have since withdrawn). Drives
 * the degraded-banner "accept your grant" branch so a grant-holder is never
 * told to buy a separate Anthropic account when one click would unblock them.
 *
 * Fail-quiet: any error → false + Sentry mirror (the banner then falls back to
 * the generic add-key CTA, which is safe).
 */
export async function userHasPendingByokDelegation(
  callerUserId: string,
): Promise<boolean> {
  try {
    const supabase = createServiceClient();
    const workspaceId = await getDefaultWorkspaceForUser(callerUserId, supabase);
    const orgId = await resolveOrgIdForWorkspace(workspaceId);
    const identity: Identity = { userId: callerUserId, role: "prd", orgId };
    if (!(await isByokDelegationsEnabled(orgId, identity))) return false;

    const { data: delegation } = await supabase
      .from("byok_delegations")
      .select("id")
      .eq("grantee_user_id", callerUserId)
      .eq("workspace_id", workspaceId)
      .is("revoked_at", null)
      .maybeSingle<{ id: string }>();
    if (!delegation) return false;

    const status = await resolveGranteeAcceptanceStatus(callerUserId, delegation.id);
    const acceptedCurrent =
      status.accepted &&
      !status.withdrawn &&
      status.sideLetterVersion === status.currentVersion;
    return !acceptedCurrent;
  } catch (err) {
    reportSilentFallback(err, {
      feature: "byok-resolver",
      op: "userHasPendingByokDelegation",
    });
    return false;
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────


async function resolveOrgIdForWorkspace(workspaceId: string): Promise<string | null> {
  const supabase = createServiceClient();
  const { data, error } = await supabase
    .from("workspaces")
    .select("organization_id")
    .eq("id", workspaceId)
    .maybeSingle<{ organization_id: string | null }>();
  if (error || !data) return null;
  return data.organization_id ?? null;
}
