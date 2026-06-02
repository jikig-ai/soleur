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
  // Post-join cap edit (#4779-followup): an active delegation's daily cap can
  // be changed in place via PATCH (the WORM Shape-3 flip), without revoke+
  // re-grant. `displayCapCents` is the cap shown in the $spent/$cap label; it
  // updates locally on a successful save. `editingCap` toggles the inline
  // editor; `draftDollars` holds the raw input string (parsed on save so
  // mid-typing never clamps).
  const [displayCapCents, setDisplayCapCents] = useState(delegation?.dailyCapCents ?? 0);
  const [editingCap, setEditingCap] = useState(false);
  const [draftDollars, setDraftDollars] = useState(
    String((delegation?.dailyCapCents ?? 2000) / 100),
  );

  const handleSaveCap = useCallback(async () => {
    if (!delegation) return;
    const nextCapCents = Math.max(100, Math.round(Number(draftDollars) * 100));
    setLoading(true);
    try {
      const res = await fetch("/api/workspace/delegations", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ delegationId: delegation.id, dailyCapCents: nextCapCents }),
      });
      if (res.ok) {
        setDisplayCapCents(nextCapCents);
        setEditingCap(false);
      } else {
        // Mirror the grant/revoke error posture (AC5): a failed write must be
        // operator-visible, never a silent revert. Close the editor so the
        // unchanged $spent/$cap label signals the cap did NOT change.
        console.error("[delegation-toggle] cap update failed:", res.status);
        window.alert("Couldn't update the daily cap. Please try again.");
        setEditingCap(false);
      }
    } catch (err) {
      console.error("[delegation-toggle] cap update request failed:", err);
      window.alert("Something went wrong. Please check your connection and try again.");
      setEditingCap(false);
    } finally {
      setLoading(false);
    }
  }, [delegation, draftDollars]);

  const handleToggle = useCallback(async () => {
    setLoading(true);
    try {
      if (active && delegation) {
        const res = await fetch("/api/workspace/delegations", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ delegationId: delegation.id, reason: "grantor_revoke" }),
        });
        if (res.ok) {
          setActive(false);
        } else {
          // AC5: never silently swallow a non-OK response — a failed write must
          // be operator-visible, not a toggle that snaps back with no signal.
          console.error("[delegation-toggle] revoke failed:", res.status);
          window.alert("Couldn't stop sharing the key. Please try again.");
        }
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
        if (res.ok) {
          setActive(true);
        } else {
          console.error("[delegation-toggle] grant failed:", res.status);
          window.alert("Couldn't share a key with this member. Please try again.");
        }
      }
    } catch (err) {
      // A thrown fetch (offline, DNS/TLS failure, aborted request) bypasses the
      // !res.ok branches above; without this catch the toggle would snap back
      // to its prior state with no signal — the same silent no-op AC5 fixes for
      // non-OK responses. Surface it the same way.
      console.error("[delegation-toggle] request failed:", err);
      window.alert("Something went wrong. Please check your connection and try again.");
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
      {active && delegation && !editingCap && (
        <>
          <span className="text-xs text-soleur-text-muted">
            ${(delegation.todaySpentCents / 100).toFixed(2)}/
            ${(displayCapCents / 100).toFixed(0)}
          </span>
          <button
            type="button"
            disabled={loading}
            onClick={() => {
              setDraftDollars(String(displayCapCents / 100));
              setEditingCap(true);
            }}
            className="text-xs text-soleur-text-muted underline decoration-dotted underline-offset-2 hover:text-soleur-text-secondary"
          >
            Edit cap
          </button>
        </>
      )}
      {active && delegation && editingCap && (
        <>
          <input
            type="number"
            min={1}
            value={draftDollars}
            onChange={(e) => setDraftDollars(e.target.value)}
            className="w-16 rounded border border-soleur-border-default bg-soleur-bg-base px-1 py-0.5 text-xs text-soleur-text-primary"
            aria-label="Daily cap in dollars"
          />
          <button
            type="button"
            disabled={loading}
            onClick={handleSaveCap}
            className="text-xs font-medium text-soleur-accent-gold-fg hover:underline"
          >
            Save
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={() => setEditingCap(false)}
            className="text-xs text-soleur-text-muted hover:text-soleur-text-secondary"
          >
            Cancel
          </button>
        </>
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
