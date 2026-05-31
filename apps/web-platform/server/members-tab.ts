import { createClient } from "@/lib/supabase/server";
import { isTeamWorkspaceInviteEnabled, type Identity } from "@/lib/feature-flags/server";
import {
  resolveCurrentOrganizationId,
  userHasWorkspaceMembership,
} from "@/server/workspace-resolver";
import { reportSilentFallback } from "@/server/observability";

export interface SettingsTab {
  href: string;
  label: string;
}

/**
 * Server-side resolution of the Settings "Members" tab (feat-team-workspace-multi-user).
 *
 * The tab — and the dependent "Team Activity" tab — render only when an
 * authenticated user has a resolved current org AND the team-workspace-invite
 * flag evaluates ON for it. AC-A requires the Members link href
 * (`/dashboard/settings/team`) NOT appear in the client bundle when the gate is
 * closed, so the layout passes the result as a prop rather than gating
 * client-side on a runtime boolean.
 *
 * Extracted from settings/layout.tsx into a server-only module so the gate
 * composition — including the silent-failure observability branch — is unit
 * testable without dragging the layout's "use client" SettingsShell import into
 * the test (feat-fix-multi-user-feature-not-visible).
 */
export async function resolveMembersTab(): Promise<SettingsTab | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const orgId = await resolveCurrentOrganizationId(user.id, supabase);
  if (!orgId) {
    // Silent-failure guard. A user WITH workspace membership resolving a null
    // current org means the Members + Team Activity tabs vanish with no error —
    // the exact silent class behind the 2026-05-31 ops@jikigai.com report.
    // Surface it to Sentry so the next occurrence is observed, not user-reported.
    // A genuinely org-less identity (no membership) is the normal solo case and
    // stays silent. `userId` is pseudonymized at the emit boundary (Recital 26).
    if (await userHasWorkspaceMembership(user.id, supabase)) {
      reportSilentFallback(null, {
        feature: "settings-members-tab",
        op: "resolveMembersTab",
        message: "member resolved null current_organization_id; org-gated tabs hidden",
        extra: { userId: user.id },
      });
    }
    return null;
  }

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isTeamWorkspaceInviteEnabled(orgId, identity))) return null;
  return { href: "/dashboard/settings/team", label: "Members" };
}
