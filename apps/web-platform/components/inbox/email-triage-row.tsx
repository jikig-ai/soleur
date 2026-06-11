"use client";

// feat-operator-inbox-delegation Phase 5b — email-triage inbox row.
//
// INVARIANT — plain-text rendering only. `subject`, `sender`, and `summary`
// are ATTACKER-CONTROLLED (arbitrary inbound email). They pass through
// `sanitizeDisplayString` (bidi/Cf strip — an RLO in a subject visually
// spoofs the row — plus control strip + length cap) and render as plain
// React text nodes ONLY:
//   - never `markdown-renderer.tsx` (would turn `[x](url)` into a live link),
//   - never `dangerouslySetInnerHTML`,
//   - never an <a>/href built from item content (the only navigation is a
//     router push to `/dashboard/inbox/email/{id}` built from the
//     server-generated DB uuid, not from any email-derived value).
// The component test (test/components/inbox/email-triage-row.test.tsx)
// asserts zero anchors and a neutralized bidi fixture — keep it in lockstep.

import { useState } from "react";
import { useRouter } from "next/navigation";
import { sanitizeDisplayString } from "@/lib/sanitize-display";
import { relativeTime } from "@/lib/relative-time";
import { triagePillClass, triagePillLabel } from "@/lib/email-triage-display";
import {
  STATUTORY_RULES,
  formatDueDate,
} from "@/lib/email-triage/statutory-rules";

export interface EmailTriageItem {
  id: string;
  message_id: string | null;
  sender: string;
  subject: string;
  summary: string | null;
  mail_class: string | null;
  statutory_class: string | null;
  rule_id: string | null;
  status: string;
  status_changed_at: string | null;
  acknowledged_at: string | null;
  received_at: string;
  created_at: string;
}

interface EmailTriageRowProps {
  item: EmailTriageItem;
  /** Called after a successful acknowledge/archive — the dashboard refetches. */
  onChanged?: () => void;
}

export function EmailTriageRow({ item, onChanged }: EmailTriageRowProps) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const isStatutory = item.statutory_class !== null;
  // Pinned treatment only while unacknowledged — acknowledgment unpins but
  // the item stays visible with its clock.
  const isPinned = isStatutory && item.status === "new";
  const isAcknowledged = isStatutory && item.status === "acknowledged";
  const isLegalReview = !isStatutory && item.mail_class === "legal-review";

  const subject = sanitizeDisplayString(item.subject);
  const sender = sanitizeDisplayString(item.sender);
  const summary = item.summary ? sanitizeDisplayString(item.summary) : null;

  // Registry lookup — the statutory-rules module is the single
  // system-of-record for clocks; no due-date columns exist in the DB.
  const rule = item.rule_id
    ? STATUTORY_RULES.find((r) => r.ruleId === item.rule_id) ?? null
    : null;
  const dueText = isStatutory && rule
    ? formatDueDate(item.received_at, rule.dueRule)
    : null;

  const pillLabel = triagePillLabel(item);
  const pillClass = triagePillClass(item);

  const containerClass = isPinned
    ? "border-red-500/30 bg-red-500/[0.06] hover:bg-red-500/[0.1]"
    : isLegalReview
      ? "border-amber-500/30 bg-amber-500/[0.06] hover:bg-amber-500/[0.1]"
      : "border-soleur-border-default bg-soleur-bg-surface-1/50 hover:bg-soleur-bg-surface-2/50";

  async function runAction(action: "acknowledge" | "archive") {
    if (pending) return;
    setPending(true);
    setActionError(null);
    try {
      const res = await fetch(`/api/inbox/emails/${item.id}/${action}`, {
        method: "POST",
      });
      if (res.ok) {
        onChanged?.();
      } else if (res.status === 409) {
        // Row already transitioned elsewhere (another tab/device) — the
        // refetch reconciles the stale row, so report the change upward.
        onChanged?.();
      } else {
        setActionError(
          action === "acknowledge"
            ? "Couldn't acknowledge — try again."
            : "Couldn't archive — try again.",
        );
      }
    } catch {
      // Network drop: surface it; the operator can retry.
      setActionError("Network error — try again.");
    } finally {
      setPending(false);
    }
  }

  const navigate = () => router.push(`/dashboard/inbox/email/${item.id}`);

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={navigate}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          navigate();
        }
      }}
      className={`flex w-full min-h-[44px] cursor-pointer items-start gap-3 rounded-lg border p-3 text-left transition-colors md:gap-4 md:p-4 ${containerClass}`}
    >
      <div className="flex w-full flex-col gap-1.5">
        <div className="flex items-center justify-between gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <span
              className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${pillClass}`}
            >
              {pillLabel}
            </span>
            {isPinned && (
              <span className="inline-flex items-center rounded-full bg-red-500/15 px-2 py-0.5 text-[10px] font-medium text-red-500">
                Pinned
              </span>
            )}
          </div>
          <span className="shrink-0 text-xs tabular-nums text-soleur-text-muted">
            {relativeTime(item.received_at)}
          </span>
        </div>

        <p className="text-sm font-medium text-soleur-text-primary">{subject}</p>

        {summary && (
          <p className="text-xs text-soleur-text-secondary">{summary}</p>
        )}

        <p className="text-xs text-soleur-text-muted">{sender}</p>

        {dueText && (
          <p
            className={`text-xs font-medium ${isPinned ? "text-red-500" : "text-soleur-text-secondary"}`}
          >
            {dueText}
          </p>
        )}

        {isLegalReview && (
          <p className="text-xs font-medium text-amber-400">
            Rules did not match — verify against the original, normally
            retained in the Proton ops@ mailbox
          </p>
        )}

        {isAcknowledged && (
          <p className="text-xs text-soleur-text-secondary">
            Acknowledged — workflow state, not legal resolution
          </p>
        )}

        <div className="flex items-center justify-end gap-2">
          {actionError && (
            <p role="alert" className="text-xs font-medium text-red-500">
              {actionError}
            </p>
          )}
          {isStatutory && item.status === "new" && (
            <button
              type="button"
              aria-label="Acknowledge email"
              disabled={pending}
              onClick={(e) => {
                e.stopPropagation();
                void runAction("acknowledge");
              }}
              className="min-h-[32px] rounded-md border border-red-500/30 px-3 py-1 text-xs font-medium text-red-500 transition-colors hover:bg-red-500/10 disabled:opacity-50"
            >
              Acknowledge
            </button>
          )}
          {!isStatutory && item.status !== "archived" && (
            <button
              type="button"
              aria-label="Archive email"
              disabled={pending}
              onClick={(e) => {
                e.stopPropagation();
                void runAction("archive");
              }}
              className="min-h-[32px] rounded-md border border-soleur-border-default px-3 py-1 text-xs font-medium text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 disabled:opacity-50"
            >
              Archive
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
