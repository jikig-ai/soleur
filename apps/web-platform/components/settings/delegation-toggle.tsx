"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";

interface DelegationToggleProps {
  memberUserId: string;
  memberEmail: string;
  workspaceId: string;
  isOwner: boolean;
  delegation?: {
    id: string;
    dailyCapCents: number;
    /** null = not computed on this surface; render unknown, never $0.00. */
    todaySpentCents: number | null;
    active: boolean;
  } | null;
  delegationToMe?: {
    grantorDisplayName: string;
    dailyCapCents: number;
    /** null = not computed on this surface; render unknown, never $0.00. */
    todaySpentCents: number | null;
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
    /** null = not computed on this surface; render unknown, never $0.00. */
    todaySpentCents: number | null;
    active: boolean;
  } | null;
}) {
  // Pre-grant `<input>` model (only shown when there is no active delegation).
  const [grantDraftCapCents, setGrantDraftCapCents] = useState(delegation?.dailyCapCents ?? 2000);
  const [active, setActive] = useState(!!delegation?.active);
  // Post-join cap edit (#4779-followup): an active delegation's daily cap can
  // be changed in place via PATCH (the WORM Shape-3 flip), without revoke+
  // re-grant. `displayCapCents` is the cap shown in the $spent/$cap label; it
  // updates locally on a successful save. `editingCap` toggles the inline
  // editor; `draftDollars` holds the raw input string (parsed on save so
  // mid-typing never clamps).
  const [displayCapCents, setDisplayCapCents] = useState(delegation?.dailyCapCents ?? 2000);
  const [editingCap, setEditingCap] = useState(false);
  const [draftDollars, setDraftDollars] = useState(
    String((delegation?.dailyCapCents ?? 2000) / 100),
  );

  // One shared flag for toggle + cap-edit: they are the same action-group, so
  // a pending write must disable both controls. asyncFn never throws —
  // failures surface via window.alert (AC5, regression-pinned by tests).
  const { run, pending: loading } = usePendingAction(
    async (op: "toggle" | "saveCap") => {
      try {
        if (op === "saveCap") {
          if (!delegation) return;
          const nextCapCents = Math.max(100, Math.round(Number(draftDollars) * 100));
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
          return;
        }
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
              dailyCapCents: grantDraftCapCents,
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
        console.error(
          op === "saveCap"
            ? "[delegation-toggle] cap update request failed:"
            : "[delegation-toggle] request failed:",
          err,
        );
        window.alert("Something went wrong. Please check your connection and try again.");
        if (op === "saveCap") setEditingCap(false);
      }
    },
  );

  const handleSaveCap = () => run("saveCap");
  const handleToggle = () => run("toggle");

  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        role="switch"
        aria-checked={active}
        aria-label={`Fund ${memberEmail.split("@")[0]}'s runs`}
        aria-busy={loading || undefined}
        disabled={loading}
        onClick={handleToggle}
        data-button-exempt="role=switch composite — fixed h-5 w-9 track + sliding thumb span cannot reduce to Button's padding/radius geometry"
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
            {delegation.todaySpentCents === null
              ? "spend unknown"
              : `$${(delegation.todaySpentCents / 100).toFixed(2)}`}
            /${(displayCapCents / 100).toFixed(0)}
          </span>
          <Button
            variant="ghost"
            type="button"
            disabled={loading}
            onClick={() => {
              setDraftDollars(String(displayCapCents / 100));
              setEditingCap(true);
            }}
            className="text-xs underline decoration-dotted underline-offset-2"
          >
            Edit cap
          </Button>
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
          <Button
            variant="ghost"
            type="button"
            // Block Save on empty/invalid/sub-$1 input so clearing the field and
            // saving can't silently write the $1.00 floor (an unintended de-fund).
            disabled={loading || !(Number(draftDollars) >= 1)}
            loading={loading}
            loadingLabel="Saving"
            onClick={handleSaveCap}
            className="text-xs"
            // text-soleur-accent-gold-fg loses Tailwind emit-order against the
            // ghost variant's text-soleur-text-secondary — preserve the gold
            // action affordance via the token directly.
            style={{ color: "var(--soleur-accent-gold-fg)" }}
          >
            Save
          </Button>
          <Button
            variant="ghost"
            type="button"
            disabled={loading}
            onClick={() => setEditingCap(false)}
            className="text-xs"
          >
            Cancel
          </Button>
        </>
      )}
      {!active && !delegation && (
        <input
          type="number"
          min={1}
          value={grantDraftCapCents / 100}
          onChange={(e) => setGrantDraftCapCents(Math.max(100, Math.round(Number(e.target.value) * 100)))}
          className="w-16 rounded border border-soleur-border-default bg-soleur-bg-base px-1 py-0.5 text-xs text-soleur-text-primary"
          aria-label="Daily cap in dollars"
        />
      )}
    </div>
  );
}
