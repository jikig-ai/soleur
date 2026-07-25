"use client";

import { useState, useEffect, useCallback } from "react";
import type { GrantorDelegation } from "@/server/byok-delegation-ui-resolver";
import { useIsMobile } from "@/hooks/use-is-mobile";

interface DelegationFundedPaneProps {
  workspaceId: string;
  flagEnabled: boolean;
}

export function DelegationFundedPane({ workspaceId, flagEnabled }: DelegationFundedPaneProps) {
  if (!flagEnabled) return null;

  return <FundedPaneInner workspaceId={workspaceId} />;
}

function formatUsd(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function formatLastRun(lastInvocationAt: GrantorDelegation["lastInvocationAt"]): string {
  return lastInvocationAt
    ? new Date(lastInvocationAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    : "—";
}

function FundedPaneInner({ workspaceId }: { workspaceId: string }) {
  const isMobile = useIsMobile();
  const [delegations, setDelegations] = useState<GrantorDelegation[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch(`/api/workspace/delegations?workspaceId=${encodeURIComponent(workspaceId)}`)
      .then((res) => res.json())
      .then((data) => {
        setDelegations(data.delegations ?? []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, [workspaceId]);

  const handleRevoke = useCallback(async (delegationId: string) => {
    if (!window.confirm("Revoke this delegation? The member will lose funded access immediately.")) {
      return;
    }
    const res = await fetch("/api/workspace/delegations", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ delegationId, reason: "grantor_revoke" }),
    });
    if (res.ok) {
      setDelegations((prev) => prev.filter((d) => d.id !== delegationId));
    }
  }, []);

  if (loading) return null;
  if (delegations.length === 0) return null;

  return (
    <section className="mt-8 rounded-lg border border-soleur-border-default">
      <div className="border-b border-soleur-border-default px-6 py-4">
        <h2 className="text-base font-semibold text-soleur-text-primary">Funded for Others</h2>
        <p className="mt-0.5 text-xs text-soleur-text-muted">
          Members running on your API key via BYOK delegation.
        </p>
      </div>
      {isMobile ? (
        <div className="space-y-3 p-3">
          {delegations.map((d) => (
            <div
              key={d.id}
              className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3"
            >
              <div className="min-w-0">
                <p className="min-w-0 truncate font-medium text-soleur-text-primary">
                  {d.granteeDisplayName}
                </p>
                <p className="mt-0.5 text-xs text-soleur-text-muted">
                  Running on your API key · BYOK delegation
                </p>
              </div>
              <div className="mt-3 grid grid-cols-2 gap-2">
                <div className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 p-2">
                  <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-muted">
                    Today
                  </p>
                  <p className="mt-0.5 text-sm font-semibold text-soleur-text-primary">
                    {formatUsd(d.todaySpentCents)}
                  </p>
                </div>
                <div className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 p-2">
                  <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-muted">
                    MTD
                  </p>
                  <p className="mt-0.5 text-sm font-semibold text-soleur-text-primary">
                    {formatUsd(d.mtdSpentCents)}
                  </p>
                </div>
                <div className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 p-2">
                  <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-muted">
                    Cap Left
                  </p>
                  <p className="mt-0.5 text-sm font-semibold text-soleur-accent-gold-text">
                    {formatUsd(d.capRemainingCents)}
                  </p>
                </div>
                <div className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 p-2">
                  <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-muted">
                    Last Run
                  </p>
                  <p className="mt-0.5 text-sm font-semibold text-soleur-text-secondary">
                    {formatLastRun(d.lastInvocationAt)}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => handleRevoke(d.id)}
                className="mt-3 flex min-h-11 w-full items-center justify-center rounded-md border border-red-400/40 text-sm font-medium text-red-400 hover:bg-soleur-bg-surface-2"
              >
                Revoke delegation
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="divide-y divide-soleur-border-default">
          <div className="grid grid-cols-[1fr_auto_auto_auto_auto_auto] items-center gap-4 px-6 py-2 text-xs font-medium uppercase tracking-wider text-soleur-text-muted">
            <span>Member</span>
            <span>Today</span>
            <span>MTD</span>
            <span>Cap Left</span>
            <span>Last Run</span>
            <span className="w-16" />
          </div>
          {delegations.map((d) => (
            <div
              key={d.id}
              className="grid grid-cols-[1fr_auto_auto_auto_auto_auto] items-center gap-4 px-6 py-3"
            >
              <span className="truncate text-sm text-soleur-text-primary">{d.granteeDisplayName}</span>
              <span className="text-xs text-soleur-text-secondary">{formatUsd(d.todaySpentCents)}</span>
              <span className="text-xs text-soleur-text-secondary">{formatUsd(d.mtdSpentCents)}</span>
              <span className="text-xs text-soleur-text-secondary">{formatUsd(d.capRemainingCents)}</span>
              <span className="text-xs text-soleur-text-muted">{formatLastRun(d.lastInvocationAt)}</span>
              <button
                type="button"
                onClick={() => handleRevoke(d.id)}
                className="rounded px-2 py-1 text-xs text-red-400 hover:bg-soleur-bg-surface-2"
              >
                Revoke
              </button>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
