"use client";

import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

export function ApiUsageRetryButton() {
  const router = useRouter();
  return (
    <Button
      variant="outlined"
      type="button"
      onClick={() => router.refresh()}
      className="rounded-md text-soleur-text-secondary shadow-sm focus:outline-none focus:ring-2 focus:ring-soleur-border-emphasized focus:ring-offset-2"
    >
      Retry
    </Button>
  );
}
