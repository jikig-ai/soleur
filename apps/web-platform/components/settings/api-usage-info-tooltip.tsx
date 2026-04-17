"use client";

import type { ReactNode } from "react";

interface ApiUsageInfoTooltipProps {
  label: string;
  children: ReactNode;
}

// Uses native <details>/<summary> for click-to-open behavior that works on
// both desktop and touch devices without pulling in a dependency for two
// tooltips. Details elements are accessible out of the box (keyboard
// toggle via Enter/Space, screen readers announce expansion state).
export function ApiUsageInfoTooltip({
  label,
  children,
}: ApiUsageInfoTooltipProps) {
  return (
    <details className="group relative inline-block">
      <summary
        className="inline-flex cursor-pointer list-none items-center gap-1 rounded text-xs text-zinc-500 hover:text-zinc-700 focus:outline-none focus:ring-1 focus:ring-zinc-400 dark:text-zinc-400 dark:hover:text-zinc-200 [&::-webkit-details-marker]:hidden"
        aria-label={label}
      >
        <span
          aria-hidden="true"
          className="inline-flex h-4 w-4 items-center justify-center rounded-full border border-zinc-300 text-[10px] font-semibold leading-none dark:border-zinc-600"
        >
          ?
        </span>
        <span>{label}</span>
      </summary>
      <div
        role="tooltip"
        className="absolute left-0 top-full z-10 mt-1 w-64 rounded-md border border-zinc-200 bg-white p-3 text-xs text-zinc-700 shadow-lg dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-200"
      >
        {children}
      </div>
    </details>
  );
}
