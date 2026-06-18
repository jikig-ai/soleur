import type { ReactNode } from "react";
import { ConversationsRailPortal } from "@/components/chat/conversations-rail-portal";
import { DelegationBanner, type DelegationBannerProps } from "@/components/chat/delegation-banner";
import { PendingInviteBanner } from "@/components/dashboard/pending-invite-banner";
import { createClient } from "@/lib/supabase/server";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveCurrentOrganizationId, resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import { resolveGranteeDelegation, resolveGranteeAcceptanceStatus } from "@/server/byok-delegation-ui-resolver";
import { getPendingInvitesForUser } from "@/server/workspace-invitations";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

export default async function ChatLayout({ children }: { children: ReactNode }) {
  let bannerProps: DelegationBannerProps | null = null;

  let pendingInvite: {
    invitationId: string;
    inviterName: string;
    workspaceName: string;
  } | null = null;

  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      // Start the pending-invites fetch immediately — it depends only on
      // `user`, not on orgId/the delegation chain. Letting it overlap the
      // sequential delegation resolution below removes a serial round-trip
      // from chat TTFB (audit H3) instead of awaiting it after the branch.
      const invitesPromise = getPendingInvitesForUser(user.id, user.email ?? "");

      const orgId = await resolveCurrentOrganizationId(user.id, supabase);
      if (orgId) {
        const identity: Identity = { userId: user.id, role: "prd", orgId };
        if (await isByokDelegationsEnabled(orgId, identity)) {
          // The grantee's delegation lives in the ACTIVE (shared) workspace the
          // owner granted into — NOT their oldest/solo workspace. Resolve the
          // current workspace (ADR-044) so an invited member with a pre-existing
          // solo account sees their chat delegation banner (#4767). Fails closed
          // to the caller's own solo workspace on error, never a sibling.
          const workspaceId = await resolveCurrentWorkspaceId(user.id, supabase);
          const delegation = await resolveGranteeDelegation(user.id, workspaceId, orgId, identity);
          if (delegation) {
            const acceptance = await resolveGranteeAcceptanceStatus(user.id, delegation.id);
            bannerProps = {
              grantorDisplayName: delegation.grantorDisplayName,
              todaySpentCents: delegation.todaySpentCents,
              dailyCapCents: delegation.dailyCapCents,
              hourlyCapCents: delegation.hourlyCapCents,
              delegationId: delegation.id,
              sideLetterVersion: BYOK_SIDE_LETTER_VERSION,
              alreadyAccepted: acceptance.accepted,
              withdrawn: acceptance.withdrawn,
            };
          }
        }
      }

      const invites = await invitesPromise; // already in-flight; no added latency
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
      {/* The conversations rail now lives in the single nav rail's secondary
          slot (ADR-047) — portaled there from this segment so the rail swaps
          to it on /dashboard/chat. The old sibling <aside> is deleted; only
          the async delegation/invite banner resolution above stays here. */}
      <ConversationsRailPortal />
      <div className="flex min-w-0 flex-1 flex-col">
        {pendingInvite && <PendingInviteBanner {...pendingInvite} />}
        {bannerProps && <DelegationBanner {...bannerProps} />}
        <main className="min-w-0 flex-1">{children}</main>
      </div>
    </div>
  );
}
