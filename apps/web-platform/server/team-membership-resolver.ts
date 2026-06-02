import { isTeamWorkspaceInviteEnabled, isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveCurrentOrganizationId, resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import { userHasEffectiveByokKey } from "@/server/byok-resolver";
import { reportSilentFallback } from "@/server/observability";

// Server-only resolver for the /dashboard/settings/team membership page.
// Factored out of the page component so AC-A's flag-OFF → notFound() behavior
// is unit-testable without spinning up a Next.js render harness.

export interface TeamMembershipRow {
  userId: string;
  email: string;
  role: "owner" | "member";
  addedAt: string; // membership.created_at
  isSelf: boolean;
  /**
   * #4715: whether THIS member has their own effective BYOK key (own valid key
   * OR accepted delegation), via userHasEffectiveByokKey (own-key signal only).
   * Drives the owner "Share a key" prompt — shown for a keyless, undelegated
   * member. Fail-closed (false) on resolver error so the prompt surfaces rather
   * than hiding a genuinely keyless member.
   */
  hasEffectiveKey: boolean;
  delegationFromMe?: {
    id: string;
    dailyCapCents: number;
    todaySpentCents: number;
    active: boolean;
  };
  delegationToMe?: {
    id: string;
    grantorDisplayName: string;
    dailyCapCents: number;
    todaySpentCents: number;
  };
}

export interface TeamMembershipPageData {
  organizationId: string;
  organizationName: string | null;
  workspaceId: string;
  currentUserId: string;
  members: TeamMembershipRow[];
  byokDelegationsEnabled: boolean;
}

export type TeamMembershipPageResult =
  | { ok: true; data: TeamMembershipPageData }
  | { ok: false; reason: "not-found" | "no-org" | "no-membership" };

// Minimal structural shapes — we don't pull SupabaseClient<Database> generics
// across the resolver boundary; the page passes the real client at runtime
// and the test passes mocked thenables (same shape as workspace-resolver.ts).
interface AuthClient {
  auth: {
    getUser: () => Promise<{
      data: { user: { id: string; app_metadata?: Record<string, unknown> } | null };
      error: unknown;
    }>;
  };
}

interface ServiceClient {
  from: (table: string) => unknown;
}

interface MembershipRow {
  workspace_id: string;
  user_id: string;
  role: "owner" | "member";
  created_at: string;
}

interface UserRow {
  id: string;
  email: string | null;
}

export async function resolveTeamMembershipPageData(
  supabase: AuthClient,
  service: ServiceClient,
): Promise<TeamMembershipPageResult> {
  const userResp = await supabase.auth.getUser();
  const user = userResp.data?.user;
  if (!user) return { ok: false, reason: "not-found" };

  const orgId = await resolveCurrentOrganizationId(user.id, service);
  if (!orgId) return { ok: false, reason: "no-org" };

  const orgNameResp = await (service.from("organizations") as {
    select: (cols: string) => {
      eq: (col: string, val: string) => {
        single: () => Promise<{ data: { name: string | null } | null; error: unknown }>;
      };
    };
  }).select("name").eq("id", orgId).single();
  const organizationName: string | null = orgNameResp.data?.name ?? null;

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isTeamWorkspaceInviteEnabled(orgId, identity))) {
    return { ok: false, reason: "not-found" };
  }

  // Resolve the membership rows for the current org. We query through service
  // role because the page needs every member's email, and email lives on
  // auth.users which the RLS-bound anon client can't read for peers.
  const membershipChain = service.from("workspace_members") as {
    select: (cols: string) => {
      eq: (col: string, val: string) => {
        order: (
          col: string,
          opts?: { ascending?: boolean },
        ) => Promise<{ data: MembershipRow[] | null; error: unknown }>;
      };
    };
  };

  // ADR-044 active-workspace convergence. #4767 applied this member-side; this
  // applies it owner-side. The page MUST read delegations from — and pass to the
  // grant POST body — the SAME workspace the member consumes from: the canonical
  // current_workspace_id. The legacy unordered `workspaces.organization_id=orgId
  // [0]` was a third, order-dependent resolution mechanism (neither
  // getDefaultWorkspaceForUser nor resolveCurrentWorkspaceId). For a >1-workspace
  // org it could pick a workspace different from the one the grant was written
  // to, so the persisted toggle state was invisible on reload (symptom 1) and
  // grants landed where the member never read them (symptom 2).
  let workspaceId = await resolveCurrentWorkspaceId(user.id, service);

  // J5 self-heal parity (mirrors resolveActiveWorkspaceKbRoot): a non-solo claim
  // the caller is no longer a member of must fall back to the caller's OWN solo
  // workspace (user.id) — never a sibling tenant's workspace (preserves the
  // #4767 cross-tenant invariant). Read-only; no corrective write on a page read.
  if (workspaceId !== user.id) {
    const probe = service.from("workspace_members") as {
      select: (cols: string) => {
        eq: (col: string, val: string) => {
          eq: (col: string, val: string) => {
            maybeSingle: () => Promise<{ data: { user_id: string } | null; error: unknown }>;
          };
        };
      };
    };
    const membership = await probe
      .select("user_id")
      .eq("workspace_id", workspaceId)
      .eq("user_id", user.id)
      .maybeSingle();
    // A transient probe error must page (cq-silent-fallback-must-mirror-to-sentry,
    // matching resolveActiveWorkspaceKbRoot's membership probe) — but it still
    // fails CLOSED to solo, never the sibling. A clean `!membership.data` is the
    // legitimate non-member case (no mirror).
    if (membership.error) {
      reportSilentFallback(membership.error, {
        feature: "team-membership-resolver",
        op: "resolveTeamMembershipPageData.workspace-claim-membership-probe",
        extra: { userId: user.id, claimedWorkspaceId: workspaceId },
      });
    }
    if (membership.error || !membership.data) {
      workspaceId = user.id; // never the sibling
    }
  }

  const membersResp = await membershipChain
    .select("workspace_id, user_id, role, created_at")
    .eq("workspace_id", workspaceId)
    .order("created_at", { ascending: true });
  if (membersResp.error || !membersResp.data) {
    return { ok: false, reason: "no-membership" };
  }
  const rows = membersResp.data;
  if (rows.length === 0) {
    return { ok: false, reason: "no-membership" };
  }

  const userIds = rows.map((r) => r.user_id);
  const usersChain = service.from("users") as {
    select: (cols: string) => {
      in: (
        col: string,
        vals: string[],
      ) => Promise<{ data: UserRow[] | null; error: unknown }>;
    };
  };
  const usersResp = await usersChain.select("id, email").in("id", userIds);
  const emailByUserId = new Map<string, string>();
  for (const row of usersResp.data ?? []) {
    if (row.email) emailByUserId.set(row.id, row.email);
  }

  const byokEnabled = await isByokDelegationsEnabled(orgId, identity);

  let delegationsByGrantor = new Map<string, { id: string; grantee_user_id: string; daily_cap_cents: number }>();
  let delegationsByGrantee = new Map<string, { id: string; grantor_user_id: string; daily_cap_cents: number }>();

  if (byokEnabled) {
    const delegChain = service.from("byok_delegations") as {
      select: (cols: string) => {
        eq: (col: string, val: string) => {
          is: (col: string, val: null) => Promise<{ data: Array<{ id: string; grantor_user_id: string; grantee_user_id: string; daily_cap_cents: number }> | null; error: unknown }>;
        };
      };
    };
    const delegResp = await delegChain
      .select("id, grantor_user_id, grantee_user_id, daily_cap_cents")
      .eq("workspace_id", workspaceId)
      .is("revoked_at", null);
    for (const d of delegResp.data ?? []) {
      delegationsByGrantor.set(`${d.grantor_user_id}:${d.grantee_user_id}`, d);
      delegationsByGrantee.set(d.grantee_user_id, d);
    }
  }

  // #4715: per-member own-key status. N round-trips is fine for v1's tiny
  // member lists (batch only if lists grow). userHasEffectiveByokKey is the
  // own-key signal ONLY — Phase 9's `!delegationFromMe` already owns the
  // delegation term, so we do NOT OR delegationsByGrantee here (avoids the
  // own-default-workspace-context nuance). NEVER read api_keys directly
  // (2026-05-29-byok-delegation-aware-onboarding-gating).
  const effectiveKeyByUserId = new Map<string, boolean>();
  await Promise.all(
    rows.map(async (r) => {
      effectiveKeyByUserId.set(
        r.user_id,
        await userHasEffectiveByokKey(r.user_id, { onErrorReturn: false }),
      );
    }),
  );

  const members: TeamMembershipRow[] = rows.map((r) => {
    const row: TeamMembershipRow = {
      userId: r.user_id,
      email: emailByUserId.get(r.user_id) ?? "",
      role: r.role,
      addedAt: r.created_at,
      isSelf: r.user_id === user.id,
      hasEffectiveKey: effectiveKeyByUserId.get(r.user_id) ?? false,
    };

    if (byokEnabled) {
      const fromMe = delegationsByGrantor.get(`${user.id}:${r.user_id}`);
      if (fromMe) {
        row.delegationFromMe = {
          id: fromMe.id,
          dailyCapCents: fromMe.daily_cap_cents,
          todaySpentCents: 0,
          active: true,
        };
      }
      const toMe = r.user_id === user.id ? delegationsByGrantee.get(user.id) : undefined;
      if (toMe) {
        const grantorEmail = emailByUserId.get(toMe.grantor_user_id) ?? "Unknown";
        row.delegationToMe = {
          id: toMe.id,
          grantorDisplayName: grantorEmail.split("@")[0],
          dailyCapCents: toMe.daily_cap_cents,
          todaySpentCents: 0,
        };
      }
    }

    return row;
  });

  return {
    ok: true,
    data: {
      organizationId: orgId,
      organizationName,
      workspaceId,
      currentUserId: user.id,
      members,
      byokDelegationsEnabled: byokEnabled,
    },
  };
}
