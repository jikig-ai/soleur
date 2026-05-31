"use client";

import { useState, useCallback } from "react";

interface DelegationToggleProps {
  memberUserId: string;
  memberEmail: string;
  workspaceId: string;
  isOwner: boolean;
  delegation?: {
    id: string;
    dailyCapCents: number;
    todaySpentCents: number;
    active: boolean;
  } | null;
  delegationToMe?: {
    grantorDisplayName: string;
    dailyCapCents: number;
    todaySpentCents: number;
  } | null;
  isSelf: boolean;
  flagEnabled: boolean;
  /**
   * #4715: render a "Share a key" label above the grant control when the owner
   * is being prompted to fund a keyless, undelegated member. Purely a label —
   * the control still creates a GRANT only (TR3), no new logic.
   */
  promptShareKey?: boolean;
}

export function DelegationToggle({
  memberUserId,
  memberEmail,
  workspaceId,
  isOwner,
  delegation,
  delegationToMe,
  isSelf,
  flagEnabled,
  promptShareKey = false,
}: DelegationToggleProps) {
  if (!flagEnabled) return null;

  if (isSelf && delegationToMe) {
    return (
      <span className="text-xs text-soleur-accent-gold-fg">
        Funded by {delegationToMe.grantorDisplayName}
      </span>
    );
  }

  if (!isOwner || isSelf) return <span className="w-20" />;

  return (
    <div className="flex flex-col items-end gap-0.5">
      {promptShareKey && (
        <span className="text-xs font-medium text-soleur-accent-gold-fg">
          Share a key
        </span>
      )}
      <OwnerDelegationControl
        memberUserId={memberUserId}
        memberEmail={memberEmail}
        workspaceId={workspaceId}
        delegation={delegation ?? null}
      />
    </div>
  );
}

function OwnerDelegationControl({
  memberUserId,
  memberEmail,
  workspaceId,
  delegation,
}: {
  memberUserId: string;
  memberEmail: string;
  workspaceId: string;
  delegation: {
    id: string;
    dailyCapCents: number;
    todaySpentCents: number;
    active: boolean;
  } | null;
}) {
  const [loading, setLoading] = useState(false);
  const [capCents, setCapCents] = useState(delegation?.dailyCapCents ?? 2000);
  const [active, setActive] = useState(!!delegation?.active);

  const handleToggle = useCallback(async () => {
    setLoading(true);
    try {
      if (active && delegation) {
        const res = await fetch("/api/workspace/delegations", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ delegationId: delegation.id, reason: "grantor_revoke" }),
        });
        if (res.ok) setActive(false);
      } else {
        const res = await fetch("/api/workspace/delegations", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            workspaceId,
            granteeUserId: memberUserId,
            dailyCapCents: capCents,
          }),
        });
        if (res.ok) setActive(true);
      }
    } finally {
      setLoading(false);
    }
  }, [active, delegation, workspaceId, memberUserId, capCents]);

  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        role="switch"
        aria-checked={active}
        aria-label={`Fund ${memberEmail.split("@")[0]}'s runs`}
        disabled={loading}
        onClick={handleToggle}
        className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors ${
          active ? "bg-soleur-accent-gold-fg" : "bg-soleur-bg-surface-2"
        } ${loading ? "opacity-50" : ""}`}
      >
        <span
          className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${
            active ? "translate-x-4" : "translate-x-0"
          }`}
        />
      </button>
      {active && delegation && (
        <span className="text-xs text-soleur-text-muted">
          ${(delegation.todaySpentCents / 100).toFixed(2)}/
          ${(delegation.dailyCapCents / 100).toFixed(0)}
        </span>
      )}
      {!active && !delegation && (
        <input
          type="number"
          min={1}
          value={capCents / 100}
          onChange={(e) => setCapCents(Math.max(100, Math.round(Number(e.target.value) * 100)))}
          className="w-16 rounded border border-soleur-border-default bg-soleur-bg-base px-1 py-0.5 text-xs text-soleur-text-primary"
          aria-label="Daily cap in dollars"
        />
      )}
    </div>
  );
}
