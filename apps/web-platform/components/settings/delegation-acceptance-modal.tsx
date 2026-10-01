"use client";

import { useState } from "react";
import { reportSilentFallback } from "@/lib/client-observability";
import { Button } from "@/components/ui/button";
import { ResponsiveModal } from "@/components/ui/responsive-modal";
import { usePendingAction } from "@/hooks/use-pending-action";

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
  // Inline telemetry-visibility acknowledgment (CPO finding): the grantee
  // must actively acknowledge that the grantor sees their run cost telemetry
  // before "I accept" is enabled.
  const [telemetryAck, setTelemetryAck] = useState(false);
  // New error surface (#9053): a failed write was reportSilentFallback-only —
  // a silent dead click. Render the failure so the grantee knows it happened.
  const [actionError, setActionError] = useState<string | null>(null);

  // One shared flag for accept/decline/withdraw — a pending op must disable
  // the sibling controls. asyncFn never throws.
  const { run, pending: loading } = usePendingAction(
    async (op: "accept" | "decline" | "withdraw") => {
      setActionError(null);
      try {
        if (op === "accept") {
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
            setActionError("Couldn't accept the delegation. Please try again.");
          }
        } else if (op === "decline") {
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
            setActionError("Couldn't decline the delegation. Please try again.");
          }
        } else {
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
            setActionError("Couldn't withdraw consent. Please try again.");
          }
        }
      } catch (err) {
        reportSilentFallback(err, {
          feature: "byok-delegation",
          op,
        });
        setActionError("Something went wrong. Please check your connection and try again.");
      }
    },
  );

  const handleAccept = () => run("accept");
  const handleDecline = () => run("decline");
  const handleWithdraw = () => run("withdraw");

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

      {actionError && (
        <p
          role="alert"
          className="mt-3 rounded-md border border-red-800/50 bg-red-950/30 px-3 py-2 text-sm text-red-300"
        >
          {actionError}
        </p>
      )}

      {alreadyAccepted ? (
        <>
          <p className="mt-4 text-sm text-soleur-text-secondary">
            You can withdraw your consent at any time. After withdrawal,
            new runs stop using {grantorDisplayName}&apos;s key and any
            in-flight run is billed back to you within one turn.
          </p>
          <div className="mt-6 flex gap-3">
            <Button
              variant="outlined"
              type="button"
              onClick={handleWithdraw}
              disabled={loading}
              loading={loading}
              loadingLabel="Processing"
              modal
              className="flex-1 text-soleur-text-secondary"
            >
              Withdraw consent
            </Button>
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
            <Button
              variant="outlined"
              type="button"
              onClick={handleDecline}
              disabled={loading}
              className="flex-1 text-soleur-text-secondary"
            >
              Decline
            </Button>
            <Button
              variant="gold"
              type="button"
              onClick={handleAccept}
              disabled={loading || !telemetryAck}
              loading={loading}
              loadingLabel="Processing"
              modal
              className="flex-1"
            >
              I accept
            </Button>
          </div>
        </>
      )}
    </ResponsiveModal>
  );
}
