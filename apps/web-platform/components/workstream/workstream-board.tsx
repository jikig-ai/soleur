"use client";

// The Workstream kanban board (client). SWR-fetches the issue feed + board
// precedence meta, renders 7 columns, a search field + New Issue trigger, and a
// detail Sheet.
//
// Writes are REAL now (ADR-109) — Create / status-change / close / reopen POST/
// PATCH the audited write endpoints. Write-integrity (the load-bearing rule at
// single-user threshold): the optimistic cache edit is RECONCILED from GitHub's
// returned canonical issue on success (mutate the SWR key — ADR-067, NOT
// router.refresh alone), and ROLLED BACK on failure with a retryable surface.
// A read-only-install 403 flips the board to a read-only state (honest hint, no
// 403 retry loop); a 429 surfaces a distinct "slow down" toast.
//
// URL <-> drawer sync (unchanged): OPEN pushState ?issue=<id>; CLOSE replaceState
// to the bare path; popstate re-reads ?issue on Back/Forward + hydrates on mount.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
import { MobileBoard } from "./mobile-board";
import { IssueDetailSheet } from "./issue-detail-sheet";
import { NewIssueDialog } from "./new-issue-dialog";
import {
  NEW_ISSUE_DIALOG_EVENT,
  type NewIssueDialogEventDetail,
} from "./new-issue-dialog-event";
import {
  createIssueRequest,
  patchIssueRequest,
  isReadOnly,
  isRateLimited,
  type CreateIssueBody,
  type PatchIssueBody,
} from "./workstream-writes";

interface BoardMeta {
  onKanbanOrg: boolean;
  projectWritable: boolean;
}
type IssuesResponse = { issues: WorkstreamIssue[]; board?: BoardMeta };

const COLLAPSED_STORAGE_KEY = "workstream:collapsed-columns-v2";

// Monotonic optimistic-card id (local only; replaced by the real number on ack).
let tempSeq = 0;
function newTempId(): string {
  tempSeq += 1;
  return `SOLAA-N${tempSeq}`;
}

function readCollapsedColumns(): Set<WorkstreamStatus> {
  try {
    const raw = window.localStorage.getItem(COLLAPSED_STORAGE_KEY);
    if (!raw) return new Set();
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed as WorkstreamStatus[]);
  } catch {
    return new Set();
  }
}

/** The numeric issue number from a card id, or null for an optimistic temp card
 *  (which cannot be PATCHed — it has no real GitHub number yet). */
function issueNumberOf(id: string): number | null {
  const n = Number(id);
  return Number.isInteger(n) && n > 0 ? n : null;
}

