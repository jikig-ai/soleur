"use client";

import { useState } from "react";
import { InviteMemberModal } from "@/components/settings/invite-member-modal";

// Small client wrapper that pairs the "+ Invite member" trigger with the
// modal — separated from the server-rendered page so the page itself stays
// async + RSC-clean.
export function InviteMemberAction({ workspaceId }: { workspaceId: string }) {
  const [open, setOpen] = useState(false);
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
        onClose={() => setOpen(false)}
      />
    </>
  );
}
