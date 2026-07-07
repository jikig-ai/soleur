"use client";

// The Workstream kanban board (client). SWR-fetches the read-only issue feed,
// renders 7 columns, a search field + New Issue trigger, and a detail Sheet
// driven by LOCAL STATE so open/close is INSTANT (no router.push navigation).
// URL ↔ drawer sync, three moving parts:
//   - OPEN (openIssue): pushState `?issue=<id>` — a real history entry so Back
//     can pop it. Local state still drives the drawer, so open stays instant.
//   - CLOSE (closeIssue): replaceState back to the bare path — strips the param
//     WITHOUT adding an entry (closing isn't a navigation you'd want to "undo").
//   - SYNC (popstate): re-reads ?issue from window.location.search on Back/
//     Forward, so popping the pushed entry (→ no ?issue) closes the drawer, and
//     deep-link/reload hydrates activeId from the same param on mount.
// Net effect: open/close are instant AND Back closes the drawer. Mutations
// (New Issue, status change) are optimistic + LOCAL ONLY (not persisted across
// reload) — surfaced honestly via the "Preview" banner + a note at each action.

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import useSWR from "swr";
import {
  COLUMNS,
  deriveFilterOptions,
  emptyFilters,
  hasActiveFilters,
  matchesFilters,
  matchesSearch,
  type WorkstreamFilters,
  type WorkstreamIssue,
  type WorkstreamStatus,
} from "@/lib/workstream";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import { ErrorCard } from "@/components/ui/error-card";
import { GoldButton } from "@/components/ui/gold-button";
import { RefreshIcon, SearchIcon, SpinnerIcon } from "@/components/icons";
import { FilterBar } from "./filter-bar";
import { IssueColumn } from "./issue-column";
import { IssueDetailSheet } from "./issue-detail-sheet";
import { NewIssueDialog } from "./new-issue-dialog";

type IssuesResponse = { issues: WorkstreamIssue[] };

// v2 key: the v1 key ("workstream:collapsed-columns") stored a now-defunct
// semantics where columns could be force-collapsed irrespective of the
// content-open-by-default rule; starting fresh avoids resurrecting any stale
// per-column collapse from that era. Empty columns are never written here — only
// the user's explicit collapse of a CONTENT column is persisted.
const COLLAPSED_STORAGE_KEY = "workstream:collapsed-columns-v2";

function readCollapsedColumns(): Set<WorkstreamStatus> {
  try {
    const raw = window.localStorage.getItem(COLLAPSED_STORAGE_KEY);
    if (!raw) return new Set();
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed as WorkstreamStatus[]);
  } catch {
    // private mode / quota / malformed — degrade to "nothing collapsed".
    return new Set();
  }
}