export function WorkstreamBoard() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const [search, setSearch] = useState("");
  const [filters, setFilters] = useState<WorkstreamFilters>(emptyFilters);
  const [newOpen, setNewOpen] = useState(false);
  const [readOnly, setReadOnly] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  useEffect(() => {
    function onTourToggle(e: Event) {
      const detail = (e as CustomEvent<NewIssueDialogEventDetail>).detail;
      setNewOpen(Boolean(detail?.open));
    }
    window.addEventListener(NEW_ISSUE_DIALOG_EVENT, onTourToggle);
    return () => window.removeEventListener(NEW_ISSUE_DIALOG_EVENT, onTourToggle);
  }, []);

  const [activeId, setActiveId] = useState<string | null>(() =>
    searchParams.get("issue"),
  );

  const [collapsed, setCollapsed] = useState<Set<WorkstreamStatus>>(
    () => new Set(),
  );
  useEffect(() => {
    setCollapsed(readCollapsedColumns());
  }, []);

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
  const board = data?.board;
  // Board precedence: for the dogfood org repo the Project board Status WINS
  // over labels on read, and the label→board mirror needs a still-ungranted
  // write scope — so a label-driven column move would snap back. Disable those
  // moves while the grant is absent (lifts automatically once granted).
  const boardPrecedence = Boolean(board?.onKanbanOrg && !board?.projectWritable);

  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  const refreshFailed = error != null && data != null;
  // First-load degrade (502 before any data): the board shows <ErrorCard>. Guard
  // the TOOLBAR New-Issue button (the only create trigger rendered in this state)
  // so an optimistic create can't flip `data` non-null and resurrect the false
  // <EmptyState> when its POST then fails against the same cold backend (rollback
  // → { issues: [] }). The EmptyState button needs no guard — it only renders
  // when `data != null`, where `firstLoadFailed` is definitionally false.
  const firstLoadFailed = error != null && data == null;

  const resetFilters = useCallback(() => {
    setFilters(emptyFilters());
    setSearch("");
  }, []);

  // Surface a failure honestly. A 403 flips the board read-only (no retry loop);
  // a 429 is a distinct slow-down; anything else is a retryable board toast.
  const surfaceWriteError = useCallback((e: unknown) => {
    if (isReadOnly(e)) {
      setReadOnly(true);
      setToast("Read-only access — this install can't write issues.");
    } else if (isRateLimited(e)) {
      setToast("Slowing down — too many changes at once. Try again in a moment.");
    } else {
      setToast("Couldn't save that change. Please try again.");
    }
  }, []);

  // CREATE — optimistic temp card atop Backlog, reconcile with the returned real
  // issue on success, remove it on failure (the dialog shows the error/retry).
  const createIssue = useCallback(
    async (input: CreateIssueBody): Promise<void> => {
      const tempId = newTempId();
      const now = new Date().toISOString();
      const temp: WorkstreamIssue = {
        id: tempId,
        title: input.title,
        description: input.body ?? "",
        status: input.status ?? "backlog",
        priority: "medium",
        assigneeRole: null,
        createdAt: now,
        updatedAt: now,
      };
      void mutate(
        (cur) => ({ issues: [temp, ...(cur?.issues ?? [])], board: cur?.board }),
        { revalidate: false },
      );
      try {
        const returned = await createIssueRequest(input);
        void mutate(
          (cur) => ({
            issues: (cur?.issues ?? []).map((i) =>
              i.id === tempId ? returned : i,
            ),
            board: cur?.board,
          }),
          { revalidate: false },
        );
      } catch (e) {
        void mutate(
          (cur) => ({
            issues: (cur?.issues ?? []).filter((i) => i.id !== tempId),
            board: cur?.board,
          }),
          { revalidate: false },
        );
        surfaceWriteError(e);
        throw e; // let the dialog keep the form + show inline retry
      }
    },
    [mutate, surfaceWriteError],
  );

  // STATUS change (also close: status=done + reason) — optimistic move, reconcile
  // from the returned canonical issue, roll back on failure.
  const changeStatus = useCallback(
    async (
      id: string,
      status: WorkstreamStatus,
      stateReason?: "completed" | "not_planned",
    ): Promise<void> => {
      const number = issueNumberOf(id);
      if (number === null) return; // optimistic temp card — nothing to persist
      const prev = issues?.find((i) => i.id === id);
      void mutate(
        (cur) =>
          cur
            ? {
                ...cur,
                issues: cur.issues.map((i) =>
                  i.id === id
                    ? { ...i, status, updatedAt: new Date().toISOString() }
                    : i,
                ),
              }
            : cur,
        { revalidate: false },
      );
      try {
        const returned = await patchIssueRequest(number, {
          status,
          ...(stateReason ? { state_reason: stateReason } : {}),
        });
        void mutate(
          (cur) =>
            cur
              ? {
                  ...cur,
                  issues: cur.issues.map((i) =>
                    i.id === returned.id ? returned : i,
                  ),
                }
              : cur,
          { revalidate: false },
        );
      } catch (e) {
        if (prev) {
          void mutate(
            (cur) =>
              cur
                ? {
                    ...cur,
                    issues: cur.issues.map((i) => (i.id === id ? prev : i)),
                  }
                : cur,
            { revalidate: false },
          );
        }
        surfaceWriteError(e);
      }
    },
    [issues, mutate, surfaceWriteError],
  );

  // TITLE edit — optimistic, reconcile from the returned canonical issue.
  const updateTitle = useCallback(
    async (id: string, title: string): Promise<void> => {
      const number = issueNumberOf(id);
      if (number === null) return;
      const prev = issues?.find((i) => i.id === id);
      void mutate(
        (cur) =>
          cur
            ? {
                ...cur,
                issues: cur.issues.map((i) =>
                  i.id === id ? { ...i, title } : i,
                ),
              }
            : cur,
        { revalidate: false },
      );
      try {
        const returned = await patchIssueRequest(number, { title });
        void mutate(
          (cur) =>
            cur
              ? {
                  ...cur,
                  issues: cur.issues.map((i) =>
                    i.id === returned.id ? returned : i,
                  ),
                }
              : cur,
          { revalidate: false },
        );
      } catch (e) {
        if (prev) {
          void mutate(
            (cur) =>
              cur
                ? {
                    ...cur,
                    issues: cur.issues.map((i) => (i.id === id ? prev : i)),
                  }
                : cur,
            { revalidate: false },
          );
        }
        surfaceWriteError(e);
        throw e; // let the inline editor keep edit mode for retry
      }
    },
    [issues, mutate, surfaceWriteError],
  );

  // FIELDS edit (body/labels/assignees/milestone) — optimistic merge of the
  // provided fields, reconcile from the returned canonical issue, roll back on
  // failure. Mirrors updateTitle's shape; the optimistic shape is passed in
  // because the milestone patch is a number while the card holds { number, title }.
  const updateFields = useCallback(
    async (
      id: string,
      optimistic: Partial<WorkstreamIssue>,
      patch: PatchIssueBody,
    ): Promise<void> => {
      const number = issueNumberOf(id);
      if (number === null) return;
      const prev = issues?.find((i) => i.id === id);
      void mutate(
        (cur) =>
          cur
            ? {
                ...cur,
                issues: cur.issues.map((i) =>
                  i.id === id ? { ...i, ...optimistic } : i,
                ),
              }
            : cur,
        { revalidate: false },
      );
      try {
        const returned = await patchIssueRequest(number, patch);
        void mutate(
          (cur) =>
            cur
              ? {
                  ...cur,
                  issues: cur.issues.map((i) =>
                    i.id === returned.id ? returned : i,
                  ),
                }
              : cur,
          { revalidate: false },
        );
      } catch (e) {
        if (prev) {
          void mutate(
            (cur) =>
              cur
                ? {
                    ...cur,
                    issues: cur.issues.map((i) => (i.id === id ? prev : i)),
                  }
                : cur,
            { revalidate: false },
          );
        }
        surfaceWriteError(e);
        throw e; // let the inline editor keep edit mode for retry
      }
    },
    [issues, mutate, surfaceWriteError],
  );

  // REOPEN — PATCH state=open; the card leaves Done and lands where its surviving
  // labels derive. Reconcile from the returned canonical issue.
  const reopenIssue = useCallback(
    async (id: string): Promise<void> => {
      const number = issueNumberOf(id);
      if (number === null) return;
      try {
        const returned = await patchIssueRequest(number, { reopen: true });
        void mutate(
          (cur) =>
            cur
              ? {
                  ...cur,
                  issues: cur.issues.map((i) =>
                    i.id === returned.id ? returned : i,
                  ),
                }
              : cur,
          { revalidate: false },
        );
      } catch (e) {
        // Reopen makes NO optimistic pre-update (the card stays in Done until
        // the PATCH confirms), so there is nothing to roll back — do NOT call
        // mutate(undefined) here (it would blank the board to the skeleton with
        // no auto-recovery). Just surface the retryable error.
        surfaceWriteError(e);
      }
    },
    [issues, mutate, surfaceWriteError],
  );

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
  const closeIssue = useCallback(() => {
    setActiveId(null);
    try {
      window.history.replaceState({}, "", pathname);
    } catch {
      /* history unavailable */
    }
  }, [pathname]);

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
        /* localStorage unavailable */
      }
      return next;
    });
  }, []);

  const filterOptions = useMemo(
    () => deriveFilterOptions(issues ?? []),
    [issues],
  );

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
      <div className="mb-4 flex items-center gap-2">
        <h1 className="text-2xl font-medium text-soleur-text-primary">
          Workstream
        </h1>
        {readOnly ? (
          <span className="rounded-full border border-amber-500/40 bg-amber-500/10 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-amber-500/90">
            Read-only
          </span>
        ) : null}
      </div>
      <p className="mb-5 text-xs text-soleur-text-tertiary">
        Issues are backed by your connected GitHub repo.
      </p>

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
          <GoldButton
            onClick={() => setNewOpen(true)}
            disabled={readOnly || firstLoadFailed}
            data-tour-id="action:new-issue"
          >
            + New Issue
          </GoldButton>
        </div>
      </div>
      {refreshFailed ? (
        <p className="mb-3 text-xs text-amber-500/90" role="status">
          Couldn&apos;t refresh — showing the last loaded issues.
        </p>
      ) : null}
      {readOnly ? (
        <p className="mb-3 text-xs text-amber-500/90" role="status">
          Read-only access — connect a repo whose GitHub App install has issue
          write permission to create or move issues.
        </p>
      ) : null}
      {toast ? (
        <div
          role="alert"
          className="mb-3 flex items-center justify-between gap-3 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs text-amber-500/90"
        >
          <span>{toast}</span>
          <button
            type="button"
            onClick={() => setToast(null)}
            className="rounded border border-amber-500/40 px-2 py-0.5 font-medium hover:bg-amber-500/10"
          >
            Dismiss
          </button>
        </div>
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
        <EmptyState onNew={() => setNewOpen(true)} disabled={readOnly} />
      ) : filtered.length === 0 ? (
        <NoResults onReset={resetFilters} />
      ) : (
        <>
          {/* Desktop: the 7-column horizontal board. Mobile (below md): a
              status-selector + single full-width column (MobileBoard). Both
              consume the same `filtered` array + `openIssue`, so filters/search,
              ?issue URL sync, and write handling are shared. */}
          <div className="hidden gap-3 overflow-x-auto pb-4 md:flex">
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
          <MobileBoard issues={filtered} onOpen={openIssue} className="md:hidden" />
        </>
      )}

      <IssueDetailSheet
        open={activeId != null}
        issue={selected}
        loading={activeId != null && issues == null && !error}
        notFound={activeId != null && issues != null && selected == null}
        readOnly={readOnly}
        boardPrecedence={boardPrecedence}
        onKanbanOrg={Boolean(board?.onKanbanOrg)}
        onClose={closeIssue}
        onChangeStatus={changeStatus}
        onReopen={reopenIssue}
        onUpdateTitle={updateTitle}
        onUpdateFields={updateFields}
      />

      <NewIssueDialog
        open={newOpen}
        onClose={() => setNewOpen(false)}
        onSubmit={createIssue}
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

function EmptyState({
  onNew,
  disabled,
}: {
  onNew: () => void;
  disabled?: boolean;
}) {
  return (
    <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 py-16 text-center">
      <p className="text-sm text-soleur-text-secondary">No issues to display</p>
      <p className="mt-1 text-xs text-soleur-text-tertiary">
        Issues sync from your connected GitHub repo.
      </p>
      <div className="mt-4 flex justify-center">
        <GoldButton onClick={onNew} disabled={disabled}>
          + New Issue
        </GoldButton>
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
