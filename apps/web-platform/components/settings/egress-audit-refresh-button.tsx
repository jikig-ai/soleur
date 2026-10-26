"use client";

import { useEffect, useRef, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { EGRESS_AUDIT_HEADING_ID } from "@/components/settings/egress-audit-focus";

// #9545 PR2 — "Try again" / "Refresh" on the egress audit page. The page is server-rendered, so a retry
// is a router refresh (the loader runs again); no client fetch, no abort guard. The button is busy for
// as long as the React transition around router.refresh() is pending, i.e. until the server data has
// arrived and committed. (usePendingAction is not used: it releases after a microtask, long before the
// refresh finishes, so the button would never show busy.)
//
// A successful refresh usually swaps the state card for the table, which unmounts this button and would
// drop focus to <body>. So when the refresh settles (or the button unmounts mid-refresh) focus moves to
// the page heading; it is a no-op when the heading is absent.
function focusHeading() {
  document.getElementById(EGRESS_AUDIT_HEADING_ID)?.focus();
}

export function EgressAuditRefreshButton({ label }: { label: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const wasPending = useRef(false);

  useEffect(() => {
    if (wasPending.current && !pending) focusHeading();
    wasPending.current = pending;
  }, [pending]);

  // The commit that swaps the card out unmounts this component before the pending=false effect can run.
  useEffect(
    () => () => {
      if (wasPending.current) focusHeading();
    },
    [],
  );

  return (
    <Button
      variant="outlined"
      type="button"
      loading={pending}
      loadingLabel={label}
      onClick={() => {
        if (pending) return;
        startTransition(() => router.refresh());
      }}
      className="rounded-none text-xs font-medium"
    >
      {label}
    </Button>
  );
}
