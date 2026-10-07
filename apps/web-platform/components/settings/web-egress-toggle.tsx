"use client";

import { useState, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";

/**
 * feat-open-web-egress (#9534) — per-workspace "Agent web access" toggle.
 *
 * When ON, hosted agent sessions in this workspace route HTTPS traffic to
 * the public internet through the egress gateway. Because that widens the
 * security boundary for every session, turning it ON is gated behind an
 * explicit risk interstitial (clone of the bash-autonomous consent shape —
 * see agent-web-access.pen). Turning it OFF needs no confirmation — it
 * revokes live web access on the session's next dispatch (the warm-path
 * re-resolution kills its forwarder + gateway token).
 *
 * Owner-only WRITE: the underlying RPC raises for non-owners. A non-owner
 * sees the current state as a disabled (read-only) switch — the debug-mode
 * toggle's member treatment — rather than hiding the card, so members can
 * see whether the workspace runs agents with open egress.
 */
export function WebEgressToggle({
  initialWebEgress,
  isOwner,
}: {
  initialWebEgress: boolean;
  isOwner: boolean;
}) {
  const [webEgress, setWebEgress] = useState(initialWebEgress);
  const [confirmOpen, setConfirmOpen] = useState(false);

  // asyncFn never throws: failure surfaces are the window.alert paths below.
  const { run: persist, pending: loading } = usePendingAction(
    async (value: boolean) => {
      try {
        const res = await fetch("/api/workspace/web-egress", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ value }),
        });
        if (res.ok) {
          const data = (await res.json()) as { webEgress?: boolean };
          setWebEgress(data.webEgress ?? value);
        } else {
          // Never silently swallow a non-OK response — a failed write must be
          // visible, not a toggle that snaps back with no signal.
          console.error("[web-egress-toggle] write failed:", res.status);
          window.alert(
            res.status === 403
              ? "Only a workspace owner can change agent web access."
              : "Couldn't update agent web access. Please try again.",
          );
        }
      } catch (err) {
        console.error("[web-egress-toggle] request failed:", err);
        window.alert(
          "Something went wrong. Please check your connection and try again.",
        );
      }
    },
  );

  const handleToggleClick = useCallback(() => {
    if (loading || !isOwner) return;
    if (webEgress) {
      // Turning OFF is always safe — no confirmation needed.
      persist(false);
    } else {
      // Turning ON requires the explicit risk interstitial.
      setConfirmOpen(true);
    }
  }, [webEgress, loading, isOwner, persist]);

  const handleConfirmEnable = useCallback(() => {
    setConfirmOpen(false);
    persist(true);
  }, [persist]);

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <span className="text-sm font-semibold text-soleur-text-primary">
            Agent web access
          </span>
          <span className="text-xs text-soleur-text-muted">
            HTTPS-only outbound access for agent sessions. Workspace-wide.
            {!isOwner && " Owner-only — read-only for you."}
          </span>
          {webEgress && (
            <span className="text-xs text-soleur-text-secondary">
              On. Sandboxed commands run without stored credentials — agents
              can't push to git remotes or use stored API keys while this is
              on. Applies to sessions started after enabling; turning off
              revokes live access on the session's next dispatch.
            </span>
          )}
          {/* The wireframe's "Widens the security boundary" risk callout is
              rendered by the SECTION (scope-grants/page.tsx), not this
              toggle — unconditional, since a member viewing the locked
              state sees the same warning. The "View egress audit log"
              affordance is deferred to #9545 (no queryable store in Phase
              A). */}
        </div>
        <button
          type="button"
          role="switch"
          aria-checked={webEgress}
          aria-label="Agent web access"
          aria-busy={loading || undefined}
          disabled={loading || !isOwner}
          onClick={handleToggleClick}
          data-button-exempt="role=switch composite — fixed h-5 w-9 track + sliding thumb span cannot reduce to Button's padding/radius geometry"
          className={`relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors ${
            webEgress ? "bg-soleur-accent-gold-fg" : "bg-soleur-bg-surface-2"
          } ${loading || !isOwner ? "cursor-not-allowed opacity-50" : "cursor-pointer"}`}
        >
          <span
            className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${
              webEgress ? "translate-x-4" : "translate-x-0"
            }`}
          />
        </button>
      </div>

      {confirmOpen && isOwner && (
        <div
          role="alertdialog"
          aria-modal="true"
          aria-label="Turn on web access for this workspace?"
          className="flex flex-col gap-3 rounded-none border border-soleur-accent-gold-fg bg-soleur-bg-surface-1 p-4"
        >
          <span className="text-sm font-semibold text-soleur-text-primary">
            Turn on web access for this workspace?
          </span>
          <p className="text-xs text-soleur-text-secondary">
            Agents will reach the public internet over HTTPS and could send
            data to external hosts if compromised or prompt-injected.
            Sandboxed commands run without stored credentials while this is
            on — agents can't push to git remotes or use stored API keys.
            Every outbound request is logged with workspace attribution.
          </p>
          <div className="flex justify-end gap-2">
            <Button
              variant="outlined"
              type="button"
              disabled={loading}
              onClick={() => setConfirmOpen(false)}
              className="rounded-none text-xs font-medium"
            >
              Cancel
            </Button>
            <Button
              variant="gold"
              type="button"
              disabled={loading}
              loading={loading}
              loadingLabel="Turning on"
              onClick={handleConfirmEnable}
              className="rounded-none text-xs font-semibold"
            >
              I understand — turn it on
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
