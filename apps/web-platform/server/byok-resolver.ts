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
import { isByokDelegationsEnabled } from "@/lib/feature-flags/server";
import { getDefaultWorkspaceForUser } from "./workspace-resolver";

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
  // Phase 1 of the flag check: env-only fast path. If FLAG_BYOK_-
  // DELEGATIONS is 0/unset, skip the workspace + allowlist resolution
  // entirely. The cost-writer's solo path takes over from here.
  if (!envOnly("byok-delegations")) {
    return runWithByokLease(
      { workspaceContextUserId, keyOwnerUserId: callerUserId },
      fn,
    );
  }

  // Phase 2 of the flag check: derive workspace_id + organization_id,
  // then consult the allowlist. Failing either side is a soft fall-
  // through to the direct lease (the resolver is best-effort under the
  // flag; the lease body still fail-closes on missing key).
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
  if (!isByokDelegationsEnabled(orgId)) {
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

// ─── Helpers ──────────────────────────────────────────────────────────

// Sync env-only flag probe. Avoids importing `getFlag` from
// feature-flags/server because that path expects an EnvFlagName
// literal (here we lean on the same env var name). Keeps the fast
// path one process.env read.
function envOnly(name: "byok-delegations"): boolean {
  if (name !== "byok-delegations") return false;
  return process.env.FLAG_BYOK_DELEGATIONS === "1";
}

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
