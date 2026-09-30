"use client";

// Unified severity-ranked inbox surface (feat-severity-ranked-inbox #6007).
// Client component rendered inside a <Suspense> by the Server page at
// app/(dashboard)/dashboard/inbox. Consumes GET /api/inbox (which merges
// inbox_item + email_triage_items and owns the pin/severity ordering) and
// renders two groups — NEEDS YOU (action_required) over GOOD TO KNOW
// (attention/info) — dispatching each row to EmailTriageRow (email) or
// InboxItemRow (native) by source. Items render in the order the API returns
// them (statutory pinned first) — never re-sorted; only partitioned into the
// two groups (order preserved within each). The Active / Archived tabs drive
// the ?status=archived query param so the view is deep-linkable.
//
// Bulk archive (feat-inbox-bulk-archive #9284): Active-tab rows carry a
// sibling checkbox (never nested — the rows' role="button" keydown eats
// bubbled Space). A "Select all" strip under each group header operates on
// that section's ARCHIVABLE rendered rows only; ineligible rows get a
// disabled checkbox + reason. The bulk bar confirms via ResponsiveModal and
// POSTs once to /api/inbox/bulk-archive — the server loops the existing
// per-id RPCs and returns per-item outcomes, rendered as an honest split in
// the result line above the list.

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { usePendingRouter } from "@/hooks/use-pending-router";
import useSWR, { useSWRConfig } from "swr";
import { EmailTriageRow } from "@/components/inbox/email-triage-row";
import { InboxItemRow } from "@/components/inbox/inbox-item-row";
import { Button } from "@/components/ui/button";
import { ResponsiveModal } from "@/components/ui/responsive-modal";
import { ErrorCard } from "@/components/ui/error-card";
import { RefreshShimmer } from "@/components/ui/refresh-shimmer";
import { StaleRefreshBar } from "@/components/ui/stale-refresh-bar";
import { usePendingAction } from "@/hooks/use-pending-action";
import { useRowSelection } from "@/hooks/use-row-selection";
import { swrKeys } from "@/lib/swr-config";
import {
  archiveEligibility,
  keyOf,
  REASON_COPY,
  type BulkItemRef,
} from "@/lib/inbox-archive-eligibility";
import {
  partitionForDisplay,
  type MergedInboxItem,
} from "@/lib/inbox-severity";

export async function fetchMergedInbox([, status]: readonly [
  string,
  string,
]): Promise<MergedInboxItem[]> {
  const res = await fetch(
    `/api/inbox${status === "archived" ? "?status=archived" : ""}`,
  );
  if (!res.ok) throw new Error(`inbox ${res.status}`);
  const body = (await res.json()) as { items: MergedInboxItem[] };
  // Render in API order — the route pins non-archived statutory first
  // (uncapped); never re-sort or a running statutory clock could fall out of
  // view. The surface only PARTITIONS into the two groups.
  return body.items ?? [];
}

function Row({
  item,
  onChanged,
}: {
  item: MergedInboxItem;
  onChanged: () => void;
}) {
  return item.kind === "email" ? (
    <EmailTriageRow item={item.email} onChanged={onChanged} />
  ) : (
    <InboxItemRow item={item.inbox} onChanged={onChanged} />
  );
}

/** Row + sibling selection checkbox. The checkbox is NOT inside the row:
 * row containers are role="button" and navigate on bubbled Enter/Space — a
 * nested checkbox's Space would navigate instead of toggle. */
function SelectableRow({
  item,
  checked,
  onToggle,
  onChanged,
}: {
  item: MergedInboxItem;
  checked: boolean;
  onToggle: (ref: BulkItemRef) => void;
  onChanged: () => void;
}) {
  const reason = archiveEligibility(item);
  const archivable = reason === "ok";
  return (
    <div className="flex items-start gap-2">
      <div className="flex w-4 shrink-0 flex-col items-center pt-4">
        <input
          type="checkbox"
          aria-label={`Select ${item.kind === "email" ? "email" : "item"}`}
          disabled={!archivable}
          title={archivable ? undefined : REASON_COPY[reason]}
          checked={checked}
          onChange={() => onToggle(item)}
          className="h-4 w-4 accent-soleur-accent-gold disabled:opacity-40"
        />
      </div>
      <div className="min-w-0 flex-1">
        <Row item={item} onChanged={onChanged} />
        {!archivable && (
          <p className="mt-0.5 px-1 text-[11px] text-soleur-text-secondary">
            {REASON_COPY[reason]}
          </p>
        )}
      </div>
    </div>
  );
}

