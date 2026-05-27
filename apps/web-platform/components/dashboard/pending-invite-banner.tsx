"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

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
        router.push("/dashboard/settings/team");
        router.refresh();
      }
    } catch {
      // silent — banner is supplementary
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
      }
    } catch {
      // silent
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="flex items-center justify-between border-b border-[#2563eb]/20 bg-[#2563eb]/5 px-4 py-3">
      <div className="flex items-center gap-2 text-sm text-soleur-text-primary">
        <svg className="h-4 w-4 text-[#2563eb]" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" />
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
          className="rounded-md bg-[#2563eb] px-3 py-1.5 text-xs font-medium text-white hover:bg-[#1d4ed8] disabled:opacity-50"
        >
          {loading === "accept" ? "..." : "Accept"}
        </button>
        <button
          onClick={handleDecline}
          disabled={loading !== null}
          className="rounded-md border border-[#2A2A2A] px-3 py-1.5 text-xs font-medium text-[#9a9a9a] hover:text-white disabled:opacity-50"
        >
          {loading === "decline" ? "..." : "Decline"}
        </button>
        <button
          onClick={() => setDismissed(true)}
          aria-label="Dismiss"
          className="ml-1 text-[#9a9a9a] hover:text-white"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18 18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    </div>
  );
}
