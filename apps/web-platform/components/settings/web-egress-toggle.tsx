"use client";

import { useState, useCallback, useEffect } from "react";
// <!-- anti-slop:disable TWO-ICON-LIBS reason="Single icon library (lucide-react); rule's regex fires on any single match of the supported-library list, not on multi-library usage — calibration FP per #4270" -->
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { NavLink } from "@/components/ui/nav-link";
import { EGRESS_AUDIT_PATH, formatAgo, type CollectionState } from "@/lib/egress-audit/summary";
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
const RECORDING_NOTICE =
  "Hosts your agents contact are recorded as best-effort summary counts: the host, whether the request was allowed, blocked or ended another way, and the number of requests. Every current member of this workspace can view them, including activity from before they joined. No member or session is recorded, some entries may be missing, and counts are minimums. Records are deleted about 30 days after they were recorded. Turning web access off stops new records but does not delete existing ones.";
// "unknown" = any case where the loader could not determine it (Flagsmith outage, failed org lookup,
// pointer fault or timeout, unbound workspace, overall bound, the page's workspace-mismatch override).
// In every such case the state is undetermined, and it must never hide the disclosure from the owner who
// is about to enable web access: the full notice is shown, conditionally.
const RECORDING_NOTICE_UNKNOWN = `We couldn't check whether recording is on for this workspace. If it is, the following applies. ${RECORDING_NOTICE}`;
const CARD_NOTE: Record<"true" | "unknown", string> = {
  true: "Activity through web access is recorded for this workspace and visible to every current member.",
  unknown: "Activity through web access may be recorded for this workspace and visible to every current member.",
};

export function WebEgressToggle({
  initialWebEgress,
  isOwner,
  lastRequestAt,
  collection,
}: {
  initialWebEgress: boolean;
  isOwner: boolean;
  /** ISO time of the newest recorded request, or null (none, or the read failed and the hint is hidden). */
  lastRequestAt: string | null;
  /** Whether egress audit collection is on for this workspace's org; "unknown" when it could not be read. Required: no fail-open default. */
  collection: CollectionState;
}) {
  const [webEgress, setWebEgress] = useState(initialWebEgress);
  const [confirmOpen, setConfirmOpen] = useState(false);
  // Relative time is rendered after mount so server and client markup never disagree about "now".
  const [ago, setAgo] = useState<string | null>(null);
  useEffect(() => {
    setAgo(lastRequestAt ? formatAgo(lastRequestAt) : null);
  }, [lastRequestAt]);

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
              state sees the same warning. */}
          {!webEgress && lastRequestAt && (
            <span className="text-xs text-soleur-text-muted">
              Existing records stay visible to members until deleted about 30
              days after they were recorded.
            </span>
          )}
          {collection !== false && (
            <span className="text-xs text-soleur-text-muted">
              {CARD_NOTE[collection === true ? "true" : "unknown"]}
            </span>
          )}
          <div className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1">
            <NavLink
              href={EGRESS_AUDIT_PATH}
              className="inline-flex items-center gap-1.5 text-xs font-medium text-soleur-accent-gold-fg"
            >
              View egress audit log
              <ArrowRight aria-hidden="true" className="h-3 w-3" />
            </NavLink>
            {ago && (
              <span className="text-xs text-soleur-text-muted">
                Last recorded request: {ago}
              </span>
            )}
          </div>
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
          </p>
          {collection === true && (
            <p className="text-xs text-soleur-text-secondary">
              {RECORDING_NOTICE}
            </p>
          )}
          {collection === "unknown" && (
            <p className="text-xs text-soleur-text-secondary">
              {RECORDING_NOTICE_UNKNOWN}
            </p>
          )}
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
