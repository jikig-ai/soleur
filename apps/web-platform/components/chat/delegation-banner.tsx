"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { DelegationAcceptanceModal } from "@/components/settings/delegation-acceptance-modal";

export interface DelegationBannerProps {
  grantorDisplayName: string;
  todaySpentCents: number;
  dailyCapCents: number;
  hourlyCapCents: number | null;
  delegationId: string;
  sideLetterVersion: string;
  alreadyAccepted: boolean;
  withdrawn: boolean;
}

export function DelegationBanner({
  grantorDisplayName,
  todaySpentCents,
  dailyCapCents,
  hourlyCapCents,
  delegationId,
  sideLetterVersion,
  alreadyAccepted,
  withdrawn,
}: DelegationBannerProps) {
  const router = useRouter();
  const [open, setOpen] = useState(false);

  // 3-state enum per `AcceptanceStatus` (byok-delegation-ui-resolver.ts):
  //   never-accepted (!alreadyAccepted && !withdrawn) → accept flow
  //   active         (alreadyAccepted && !withdrawn)  → manage / withdraw
  //   withdrawn      (withdrawn=true)                 → re-accept (same as
  //                                                    never-accepted; the
  //                                                    SQL gate at mig 075
  //                                                    closes out on
  //                                                    withdrawn=true).
  const showAcceptFlow = !alreadyAccepted || withdrawn;

  // 3 distinct refresh call sites — success-only — required so a future
  // refactor cannot hoist into a shared finally and clobber the modal's
  // pessimistic-revert (learning 2026-05-19).
  const handleAccepted = () => {
    setOpen(false);
    router.refresh();
  };
  const handleDeclined = () => {
    setOpen(false);
    router.refresh();
  };
  const handleWithdrawn = () => {
    setOpen(false);
    router.refresh();
  };

  if (showAcceptFlow) {
    return (
      <div className="flex items-center gap-2 border-b border-soleur-accent-gold-fg/20 bg-soleur-accent-gold-fill/10 px-4 py-2 text-sm text-soleur-accent-gold-fg">
        <span className="font-medium">Pending acceptance</span>
        <span className="text-soleur-text-muted">—</span>
        <span>
          {grantorDisplayName} has offered to fund your runs. Accept the
          Delegation Consent Side Letter to activate.
        </span>
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="ml-auto rounded-md bg-soleur-accent-gold-fg px-3 py-1 text-xs font-medium text-soleur-bg-surface-1 hover:opacity-90"
        >
          Review &amp; accept
        </button>
        {open && (
          <DelegationAcceptanceModal
            delegationId={delegationId}
            grantorDisplayName={grantorDisplayName}
            dailyCapCents={dailyCapCents}
            hourlyCapCents={hourlyCapCents}
            sideLetterVersion={sideLetterVersion}
            alreadyAccepted={false}
            onAccepted={handleAccepted}
            onDeclined={handleDeclined}
          />
        )}
      </div>
    );
  }

  return (
    <div
      className="flex items-center gap-2 border-b border-soleur-accent-gold-fg/20 bg-soleur-accent-gold-fill/10 px-4 py-2 text-sm text-soleur-accent-gold-fg"
      role="status"
      aria-live="polite"
    >
      <span className="font-medium">
        Running on {grantorDisplayName}&apos;s key
      </span>
      <span className="text-soleur-text-muted">—</span>
      <span>
        ${(todaySpentCents / 100).toFixed(2)} of $
        {(dailyCapCents / 100).toFixed(0)} today
      </span>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="ml-auto text-xs underline hover:text-soleur-accent-gold-fg/80"
      >
        Manage
      </button>
      {open && (
        <DelegationAcceptanceModal
          delegationId={delegationId}
          grantorDisplayName={grantorDisplayName}
          dailyCapCents={dailyCapCents}
          hourlyCapCents={hourlyCapCents}
          sideLetterVersion={sideLetterVersion}
          alreadyAccepted={true}
          onAccepted={handleAccepted}
          onDeclined={handleDeclined}
          onWithdrawn={handleWithdrawn}
        />
      )}
    </div>
  );
}