/** Per-section "Select all" strip — its own line under the group header,
 * operating on the section's archivable rendered rows. */
function SelectAllStrip({
  items,
  selected,
  onToggleSection,
}: {
  items: MergedInboxItem[];
  selected: ReadonlySet<string>;
  onToggleSection: (items: MergedInboxItem[]) => void;
}) {
  const archivable = items.filter((i) => archiveEligibility(i) === "ok");
  const count = archivable.filter((i) => selected.has(keyOf(i))).length;
  const indeterminate = count > 0 && count < archivable.length;
  return (
    <label className="flex items-center gap-2 px-1 py-1.5 text-xs font-medium text-soleur-text-secondary">
      <input
        type="checkbox"
        aria-label="Select all"
        disabled={archivable.length === 0}
        checked={archivable.length > 0 && count === archivable.length}
        ref={(el) => {
          if (el) el.indeterminate = indeterminate;
        }}
        onChange={() => onToggleSection(items)}
        className="h-4 w-4 accent-soleur-accent-gold disabled:opacity-40"
      />
      Select all
      {archivable.length > 0 && count > 0 && (
        <span className="text-soleur-text-secondary/70">
          ({count} of {archivable.length})
        </span>
      )}
    </label>
  );
}

function GroupHeader({ title, helper }: { title: string; helper: string }) {
  return (
    <div className="mb-2 mt-6 first:mt-0">
      <h2 className="text-xs font-semibold uppercase tracking-wider text-soleur-accent-gold-text">
        {title}
      </h2>
      <p className="mt-0.5 text-xs text-soleur-text-secondary">{helper}</p>
    </div>
  );
}

function EmptyState({
  primary,
  secondary,
}: {
  primary: string;
  secondary: string;
}) {
  return (
    <div className="py-8">
      <p className="text-sm font-medium text-soleur-text-primary">{primary}</p>
      <p className="mt-1 text-sm text-soleur-text-secondary">{secondary}</p>
    </div>
  );
}

type BulkOutcome = "archived" | "guarded" | "not_found" | "conflict" | "error";
interface BulkResult extends BulkItemRef {
  outcome: BulkOutcome;
  reason?: string;
}

/** Split result copy — archived vs guarded vs handled-elsewhere vs failed,
 * never lumped into one count (honest partial-failure copy per spec). */
function resultLine(results: BulkResult[]): string {
  const c = { archived: 0, guarded: 0, handled: 0, error: 0 };
  for (const r of results) {
    if (r.outcome === "archived") c.archived++;
    else if (r.outcome === "guarded") c.guarded++;
    else if (r.outcome === "error") c.error++;
    else c.handled++;
  }
  const parts: string[] = [];
  if (c.archived) parts.push(`Archived ${c.archived}.`);
  if (c.guarded) parts.push(`${c.guarded} can't be archived until handled.`);
  if (c.handled) parts.push(`${c.handled} were already handled elsewhere.`);
  if (c.error)
    parts.push(
      `${c.error} failed — try again (some items may already have been archived).`,
    );
  return parts.join(" ");
}

