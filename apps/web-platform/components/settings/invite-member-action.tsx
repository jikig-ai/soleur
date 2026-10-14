"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
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
      <Button
        variant="gold"
        type="button"
        onClick={() => setOpen(true)}
        className="rounded-md"
      >
        + Invite member
      </Button>
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