export function WorkstreamBoard() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const [search, setSearch] = useState("");
  const [filters, setFilters] = useState<WorkstreamFilters>(emptyFilters);
  const [newOpen, setNewOpen] = useState(false);

  // Drawer is driven by LOCAL state (instant open/close). Hydrate from the
  // ?issue= param on mount (deep-link/reload support).
  const [activeId, setActiveId] = useState<string | null>(() =>
    searchParams.get("issue"),
  );

  // Per-column collapse choice (content columns only), persisted in localStorage.
  // Content is OPEN by default — a status is in this set ONLY if the user
  // explicitly collapsed it. SSR-safe: read in an effect, never during render.
  const [collapsed, setCollapsed] = useState<Set<WorkstreamStatus>>(
    () => new Set(),
  );
  useEffect(() => {
    setCollapsed(readCollapsedColumns());
  }, []);

  // Reconcile the drawer with the URL on Back/Forward (and deep-link history).
  useEffect(() => {
    function onPopState() {
      const param = new URLSearchParams(window.location.search).get("issue");
      setActiveId(param);
    }
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  const { data, error, mutate, isValidating } = useSWR<IssuesResponse>(
    swrKeys.workstreamIssues(),
    jsonFetcher,
  );
  const issues = data?.issues;

  // Revalidate from the server (the ErrorCard retry AND the Refresh button).
  // Filters + search live in React state untouched by mutate(), so they survive
  // the refetch automatically (D6). When a revalidation fails while we still
  // hold data, SWR keeps `data` and sets `error` — that `error && data` pair is
  // the "couldn't refresh, showing last loaded" signal below, and SWR clears
  // `error` on the next success so the notice can never outlive the failure.
  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  // A failed REFRESH (vs a failed first load) is "error present BUT stale data
  // retained" — surface an honest inline notice without discarding the board.
  const refreshFailed = error != null && data != null;

  const resetFilters = useCallback(() => {
    setFilters(emptyFilters());
    setSearch("");
  }, []);

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

  // Open is INSTANT (local state); we pushState a `?issue=` entry so Back pops
  // it and the popstate listener clears the drawer (vs replaceState, which left
  // no entry to pop — Back then navigated off the board).
  const openIssue = useCallback(
    (id: string) => {
      setActiveId(id);
      try {
        window.history.pushState(
          {},
          "",
          `${pathname}?issue=${encodeURIComponent(id)}`,
        );
      } catch {
        /* history unavailable — local state still drives the drawer */
      }
    },
    [pathname],
  );
  // Close strips the param WITHOUT adding a history entry (replaceState) — an
  // explicit close isn't a navigation you'd want to "undo" via Forward.
  const closeIssue = useCallback(() => {
    setActiveId(null);
    try {
      window.history.replaceState({}, "", pathname);
    } catch {
      /* history unavailable — local state still drives the drawer */
    }
  }, [pathname]);

  // Toggle a content column's collapse choice and persist it. Empty columns are
  // collapsed by IssueColumn regardless and never reach this handler (they render
  // no toggle), so the persisted set only ever holds user-collapsed CONTENT
  // columns.
  const toggleCollapse = useCallback((status: WorkstreamStatus) => {
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(status)) next.delete(status);
      else next.add(status);
      try {
        window.localStorage.setItem(
          COLLAPSED_STORAGE_KEY,
          JSON.stringify([...next]),
        );
      } catch {
        /* localStorage unavailable — in-memory toggle still works this session */
      }
      return next;
    });
  }, []);

  // Faceted filter options derive from the FULL loaded set (stable, no thrash).
  const filterOptions = useMemo(
    () => deriveFilterOptions(issues ?? []),
    [issues],
  );

  // Compose: text search AND the four filter dimensions, over the loaded set.
  const filtered = useMemo(
    () =>
      (issues ?? []).filter(
        (i) => matchesSearch(i, search) && matchesFilters(i, filters),
      ),
    [issues, search, filters],
  );

  const anyActive = hasActiveFilters(filters, search);

  const selected =
    activeId && issues
      ? (issues.find((i) => i.id === activeId) ?? null)
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

      {/* Top bar: search + filters + Reset/Refresh + New Issue (rendered in
          every non-error state so the surface is never stranded). */}
      <div className="mb-5 flex flex-wrap items-center gap-2">
        <label className="relative flex items-center">
          <SearchIcon className="pointer-events-none absolute left-3 h-4 w-4 text-soleur-text-tertiary" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search issues…"
            aria-label="Search issues"
            className="w-56 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 py-2 pl-9 pr-3 text-sm text-soleur-text-primary placeholder:text-soleur-text-tertiary focus:border-soleur-text-muted focus:outline-none"
          />
        </label>
        <FilterBar
          options={filterOptions}
          filters={filters}
          onChange={setFilters}
        />
        <div className="ml-auto flex items-center gap-2">
          <button
            type="button"
            onClick={resetFilters}
            disabled={!anyActive}
            className="flex items-center gap-1.5 rounded-lg border border-soleur-border-default bg-transparent px-3 py-2 text-sm font-medium text-soleur-text-secondary transition-colors hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-40"
          >
            Reset filters
          </button>
          <button
            type="button"
            onClick={refetch}
            disabled={isValidating}
            aria-label="Refresh"
            className="flex items-center gap-1.5 rounded-lg border border-soleur-border-default bg-transparent px-3 py-2 text-sm font-medium text-soleur-text-secondary transition-colors hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isValidating ? (
              <SpinnerIcon className="h-4 w-4" />
            ) : (
              <RefreshIcon className="h-4 w-4" />
            )}
            {isValidating ? "Refreshing…" : "Refresh"}
          </button>
          <GoldButton onClick={() => setNewOpen(true)} data-tour-id="action:new-issue">+ New Issue</GoldButton>
        </div>
      </div>
      {refreshFailed ? (
        <p className="mb-3 text-xs text-amber-500/90" role="status">
          Couldn&apos;t refresh — showing the last loaded issues.
        </p>
      ) : null}

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
        <NoResults onReset={resetFilters} />
      ) : (
        <div className="flex gap-3 overflow-x-auto pb-4">
          {COLUMNS.map((column) => (
            <IssueColumn
              key={column.status}
              column={column}
              issues={filtered.filter((i) => i.status === column.status)}
              onOpen={openIssue}
              collapsed={collapsed.has(column.status)}
              onToggleCollapse={toggleCollapse}
            />
          ))}
        </div>
      )}

      <IssueDetailSheet
        open={activeId != null}
        issue={selected}
        loading={activeId != null && issues == null && !error}
        notFound={activeId != null && issues != null && selected == null}
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
        No issues to display
      </p>
      <p className="mt-1 text-xs text-soleur-text-tertiary">
        Issues sync from your connected GitHub repo.
      </p>
      <div className="mt-4 flex justify-center">
        <GoldButton onClick={onNew}>+ New Issue</GoldButton>
      </div>
    </div>
  );
}

function NoResults({ onReset }: { onReset: () => void }) {
  return (
    <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 py-16 text-center">
      <p className="text-sm text-soleur-text-secondary">
        No issues match your filters or search.
      </p>
      <button
        type="button"
        onClick={onReset}
        className="mt-3 rounded-lg border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:text-soleur-text-primary"
      >
        Reset filters
      </button>
    </div>
  );
}