export function InboxSurface() {
  const router = usePendingRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const archived = searchParams.get("status") === "archived";
  const status = archived ? "archived" : "active";

  const {
    data: items,
    error,
    isValidating,
    mutate,
  } = useSWR(swrKeys.inbox(status), fetchMergedInbox);
  // Unbound mutate — refreshes BOTH the active list and any cached archived
  // list (the hook-bound mutate only hits the mounted key).
  const { mutate: globalMutate } = useSWRConfig();

  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  const selectTab = (toArchived: boolean) => {
    router.push(toArchived ? `${pathname}?status=archived` : pathname);
  };

  // Selection is active-tab-only (rendered as children of renderActive only).
  const selection = useRowSelection(archived ? undefined : items);
  const { selected, toggle, toggleSection, clear, setKeys } = selection;
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const resultRef = useRef<HTMLParagraphElement>(null);
  const titleId = useId();

  // Escape clears the selection — gated on the confirm dialog being closed
  // (ResponsiveModal handles its own Esc; don't let one keystroke do both).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !confirmOpen) {
        setResult(null);
        clear();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [confirmOpen, clear]);

  // The next USER selection change supersedes the previous result line.
  const userToggle = useCallback(
    (ref: BulkItemRef) => {
      setResult(null);
      toggle(ref);
    },
    [toggle],
  );
  const userToggleSection = useCallback(
    (section: MergedInboxItem[]) => {
      setResult(null);
      toggleSection(section);
    },
    [toggleSection],
  );
  const userClear = useCallback(() => {
    setResult(null);
    clear();
  }, [clear]);

  const bulkArchive = usePendingAction(async () => {
    const items = [...selected].map((key) => {
      const idx = key.indexOf(":");
      return { kind: key.slice(0, idx) as "inbox" | "email", id: key.slice(idx + 1) };
    });
    const res = await fetch("/api/inbox/bulk-archive", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ items }),
    });
    if (res.status === 429) {
      setResult("Too many actions — wait a moment and try again.");
      return;
    }
    if (!res.ok) {
      setResult("Something went wrong — try again.");
      return;
    }
    const { results } = (await res.json()) as { results: BulkResult[] };
    const archivedKeys = new Set(
      results.filter((r) => r.outcome === "archived").map(keyOf),
    );
    // Residual selection: non-archived ids stay selected so the set that
    // still needs attention is self-identifying after the refetch.
    setKeys([...selected].filter((k) => !archivedKeys.has(k)));
    setConfirmOpen(false);
    setResult(resultLine(results));
    // Refresh the active list AND any cached archived list (the nav badge
    // shares swrKeys.inbox("active")).
    void globalMutate(swrKeys.inbox("active"));
    void globalMutate(swrKeys.inbox("archived"));
    // Move focus to the outcome so it's announced + discoverable.
    requestAnimationFrame(() => resultRef.current?.focus());
  });

  const part = items ? partitionForDisplay(items) : null;

  return (
    <div>
      <RefreshShimmer active={isValidating && items !== undefined} />
      <div
        role="tablist"
        data-tour-id="action:inbox-triage"
        className="mb-5 flex gap-5 border-b border-soleur-border-default"
      >
        <TabButton active={!archived} onClick={() => selectTab(false)}>
          Active
        </TabButton>
        <TabButton active={archived} onClick={() => selectTab(true)}>
          Archived
        </TabButton>
      </div>

      {error && items !== undefined && <StaleRefreshBar onRetry={refetch} />}

      {result && (
        <p
          ref={resultRef}
          role="status"
          tabIndex={-1}
          className="mb-3 rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm text-soleur-text-primary"
        >
          {result}
        </p>
      )}

      <div
        role="tabpanel"
        aria-label={archived ? "Archived items" : "Active items"}
      >
        {error && items === undefined ? (
          <ErrorCard
            title="Failed to load inbox"
            message="Something went wrong loading your inbox. Please try again."
            onRetry={refetch}
          />
        ) : items === undefined || part === null ? (
          <p className="py-8 text-sm text-soleur-text-secondary">Loading…</p>
        ) : archived ? (
          renderArchived(part, refetch)
        ) : (
          renderActive(part, refetch, {
            selected,
            toggle: userToggle,
            toggleSection: userToggleSection,
          })
        )}
      </div>

      {selected.size > 0 && (
        <div className="sticky bottom-0 mt-4 flex items-center justify-between gap-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-3">
          <span className="text-sm text-soleur-text-primary">
            {selected.size} selected
          </span>
          <div className="flex items-center gap-2">
            <Button variant="ghost" type="button" onClick={userClear}>
              Clear
            </Button>
            <Button
              variant="gold"
              type="button"
              onClick={() => setConfirmOpen(true)}
            >
              Archive {selected.size} selected
            </Button>
          </div>
        </div>
      )}

      <ResponsiveModal
        open={confirmOpen}
        onClose={bulkArchive.pending ? undefined : () => setConfirmOpen(false)}
        desktopMaxWidth="max-w-md"
        aria-labelledby={titleId}
      >
        <div aria-busy={bulkArchive.pending || undefined}>
          <h2
            id={titleId}
            className="mb-2 text-lg font-semibold text-soleur-text-primary"
          >
            Archive {selected.size} items?
          </h2>
          <p className="mb-5 text-sm text-soleur-text-secondary">
            They'll stay in the Archived tab — nothing is deleted.
          </p>
          <div className="flex justify-end gap-2">
            <Button
              variant="ghost"
              type="button"
              disabled={bulkArchive.pending}
              onClick={() => setConfirmOpen(false)}
            >
              Cancel
            </Button>
            <Button
              variant="gold"
              type="button"
              disabled={bulkArchive.pending}
              loading={bulkArchive.pending}
              onClick={() => bulkArchive.run()}
            >
              Archive
            </Button>
          </div>
        </div>
      </ResponsiveModal>
    </div>
  );
}

