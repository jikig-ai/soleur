import { createClient } from "@/lib/supabase/server";
import { SettingsShell } from "@/components/settings/settings-shell";
import { isTeamWorkspaceInviteEnabled, type Identity } from "@/lib/feature-flags/server";
import { getCurrentOrganizationId } from "@/server/workspace-resolver";

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

  // JWT custom-claim (migration 060). Synchronous; no DB call.
  const session = { user: { id: user.id, app_metadata: user.app_metadata } };
  const orgId = getCurrentOrganizationId(session);
  if (!orgId) return null;

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isTeamWorkspaceInviteEnabled(orgId, identity))) return null;
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
