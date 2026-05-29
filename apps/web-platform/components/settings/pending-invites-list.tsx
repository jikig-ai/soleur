"use client";

import { useState } from "react";

function timeUntilExpiry(expiresAt: string): string {
  const diff = new Date(expiresAt).getTime() - Date.now();
  if (diff <= 0) return "Expired";
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
  if (days > 0) return `Expires in ${days}d ${hours}h`;
  return `Expires in ${hours}h`;
}

type Invite = {
  id: string;
  invitee_email: string;
  role: string;
  expires_at: string;
  created_at: string;
};

export function PendingInvitesList({
  invites: initialInvites,
  workspaceId,
  isOwner,
}: {
  invites: Invite[];
  workspaceId: string;
  isOwner: boolean;
}) {
  const [invites, setInvites] = useState(initialInvites);
  // Per-row state: multiple invites can be in-flight independently, so a
  // scalar pendingId/errorId would let a second click re-enable the first
  // row's button mid-request. Key by invite id.
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());
  const [errorIds, setErrorIds] = useState<Set<string>>(new Set());

  if (invites.length === 0) return null;

  const withoutId = (s: Set<string>, id: string) => {
    const next = new Set(s);
    next.delete(id);
    return next;
  };

  async function handleCancel(invite: Invite) {
    setPendingIds((prev) => new Set(prev).add(invite.id));
    setErrorIds((prev) => withoutId(prev, invite.id));
    try {
      const res = await fetch("/api/workspace/cancel-invite", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ workspaceId, invitationId: invite.id }),
      });
      const body = (await res.json().catch(() => ({}))) as { ok?: boolean };
      // Commit removal only once the server confirms — never a silent no-op.
      if (res.ok && body?.ok === true) {
        setInvites((prev) => prev.filter((i) => i.id !== invite.id));
      } else {
        setErrorIds((prev) => new Set(prev).add(invite.id));
      }
    } catch {
      setErrorIds((prev) => new Set(prev).add(invite.id));
    } finally {
      setPendingIds((prev) => withoutId(prev, invite.id));
    }
  }

  return (
    <div className="mt-6 rounded-lg border border-soleur-border-default">
      <div className="border-b border-soleur-border-default px-6 py-4">
        <h2 className="text-base font-semibold text-soleur-text-primary">
          Pending invites
        </h2>
        <p className="mt-0.5 text-xs text-soleur-text-muted">
          {invites.length === 1
            ? "1 pending invite"
            : `${invites.length} pending invites`}
        </p>
      </div>
      <ul>
        {invites.map((invite) => (
          <li
            key={invite.id}
            className="flex items-center justify-between border-b border-soleur-border-default px-6 py-3 last:border-b-0"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-soleur-bg-surface-2 text-xs font-medium text-soleur-text-muted">
                {invite.invitee_email.charAt(0).toUpperCase()}
              </div>
              <div>
                <p className="text-sm text-soleur-text-primary">
                  {invite.invitee_email}
                </p>
                <p className="text-xs text-soleur-text-muted">
                  <span
                    className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-medium ${
                      invite.role === "owner"
                        ? "bg-[#2563eb]/10 text-[#2563eb]"
                        : "bg-soleur-bg-surface-2 text-soleur-text-muted"
                    }`}
                  >
                    {invite.role}
                  </span>
                  <span className="ml-2 text-amber-500/80">
                    {timeUntilExpiry(invite.expires_at)}
                  </span>
                </p>
                {errorIds.has(invite.id) && (
                  <p className="mt-1 text-xs text-red-500" role="alert">
                    Couldn&apos;t cancel — try again.
                  </p>
                )}
              </div>
            </div>
            {isOwner && (
              <button
                type="button"
                onClick={() => handleCancel(invite)}
                disabled={pendingIds.has(invite.id)}
                aria-label={`Cancel invite for ${invite.invitee_email}`}
                className="rounded-md border border-soleur-border-default px-3 py-1 text-xs font-medium text-soleur-text-secondary transition-colors hover:text-soleur-text-primary disabled:opacity-50"
              >
                {pendingIds.has(invite.id) ? "Cancelling…" : "Cancel"}
              </button>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
