"use client";

// Right slide-in detail drawer for a Workstream issue (portal overlay). Renders
// the resolved issue, a loading state, or an "Issue not found" state.
//
// Writes are REAL (ADR-109): inline title edit → PATCH {title}; the Status
// control → PATCH {status} (the ONE server primitive); Close → PATCH {status:
// done, state_reason}; Reopen → PATCH {reopen}. All are optimistic + reconciled
// by the board. Gating:
//   - readOnly (an issues:read-only install): every write affordance is disabled
//     with a hint — no 403 retry loop.
//   - boardPrecedence (dogfood org repo, org-projects:write ungranted): label-
//     driven column moves are disabled (they'd snap back); Close/Reopen still
//     work (state changes mirror). The "Syncing to Project board…" note renders
//     ONLY for the org-board repo — a user's own repo has no Project board.

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
  readOnly = false,
  boardPrecedence = false,
  onKanbanOrg = false,
  onClose,
  onChangeStatus,
  onReopen,
  onUpdateTitle,
}: {
  open: boolean;
  issue: WorkstreamIssue | null;
  notFound: boolean;
  loading?: boolean;
  readOnly?: boolean;
  boardPrecedence?: boolean;
  onKanbanOrg?: boolean;
  onClose: () => void;
  onChangeStatus: (
    id: string,
    status: WorkstreamStatus,
    stateReason?: "completed" | "not_planned",
  ) => void | Promise<void>;
  onReopen: (id: string) => void | Promise<void>;
  onUpdateTitle: (id: string, title: string) => void | Promise<void>;
}) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const closeBtnRef = useRef<HTMLButtonElement | null>(null);

  // Inline title-edit state (reset whenever the active issue changes).
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleDraft, setTitleDraft] = useState("");
  const [closeMenuOpen, setCloseMenuOpen] = useState(false);
  const issueId = issue?.id ?? null;
  useEffect(() => {
    setEditingTitle(false);
    setCloseMenuOpen(false);
  }, [issueId]);

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
  const isClosed = issue?.status === "done";
  const statusDisabled = readOnly || boardPrecedence;

  function startEditTitle() {
    if (!issue || readOnly) return;
    setTitleDraft(issue.title);
    setEditingTitle(true);
  }

  async function saveTitle() {
    if (!issue) return;
    const next = titleDraft.trim();
    if (!next || next === issue.title) {
      setEditingTitle(false);
      return;
    }
    try {
      await onUpdateTitle(issue.id, next);
      setEditingTitle(false);
    } catch {
      // keep edit mode open so the user can retry (board toasted + rolled back)
    }
  }

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
              <div className="min-w-0 flex-1">
                <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-tertiary">
                  {issue.id}
                </p>
                {editingTitle ? (
                  <div className="mt-1 flex flex-col gap-2">
                    <input
                      aria-label="Edit title"
                      value={titleDraft}
                      onChange={(e) => setTitleDraft(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") {
                          e.preventDefault();
                          void saveTitle();
                        } else if (e.key === "Escape") {
                          e.preventDefault();
                          e.stopPropagation();
                          setEditingTitle(false);
                        }
                      }}
                      autoFocus
                      className="w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-2 py-1 text-base text-soleur-text-primary focus:outline-none"
                    />
                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={() => void saveTitle()}
                        className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-2.5 py-1 text-xs font-medium text-soleur-text-primary"
                      >
                        Save
                      </button>
                      <button
                        type="button"
                        onClick={() => setEditingTitle(false)}
                        className="rounded-md px-2.5 py-1 text-xs text-soleur-text-secondary hover:text-soleur-text-primary"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="mt-1 flex items-start gap-2">
                    <h2 className="text-base font-medium text-soleur-text-primary">
                      {issue.title}
                    </h2>
                    {!readOnly ? (
                      <button
                        type="button"
                        aria-label="Edit title"
                        onClick={startEditTitle}
                        className="mt-0.5 shrink-0 rounded p-0.5 text-soleur-text-muted transition-colors hover:text-soleur-text-primary"
                      >
                        <svg
                          width="14"
                          height="14"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M12 20h9" />
                          <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4Z" />
                        </svg>
                      </button>
                    ) : null}
                  </div>
                )}
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
              <dl className="space-y-3 text-sm">
                <Row label="Status">
                  <div className="flex items-center gap-2">
                    <span className={statusPillClass(issue.status)}>
                      {statusLabel(issue.status)}
                    </span>
                    <select
                      aria-label="Change status"
                      value={issue.status}
                      disabled={statusDisabled}
                      onChange={(e) =>
                        onChangeStatus(
                          issue.id,
                          e.target.value as WorkstreamStatus,
                        )
                      }
                      className="rounded border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1 text-xs text-soleur-text-primary focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
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

              {/* Board-precedence / sync notes — org-board repo only. */}
              {onKanbanOrg && boardPrecedence ? (
                <p className="mt-3 text-xs text-soleur-text-tertiary">
                  Column moves sync to the Project board and are paused until the
                  board write grant lands. Close and Reopen still work.
                </p>
              ) : onKanbanOrg ? (
                <p className="mt-3 text-xs text-soleur-text-tertiary">
                  Status changes sync to the Project board asynchronously.
                </p>
              ) : null}
              {readOnly ? (
                <p className="mt-3 text-xs text-amber-500/90" role="status">
                  Read-only access — this install can&apos;t modify issues.
                </p>
              ) : null}

              {/* Close / Reopen — always available (state changes mirror). */}
              {!readOnly ? (
                <div className="mt-4">
                  {isClosed ? (
                    <button
                      type="button"
                      onClick={() => void onReopen(issue.id)}
                      className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-1.5 text-sm font-medium text-soleur-text-primary transition-colors hover:border-soleur-text-muted"
                    >
                      Reopen issue
                    </button>
                  ) : closeMenuOpen ? (
                    <div className="flex flex-col gap-2 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 p-3">
                      <p className="text-xs text-soleur-text-tertiary">
                        Close as…
                      </p>
                      <div className="flex flex-wrap gap-2">
                        <button
                          type="button"
                          onClick={() => {
                            setCloseMenuOpen(false);
                            void onChangeStatus(issue.id, "done", "completed");
                          }}
                          className="rounded-md border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-primary hover:border-soleur-text-muted"
                        >
                          Completed
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            setCloseMenuOpen(false);
                            void onChangeStatus(issue.id, "done", "not_planned");
                          }}
                          className="rounded-md border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-primary hover:border-soleur-text-muted"
                        >
                          Not planned
                        </button>
                        <button
                          type="button"
                          onClick={() => setCloseMenuOpen(false)}
                          className="rounded-md px-3 py-1.5 text-sm text-soleur-text-secondary hover:text-soleur-text-primary"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : (
                    <button
                      type="button"
                      onClick={() => setCloseMenuOpen(true)}
                      className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-1.5 text-sm font-medium text-soleur-text-primary transition-colors hover:border-soleur-text-muted"
                    >
                      Close issue
                    </button>
                  )}
                </div>
              ) : null}

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
