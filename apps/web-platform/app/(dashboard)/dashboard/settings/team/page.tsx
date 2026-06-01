import { notFound, redirect } from "next/navigation";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";
import { TeamMembershipList } from "@/components/settings/team-membership-list";
import { InviteMemberAction } from "@/components/settings/invite-member-action";
import { PendingInvitesList } from "@/components/settings/pending-invites-list";
import { RenameWorkspaceAction } from "@/components/settings/rename-workspace-action";

// AC-A: flag OFF → HTTP 404 via notFound(). Flagsmith single-control gate
// lives inside resolveTeamMembershipPageData. The "/dashboard/settings/team"
// href is not present in the client bundle when the gate is OFF because the
// layout never injects the Members tab.
export default async function TeamMembershipPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    redirect("/login");
  }

  const service = createServiceClient();
  const result = await resolveTeamMembershipPageData(supabase, service);
  if (!result.ok) {
    if (result.reason === "no-membership" || result.reason === "no-org") {
      // Integrity surface — treat as 404 for the operator's view (Sentry will
      // alarm separately via failure_modes #1).
      notFound();
    }
    notFound();
  }

  const { data } = result;
  const memberCount = data.members.length;
  const isOwner = data.members.some(
    (m) => m.userId === data.currentUserId && m.role === "owner",
  );

  const pendingInvites = await (async () => {
    const { data: rows, error } = await service
      .from("workspace_invitations")
      .select("id, invitee_email, role, expires_at, created_at")
      .eq("workspace_id", data.workspaceId)
      .is("accepted_at", null)
      .is("declined_at", null)
      .is("revoked_at", null)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false });
    if (error || !rows) return [];
    return rows;
  })();

  return (
    <div>
      <h1 className="mb-2 text-2xl font-semibold text-soleur-text-primary">Team</h1>
      <p className="mb-6 text-sm text-soleur-text-secondary">
        People who can act in this workspace. All members share the same
        workspace data, agents, and billing.
      </p>

      <RenameWorkspaceAction
        organizationId={data.organizationId}
        organizationName={data.organizationName}
        isOwner={isOwner}
      />

      <div className="rounded-lg border border-soleur-border-default">
        <div className="flex items-center justify-between border-b border-soleur-border-default px-6 py-4">
          <div>
            <h2 className="text-base font-semibold text-soleur-text-primary">Members</h2>
            <p className="mt-0.5 text-xs text-soleur-text-muted">
              {memberCount === 1 ? "1 member" : `${memberCount} members`}
            </p>
          </div>
          <InviteMemberAction
            workspaceId={data.workspaceId}
            isOwner={isOwner}
            organizationId={data.organizationId}
            organizationName={data.organizationName}
          />
        </div>

        <TeamMembershipList
          members={data.members}
          currentUserId={data.currentUserId}
          workspaceId={data.workspaceId}
          isOwner={isOwner}
          byokDelegationsEnabled={data.byokDelegationsEnabled}
          organizationName={data.organizationName}
        />
      </div>

      <PendingInvitesList
        invites={pendingInvites}
        workspaceId={data.workspaceId}
        isOwner={isOwner}
      />

      {isOwner && memberCount === 1 && pendingInvites.length === 0 && (
        <p className="mt-6 text-sm text-soleur-text-secondary">
          <span className="font-medium text-soleur-accent-gold-fg">Solo for now.</span>{" "}
          Invite a teammate to share this workspace&apos;s agents, knowledge, and billing.
        </p>
      )}
    </div>
  );
}
