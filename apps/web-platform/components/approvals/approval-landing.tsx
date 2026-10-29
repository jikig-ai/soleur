"use client";

// Away-user landing surface for one approval request (#4672, wireframe 07). Renders the SAME card as the chat thread
// (layout="landing": full-width 48px buttons, Approve above Deny) and sends the decision over HTTP. It holds only the
// server's last word about the row; the card changes state when that word changes, never optimistically.

import { useCallback, useState } from "react";
import { ApprovalRequestCard } from "@/components/chat/approval-request-card";
import { formatExpiryDateTimeTz } from "@/lib/approval-copy";
import { inferAgentWaiting } from "@/lib/approval-card-state";
import type { ApprovalCardView, ApprovalDecideOutcomeWire, ApprovalDecisionWire, ApprovalWireStatus } from "@/lib/types";

export interface ApprovalLandingRow {
  status: ApprovalWireStatus;
  expiresAt: string;
  createdAt: string;
  decidedAt: string | null;
  /** True when the viewer is the one who decided (drives "by you"). */
  decidedByViewer: boolean;
}

interface DecideResponse {
  outcome: ApprovalDecideOutcomeWire;
  approval: { status: ApprovalWireStatus; decided_at: string | null };
}

const OUTCOMES: readonly string[] = ["decided", "unchanged", "conflict", "expired", "closed"];
const STATUSES: readonly string[] = ["pending", "approved", "rejected", "expired", "consumed"];

function parseDecideResponse(v: unknown): DecideResponse | null {
  if (!v || typeof v !== "object") return null;
  const o = v as { outcome?: unknown; approval?: { status?: unknown; decided_at?: unknown } };
  if (typeof o.outcome !== "string" || !OUTCOMES.includes(o.outcome)) return null;
  if (!o.approval || typeof o.approval.status !== "string" || !STATUSES.includes(o.approval.status)) return null;
  const decidedAt = typeof o.approval.decided_at === "string" ? o.approval.decided_at : null;
  return {
    outcome: o.outcome as ApprovalDecideOutcomeWire,
    approval: { status: o.approval.status as ApprovalWireStatus, decided_at: decidedAt },
  };
}

export function ApprovalLanding({
  approvalId,
  view,
  initial,
  requestCount,
}: {
  approvalId: string;
  view: ApprovalCardView | null;
  initial: ApprovalLandingRow;
  requestCount: number;
}) {
  const [row, setRow] = useState(initial);
  const [outcome, setOutcome] = useState<ApprovalDecideOutcomeWire | undefined>(undefined);

  const onDecide = useCallback(
    async (decision: ApprovalDecisionWire): Promise<boolean> => {
      let res: Response;
      try {
        res = await fetch(`/api/approvals/${approvalId}/decide`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ decision }),
        });
      } catch {
        return false;
      }
      if (!res.ok) return false;
      const parsed = parseDecideResponse(await res.json().catch(() => null));
      if (!parsed) return false;
      setRow((r) => ({
        ...r,
        status: parsed.approval.status,
        decidedAt: parsed.approval.decided_at,
        decidedByViewer: parsed.outcome === "decided" || parsed.outcome === "unchanged" ? true : r.decidedByViewer,
      }));
      setOutcome(parsed.outcome);
      return true;
    },
    [approvalId],
  );

  const decidedLabel =
    row.decidedAt && row.status !== "expired"
      ? `${formatExpiryDateTimeTz(row.decidedAt)}${row.decidedByViewer ? " · by you" : ""}`
      : undefined;

  return (
    <ApprovalRequestCard
      layout="landing"
      approvalId={approvalId}
      view={view}
      status={row.status}
      expiresAt={row.expiresAt}
      requestCount={requestCount}
      viewerRole="owner"
      agentWaiting={inferAgentWaiting({ created_at: row.createdAt, decided_at: row.decidedAt }, Date.now())}
      decideOutcome={outcome}
      expiredAfterApproval={row.status === "expired" && row.decidedAt !== null}
      decidedLabel={decidedLabel}
      onDecide={onDecide}
    />
  );
}
