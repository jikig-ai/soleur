import type { ReactNode } from "react";
import { ConversationsRail } from "@/components/chat/conversations-rail";
import { DelegationBanner } from "@/components/chat/delegation-banner";
import { PendingInviteBanner } from "@/components/dashboard/pending-invite-banner";
import { createClient } from "@/lib/supabase/server";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveCurrentOrganizationId } from "@/server/workspace-resolver";
import { resolveGranteeDelegation, resolveGranteeAcceptanceStatus } from "@/server/byok-delegation-ui-resolver";
import { getPendingInvitesForUser } from "@/server/workspace-invitations";

export default async function ChatLayout({ children }: { children: ReactNode }) {
  let bannerProps: {
    grantorDisplayName: string;
    todaySpentCents: number;
    dailyCapCents: number;
    pending: boolean;
  } | null = null;

  let pendingInvite: {
    invitationId: string;
    inviterName: string;
    workspaceName: string;
  } | null = null;

  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      const orgId = await resolveCurrentOrganizationId(user.id, supabase);
      if (orgId) {
        const identity: Identity = { userId: user.id, role: "prd", orgId };
        if (await isByokDelegationsEnabled(orgId, identity)) {
          const workspaceId = user.id;
          const delegation = await resolveGranteeDelegation(user.id, workspaceId, orgId, identity);
          if (delegation) {
            const acceptance = await resolveGranteeAcceptanceStatus(user.id, delegation.id);
            bannerProps = {
              grantorDisplayName: delegation.grantorDisplayName,
              todaySpentCents: delegation.todaySpentCents,
              dailyCapCents: delegation.dailyCapCents,
              pending: !acceptance.accepted,
            };
          }
        }
      }

      const invites = await getPendingInvitesForUser(user.id, user.email ?? "");
      if (invites.length > 0) {
        pendingInvite = {
          invitationId: invites[0].id,
          inviterName: invites[0].inviter_name,
          workspaceName: invites[0].workspace_name,
        };
      }
    }
  } catch {
    // Flag off or resolver error — no banner
  }

  return (
    <div className="flex h-full min-h-0 flex-1">
      <aside
        data-testid="conversations-rail"
        className="hidden md:block md:w-72 md:shrink-0 md:border-r md:border-soleur-border-default md:bg-soleur-bg-base"
      >
        <ConversationsRail />
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        {pendingInvite && <PendingInviteBanner {...pendingInvite} />}
        {bannerProps && <DelegationBanner {...bannerProps} />}
        <main className="min-w-0 flex-1">{children}</main>
      </div>
    </div>
  );
}
