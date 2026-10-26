"use client";

import { useEffect, useRef, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { EGRESS_AUDIT_HEADING_ID } from "@/components/settings/egress-audit-focus";

// #9545 PR2 — "Try again" / "Refresh" on the egress audit page. The page is server-rendered, so a retry
// is a router refresh (the loader runs again); no client fetch, no abort guard. The button is busy for
// as long as the React transition around router.refresh() is pending.
//
// What the unit tests prove: the component starts a transition, the busy state tracks that transition,
// and the focus rules below. What they do NOT prove: that Next keeps a router.refresh() transition
// pending until the server data has committed. The unit mock returns a pending promise from
// router.refresh(); the real one returns void, so that behaviour of Next is assumed here, not tested.
// (usePendingAction is not used: it releases after a microtask, long before a refresh would finish.)
//
// Focus: a successful refresh usually swaps the state card for the table, which unmounts this button and
// would drop focus to <body>; so if the button unmounts mid-refresh, focus moves to the page heading
// (a no-op when the heading is absent). If the button is still mounted when the refresh settles (a
// failed retry re-rendering the same alert), focus stays on / returns to the button, so a screen reader
// hears the alert rather than being sent to the heading. An idle unmount moves focus nowhere.
function focusHeading() {
  document.getElementById(EGRESS_AUDIT_HEADING_ID)?.focus();
}

export function EgressAuditRefreshButton({ label }: { label: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const wasPending = useRef(false);
  const buttonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (wasPending.current && !pending) {
      // A disabled (busy) button can lose focus to <body>; give it back unless the user moved elsewhere.
      const active = document.activeElement;
      if (!active || active === document.body || active === buttonRef.current) buttonRef.current?.focus();
    }
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
      ref={buttonRef}
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
