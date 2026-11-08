"use client";

// Founder legal-text row (CPO ruling P3, CTO ruling T7, 2026-11-08; Ref #12197; wireframe: frame 23 in
// knowledge-base/product/design/approvals/approval-request.pen). One row per declared legal text, derived by the server.
//
// INVARIANTS
//   - No checkbox, no Archive, no Mark done, no state call: the row is derived data with no inbox_item behind it, so
//     /api/inbox/[id]/state would 404 and /api/inbox/bulk-archive answers 400 for its kind. The ONLY action is navigation.
//   - The destination is built from the key AFTER it passes the registry key shape (never a path from a free string); a key
//     that fails the check renders non-navigating.
//   - Plain text only; every word comes from the deck (`lib/legal-inbox-copy.ts`), none is written here.

import { usePendingRouter } from "@/hooks/use-pending-router";
import { LEGAL_KEY_RE } from "@/lib/legal-acceptance-wire";
import { legalInboxWords } from "@/lib/legal-inbox-copy";
import type { InboxItemSeverity, MergedInboxItem } from "@/lib/inbox-severity";

export type LegalInboxItem = Extract<MergedInboxItem, { kind: "legal" }>;

const DOT_CLASS: Record<InboxItemSeverity, string> = {
  action_required: "bg-red-500",
  attention: "bg-amber-500",
  info: "bg-soleur-text-muted",
};

const CONTAINER_CLASS: Record<InboxItemSeverity, string> = {
  action_required: "border-red-500/30 bg-red-500/[0.06] hover:bg-red-500/[0.1]",
  attention: "border-amber-500/30 bg-amber-500/[0.06] hover:bg-amber-500/[0.1]",
  info: "border-soleur-border-default bg-soleur-bg-surface-1/50 hover:bg-soleur-bg-surface-2/50",
};

/** Where the row leads, or null for a key that is not registry-shaped. */
export function legalInboxHref(key: string): string | null {
  return LEGAL_KEY_RE.test(key) ? `/dashboard/approvals/legal/${key}` : null;
}

export function LegalInboxRow({ item }: { item: LegalInboxItem }) {
  const router = usePendingRouter();
  const words = legalInboxWords(item.legal);
  const href = legalInboxHref(item.legal.key);

  const navigate = () => {
    if (href) router.push(href);
  };

  return (
    <div
      data-testid="legal-inbox-row"
      data-state={item.legal.state}
      role={href ? "button" : undefined}
      tabIndex={href ? 0 : undefined}
      onClick={href ? navigate : undefined}
      onKeyDown={
        href
          ? (e) => {
              if (e.target !== e.currentTarget) return;
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                navigate();
              }
            }
          : undefined
      }
      className={`flex w-full min-h-[44px] items-start gap-3 rounded-lg border p-3 text-left transition-colors md:gap-4 md:p-4 ${
        href ? "cursor-pointer" : "cursor-default"
      } ${CONTAINER_CLASS[item.severity]}`}
    >
      <span aria-hidden="true" className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${DOT_CLASS[item.severity]}`} />
      <div className="flex w-full min-w-0 flex-col gap-1.5">
        <p className="min-w-0 text-sm font-medium text-soleur-text-primary [overflow-wrap:anywhere]">{words.title}</p>
        <div className="flex flex-wrap items-center gap-2 text-xs text-soleur-text-secondary">
          <span className="rounded-md bg-soleur-bg-surface-2/70 px-2 py-0.5 font-medium text-soleur-accent-gold-text">{words.badge}</span>
          {words.openUntil && (
            <span data-testid="legal-row-open-until" className="rounded-md bg-soleur-bg-surface-2/70 px-2 py-0.5 font-medium text-soleur-accent-gold-text">
              {words.openUntil}
            </span>
          )}
          <span className="[overflow-wrap:anywhere]">{words.meta}</span>
        </div>
      </div>
    </div>
  );
}
