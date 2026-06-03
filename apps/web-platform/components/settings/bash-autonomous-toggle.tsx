"use client";

import { useState, useCallback } from "react";

/**
 * Issue B part 2 — per-workspace "autonomous mode" toggle for the Concierge.
 *
 * When ON, the Concierge auto-approves every NON-BLOCKED Bash command (skips
 * the per-command Approve/Deny gate). Because that is an approval-bypass on a
 * code-executing surface, turning it ON is gated behind an explicit, unavoidable
 * risk interstitial (the user's informed-consent surface). Turning it OFF needs
 * no confirmation. Owner-only: the underlying RPC raises for non-owners, but we
 * also hide the control for non-owners. See concierge-autonomous-toggle.pen.
 */
export function BashAutonomousToggle({
  initialAutonomous,
  isOwner,
}: {
  initialAutonomous: boolean;
  isOwner: boolean;
}) {
  const [autonomous, setAutonomous] = useState(initialAutonomous);
  const [loading, setLoading] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);

  const persist = useCallback(async (value: boolean) => {
    setLoading(true);
    try {
      const res = await fetch("/api/workspace/bash-autonomous", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ value }),
      });
      if (res.ok) {
        const data = (await res.json()) as { autonomous?: boolean };
        setAutonomous(data.autonomous ?? value);
      } else {
        // Never silently swallow a non-OK response — a failed write must be
        // visible, not a toggle that snaps back with no signal.
        console.error("[bash-autonomous-toggle] write failed:", res.status);
        window.alert(
          res.status === 403
            ? "Only a workspace owner can change autonomous mode."
            : "Couldn't update autonomous mode. Please try again.",
        );
      }
    } catch (err) {
      console.error("[bash-autonomous-toggle] request failed:", err);
      window.alert(
        "Something went wrong. Please check your connection and try again.",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  const handleToggleClick = useCallback(() => {
    if (loading) return;
    if (autonomous) {
      // Turning OFF is always safe — no confirmation needed.
      void persist(false);
    } else {
      // Turning ON requires the explicit risk interstitial.
      setConfirmOpen(true);
    }
  }, [autonomous, loading, persist]);

  const handleConfirmEnable = useCallback(async () => {
    setConfirmOpen(false);
    await persist(true);
  }, [persist]);

  if (!isOwner) return null;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <span className="text-sm font-semibold text-soleur-text-primary">
            Autonomous mode
          </span>
          <span className="text-xs text-soleur-text-muted">
            Let the Concierge run commands without asking you to approve each
            one. Off by default. The command blocklist (curl, wget, sudo, …)
            always applies — even when this is on.
          </span>
        </div>
        <button
          type="button"
          role="switch"
          aria-checked={autonomous}
          aria-label="Autonomous mode"
          disabled={loading}
          onClick={handleToggleClick}
          className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors ${
            autonomous ? "bg-soleur-accent-gold-fg" : "bg-soleur-bg-surface-2"
          } ${loading ? "opacity-50" : ""}`}
        >
          <span
            className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${
              autonomous ? "translate-x-4" : "translate-x-0"
            }`}
          />
        </button>
      </div>

      {confirmOpen && (
        <div
          role="alertdialog"
          aria-modal="true"
          aria-label="Turn on autonomous mode?"
          className="flex flex-col gap-3 rounded-md border border-soleur-accent-gold-fg bg-soleur-bg-surface-1 p-4"
        >
          <span className="text-sm font-semibold text-soleur-text-primary">
            Turn on autonomous mode?
          </span>
          <p className="text-xs text-soleur-text-secondary">
            The Concierge will run any non-blocked command without asking. If a
            malicious issue or repo file tricks the agent (prompt injection), it
            could delete files or leak data with no approval step. Only turn this
            on for repos and workspaces you fully trust.
          </p>
          <div className="flex justify-end gap-2">
            <button
              type="button"
              disabled={loading}
              onClick={() => setConfirmOpen(false)}
              className="rounded border border-soleur-border-default px-3 py-1.5 text-xs font-medium text-soleur-text-primary hover:bg-soleur-bg-surface-2"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={loading}
              onClick={handleConfirmEnable}
              className="rounded bg-soleur-accent-gold-fg px-3 py-1.5 text-xs font-semibold text-black hover:opacity-90 disabled:opacity-50"
            >
              I understand — turn it on
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
