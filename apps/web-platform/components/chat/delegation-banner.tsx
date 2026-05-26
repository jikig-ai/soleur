"use client";

interface DelegationBannerProps {
  grantorDisplayName: string;
  todaySpentCents: number;
  dailyCapCents: number;
  pending: boolean;
}

export function DelegationBanner({
  grantorDisplayName,
  todaySpentCents,
  dailyCapCents,
  pending,
}: DelegationBannerProps) {
  if (pending) {
    return (
      <div className="flex items-center gap-2 border-b border-soleur-accent-gold-fg/20 bg-soleur-accent-gold-fill/10 px-4 py-2 text-sm text-soleur-accent-gold-fg">
        <span className="font-medium">Pending acceptance</span>
        <span className="text-soleur-text-muted">—</span>
        <span>{grantorDisplayName} has offered to fund your runs. Accept the Delegation Consent Side Letter to activate.</span>
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
        ${(todaySpentCents / 100).toFixed(2)} of ${(dailyCapCents / 100).toFixed(0)} today
      </span>
      <a
        href="/dashboard/settings/billing"
        className="ml-auto text-xs underline hover:text-soleur-accent-gold-fg/80"
      >
        Details
      </a>
    </div>
  );
}
