"use client";

import { useState, useCallback } from "react";
import { reportSilentFallback } from "@/lib/client-observability";
import { ResponsiveModal } from "@/components/ui/responsive-modal";

interface DelegationAcceptanceModalProps {
  delegationId: string;
  grantorDisplayName: string;
  dailyCapCents: number;
  hourlyCapCents: number | null;
  sideLetterVersion: string;
  /**
   * When true the grantee has already accepted: render the post-acceptance
   * surface (a withdraw affordance — Art. 7(3) "as easy to withdraw as to
   * give") instead of the review-and-accept flow.
   */
  alreadyAccepted?: boolean;
  onAccepted: () => void;
  onDeclined: () => void;
  /** Called after a successful consent withdrawal. */
  onWithdrawn?: () => void;
}

export function DelegationAcceptanceModal({
  delegationId,
  grantorDisplayName,
  dailyCapCents,
  hourlyCapCents,
  sideLetterVersion,
  alreadyAccepted = false,
  onAccepted,
  onDeclined,
  onWithdrawn,
}: DelegationAcceptanceModalProps) {
  const [loading, setLoading] = useState(false);
  // Inline telemetry-visibility acknowledgment (CPO finding): the grantee
  // must actively acknowledge that the grantor sees their run cost telemetry
  // before "I accept" is enabled.
  const [telemetryAck, setTelemetryAck] = useState(false);

  const handleAccept = useCallback(async () => {
    setLoading(true);
    try {
      // The version is server-owned; the route stamps
      // BYOK_SIDE_LETTER_VERSION. We send only the delegationId (#4625
      // Phase 1 / AC3). `sideLetterVersion` is a display-only prop below.
      const res = await fetch("/api/workspace/delegations/accept", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ delegationId }),
      });
      if (res.ok) {
        onAccepted();
      } else {
        reportSilentFallback(
          new Error(`delegation accept returned ${res.status}`),
          { feature: "byok-delegation", op: "accept" },
        );
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "byok-delegation",
        op: "accept",
      });
    } finally {
      setLoading(false);
    }
  }, [delegationId, onAccepted]);

  const handleDecline = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/workspace/delegations", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ delegationId, reason: "grantee_decline" }),
      });
      if (res.ok) {
        onDeclined();
      } else {
        reportSilentFallback(
          new Error(`delegation decline returned ${res.status}`),
          { feature: "byok-delegation", op: "decline" },
        );
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "byok-delegation",
        op: "decline",
      });
    } finally {
      setLoading(false);
    }
  }, [delegationId, onDeclined]);

  const handleWithdraw = useCallback(async () => {
    setLoading(true);
    try {
      // Art. 7(3) withdrawal. The RPC derives the user from the session;
      // we send only the delegationId (#4625 Phase 3).
      const res = await fetch("/api/workspace/delegations/withdraw", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ delegationId }),
      });
      if (res.ok) {
        onWithdrawn?.();
      } else {
        reportSilentFallback(
          new Error(`delegation withdraw returned ${res.status}`),
          { feature: "byok-delegation", op: "withdraw" },
        );
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "byok-delegation",
        op: "withdraw",
      });
    } finally {
      setLoading(false);
    }
  }, [delegationId, onWithdrawn]);

  return (
    <ResponsiveModal
      open
      closeOnBackdrop={false}
      desktopMaxWidth="max-w-lg"
      aria-labelledby="delegation-consent-title"
    >
      <h2
        id="delegation-consent-title"
        className="text-lg font-semibold text-soleur-text-primary"
      >
        {alreadyAccepted ? "Delegation Consent — active" : "Delegation Consent"}
      </h2>
      <p className="mt-2 text-sm text-soleur-text-secondary">
        {alreadyAccepted
          ? `${grantorDisplayName} is funding your AI agent runs.`
          : `${grantorDisplayName} has offered to fund your AI agent runs.`}
      </p>

      <div className="mt-4 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4">
        <h3 className="text-sm font-medium text-soleur-text-primary">
          What you&apos;re agreeing to:
        </h3>
        <ul className="mt-2 space-y-1.5 text-sm text-soleur-text-secondary">
          <li>
            {grantorDisplayName} will see cost telemetry for your runs
            (token count, cost, timestamp, agent role)
          </li>
          <li>
            {grantorDisplayName} will <strong>NOT</strong> see your prompt
            content or responses
          </li>
          <li>
            Daily cap: ${(dailyCapCents / 100).toFixed(0)}
            {hourlyCapCents && ` / Hourly cap: $${(hourlyCapCents / 100).toFixed(0)}`}
          </li>
          <li>
            Either party can terminate the delegation at any time
          </li>
        </ul>
      </div>

      <p className="mt-3 text-xs text-soleur-text-muted">
        By accepting, you consent to the terms of the Delegation Consent
        Side Letter (version {sideLetterVersion}). See the Data Protection
        Disclosure Section 2.3(w) for full details.
      </p>

      {alreadyAccepted ? (
        <>
          <p className="mt-4 text-sm text-soleur-text-secondary">
            You can withdraw your consent at any time. After withdrawal,
            new runs stop using {grantorDisplayName}&apos;s key and any
            in-flight run is billed back to you within one turn.
          </p>
          <div className="mt-6 flex gap-3">
            <button
              type="button"
              onClick={handleWithdraw}
              disabled={loading}
              className="flex-1 rounded-lg border border-soleur-border-default px-4 py-2 text-sm font-medium text-soleur-text-secondary hover:bg-soleur-bg-surface-2 disabled:opacity-50"
            >
              {loading ? "Processing..." : "Withdraw consent"}
            </button>
          </div>
        </>
      ) : (
        <>
          <label className="mt-4 flex items-start gap-2 text-sm text-soleur-text-secondary">
            <input
              type="checkbox"
              checked={telemetryAck}
              onChange={(e) => setTelemetryAck(e.target.checked)}
              className="mt-0.5"
            />
            <span>
              I acknowledge that {grantorDisplayName} will see itemized cost
              telemetry for every run I make under their key.
            </span>
          </label>

          <div className="mt-6 flex gap-3">
            <button
              type="button"
              onClick={handleDecline}
              disabled={loading}
              className="flex-1 rounded-lg border border-soleur-border-default px-4 py-2 text-sm font-medium text-soleur-text-secondary hover:bg-soleur-bg-surface-2 disabled:opacity-50"
            >
              Decline
            </button>
            <button
              type="button"
              onClick={handleAccept}
              disabled={loading || !telemetryAck}
              className="flex-1 rounded-lg bg-soleur-accent-gold-fg px-4 py-2 text-sm font-medium text-soleur-bg-surface-1 hover:opacity-90 disabled:opacity-50"
            >
              {loading ? "Processing..." : "I accept"}
            </button>
          </div>
        </>
      )}
    </ResponsiveModal>
  );
}
