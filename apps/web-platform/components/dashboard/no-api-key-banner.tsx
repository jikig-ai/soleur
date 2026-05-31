"use client";

// feat-skip-api-key-onboarding (#4642) — degraded-state banner for a user who
// skipped (or is delegated-but-keyless). Self-fetches /api/byok/effective-
// status (the dashboard layout is a client component and cannot run the
// service-role effective-key resolution). Renders ONLY when the user has no
// effective key. Non-dismissible while keyless — the capability is genuinely
// blocked, so unlike the runtime explainer there is no dismiss affordance.
//
// Copy branches on `pendingDelegation`: a grant-holder is told to ACCEPT the
// grant (one click) rather than to buy a separate Anthropic account.

import { useEffect, useState } from "react";
import Link from "next/link";
import { reportSilentFallback } from "@/lib/client-observability";

interface EffectiveStatus {
  hasEffectiveKey: boolean;
  pendingDelegation: boolean;
  isSharedWorkspaceMember: boolean;
}

export function NoApiKeyBanner() {
  const [status, setStatus] = useState<EffectiveStatus | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/byok/effective-status");
        if (!res.ok) {
          // Server-error path is a real silent fallback (a persistent 500 hides
          // the banner from every keyless user) — mirror it, then degrade.
          reportSilentFallback(null, {
            feature: "no-api-key-banner",
            op: "effective-status-non-ok",
            extra: { status: res.status },
          });
          return;
        }
        const data = (await res.json()) as Partial<EffectiveStatus>;
        // Only act on a well-formed response — a malformed payload must leave
        // the banner hidden, never render a half-populated state.
        if (typeof data?.hasEffectiveKey !== "boolean") return;
        if (!cancelled) {
          setStatus({
            hasEffectiveKey: data.hasEffectiveKey,
            pendingDelegation: data.pendingDelegation === true,
            isSharedWorkspaceMember: data.isSharedWorkspaceMember === true,
          });
        }
      } catch (err) {
        // Safe degradation: leave the banner hidden rather than render a
        // broken state. Mirror to Sentry so a persistent failure is visible.
        reportSilentFallback(err, {
          feature: "no-api-key-banner",
          op: "effective-status-fetch",
        });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Hidden for users with a usable key (own valid key OR accepted delegation),
  // and while the status is still loading.
  if (!status || status.hasEffectiveKey) return null;

  const pending = status.pendingDelegation;
  // A keyless invited member (#4715) — must not see the solo "buy a separate
  // paid account" dead-end. They can browse the shared workspace; running tasks
  // just needs a key (owner-shared or their own). The pending-grant branch takes
  // precedence (a grant awaiting acceptance is the one-click path).
  const joiner = !pending && status.isSharedWorkspaceMember;

  let title: string;
  let body: string;
  if (pending) {
    title = "You've been granted shared access";
    body = "Accept your grant to start running tasks.";
  } else if (joiner) {
    title = "You're in — tasks need an API key";
    body =
      "You can browse this workspace, but running tasks needs an API key. Ask your workspace owner to share one, or add your own.";
  } else {
    title = "Tasks are disabled until you add a key";
    body =
      "Soleur needs your own Anthropic API key to run tasks. Getting a key requires a separate, paid Anthropic account.";
  }

  const ctaHref = pending ? "/dashboard/chat" : "/dashboard/settings/services";
  const ctaLabel = pending
    ? "Accept access"
    : joiner
      ? "Add your own key"
      : "Add your API key";

  return (
    <div
      role="region"
      aria-labelledby="no-api-key-title"
      className="border-b border-soleur-gold/40 bg-soleur-bg-surface-1 px-4 py-3"
    >
      <div className="mx-auto flex max-w-4xl items-center justify-between gap-3">
        <div className="min-w-0 space-y-0.5">
          <p id="no-api-key-title" className="text-sm font-medium text-soleur-text-primary">
            {title}
          </p>
          <p className="text-xs text-soleur-text-secondary">{body}</p>
        </div>
        <Link
          href={ctaHref}
          className="shrink-0 rounded-lg bg-soleur-accent-gold-fill px-3 py-1.5 text-xs font-medium text-soleur-text-on-accent hover:opacity-90"
        >
          {ctaLabel}
        </Link>
      </div>
    </div>
  );
}