interface SelectionApi {
  selected: ReadonlySet<string>;
  toggle: (ref: BulkItemRef) => void;
  toggleSection: (items: MergedInboxItem[]) => void;
}

function renderActive(
  part: ReturnType<typeof partitionForDisplay>,
  refetch: () => void,
  selection: SelectionApi,
) {
  const { needsYouVisible, needsYouOverflow, goodToKnow } = part;

  if (needsYouVisible.length === 0 && goodToKnow.length === 0) {
    return (
      <EmptyState
        primary="You're all caught up."
        secondary="Your organization is handling things. Anything that needs you will show up here."
      />
    );
  }

  return (
    <>
      <GroupHeader title="NEEDS YOU" helper="A few things are waiting on your call." />
      {needsYouVisible.length > 0 ? (
        <div className="space-y-2">
          <SelectAllStrip
            items={needsYouVisible}
            selected={selection.selected}
            onToggleSection={selection.toggleSection}
          />
          {needsYouVisible.map((m) => (
            <SelectableRow
              key={m.id}
              item={m}
              checked={selection.selected.has(keyOf(m))}
              onToggle={selection.toggle}
              onChanged={refetch}
            />
          ))}
          {needsYouOverflow > 0 && (
            <p className="px-1 py-2 text-xs font-medium text-soleur-text-secondary">
              +{needsYouOverflow} more need you
            </p>
          )}
        </div>
      ) : (
        <EmptyState
          primary="Nothing needs your call right now."
          secondary="The updates below are just to keep you in the loop."
        />
      )}

      {goodToKnow.length > 0 && (
        <>
          <GroupHeader
            title="GOOD TO KNOW"
            helper="Updates from your organization. Nothing to do here."
          />
          <div className="space-y-2">
            <SelectAllStrip
              items={goodToKnow}
              selected={selection.selected}
              onToggleSection={selection.toggleSection}
            />
            {goodToKnow.map((m) => (
              <SelectableRow
                key={m.id}
                item={m}
                checked={selection.selected.has(keyOf(m))}
                onToggle={selection.toggle}
                onChanged={refetch}
              />
            ))}
          </div>
        </>
      )}
    </>
  );
}

function renderArchived(
  part: ReturnType<typeof partitionForDisplay>,
  refetch: () => void,
) {
  const { needsYouVisible, needsYouOverflow, goodToKnow } = part;

  if (needsYouVisible.length === 0 && goodToKnow.length === 0) {
    return (
      <EmptyState
        primary="Nothing here yet."
        secondary="Items you've handled or set aside are kept here."
      />
    );
  }

  // Archived is grouped the same way (Appendix B); archived items are never
  // pinned, so any leftover action_required simply groups under NEEDS YOU.
  // No checkboxes on this tab — bulk archive is an Active-tab action.
  return (
    <>
      {needsYouVisible.length > 0 && (
        <>
          <GroupHeader title="NEEDS YOU" helper="Handled items that needed your call." />
          <div className="space-y-2">
            {needsYouVisible.map((m) => (
              <Row key={m.id} item={m} onChanged={refetch} />
            ))}
            {needsYouOverflow > 0 && (
              <p className="px-1 py-2 text-xs font-medium text-soleur-text-secondary">
                +{needsYouOverflow} more
              </p>
            )}
          </div>
        </>
      )}
      {goodToKnow.length > 0 && (
        <>
          <GroupHeader
            title="GOOD TO KNOW"
            helper="Updates you've set aside."
          />
          <div className="space-y-2">
            {goodToKnow.map((m) => (
              <Row key={m.id} item={m} onChanged={refetch} />
            ))}
          </div>
        </>
      )}
    </>
  );
}

function TabButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      data-button-exempt="role=tab + aria-selected toggle tab strip"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`-mb-px border-b-2 pb-2 text-sm ${
        active
          ? "border-soleur-text-primary text-soleur-text-primary"
          : "border-transparent text-soleur-text-secondary hover:text-soleur-text-primary"
      }`}
    >
      {children}
    </button>
  );
}
