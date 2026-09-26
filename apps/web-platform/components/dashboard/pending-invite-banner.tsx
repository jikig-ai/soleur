"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
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
  // feat-ui-action-feedback: a pending episode must terminate into success or
  // a visible, announced error — Sentry-only reporting left the founder with
  // a silent dead click.
  const [actionError, setActionError] = useState<string | null>(null);

  if (dismissed) return null;

  async function handleAccept() {
    setLoading("accept");
    setActionError(null);
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
        // Redirect latch (brief §3.6): the hard nav owns teardown — never
        // re-enable the buttons in the gap before the document loads.
        return;
      }
      reportSilentFallback(
        new Error(`accept-invite returned ${res.status}`),
        { feature: "workspace-invitations", op: "accept" },
      );
      setActionError(`Couldn't accept the invite (${res.status}) — try again.`);
    } catch (err) {
      reportSilentFallback(err, {
        feature: "workspace-invitations",
        op: "accept",
      });
      setActionError("Couldn't accept the invite — network error. Try again.");
    } finally {
      setLoading(null);
    }
  }

  async function handleDecline() {
    setLoading("decline");
    setActionError(null);
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
        setActionError(`Couldn't decline the invite (${res.status}) — try again.`);
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "workspace-invitations",
        op: "decline",
      });
      setActionError("Couldn't decline the invite — network error. Try again.");
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="flex flex-wrap items-center justify-between border-b border-soleur-accent-gold-fg/20 bg-soleur-accent-gold-fill/10 px-4 py-3">
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
        <Button
          variant="gold"
          type="button"
          onClick={handleAccept}
          disabled={loading !== null}
          loading={loading === "accept"}
          loadingLabel="Accept"
          className="text-xs"
        >
          Accept
        </Button>
        <Button
          variant="outlined"
          type="button"
          onClick={handleDecline}
          disabled={loading !== null}
          loading={loading === "decline"}
          loadingLabel="Decline"
          className="text-xs text-soleur-text-secondary hover:text-soleur-text-primary"
        >
          Decline
        </Button>
        <Button
          variant="ghost"
          type="button"
          onClick={() => setDismissed(true)}
          aria-label="Dismiss"
          className="ml-1 hover:text-soleur-text-primary"
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
        </Button>
      </div>
      {actionError ? (
        <p role="alert" className="basis-full pt-1 text-xs text-red-400">
          {actionError}
        </p>
      ) : null}
    </div>
  );
}
