"use client";

// Dedicated inbox surface (#5512). Client component rendered inside a
// <Suspense> boundary by the Server page at app/(dashboard)/dashboard/inbox.
// Reuses GET /api/inbox/emails (which owns the stub/probe/statutory-pin filter
// logic) and the EmailTriageRow component — no DB access here. The Active /
// Archived tabs drive the `?status=archived` query param so the view is
// shareable/deep-linkable; the active tab derives from the param, not local
// state. Items render in the order the API returns them (statutory pinned
// first) — never re-sorted.

import { useCallback, useEffect, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import {
  EmailTriageRow,
  type EmailTriageItem,
} from "@/components/inbox/email-triage-row";
import { ErrorCard } from "@/components/ui/error-card";

export function InboxSurface() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const archived = searchParams.get("status") === "archived";

  // `null` = loading (not yet resolved). [] = resolved-empty.
  const [items, setItems] = useState<EmailTriageItem[] | null>(null);
  const [error, setError] = useState(false);

  const fetchItems = useCallback(async () => {
    setError(false);
    setItems(null);
    try {
      const res = await fetch(
        `/api/inbox/emails${archived ? "?status=archived" : ""}`,
      );
      if (!res.ok) {
        setError(true);
        return;
      }
      const body = (await res.json()) as { items: EmailTriageItem[] };
      // Render in API order — the route pins unacknowledged statutory rows
      // first (uncapped); never re-sort or a running statutory clock could
      // fall out of view.
      setItems(body.items ?? []);
    } catch {
      setError(true);
    }
  }, [archived]);

  useEffect(() => {
    void fetchItems();
  }, [fetchItems]);

  const selectTab = (toArchived: boolean) => {
    router.push(toArchived ? `${pathname}?status=archived` : pathname);
  };

  return (
    <div>
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

      {error ? (
        <ErrorCard
          title="Failed to load inbox"
          message="Something went wrong loading your inbox. Please try again."
          onRetry={fetchItems}
        />
      ) : items === null ? (
        <p className="py-8 text-sm text-soleur-text-secondary">Loading…</p>
      ) : items.length === 0 ? (
        <p className="py-8 text-sm text-soleur-text-secondary">
          {archived ? "Nothing archived yet" : "No items needing attention"}
        </p>
      ) : (
        <div className="space-y-2">
          {items.map((item) => (
            <EmailTriageRow key={item.id} item={item} onChanged={fetchItems} />
          ))}
        </div>
      )}
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
