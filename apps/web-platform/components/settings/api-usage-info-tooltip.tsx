import type { ReactNode } from "react";

interface ApiUsageInfoTooltipProps {
  label: string;
  children: ReactNode;
}

// Native <details>/<summary> disclosure — click/tap to expand on both desktop
// and touch devices with zero JS. Keyboard-accessible (Enter/Space) and
// screen-reader-announced (disclosure semantics) out of the box. Deliberately
// NOT a server- or client-boundary concern — no hooks, no handlers — so no
// "use client" directive is needed.
export function ApiUsageInfoTooltip({
  label,
  children,
}: ApiUsageInfoTooltipProps) {
  return (
    <details className="group relative inline-block">
      <summary
        className="inline-flex cursor-pointer list-none items-center gap-1 whitespace-nowrap rounded text-xs text-zinc-500 hover:text-zinc-700 focus:outline-none focus:ring-1 focus:ring-zinc-400 dark:text-zinc-400 dark:hover:text-zinc-200 [&::-webkit-details-marker]:hidden"
      >
        <span
          aria-hidden="true"
          className="inline-flex h-4 w-4 items-center justify-center rounded-full border border-zinc-300 text-[10px] font-semibold leading-none dark:border-zinc-600"
        >
          ?
        </span>
        <span>{label}</span>
      </summary>
      <div className="absolute left-0 top-full z-10 mt-1 w-64 rounded-md border border-zinc-200 bg-white p-3 text-xs text-zinc-700 shadow-lg dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-200">
        {children}
      </div>
    </details>
  );
}
