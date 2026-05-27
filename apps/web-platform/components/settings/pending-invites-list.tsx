"use client";

import { useState } from "react";
import type { PendingInvite } from "@/server/workspace-invitations";

function timeUntilExpiry(expiresAt: string): string {
  const diff = new Date(expiresAt).getTime() - Date.now();
  if (diff <= 0) return "Expired";
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
  if (days > 0) return `Expires in ${days}d ${hours}h`;
  return `Expires in ${hours}h`;
}

export function PendingInvitesList({
  invites: initialInvites,
  workspaceId,
}: {
  invites: Array<{
    id: string;
    invitee_email: string;
    role: string;
    expires_at: string;
    created_at: string;
  }>;
  workspaceId: string;
}) {
  const [invites, setInvites] = useState(initialInvites);

  if (invites.length === 0) return null;

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
              </div>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
