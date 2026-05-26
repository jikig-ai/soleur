"use client";

const ERROR_MESSAGES: Record<string, { title: string; body: string; cta: string }> = {
  delegation_revoked_post_grace: {
    title: "Access revoked",
    body: "Your funded access has been revoked by the workspace owner.",
    cta: "Request access",
  },
  delegation_expired: {
    title: "Access expired",
    body: "Your funded access has expired.",
    cta: "Request renewal",
  },
  delegation_hourly_cap_exceeded: {
    title: "Hourly cap reached",
    body: "You've reached your hourly spending cap for funded access.",
    cta: "Ask to raise cap",
  },
  delegation_daily_cap_exceeded: {
    title: "Daily cap reached",
    body: "You've reached your daily spending cap for funded access.",
    cta: "Ask to raise cap",
  },
  delegation_cross_tenant: {
    title: "Access error",
    body: "No API key found for this workspace.",
    cta: "Request access",
  },
};

interface DelegationErrorCardProps {
  errorCode: string;
  message?: string;
}

export function DelegationErrorCard({ errorCode, message }: DelegationErrorCardProps) {
  const info = ERROR_MESSAGES[errorCode];
  if (!info) return null;

  return (
    <div className="mx-auto my-4 max-w-md rounded-lg border border-red-400/30 bg-red-400/5 p-4">
      <h3 className="text-sm font-semibold text-red-400">{info.title}</h3>
      <p className="mt-1 text-sm text-soleur-text-secondary">{message || info.body}</p>
      <a
        href="/dashboard/settings/team"
        className="mt-3 inline-block rounded-md bg-soleur-accent-gold-fg px-3 py-1.5 text-xs font-medium text-white hover:bg-soleur-accent-gold-fg/90"
      >
        {info.cta}
      </a>
    </div>
  );
}

export function isDelegationError(code: string | undefined): boolean {
  return !!code && code.startsWith("delegation_");
}
