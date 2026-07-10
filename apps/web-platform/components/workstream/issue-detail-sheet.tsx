"use client";

// Right slide-in detail drawer for a Workstream issue, rendered as a portal
// overlay (backdrop + right-aligned panel) so it floats over the board on every
// breakpoint — matching the approved mock. URL-driven open-state is owned by the
// board (?issue=<id>); this component renders the resolved issue, a loading
// state (deep-link before the feed resolves), or an "Issue not found" state, plus
// a status select that moves the card optimistically. Addendum: TWO distinct
// assignee rows — "Assignee (role)" (the role chip) and a "User" row (the
// specific person), the latter omitted cleanly when absent.
//
// Close affordances: X button, Esc, and backdrop click. Focus moves to the
// close button on open and returns to the opener (the card) on close.

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import {
  COLUMNS,
  creatorLabel,
  roleTitle,
  statusLabel,
  statusPillClass,
  type WorkstreamIssue,
  type WorkstreamStatus,
} from "@/lib/workstream";
import { AssigneeChip, UserAvatar } from "./assignee-chip";
import { PriorityPill } from "./priority-pill";
import { IssueConciergePanel } from "./issue-concierge-panel";

function formatDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function IssueDetailSheet({
  open,
  issue,
  notFound,
  loading = false,
  onClose,
  onChangeStatus,
}: {
  open: boolean;
  issue: WorkstreamIssue | null;
  notFound: boolean;
  loading?: boolean;
  onClose: () => void;
  onChangeStatus: (id: string, status: WorkstreamStatus) => void;
}) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const closeBtnRef = useRef<HTMLButtonElement | null>(null);

  // Esc closes; capture the opener and return focus to it on close.
  useEffect(() => {
    if (!open) return;
    const opener = document.activeElement as HTMLElement | null;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !e.defaultPrevented) onClose();
    };
    document.addEventListener("keydown", handler);
    const t = window.setTimeout(() => closeBtnRef.current?.focus(), 0);
    return () => {
      document.removeEventListener("keydown", handler);
      window.clearTimeout(t);
      opener?.focus?.();
    };
  }, [open, onClose]);

  if (!open || !mounted) return null;

  const ariaLabel = issue ? `Issue ${issue.id}` : "Issue detail";

  return createPortal(
    <div className="fixed inset-0 z-50">
      <div
        className="absolute inset-0 bg-black/40"
        aria-hidden="true"
        onClick={onClose}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        className="absolute right-0 top-0 flex h-full w-full max-w-[440px] flex-col border-l border-soleur-border-default bg-soleur-bg-base shadow-2xl"
      >
        {loading ? (
          <div
            className="flex flex-1 items-center justify-center p-6"
            aria-label="Loading issue"
          >
            <div className="h-24 w-full animate-pulse rounded-lg bg-soleur-bg-surface-1/40" />
          </div>
        ) : notFound || !issue ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 p-6 text-center">
            <p className="text-sm text-soleur-text-secondary">Issue not found</p>
            <button
              ref={closeBtnRef}
              type="button"
              onClick={onClose}
              className="rounded-lg border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:text-soleur-text-primary"
            >
              Back to board
            </button>
          </div>
        ) : (
          <div className="flex min-h-0 flex-1 flex-col">
            {/* Header */}
            <div className="flex items-start justify-between gap-3 border-b border-soleur-border-default p-4">
              <div className="min-w-0">
                <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-tertiary">
                  {issue.id}
                </p>
                <h2 className="mt-1 text-base font-medium text-soleur-text-primary">
                  {issue.title}
                </h2>
              </div>
              <button
                ref={closeBtnRef}
                type="button"
                onClick={onClose}
                aria-label="Close"
                className="shrink-0 rounded p-1 text-soleur-text-muted transition-colors hover:text-soleur-text-primary"
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              </button>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto p-4">
              {/* Detail rows */}
              <dl className="space-y-3 text-sm">
                <Row label="Status">
                  <div className="flex items-center gap-2">
                    <span className={statusPillClass(issue.status)}>
                      {statusLabel(issue.status)}
                    </span>
                    <select
                      aria-label="Change status"
                      value={issue.status}
                      onChange={(e) =>
                        onChangeStatus(
                          issue.id,
                          e.target.value as WorkstreamStatus,
                        )
                      }
                      className="rounded border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1 text-xs text-soleur-text-primary focus:outline-none"
                    >
                      {COLUMNS.map((c) => (
                        <option key={c.status} value={c.status}>
                          {c.label}
                        </option>
                      ))}
                    </select>
                  </div>
                </Row>

                <Row label="Assignee (role)">
                  <span className="flex items-center gap-2">
                    <AssigneeChip role={issue.assigneeRole} />
                    <span className="text-soleur-text-secondary">
                      {roleTitle(issue.assigneeRole)}
                    </span>
                  </span>
                </Row>

                {issue.user && (
                  <Row label="User">
                    <span className="flex items-center gap-2">
                      <UserAvatar user={issue.user} />
                      <span className="text-soleur-text-secondary">
                        {issue.user.name}
                      </span>
                    </span>
                  </Row>
                )}

                {issue.creator && (
                  <Row label="Created by">
                    <span className="text-soleur-text-secondary">
                      {creatorLabel(issue.creator)}
                    </span>
                  </Row>
                )}

                <Row label="Priority">
                  <PriorityPill priority={issue.priority} />
                </Row>

                <Row label="Created">
                  <span className="text-soleur-text-secondary">
                    {formatDate(issue.createdAt)}
                  </span>
                </Row>
                <Row label="Updated">
                  <span className="text-soleur-text-secondary">
                    {formatDate(issue.updatedAt)}
                  </span>
                </Row>
              </dl>

              {/* Non-persistence note at the moment of action. */}
              <p className="mt-3 text-xs text-soleur-text-tertiary">
                Preview — status changes aren&apos;t saved yet.
              </p>

              {/* Description */}
              <section className="mt-6">
                <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-soleur-text-tertiary">
                  Description
                </h3>
                <div className="text-sm text-soleur-text-secondary">
                  <MarkdownRenderer content={issue.description} />
                </div>
              </section>

              {/* Decision Making (Concierge) */}
              <IssueConciergePanel />
            </div>
          </div>
        )}
      </div>
    </div>,
    document.body,
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-soleur-text-tertiary">{label}</dt>
      <dd className="text-right">{children}</dd>
    </div>
  );
}
