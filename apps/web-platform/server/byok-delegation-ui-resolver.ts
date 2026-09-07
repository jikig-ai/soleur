import { createServiceClient } from "@/lib/supabase/service";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { reportSilentFallback } from "@/server/observability";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

// Sentry `feature` tag shared by every mirrored read in this module — the same
// value `server/cost-writer.ts` and `app/api/workspace/delegations/route.ts`
// emit, so the BYOK-delegation surface aggregates as one feature. `op` names
// the exact read; `pg_code` (promoted by reportSilentFallback from the
// PostgrestError) then discriminates 42703 (undefined_column — the #7829
// column-drift class) from 42501 (insufficient_privilege — an RLS/grant
// regression). Neither is inferable from the message alone.
const FEATURE = "byok-delegations";

/**
 * The cost of one `audit_byok_use` row, in cents.
 *
 * DERIVED FROM THE ENFORCING RPC, not from a column rename. Both cap windows in
 * `public.check_and_record_byok_delegation_use`
 * (`084_byok_delegation_withdrawals.sql`, at `INTO v_hourly_spent` and
 * `INTO v_daily_spent`) are
 *
 *     COALESCE(SUM(au.token_count * au.unit_cost_cents), 0)::int
 *
 * and the per-turn increment is `v_this_cost int := p_token_count *
 * p_unit_cost_cents`. The grantor's pane therefore sums the SAME product. The
 * table has never had a `cost_cents` column (`037_audit_byok_use.sql` declares
 * `token_count` and `unit_cost_cents`; 059 added `workspace_id`, 064
 * `delegation_id` + `attribution_shift_reason`), so the previous select 42703'd
 * on every read — but swapping `cost_cents` for a bare `unit_cost_cents` would
 * have replaced a permanent $0.00 with a figure that disagrees with the cap
 * that actually refuses the turn.
 *
 * KNOWN, SEPARATE DEFECT — #7920. `server/cost-writer.ts` puts the WHOLE TURN's
 * cost into `unit_cost_cents` (`Math.round(costDelta * 100)`), so this product
 * over-counts by a factor of `token_count`. That is deliberately NOT corrected
 * here: the three cap SUMs (084 hourly, 084 daily, 121 founder) multiply the
 * same way, and correcting only the display side would desynchronise the pane
 * from the live cap — a new lie in place of the old one. When #7920 is settled,
 * this expression and those SUMs move together.
 */
function rowCostCents(row: { token_count: number; unit_cost_cents: number }): number {
  return row.token_count * row.unit_cost_cents;
}

/** Rows the spend windows read. `ts`, `token_count`, `unit_cost_cents` are all NOT NULL (037). */
interface AuditSpendRow {
  delegation_id?: string;
  token_count: number;
  unit_cost_cents: number;
  ts: string;
}

export interface GrantorDelegation {
  id: string;
  granteeUserId: string;
  granteeDisplayName: string;
  dailyCapCents: number;
  hourlyCapCents: number | null;
  /**
   * Rolling-24h spend, matching the RPC's daily window. `null` = DEGRADED: the
   * `audit_byok_use` read failed and the figure is unknown. Never render `null`
   * as `$0.00` — on a billing surface a confident zero is worse than an honest
   * "unavailable" (that conflation is exactly what #7829 shipped).
   */
  todaySpentCents: number | null;
  /** Month-to-date spend, or `null` when the spend read failed. */
  mtdSpentCents: number | null;
  /** `dailyCapCents - todaySpentCents`, floored at 0; `null` when unknown. */
  capRemainingCents: number | null;
  lastInvocationAt: string | null;
  active: boolean;
  createdAt: string;
}

export interface GranteeDelegation {
  id: string;
  grantorDisplayName: string;
  dailyCapCents: number;
  hourlyCapCents: number | null;
  /** Rolling-24h spend; `null` = DEGRADED (see `GrantorDelegation.todaySpentCents`). */
  todaySpentCents: number | null;
  /** `dailyCapCents - todaySpentCents`, floored at 0; `null` when unknown. */
  capRemainingCents: number | null;
  lastInvocationAt: string | null;
  active: boolean;
}

export interface AcceptanceStatus {
  accepted: boolean;
  acceptedAt: string | null;
  sideLetterVersion: string | null;
  /** The canonical server-owned version. A `sideLetterVersion` that differs
   * is stale and fails CLOSED at the SQL lease gate (#4625). */
  currentVersion: string;
  /** True when a consent withdrawal post-dates the latest acceptance
   * (Art. 7(3)). Non-terminal: a later re-acceptance clears it. */
  withdrawn: boolean;
  withdrawnAt: string | null;
}

