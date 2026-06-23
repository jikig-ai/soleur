"use client";

// Dedicated inbox surface (#5512). Client component rendered inside a
// <Suspense> boundary by the Server page at app/(dashboard)/dashboard/inbox.
// Reuses GET /api/inbox/emails (which owns the stub/probe/statutory-pin filter
// logic) and the EmailTriageRow component — no DB access here. The Active /
// Archived tabs drive the `?status=archived` query param so the view is
// shareable/deep-linkable; the active tab derives from the param, not local
// state. Items render in the order the API returns them (statutory pinned
// first) — never re-sorted.

import { useCallback } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import useSWR from "swr";
import {
  EmailTriageRow,
  type EmailTriageItem,
} from "@/components/inbox/email-triage-row";
import { ErrorCard } from "@/components/ui/error-card";
import { RefreshShimmer } from "@/components/ui/refresh-shimmer";
import { StaleRefreshBar } from "@/components/ui/stale-refresh-bar";
import { swrKeys } from "@/lib/swr-config";

async function fetchInboxItems([, status]: readonly [
  string,
  string,
]): Promise<EmailTriageItem[]> {
  const res = await fetch(
    `/api/inbox/emails${status === "archived" ? "?status=archived" : ""}`,
  );
  if (!res.ok) throw new Error(`inbox emails ${res.status}`);
  const body = (await res.json()) as { items: EmailTriageItem[] };
  // Render in API order — the route pins unacknowledged statutory rows first
  // (uncapped); never re-sort or a running statutory clock could fall out of
  // view.
  return body.items ?? [];
}

export function InboxSurface() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const archived = searchParams.get("status") === "archived";
  const status = archived ? "archived" : "active";

  // ADR-067: per-filter cache key (FR5) — Active and Archived cache under
  // distinct keys, so switching tabs renders cached-instant if previously
  // loaded. SWR's stale-while-revalidate gives an instant render on remount;
  // background revalidation never re-shows the first-load skeleton because the
  // loading gate is `!data` (GAP F), not `isValidating`.
  const {
    data: items,
    error,
    isValidating,
    mutate,
  } = useSWR(swrKeys.inboxEmails(status), fetchInboxItems);

  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  const selectTab = (toArchived: boolean) => {
    router.push(toArchived ? `${pathname}?status=archived` : pathname);
  };

  return (
    <div>
      {/* Ambient gold shimmer while revalidating a warm cache hit (Option A). */}
      <RefreshShimmer active={isValidating && items !== undefined} />
      {/* Tabs render in every state (including error) so the user is never
          stranded on a failed Archived view. */}
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

      {/* Stale-failure affordance: revalidation failed while stale data is
          still shown — keep the content, offer a retry (GAP #4 / AC8). */}
      {error && items !== undefined && <StaleRefreshBar onRetry={refetch} />}

      <div role="tabpanel" aria-label={archived ? "Archived items" : "Active items"}>
        {error && items === undefined ? (
          <ErrorCard
            title="Failed to load inbox"
            message="Something went wrong loading your inbox. Please try again."
            onRetry={refetch}
          />
        ) : items === undefined ? (
          <p className="py-8 text-sm text-soleur-text-secondary">Loading…</p>
        ) : items.length === 0 ? (
          <p className="py-8 text-sm text-soleur-text-secondary">
            {archived ? "Nothing archived yet" : "No items needing attention"}
          </p>
        ) : (
          <div className="space-y-2">
            {items.map((item) => (
              <EmailTriageRow
                key={item.id}
                item={item}
                onChanged={refetch}
              />
            ))}
          </div>
        )}
      </div>
    </div>
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
