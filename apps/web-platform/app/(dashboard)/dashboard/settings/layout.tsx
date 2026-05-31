import { createClient } from "@/lib/supabase/server";
import { SettingsShell } from "@/components/settings/settings-shell";
import { isTeamWorkspaceInviteEnabled, type Identity } from "@/lib/feature-flags/server";
import {
  resolveCurrentOrganizationId,
  shouldShowMembersTab,
  userHasWorkspaceMembership,
} from "@/server/workspace-resolver";
import { reportSilentFallback } from "@/server/observability";

// Server-side flag evaluation. AC-A requires the "Members" link href
// (`/dashboard/settings/team`) NOT appear in the client bundle when the flag is
// OFF — so we pass `membersTab` as a prop rather than gating the link
// client-side on a runtime boolean.
async function resolveMembersTab(): Promise<{ href: string; label: string } | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const orgId = await resolveCurrentOrganizationId(user.id, supabase);
  if (!orgId) {
    // Silent-failure guard (feat-fix-multi-user-feature-not-visible). A user WITH
    // workspace membership resolving a null current org means the Members + Team
    // Activity tabs vanish with no error — the exact silent class behind the
    // 2026-05-31 ops@jikigai.com report. Surface it to Sentry so the next
    // occurrence is observed, not user-reported. A genuinely org-less identity
    // (no membership) is the normal solo case and stays silent. `userId` is
    // pseudonymized at the emit boundary (reportSilentFallback, Recital 26).
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
  const flagOn = await isTeamWorkspaceInviteEnabled(orgId, identity);
  if (!shouldShowMembersTab(orgId, flagOn)) return null;
  return { href: "/dashboard/settings/team", label: "Members" };
}

export default async function SettingsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const membersTab = await resolveMembersTab();
  const activityTab = membersTab
    ? { href: "/dashboard/settings/team-activity", label: "Team Activity" }
    : null;
  return <SettingsShell membersTab={membersTab} activityTab={activityTab}>{children}</SettingsShell>;
}
