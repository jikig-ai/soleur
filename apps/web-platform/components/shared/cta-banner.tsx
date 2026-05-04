"use client";

import Link from "next/link";
import { useState } from "react";
import { safeSession } from "@/lib/safe-session";

const STORAGE_KEY = "soleur:shared:cta-dismissed";

export function CtaBanner() {
  const [dismissed, setDismissed] = useState<boolean>(
    () => safeSession(STORAGE_KEY) === "1",
  );

  if (dismissed) return null;

  function handleDismiss() {
    safeSession(STORAGE_KEY, "1");
    setDismissed(true);
  }

  return (
    <div className="fixed bottom-0 left-0 right-0 z-40 border-t border-neutral-800 bg-neutral-900/95 px-4 py-3 backdrop-blur-sm">
      <div className="mx-auto flex max-w-3xl items-center justify-between gap-4">
        <p className="text-sm text-neutral-300">
          This document was created with{" "}
          <span className="font-medium text-amber-400">Soleur</span> — AI
          agents for every department of your startup.
        </p>
        <div className="flex shrink-0 items-center gap-2">
          <Link
            href="/signup"
            className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black transition-colors hover:bg-amber-400"
          >
            Create your account
          </Link>
          <button
            type="button"
            onClick={handleDismiss}
            className="rounded p-1 text-neutral-500 transition-colors hover:text-neutral-300"
            aria-label="Dismiss signup banner"
            data-testid="cta-banner-dismiss"
          >
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