export async function resolveGrantorDelegations(
  userId: string,
  workspaceId: string,
  orgId: string,
  identity: Identity,
): Promise<GrantorDelegation[]> {
  if (!(await isByokDelegationsEnabled(orgId, identity))) return [];

  const service = createServiceClient();

  const { data: delegations, error: delegationsError } = await service
    .from("byok_delegations")
    // Real columns are *_usd_cap_cents (migration 064:82,86); alias to the short
    // keys the GrantorDelegation shape uses. The bare names 42703 at runtime.
    .select("id, grantee_user_id, daily_cap_cents:daily_usd_cap_cents, hourly_cap_cents:hourly_usd_cap_cents, created_at, revoked_at")
    .eq("grantor_user_id", userId)
    .eq("workspace_id", workspaceId)
    .is("revoked_at", null)
    .order("created_at", { ascending: true });

  // A failed read is indistinguishable from "no delegations" to the caller — the
  // pane renders nothing either way — so it must be mirrored or the owner's
  // Funded pane vanishes with no signal anywhere.
  if (delegationsError) {
    reportSilentFallback(delegationsError, {
      feature: FEATURE,
      op: "resolveGrantorDelegations.delegations",
      extra: { userId, workspaceId },
    });
    return [];
  }
  if (!delegations || delegations.length === 0) return [];

  const granteeIds = delegations.map((d: { grantee_user_id: string }) => d.grantee_user_id);
  const { data: users, error: usersError } = await service
    .from("users")
    .select("id, email")
    .in("id", granteeIds);

  // Non-fatal: names fall back to "Unknown" and the spend figures stay valid.
  if (usersError) {
    reportSilentFallback(usersError, {
      feature: FEATURE,
      op: "resolveGrantorDelegations.grantee-users",
      extra: { userId, workspaceId, granteeCount: granteeIds.length },
    });
  }

  const emailById = new Map<string, string>();
  for (const u of users ?? []) {
    if (u.email) emailById.set(u.id, u.email.split("@")[0]);
  }

  const now = new Date();
  const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

  const delegationIds = delegations.map((d: { id: string }) => d.id);
  const { data: auditRows, error: auditError } = await service
    .from("audit_byok_use")
    // The two columns the cap RPC multiplies — see rowCostCents.
    .select("delegation_id, token_count, unit_cost_cents, ts")
    .in("delegation_id", delegationIds)
    .gte("ts", monthStart);

  if (auditError) {
    reportSilentFallback(auditError, {
      feature: FEATURE,
      op: "resolveGrantorDelegations.audit-spend",
      extra: { userId, workspaceId, delegationCount: delegationIds.length },
    });
  } else if (!auditRows) {
    reportSilentFallback(null, {
      feature: FEATURE,
      op: "resolveGrantorDelegations.audit-spend",
      message: "audit_byok_use spend read returned neither rows nor an error",
      extra: { userId, workspaceId, delegationCount: delegationIds.length },
    });
  }
  // Degraded when the spend is unknown. Propagated as `null` rather than 0 so
  // the pane can say "unavailable" instead of asserting the grantee spent
  // nothing and the whole cap is still free.
  const spendUnavailable = Boolean(auditError) || !auditRows;

  const todaySpend = new Map<string, number>();
  const mtdSpend = new Map<string, number>();
  const lastInvocation = new Map<string, string>();
  for (const row of (auditRows ?? []) as AuditSpendRow[]) {
    const did = row.delegation_id as string;
    const cents = rowCostCents(row);
    mtdSpend.set(did, (mtdSpend.get(did) ?? 0) + cents);
    if (row.ts >= twentyFourHoursAgo) {
      todaySpend.set(did, (todaySpend.get(did) ?? 0) + cents);
    }
    const prev = lastInvocation.get(did);
    if (!prev || row.ts > prev) lastInvocation.set(did, row.ts);
  }

  return delegations.map((d: { id: string; grantee_user_id: string; daily_cap_cents: number; hourly_cap_cents: number | null; created_at: string }) => {
    const today = spendUnavailable ? null : (todaySpend.get(d.id) ?? 0);
    return {
      id: d.id,
      granteeUserId: d.grantee_user_id,
      granteeDisplayName: emailById.get(d.grantee_user_id) ?? "Unknown",
      dailyCapCents: d.daily_cap_cents,
      hourlyCapCents: d.hourly_cap_cents,
      todaySpentCents: today,
      mtdSpentCents: spendUnavailable ? null : (mtdSpend.get(d.id) ?? 0),
      capRemainingCents: today === null ? null : Math.max(0, d.daily_cap_cents - today),
      lastInvocationAt: spendUnavailable ? null : (lastInvocation.get(d.id) ?? null),
      active: true,
      createdAt: d.created_at,
    };
  });
}

