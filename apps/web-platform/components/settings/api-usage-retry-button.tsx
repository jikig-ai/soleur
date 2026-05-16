"use client";

import { useRouter } from "next/navigation";

export function ApiUsageRetryButton() {
  const router = useRouter();
  return (
    <button
      type="button"
      onClick={() => router.refresh()}
      className="inline-flex items-center rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-1.5 text-sm font-medium text-soleur-text-secondary shadow-sm hover:bg-soleur-bg-surface-2 focus:outline-none focus:ring-2 focus:ring-soleur-border-emphasized focus:ring-offset-2"
    >
      Retry
    </button>
  );
}
