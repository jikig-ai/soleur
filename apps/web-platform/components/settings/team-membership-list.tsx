"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import type { TeamMembershipRow } from "@/server/team-membership-resolver";
import { DelegationToggle } from "@/components/settings/delegation-toggle";
import { TransferOwnershipDialog } from "@/components/settings/transfer-ownership-dialog";
import { useIsMobile } from "@/hooks/use-is-mobile";

function formatRelative(iso: string): string {
  try {
    const then = new Date(iso);
    if (Number.isNaN(then.getTime())) return iso;
    const now = new Date();
    // Calendar-day difference, NOT a rolling 24h window. A row created
    // yesterday afternoon viewed this morning is <24h old but a DIFFERENT
    // calendar day — labelling it "Today, 14:08" reads as a future time
    // (the symptom-4 bug). Compare day-start instants in LOCAL time, matching
    // the local getHours/getMinutes used for the clock label.
    const startOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    const day = 24 * 60 * 60 * 1000;
    const dayDiff = Math.round((startOfDay(now) - startOfDay(then)) / day);
    const hh = String(then.getHours()).padStart(2, "0");
    const mm = String(then.getMinutes()).padStart(2, "0");
    if (dayDiff === 0) return `Today, ${hh}:${mm}`;
    if (dayDiff === 1) return `Yesterday, ${hh}:${mm}`;
    if (dayDiff >= 2 && dayDiff < 7) return `${dayDiff}d ago`;
    // Older, or any future-dated row (dayDiff < 0): show the absolute date
    // rather than a misleading relative label.
    return then.toLocaleDateString();
  } catch {
    return iso;
  }
}

export function TeamMembershipList({
  members,
  currentUserId,
  workspaceId,
  isOwner,
  byokDelegationsEnabled,
  organizationName,
}: {
  members: readonly TeamMembershipRow[];
  currentUserId: string;
  workspaceId: string;
  isOwner: boolean;
  byokDelegationsEnabled: boolean;
  organizationName: string | null;
}) {
  const isMobile = useIsMobile();

  // Below `md`, the CSS grid-as-table folds into one card per member (the
  // operator-approved wireframe: mobile-phase-3/02-table-card-team-membership).
  // `useIsMobile` seeds desktop-first on SSR + first client render so hydration
  // always matches the grid, then flips after mount.
  if (isMobile) {
    return (
      <div className="space-y-3 p-3">
        {members.map((m) => (
          <MemberRow
            key={m.userId}
            variant="card"
            member={m}
            isCurrentUser={m.userId === currentUserId}
            workspaceId={workspaceId}
            isOwner={isOwner}
            byokDelegationsEnabled={byokDelegationsEnabled}
            organizationName={organizationName}
          />
        ))}
      </div>
    );
  }

  return (
    <div>
      <div className={`grid ${byokDelegationsEnabled ? "grid-cols-[1fr_auto_auto_auto_auto]" : "grid-cols-[1fr_auto_auto_auto]"} items-center gap-4 border-b border-soleur-border-default px-6 py-2 text-xs font-medium uppercase tracking-wider text-soleur-text-muted`}>
        <span>Member</span>
        <span className="text-center">Role</span>
        {byokDelegationsEnabled && <span className="text-center">Funded</span>}
        <span className="text-right">Added</span>
        <span aria-hidden="true" className="w-6" />
      </div>
      {members.map((m) => (
        <MemberRow
          key={m.userId}
          member={m}
          isCurrentUser={m.userId === currentUserId}
          workspaceId={workspaceId}
          isOwner={isOwner}
          byokDelegationsEnabled={byokDelegationsEnabled}
          organizationName={organizationName}
        />
      ))}
    </div>
  );
}

