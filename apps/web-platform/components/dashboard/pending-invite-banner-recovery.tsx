"use client";

// feat-invite-accept-membership-byok (#4715), Phase 7 / spec-flow J3. The
// recovery banner for an invitee who abandoned at /invite and reached
// /dashboard with the accept RPC never called (the missing-writer-path class).
//
// The chat layout (dashboard/chat/layout.tsx) is a SERVER component and mounts
// PendingInviteBanner via a service-role getPendingInvitesForUser fetch. But
// (dashboard)/layout.tsx is "use client" and cannot run that server fetch, so
// this wrapper mirrors the NoApiKeyBanner precedent: self-fetch the
// already-existing GET /api/workspace/pending-invites and render the banner.
//
// Double-render gate: the chat layout already shows the banner, so this client
// mount renders NOTHING on /dashboard/chat routes (direction matters — the new
// mount backs off, the established server mount wins).

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { PendingInviteBanner } from "@/components/dashboard/pending-invite-banner";
import { reportSilentFallback } from "@/lib/client-observability";

interface PendingInvite {
  id: string;
  inviter_name: string;
  workspace_name: string;
}

export function PendingInviteBannerRecovery() {
  const pathname = usePathname();
  const [invite, setInvite] = useState<PendingInvite | null>(null);

  // Chat routes already mount the banner server-side — back off to avoid a
  // double render. Gate BEFORE the fetch so chat routes don't even probe.
  const onChatRoute = pathname?.startsWith("/dashboard/chat") ?? false;

  useEffect(() => {
    if (onChatRoute) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/workspace/pending-invites");
        if (!res.ok) {
          // A persistent 500 hides the recovery path from every abandoned
          // invitee — mirror it, then degrade to no banner.
          reportSilentFallback(null, {
            feature: "pending-invite-banner-recovery",
            op: "pending-invites-non-ok",
            extra: { status: res.status },
          });
          return;
        }
        const data = (await res.json()) as { invites?: PendingInvite[] };
        const first = data?.invites?.[0];
        if (!first || typeof first.id !== "string") return;
        if (!cancelled) {
          setInvite({
            id: first.id,
            inviter_name: first.inviter_name,
            workspace_name: first.workspace_name,
          });
        }
      } catch (err) {
        // Safe degradation — leave the banner hidden, mirror to Sentry so a
        // persistent failure is visible.
        reportSilentFallback(err, {
          feature: "pending-invite-banner-recovery",
          op: "pending-invites-fetch",
        });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [onChatRoute]);

  if (onChatRoute || !invite) return null;

  return (
    <PendingInviteBanner
      invitationId={invite.id}
      inviterName={invite.inviter_name}
      workspaceName={invite.workspace_name}
    />
  );
}
