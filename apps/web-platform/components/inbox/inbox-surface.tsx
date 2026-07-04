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

import { useCallback } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import useSWR from "swr";
import { EmailTriageRow } from "@/components/inbox/email-triage-row";
import { InboxItemRow } from "@/components/inbox/inbox-item-row";
import { ErrorCard } from "@/components/ui/error-card";
import { RefreshShimmer } from "@/components/ui/refresh-shimmer";
import { StaleRefreshBar } from "@/components/ui/stale-refresh-bar";
import { swrKeys } from "@/lib/swr-config";
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

export function InboxSurface() {
  const router = useRouter();
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

  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  const selectTab = (toArchived: boolean) => {
    router.push(toArchived ? `${pathname}?status=archived` : pathname);
  };

  const part = items ? partitionForDisplay(items) : null;

  return (
    <div>
      <RefreshShimmer active={isValidating && items !== undefined} />
      <div
        role="tablist"
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
          renderActive(part, refetch)
        )}
      </div>
    </div>
  );
}

function renderActive(
  part: ReturnType<typeof partitionForDisplay>,
  refetch: () => void,
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
          {needsYouVisible.map((m) => (
            <Row key={m.id} item={m} onChanged={refetch} />
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
            {goodToKnow.map((m) => (
              <Row key={m.id} item={m} onChanged={refetch} />
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