function MemberRow({
  member,
  isCurrentUser,
  workspaceId,
  isOwner,
  byokDelegationsEnabled,
  organizationName,
  variant = "row",
}: {
  member: TeamMembershipRow;
  isCurrentUser: boolean;
  workspaceId: string;
  isOwner: boolean;
  byokDelegationsEnabled: boolean;
  organizationName: string | null;
  /** "row" = desktop grid `<div>` cells; "card" = mobile record card (below md). */
  variant?: "row" | "card";
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [transferDialogOpen, setTransferDialogOpen] = useState(false);
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

  // RBAC: the kebab menu holds only owner-only actions (Remove member,
  // Transfer ownership), so it is gated on `isOwner` — Members see no kebab on
  // any row. AC-FLOW4: an owner also gets no kebab on their own (self) row
  // (cannot remove/transfer to self).
  const showActions = !isCurrentUser && isOwner;

  // #4715: prompt the owner to share a key with a keyless, undelegated member
  // (only when delegations are enabled and this is not the owner's own row).
  // `!member.delegationFromMe` already owns the delegation term — no separate
  // delegationsByGrantee probe.
  const showShareKeyPrompt =
    byokDelegationsEnabled &&
    isOwner &&
    !isCurrentUser &&
    !member.hasEffectiveKey &&
    !member.delegationFromMe;

  // Shared across both variants: the bordered role badge classes (Owner gold /
  // Member neutral). The row variant additionally prepends `justify-self-center`
  // to sit under its grid header; the card renders the badge in a flex header
  // where justify-self is a no-op, so it is omitted there.
  const roleBadgeClass =
    member.role === "owner"
      ? "rounded-md border border-soleur-accent-gold-fg/40 px-2 py-0.5 text-xs font-medium text-soleur-accent-gold-fg"
      : "rounded-md border border-soleur-border-default px-2 py-0.5 text-xs font-medium text-soleur-text-secondary";

  // MOBILE CARD (below md). Same computed values, handlers, and sub-components
  // as the desktop row — the per-row kebab menu is promoted to explicit 44px
  // buttons; the optional Funded row shows only when delegations are enabled
  // (identical condition to the desktop column). Wireframe:
  // knowledge-base/product/design/mobile-phase-3/02-table-card-team-membership.
  if (variant === "card") {
    return (
      <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3">
        <div className="flex items-center justify-between gap-2">
          <div className="flex min-w-0 items-center gap-3">
            <div className="h-9 w-9 shrink-0 rounded-full bg-soleur-bg-surface-2" aria-hidden="true" />
            <div className="min-w-0">
              <div className="truncate text-sm font-medium text-soleur-text-primary">
                {member.email.split("@")[0]}
              </div>
              <div className="truncate text-xs text-soleur-text-muted">{member.email}</div>
            </div>
          </div>
          <span className={roleBadgeClass}>
            {member.role === "owner" ? "Owner" : "Member"}
          </span>
        </div>

        {showShareKeyPrompt && (
          <p className="mt-2 text-xs text-soleur-text-muted">
            No API key yet — can view the workspace but can&apos;t run tasks.{" "}
            <a
              href="mailto:?subject=Add%20your%20Anthropic%20API%20key%20to%20Soleur"
              className="underline decoration-dotted underline-offset-2 hover:text-soleur-text-secondary"
            >
              or ask them to add their own
            </a>
            .
          </p>
        )}

        <div className="mt-3 space-y-2 border-t border-soleur-border-default pt-3">
          {byokDelegationsEnabled && (
            <div className="flex items-center justify-between gap-3 text-xs">
              <span className="text-soleur-text-muted">Funded</span>
              <DelegationToggle
                memberUserId={member.userId}
                memberEmail={member.email}
                workspaceId={workspaceId}
                isOwner={isOwner}
                delegation={member.delegationFromMe}
                delegationToMe={member.delegationToMe}
                isSelf={isCurrentUser}
                flagEnabled={byokDelegationsEnabled}
                promptShareKey={showShareKeyPrompt}
              />
            </div>
          )}
          <div className="flex items-center justify-between gap-3 text-xs">
            <span className="text-soleur-text-muted">Added</span>
            <span className="text-soleur-text-secondary">
              {isCurrentUser ? "— (you)" : formatRelative(member.addedAt)}
            </span>
          </div>
        </div>

        {showActions && (
          <div className="mt-3 flex gap-2 border-t border-soleur-border-default pt-3">
            {isOwner && member.role !== "owner" && (
              <button
                type="button"
                onClick={() => setTransferDialogOpen(true)}
                className="flex min-h-11 flex-1 items-center justify-center rounded-md border border-soleur-border-default text-sm font-medium text-soleur-text-secondary hover:bg-soleur-bg-surface-2"
              >
                Transfer ownership
              </button>
            )}
            <button
              type="button"
              onClick={handleRemove}
              className="flex min-h-11 flex-1 items-center justify-center rounded-md border border-red-400/40 text-sm font-medium text-red-400 hover:bg-soleur-bg-surface-2"
            >
              Remove
            </button>
          </div>
        )}

        {transferDialogOpen && (
          <TransferOwnershipDialog
            targetEmail={member.email}
            confirmationTarget={organizationName || member.email}
            workspaceId={workspaceId}
            targetUserId={member.userId}
            onClose={() => setTransferDialogOpen(false)}
            onSuccess={() => window.location.reload()}
          />
        )}
      </div>
    );
  }

  return (
    <div className={`grid ${byokDelegationsEnabled ? "grid-cols-[1fr_auto_auto_auto_auto]" : "grid-cols-[1fr_auto_auto_auto]"} items-center gap-4 border-b border-soleur-border-default px-6 py-4 last:border-b-0`}>
      <div className="flex items-center gap-3">
        <div className="h-9 w-9 shrink-0 rounded-full bg-soleur-bg-surface-2" aria-hidden="true" />
        <div className="min-w-0">
          <div className="truncate text-sm font-medium text-soleur-text-primary">
            {member.email.split("@")[0]}
          </div>
          <div className="truncate text-xs text-soleur-text-muted">{member.email}</div>
          {showShareKeyPrompt && (
            <p className="mt-1 text-xs text-soleur-text-muted">
              No API key yet — can view the workspace but can&apos;t run tasks.{" "}
              <a
                href="mailto:?subject=Add%20your%20Anthropic%20API%20key%20to%20Soleur"
                className="underline decoration-dotted underline-offset-2 hover:text-soleur-text-secondary"
              >
                or ask them to add their own
              </a>
              .
            </p>
          )}
        </div>
      </div>
      {/* justify-self-center: the badge is a grid item; without it the bordered
          span stretches to fill the auto column and left-aligns, drifting from
          the text-center "Role" header. Center it to sit under the header. */}
      <span
        className={
          member.role === "owner"
            ? "justify-self-center rounded-md border border-soleur-accent-gold-fg/40 px-2 py-0.5 text-xs font-medium text-soleur-accent-gold-fg"
            : "justify-self-center rounded-md border border-soleur-border-default px-2 py-0.5 text-xs font-medium text-soleur-text-secondary"
        }
      >
        {member.role === "owner" ? "Owner" : "Member"}
      </span>
      {byokDelegationsEnabled && (
        // justify-self-center: center the Funded control under its text-center
        // header (DelegationToggle right-aligns internally; the shrink-wrapped
        // wrapper makes that a no-op while centering the cluster in the column).
        <div className="justify-self-center">
          <DelegationToggle
            memberUserId={member.userId}
            memberEmail={member.email}
            workspaceId={workspaceId}
            isOwner={isOwner}
            delegation={member.delegationFromMe}
            delegationToMe={member.delegationToMe}
            isSelf={isCurrentUser}
            flagEnabled={byokDelegationsEnabled}
            promptShareKey={showShareKeyPrompt}
          />
        </div>
      )}
      {/* justify-self-end + text-right: right-align under the text-right "Added"
          header (don't rely on the default stretch). */}
      <span className="justify-self-end text-right text-xs text-soleur-text-muted">
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
              <div className="absolute right-0 top-7 z-10 w-52 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 py-1 shadow-lg">
                {isOwner && member.role !== "owner" && (
                  <button
                    type="button"
                    onClick={() => {
                      setMenuOpen(false);
                      setTransferDialogOpen(true);
                    }}
                    className="block w-full px-3 py-2 text-left text-sm text-soleur-text-secondary hover:bg-soleur-bg-surface-2"
                  >
                    Transfer ownership
                  </button>
                )}
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
      {transferDialogOpen && (
        <TransferOwnershipDialog
          targetEmail={member.email}
          confirmationTarget={organizationName || member.email}
          workspaceId={workspaceId}
          targetUserId={member.userId}
          onClose={() => setTransferDialogOpen(false)}
          onSuccess={() => window.location.reload()}
        />
      )}
    </div>
  );
}
