"use client";

// The Workstream kanban board (client). SWR-fetches the read-only seed feed,
// renders 7 columns, a search field + New Issue trigger, and a URL-driven
// detail Sheet (?issue=<id>, set/cleared via router.push so the browser Back
// button closes it — inbox precedent). Mutations (New Issue, status change) are
// optimistic + LOCAL ONLY (not persisted across reload) — surfaced honestly via
// the "Preview" banner + a note at the moment of each action.

import { useCallback, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import useSWR from "swr";
import { COLUMNS, type WorkstreamIssue, type WorkstreamStatus } from "@/lib/workstream";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import { ErrorCard } from "@/components/ui/error-card";
import { GoldButton } from "@/components/ui/gold-button";
import { SearchIcon } from "@/components/icons";
import { IssueColumn } from "./issue-column";
import { IssueDetailSheet } from "./issue-detail-sheet";
import { NewIssueDialog } from "./new-issue-dialog";

type IssuesResponse = { issues: WorkstreamIssue[] };

export function WorkstreamBoard() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const issueParam = searchParams.get("issue");

  const [search, setSearch] = useState("");
  const [newOpen, setNewOpen] = useState(false);

  const { data, error, mutate } = useSWR<IssuesResponse>(
    swrKeys.workstreamIssues(),
    jsonFetcher,
  );
  const issues = data?.issues;

  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  // Optimistic, LOCAL-ONLY insert atop Backlog (never persisted; revalidate
  // off so a background focus-revalidate doesn't drop it mid-session).
  const addIssue = useCallback(
    (issue: WorkstreamIssue) => {
      void mutate(
        (cur) => ({ issues: [issue, ...(cur?.issues ?? [])] }),
        { revalidate: false },
      );
    },
    [mutate],
  );

  // Optimistic, LOCAL-ONLY status move (counts recompute from cache).
  const changeStatus = useCallback(
    (id: string, status: WorkstreamStatus) => {
      void mutate(
        (cur) =>
          cur
            ? {
                issues: cur.issues.map((i) =>
                  i.id === id
                    ? { ...i, status, updatedAt: new Date().toISOString() }
                    : i,
                ),
              }
            : cur,
        { revalidate: false },
      );
    },
    [mutate],
  );

  const openIssue = useCallback(
    (id: string) => {
      router.push(`${pathname}?issue=${encodeURIComponent(id)}`);
    },
    [router, pathname],
  );
  const closeIssue = useCallback(() => {
    router.push(pathname);
  }, [router, pathname]);

  const q = search.trim().toLowerCase();
  const filtered = useMemo(
    () =>
      (issues ?? []).filter(
        (i) =>
          !q ||
          i.id.toLowerCase().includes(q) ||
          i.title.toLowerCase().includes(q),
      ),
    [issues, q],
  );

  const selected =
    issueParam && issues
      ? (issues.find((i) => i.id === issueParam) ?? null)
      : null;

  return (
    <div>
      {/* Honesty: board-level non-persistence notice (CPO P0). */}
      <div className="mb-4 flex items-center gap-2">
        <h1 className="text-2xl font-medium text-soleur-text-primary">
          Workstream
        </h1>
        <span className="rounded-full border border-amber-500/40 bg-amber-500/10 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-amber-500/90">
          Preview
        </span>
      </div>
      <p className="mb-5 text-xs text-soleur-text-tertiary">
        Preview — changes aren&apos;t saved yet.
      </p>

      {/* Top bar: search + New Issue (rendered in every non-error state so the
          surface is never stranded). */}
      <div className="mb-5 flex flex-wrap items-center gap-3">
        <label className="relative flex flex-1 items-center">
          <SearchIcon className="pointer-events-none absolute left-3 h-4 w-4 text-soleur-text-tertiary" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search issues…"
            aria-label="Search issues"
            className="w-full max-w-sm rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 py-2 pl-9 pr-3 text-sm text-soleur-text-primary placeholder:text-soleur-text-tertiary focus:border-soleur-text-muted focus:outline-none"
          />
        </label>
        <GoldButton onClick={() => setNewOpen(true)}>+ New Issue</GoldButton>
      </div>

      {error && !data ? (
        <ErrorCard
          title="Failed to load the board"
          message="Something went wrong loading your workstream. Please try again."
          onRetry={refetch}
        />
      ) : !data ? (
        <BoardSkeleton />
      ) : issues && issues.length === 0 ? (
        <EmptyState onNew={() => setNewOpen(true)} />
      ) : filtered.length === 0 ? (
        <NoResults query={search} onClear={() => setSearch("")} />
      ) : (
        <div className="flex gap-3 overflow-x-auto pb-4">
          {COLUMNS.map((column) => (
            <IssueColumn
              key={column.status}
              column={column}
              issues={filtered.filter((i) => i.status === column.status)}
              onOpen={openIssue}
            />
          ))}
        </div>
      )}

      <IssueDetailSheet
        open={issueParam != null}
        issue={selected}
        loading={issueParam != null && issues == null && !error}
        notFound={issueParam != null && issues != null && selected == null}
        onClose={closeIssue}
        onChangeStatus={changeStatus}
      />

      <NewIssueDialog
        open={newOpen}
        onClose={() => setNewOpen(false)}
        onCreate={addIssue}
      />
    </div>
  );
}

function BoardSkeleton() {
  return (
    <div className="flex gap-3 overflow-x-auto pb-4" aria-label="Loading">
      {COLUMNS.map((c) => (
        <div
          key={c.status}
          className="h-48 w-72 shrink-0 animate-pulse rounded-xl border border-soleur-border-default/60 bg-soleur-bg-surface-1/40"
        />
      ))}
    </div>
  );
}

function EmptyState({ onNew }: { onNew: () => void }) {
  return (
    <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 py-16 text-center">
      <p className="text-sm text-soleur-text-secondary">
        No issues on the board yet.
      </p>
      <div className="mt-4 flex justify-center">
        <GoldButton onClick={onNew}>+ New Issue</GoldButton>
      </div>
    </div>
  );
}

function NoResults({
  query,
  onClear,
}: {
  query: string;
  onClear: () => void;
}) {
  return (
    <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 py-16 text-center">
      <p className="text-sm text-soleur-text-secondary">
        No issues match “{query.trim()}”.
      </p>
      <button
        type="button"
        onClick={onClear}
        className="mt-3 rounded-lg border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:text-soleur-text-primary"
      >
        Clear search
      </button>
    </div>
  );
}
