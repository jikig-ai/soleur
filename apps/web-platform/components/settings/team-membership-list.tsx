"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import type { TeamMembershipRow } from "@/server/team-membership-resolver";

function formatRelative(iso: string): string {
  try {
    const then = new Date(iso).getTime();
    const now = Date.now();
    const diffMs = now - then;
    const day = 24 * 60 * 60 * 1000;
    if (diffMs < day) {
      const d = new Date(iso);
      const hh = String(d.getHours()).padStart(2, "0");
      const mm = String(d.getMinutes()).padStart(2, "0");
      return `Today, ${hh}:${mm}`;
    }
    const days = Math.floor(diffMs / day);
    if (days < 7) return `${days}d ago`;
    return new Date(iso).toLocaleDateString();
  } catch {
    return iso;
  }
}

export function TeamMembershipList({
  members,
  currentUserId,
  workspaceId,
}: {
  members: readonly TeamMembershipRow[];
  currentUserId: string;
  workspaceId: string;
}) {
  return (
    <div>
      <div className="grid grid-cols-[1fr_auto_auto_auto] items-center gap-4 border-b border-soleur-border-default px-6 py-2 text-xs font-medium uppercase tracking-wider text-soleur-text-muted">
        <span>Member</span>
        <span className="text-center">Role</span>
        <span className="text-right">Added</span>
        <span aria-hidden="true" className="w-6" />
      </div>
      {members.map((m) => (
        <MemberRow
          key={m.userId}
          member={m}
          isCurrentUser={m.userId === currentUserId}
          workspaceId={workspaceId}
        />
      ))}
    </div>
  );
}

function MemberRow({
  member,
  isCurrentUser,
  workspaceId,
}: {
  member: TeamMembershipRow;
  isCurrentUser: boolean;
  workspaceId: string;
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  // Close menu on outside click
  useEffect(() => {
    if (!menuOpen) return;
    function handleClick(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [menuOpen]);

  const handleRemove = useCallback(async () => {
    setMenuOpen(false);
    if (
      !window.confirm(
        `Remove ${member.email} from this workspace? Their in-flight agent runs will be aborted.`,
      )
    ) {
      return;
    }
    const res = await fetch("/api/workspace/remove-member", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ workspaceId, userId: member.userId }),
    });
    if (!res.ok) {
      console.error("[team-membership-list] remove failed:", res.status);
      window.alert("Failed to remove member. Please try again.");
      return;
    }
    window.location.reload();
  }, [member.email, member.userId, workspaceId]);

  // AC-FLOW4: owner cannot remove self → no kebab menu trigger rendered.
  const showActions = !isCurrentUser;

  return (
    <div className="grid grid-cols-[1fr_auto_auto_auto] items-center gap-4 border-b border-soleur-border-default px-6 py-4 last:border-b-0">
      <div className="flex items-center gap-3">
        <div className="h-9 w-9 shrink-0 rounded-full bg-soleur-bg-surface-2" aria-hidden="true" />
        <div className="min-w-0">
          <div className="truncate text-sm font-medium text-soleur-text-primary">
            {member.email.split("@")[0]}
          </div>
          <div className="truncate text-xs text-soleur-text-muted">{member.email}</div>
        </div>
      </div>
      <span
        className={
          member.role === "owner"
            ? "rounded-md border border-soleur-accent-gold-fg/40 px-2 py-0.5 text-xs font-medium text-soleur-accent-gold-fg"
            : "rounded-md border border-soleur-border-default px-2 py-0.5 text-xs font-medium text-soleur-text-secondary"
        }
      >
        {member.role === "owner" ? "Owner" : "Member"}
      </span>
      <span className="text-right text-xs text-soleur-text-muted">
        {isCurrentUser ? "— (you)" : formatRelative(member.addedAt)}
      </span>
      <div className="relative w-6" ref={menuRef}>
        {showActions && (
          <>
            <button
              type="button"
              aria-label={`Row actions for ${member.email}`}
              onClick={() => setMenuOpen((v) => !v)}
              className="flex h-6 w-6 items-center justify-center rounded text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
            >
              <span aria-hidden="true">⋯</span>
            </button>
            {menuOpen && (
              <div className="absolute right-0 top-7 z-10 w-44 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 py-1 shadow-lg">
                <button
                  type="button"
                  onClick={handleRemove}
                  className="block w-full px-3 py-2 text-left text-sm text-red-400 hover:bg-soleur-bg-surface-2"
                >
                  Remove member
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