export async function resolveGranteeDelegation(
  userId: string,
  workspaceId: string,
  orgId: string,
  identity: Identity,
): Promise<GranteeDelegation | null> {
  if (!(await isByokDelegationsEnabled(orgId, identity))) return null;

  const service = createServiceClient();

  const { data: delegation, error: delegationError } = await service
    .from("byok_delegations")
    // Real columns are *_usd_cap_cents (migration 064:82,86); alias to the short
    // keys the GranteeDelegation shape uses. The bare names 42703 at runtime.
    .select("id, grantor_user_id, daily_cap_cents:daily_usd_cap_cents, hourly_cap_cents:hourly_usd_cap_cents")
    .eq("grantee_user_id", userId)
    .eq("workspace_id", workspaceId)
    .is("revoked_at", null)
    .maybeSingle();

  // A read failure hides the chat banner exactly like "no delegation" does.
  if (delegationError) {
    reportSilentFallback(delegationError, {
      feature: FEATURE,
      op: "resolveGranteeDelegation.delegation",
      extra: { userId, workspaceId },
    });
    return null;
  }
  if (!delegation) return null;

  const { data: grantor, error: grantorError } = await service
    .from("users")
    .select("email")
    .eq("id", delegation.grantor_user_id as string)
    .single();

  // Non-fatal: the banner falls back to "Unknown". Mirrored because the banner
  // naming the wrong party is itself a user-visible defect on a billing surface.
  if (grantorError) {
    reportSilentFallback(grantorError, {
      feature: FEATURE,
      op: "resolveGranteeDelegation.grantor-user",
      extra: { userId, workspaceId, delegationId: delegation.id as string },
    });
  }

  const grantorName = grantor?.email
    ? (grantor.email as string).split("@")[0]
    : "Unknown";

  const now = new Date();
  const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();

  const { data: auditRows, error: auditError } = await service
    .from("audit_byok_use")
    // The two columns the cap RPC multiplies — see rowCostCents.
    .select("token_count, unit_cost_cents, ts")
    .eq("delegation_id", delegation.id as string)
    .gte("ts", twentyFourHoursAgo);

  if (auditError) {
    reportSilentFallback(auditError, {
      feature: FEATURE,
      op: "resolveGranteeDelegation.audit-spend",
      extra: { userId, workspaceId, delegationId: delegation.id as string },
    });
  } else if (!auditRows) {
    reportSilentFallback(null, {
      feature: FEATURE,
      op: "resolveGranteeDelegation.audit-spend",
      message: "audit_byok_use spend read returned neither rows nor an error",
      extra: { userId, workspaceId, delegationId: delegation.id as string },
    });
  }
  const spendUnavailable = Boolean(auditError) || !auditRows;

  let todaySpent = 0;
  let lastTs: string | null = null;
  for (const row of (auditRows ?? []) as AuditSpendRow[]) {
    todaySpent += rowCostCents(row);
    if (!lastTs || row.ts > lastTs) lastTs = row.ts;
  }

  const dailyCapCents = delegation.daily_cap_cents as number;
  return {
    id: delegation.id as string,
    grantorDisplayName: grantorName,
    dailyCapCents,
    hourlyCapCents: delegation.hourly_cap_cents as number | null,
    todaySpentCents: spendUnavailable ? null : todaySpent,
    capRemainingCents: spendUnavailable ? null : Math.max(0, dailyCapCents - todaySpent),
    lastInvocationAt: spendUnavailable ? null : lastTs,
    active: true,
  };
}

export async function resolveGranteeAcceptanceStatus(
  userId: string,
  delegationId: string,
): Promise<AcceptanceStatus> {
  const service = createServiceClient();

  const { data, error: acceptanceError } = await service
    .from("byok_delegation_acceptances")
    .select("accepted_at, side_letter_version")
    .eq("user_id", userId)
    .eq("delegation_id", delegationId)
    .maybeSingle();

  // A failed read is returned as `accepted: false` — indistinguishable from a
  // genuine never-accepted grant, which re-prompts a member who already signed.
  if (acceptanceError) {
    reportSilentFallback(acceptanceError, {
      feature: FEATURE,
      op: "resolveGranteeAcceptanceStatus.acceptance",
      extra: { userId, delegationId },
    });
  }

  // Latest withdrawal for this (user, delegation), if any (Art. 7(3)).
  const { data: wRow, error: withdrawalError } = await service
    .from("byok_delegation_withdrawals")
    .select("withdrawn_at")
    .eq("user_id", userId)
    .eq("delegation_id", delegationId)
    .order("withdrawn_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  // A failed read is returned as `withdrawn: false` — the fail-OPEN direction on
  // an Art. 7(3) signal, so it must never be silent.
  if (withdrawalError) {
    reportSilentFallback(withdrawalError, {
      feature: FEATURE,
      op: "resolveGranteeAcceptanceStatus.withdrawal",
      extra: { userId, delegationId },
    });
  }

  const withdrawnAt = (wRow?.withdrawn_at as string | undefined) ?? null;
  const acceptedAt = (data?.accepted_at as string | undefined) ?? null;
  // Withdrawn iff a withdrawal exists that is NOT superseded by a later
  // (re-)acceptance — mirrors the version-agnostic resolver predicate
  // (no acceptance ⇒ the withdrawal stands; `>=` so a same-instant
  // withdrawal wins the tie).
  const withdrawn =
    withdrawnAt !== null && (acceptedAt === null || withdrawnAt >= acceptedAt);

  if (!data) {
    return {
      accepted: false,
      acceptedAt: null,
      sideLetterVersion: null,
      currentVersion: BYOK_SIDE_LETTER_VERSION,
      withdrawn,
      withdrawnAt,
    };
  }

  return {
    accepted: true,
    acceptedAt: data.accepted_at as string,
    sideLetterVersion: data.side_letter_version as string,
    currentVersion: BYOK_SIDE_LETTER_VERSION,
    withdrawn,
    withdrawnAt,
  };
}
