"use client";

// PR-I (#4078) — Template authorization row with founder-initiated revoke.
//
// Sibling to ScopeGrantRow (same directory). Renders one
// template_authorizations row + a Revoke button. Plan §Phase 7 + Sharp
// Edges:
//   - Pessimistic update: button disabled during in-flight.
//   - router.refresh() on success (server-component parent re-fetches).
//   - Inline error message on failure with retry.

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { humanTitle } from "@/lib/messages/action-class-copy";

export interface TemplateAuthorizationRowProps {
  id: string;
  templateHash: string;
  actionClass: string;
  authorizedAt: string;
  expiresAt: string;
  softReconfirmAt: string;
  maxSends: number;
  sendsUsed: number;
}

export function TemplateAuthorizationRow({
  templateHash,
  actionClass,
  authorizedAt,
  expiresAt,
  softReconfirmAt,
  maxSends,
  sendsUsed,
}: TemplateAuthorizationRowProps) {
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function onRevoke() {
    setError(null);
    startTransition(async () => {
      try {
        const res = await fetch("/api/template-authorizations/revoke", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            template_hash: templateHash,
            reason: "founder_revoked",
          }),
        });
        if (!res.ok) {
          setError(`Failed to revoke (${res.status})`);
          return;
        }
        router.refresh();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Network error");
      }
    });
  }

  const sendsRemaining = Math.max(0, maxSends - sendsUsed);
  const truncatedHash = templateHash.slice(0, 12);
  const expiresLabel = new Date(expiresAt).toLocaleDateString();
  const authorizedLabel = new Date(authorizedAt).toLocaleDateString();
  // softReconfirmAt is surfaced as metadata but does not gate UI in v1.
  void softReconfirmAt;

  return (
    <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4">
      <header className="flex items-start justify-between gap-4">
        <div className="min-w-0 flex-1">
          <h3 className="font-medium text-soleur-text-primary">
            {humanTitle(actionClass)}
          </h3>
          <p className="mt-1 text-xs text-soleur-text-muted">
            Authorized {authorizedLabel} • Expires {expiresLabel} •{" "}
            {sendsRemaining} of {maxSends} sends remaining
          </p>
          <code
            className="mt-2 block text-xs text-soleur-text-muted"
            title={templateHash}
          >
            {truncatedHash}…
          </code>
        </div>
        <button
          type="button"
          onClick={onRevoke}
          disabled={isPending}
          className="rounded-md px-3 py-1.5 text-xs text-soleur-text-danger hover:bg-soleur-bg-surface-2 disabled:opacity-50"
          aria-label={`Revoke template authorization for ${humanTitle(actionClass)}`}
        >
          {isPending ? "Revoking…" : "Revoke"}
        </button>
      </header>
      {error ? (
        <p
          role="alert"
          className="mt-3 text-sm text-soleur-text-danger"
        >
          {error}
        </p>
      ) : null}
    </div>
  );
}
