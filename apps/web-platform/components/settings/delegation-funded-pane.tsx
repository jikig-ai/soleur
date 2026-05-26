"use client";

import { useState, useEffect, useCallback } from "react";
import type { GrantorDelegation } from "@/server/byok-delegation-ui-resolver";

interface DelegationFundedPaneProps {
  workspaceId: string;
  flagEnabled: boolean;
}

export function DelegationFundedPane({ workspaceId, flagEnabled }: DelegationFundedPaneProps) {
  if (!flagEnabled) return null;

  return <FundedPaneInner workspaceId={workspaceId} />;
}

function FundedPaneInner({ workspaceId }: { workspaceId: string }) {
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
            <span className="text-xs text-soleur-text-secondary">
              ${(d.todaySpentCents / 100).toFixed(2)}
            </span>
            <span className="text-xs text-soleur-text-secondary">
              ${(d.mtdSpentCents / 100).toFixed(2)}
            </span>
            <span className="text-xs text-soleur-text-secondary">
              ${(d.capRemainingCents / 100).toFixed(2)}
            </span>
            <span className="text-xs text-soleur-text-muted">
              {d.lastInvocationAt
                ? new Date(d.lastInvocationAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
                : "—"}
            </span>
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
    </section>
  );
}
