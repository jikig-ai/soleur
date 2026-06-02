import { createServiceClient } from "@/lib/supabase/service";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

export interface GrantorDelegation {
  id: string;
  granteeUserId: string;
  granteeDisplayName: string;
  dailyCapCents: number;
  hourlyCapCents: number | null;
  todaySpentCents: number;
  mtdSpentCents: number;
  capRemainingCents: number;
  lastInvocationAt: string | null;
  active: boolean;
  createdAt: string;
}

export interface GranteeDelegation {
  id: string;
  grantorDisplayName: string;
  dailyCapCents: number;
  hourlyCapCents: number | null;
  todaySpentCents: number;
  capRemainingCents: number;
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

  const { data: delegations, error } = await service
    .from("byok_delegations")
    // Real columns are *_usd_cap_cents (migration 064:82,86); alias to the short
    // keys the GrantorDelegation shape uses. The bare names 42703 at runtime.
    .select("id, grantee_user_id, daily_cap_cents:daily_usd_cap_cents, hourly_cap_cents:hourly_usd_cap_cents, created_at, revoked_at")
    .eq("grantor_user_id", userId)
    .eq("workspace_id", workspaceId)
    .is("revoked_at", null)
    .order("created_at", { ascending: true });

  if (error || !delegations || delegations.length === 0) return [];

  const granteeIds = delegations.map((d: { grantee_user_id: string }) => d.grantee_user_id);
  const { data: users } = await service
    .from("users")
    .select("id, email")
    .in("id", granteeIds);

  const emailById = new Map<string, string>();
  for (const u of users ?? []) {
    if (u.email) emailById.set(u.id, u.email.split("@")[0]);
  }

  const now = new Date();
  const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

  const delegationIds = delegations.map((d: { id: string }) => d.id);
  const { data: auditRows } = await service
    .from("audit_byok_use")
    .select("delegation_id, cost_cents, ts")
    .in("delegation_id", delegationIds)
    .gte("ts", monthStart);

  const todaySpend = new Map<string, number>();
  const mtdSpend = new Map<string, number>();
  const lastInvocation = new Map<string, string>();
  for (const row of auditRows ?? []) {
    const did = row.delegation_id as string;
    const cents = (row.cost_cents as number) ?? 0;
    mtdSpend.set(did, (mtdSpend.get(did) ?? 0) + cents);
    if (row.ts >= twentyFourHoursAgo) {
      todaySpend.set(did, (todaySpend.get(did) ?? 0) + cents);
    }
    const prev = lastInvocation.get(did);
    if (!prev || row.ts > prev) lastInvocation.set(did, row.ts as string);
  }

  return delegations.map((d: { id: string; grantee_user_id: string; daily_cap_cents: number; hourly_cap_cents: number | null; created_at: string }) => {
    const today = todaySpend.get(d.id) ?? 0;
    return {
      id: d.id,
      granteeUserId: d.grantee_user_id,
      granteeDisplayName: emailById.get(d.grantee_user_id) ?? "Unknown",
      dailyCapCents: d.daily_cap_cents,
      hourlyCapCents: d.hourly_cap_cents,
      todaySpentCents: today,
      mtdSpentCents: mtdSpend.get(d.id) ?? 0,
      capRemainingCents: Math.max(0, d.daily_cap_cents - today),
      lastInvocationAt: lastInvocation.get(d.id) ?? null,
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

  const { data: delegation, error } = await service
    .from("byok_delegations")
    // Real columns are *_usd_cap_cents (migration 064:82,86); alias to the short
    // keys the GranteeDelegation shape uses. The bare names 42703 at runtime.
    .select("id, grantor_user_id, daily_cap_cents:daily_usd_cap_cents, hourly_cap_cents:hourly_usd_cap_cents")
    .eq("grantee_user_id", userId)
    .eq("workspace_id", workspaceId)
    .is("revoked_at", null)
    .maybeSingle();

  if (error || !delegation) return null;

  const { data: grantor } = await service
    .from("users")
    .select("email")
    .eq("id", delegation.grantor_user_id as string)
    .single();

  const grantorName = grantor?.email
    ? (grantor.email as string).split("@")[0]
    : "Unknown";

  const now = new Date();
  const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();

  const { data: auditRows } = await service
    .from("audit_byok_use")
    .select("cost_cents, ts")
    .eq("delegation_id", delegation.id as string)
    .gte("ts", twentyFourHoursAgo);

  let todaySpent = 0;
  let lastTs: string | null = null;
  for (const row of auditRows ?? []) {
    todaySpent += (row.cost_cents as number) ?? 0;
    if (!lastTs || (row.ts as string) > lastTs) lastTs = row.ts as string;
  }

  return {
    id: delegation.id as string,
    grantorDisplayName: grantorName,
    dailyCapCents: delegation.daily_cap_cents as number,
    hourlyCapCents: delegation.hourly_cap_cents as number | null,
    todaySpentCents: todaySpent,
    capRemainingCents: Math.max(0, (delegation.daily_cap_cents as number) - todaySpent),
    lastInvocationAt: lastTs,
    active: true,
  };
}

export async function resolveGranteeAcceptanceStatus(
  userId: string,
  delegationId: string,
): Promise<AcceptanceStatus> {
  const service = createServiceClient();

  const { data } = await service
    .from("byok_delegation_acceptances")
    .select("accepted_at, side_letter_version")
    .eq("user_id", userId)
    .eq("delegation_id", delegationId)
    .maybeSingle();

  // Latest withdrawal for this (user, delegation), if any (Art. 7(3)).
  const { data: wRow } = await service
    .from("byok_delegation_withdrawals")
    .select("withdrawn_at")
    .eq("user_id", userId)
    .eq("delegation_id", delegationId)
    .order("withdrawn_at", { ascending: false })
    .limit(1)
    .maybeSingle();

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
