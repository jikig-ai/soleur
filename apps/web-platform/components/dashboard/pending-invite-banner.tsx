"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { reportSilentFallback } from "@/lib/client-observability";

interface PendingInviteBannerProps {
  invitationId: string;
  inviterName: string;
  workspaceName: string;
}

export function PendingInviteBanner({
  invitationId,
  inviterName,
  workspaceName,
}: PendingInviteBannerProps) {
  const router = useRouter();
  const [dismissed, setDismissed] = useState(false);
  const [loading, setLoading] = useState<"accept" | "decline" | null>(null);

  if (dismissed) return null;

  async function handleAccept() {
    setLoading("accept");
    try {
      const res = await fetch("/api/workspace/accept-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ invitationId }),
      });
      if (res.ok) {
        // Hide the banner immediately AND navigate. Without setDismissed the
        // banner can re-mount before the server-side invite resolver re-fetches
        // (the SOL-49 reporter symptom: "la fenêtre … ne part pas quand on
        // accepte"). Mirrors decline's pessimistic-revert pattern below.
        setDismissed(true);
        // GAP E/workspace-switch (ADR-067 staleTimes): accept-invite calls
        // `set_current_workspace_id` server-side (accept-invite/route.ts), so
        // this crosses a workspace boundary for the same principal — the warm
        // Router Cache still holds the PREVIOUS workspace's RSC in sibling tabs.
        // HARD-nav to wipe it (a soft router.push + router.refresh only busts the
        // current route; siblings would serve prior-workspace content). Mirrors
        // the sibling accept path in invite/[token]/invite-actions.tsx and the
        // workspace switch in components/dashboard/org-switcher-container.tsx.
        window.location.assign("/dashboard/settings/team");
      } else {
        reportSilentFallback(
          new Error(`accept-invite returned ${res.status}`),
          { feature: "workspace-invitations", op: "accept" },
        );
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "workspace-invitations",
        op: "accept",
      });
    } finally {
      setLoading(null);
    }
  }

  async function handleDecline() {
    setLoading("decline");
    try {
      const res = await fetch("/api/workspace/decline-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ invitationId }),
      });
      if (res.ok) {
        setDismissed(true);
        router.refresh();
      } else {
        reportSilentFallback(
          new Error(`decline-invite returned ${res.status}`),
          { feature: "workspace-invitations", op: "decline" },
        );
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "workspace-invitations",
        op: "decline",
      });
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="flex items-center justify-between border-b border-soleur-accent-gold-fg/20 bg-soleur-accent-gold-fill/10 px-4 py-3">
      <div className="flex items-center gap-2 text-sm text-soleur-text-primary">
        <svg
          className="h-4 w-4 text-soleur-accent-gold-fg"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          strokeWidth={2}
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75"
          />
        </svg>
        <span>
          <strong>{inviterName}</strong> invited you to join{" "}
          <strong>{workspaceName}</strong>
        </span>
      </div>
      <div className="flex items-center gap-2">
        <button
          onClick={handleAccept}
          disabled={loading !== null}
          className="rounded-md bg-soleur-accent-gold-fg px-3 py-1.5 text-xs font-medium text-soleur-bg-surface-1 hover:opacity-90 disabled:opacity-50"
        >
          {loading === "accept" ? "..." : "Accept"}
        </button>
        <button
          onClick={handleDecline}
          disabled={loading !== null}
          className="rounded-md border border-soleur-border-default px-3 py-1.5 text-xs font-medium text-soleur-text-secondary hover:text-soleur-text-primary disabled:opacity-50"
        >
          {loading === "decline" ? "..." : "Decline"}
        </button>
        <button
          onClick={() => setDismissed(true)}
          aria-label="Dismiss"
          className="ml-1 text-soleur-text-muted hover:text-soleur-text-primary"
        >
          <svg
            className="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M6 18 18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>
    </div>
  );
}
