"use client";

import { useState } from "react";
import { InviteMemberModal } from "@/components/settings/invite-member-modal";

// Small client wrapper that pairs the "+ Invite member" trigger with the
// modal — separated from the server-rendered page so the page itself stays
// async + RSC-clean.
//
// RBAC: inviting a member is an owner-only action (the invite-member API route
// 403s a non-owner). Hide the trigger from Members so the UI matches the server
// boundary, mirroring the isOwner gating in PendingInvitesList / DelegationToggle.
export function InviteMemberAction({
  workspaceId,
  isOwner,
  organizationId,
  organizationName,
}: {
  workspaceId: string;
  isOwner: boolean;
  organizationId?: string;
  organizationName?: string | null;
}) {
  const [open, setOpen] = useState(false);
  if (!isOwner) return null;
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="rounded-md bg-soleur-accent-gold-fg px-4 py-2 text-sm font-medium text-soleur-bg-surface-1 hover:opacity-90"
      >
        + Invite member
      </button>
      <InviteMemberModal
        open={open}
        workspaceId={workspaceId}
        organizationId={organizationId}
        organizationName={organizationName}
        onClose={() => setOpen(false)}
      />
    </>
  );
}
