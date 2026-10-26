"use client";

import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";

// #9545 PR2 — "Try again" / "Refresh" on the egress audit page. The page is server-rendered, so a retry
// is a router refresh (the loader runs again); no client fetch, no abort guard. usePendingAction keeps
// the button busy for the refresh and releases it when the transition settles.
export function EgressAuditRefreshButton({ label }: { label: string }) {
  const router = useRouter();
  const { run, pending } = usePendingAction(() => {
    router.refresh();
  });
  return (
    <Button
      variant="outlined"
      type="button"
      loading={pending}
      loadingLabel={label}
      onClick={() => run()}
      className="rounded-none text-xs font-medium"
    >
      {label}
    </Button>
  );
}
