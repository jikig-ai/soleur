"use client";

// "New Issue" dialog. Title is required; the card defaults to Backlog + Medium
// priority + Unassigned. On submit the issue is inserted OPTIMISTICALLY atop
// Backlog (local cache only — never persisted across reload, surfaced via the
// note below). A user-created card NEVER claims "Live" (spec-flow #14 — `live`
// is left unset and the status is Backlog).

import { useEffect, useRef, useState } from "react";
import { GoldButton } from "@/components/ui/gold-button";
import type { WorkstreamIssue } from "@/lib/workstream";

function newIssueId(): string {
  return `SOLAA-${Date.now().toString().slice(-4)}`;
}

export function NewIssueDialog({
  open,
  onClose,
  onCreate,
}: {
  open: boolean;
  onClose: () => void;
  onCreate: (issue: WorkstreamIssue) => void;
}) {
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (open) {
      setTitle("");
      setDescription("");
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  const canSubmit = title.trim().length > 0;

  function handleSubmit(e?: React.FormEvent) {
    e?.preventDefault();
    if (!canSubmit) return;
    const now = new Date().toISOString();
    onCreate({
      id: newIssueId(),
      title: title.trim(),
      description: description.trim(),
      status: "backlog",
      priority: "medium",
      assigneeRole: null,
      createdAt: now,
      updatedAt: now,
      // No `live` — user-created cards never claim Live.
    });
    onClose();
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="New issue"
        className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-6 shadow-xl"
      >
        <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">
          New issue
        </h2>
        <form onSubmit={handleSubmit}>
          <label
            htmlFor="new-issue-title"
            className="mb-1 block text-sm text-soleur-text-secondary"
          >
            Title <span className="text-red-400">*</span>
          </label>
          <input
            id="new-issue-title"
            ref={inputRef}
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Issue title"
            aria-required="true"
            className="mb-4 w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-tertiary focus:outline-none"
          />

          <label
            htmlFor="new-issue-description"
            className="mb-1 block text-sm text-soleur-text-secondary"
          >
            Description
          </label>
          <textarea
            id="new-issue-description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
            placeholder="Optional"
            className="mb-3 w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-tertiary focus:outline-none"
          />

          <p className="mb-4 text-xs text-soleur-text-tertiary">
            Adds to Backlog. Preview — new issues aren&apos;t saved yet and reset
            on reload.
          </p>

          <div className="flex flex-wrap justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-2 text-sm font-medium text-soleur-text-primary"
            >
              Cancel
            </button>
            <GoldButton type="submit" disabled={!canSubmit}>
              Create issue
            </GoldButton>
          </div>
        </form>
      </div>
    </div>
  );
}
