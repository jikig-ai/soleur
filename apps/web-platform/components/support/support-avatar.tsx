"use client";

// feat-support-interface — support persona avatar. A life-buoy glyph on the gold
// gradient, visually distinct from the leader/dev LeaderAvatar. Tokens only.

import { GOLD_GRADIENT } from "@/components/ui/constants";

const SIZE_CLASS = {
  sm: "h-7 w-7",
  md: "h-9 w-9",
} as const;

export function SupportAvatar({
  size = "md",
}: {
  size?: keyof typeof SIZE_CLASS;
}) {
  return (
    <span
      className={`flex shrink-0 items-center justify-center rounded-full text-black ${SIZE_CLASS[size]}`}
      style={{ background: GOLD_GRADIENT }}
      aria-hidden="true"
    >
      {/* life-buoy glyph */}
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="h-4 w-4"
      >
        <circle cx="12" cy="12" r="10" />
        <circle cx="12" cy="12" r="4" />
        <line x1="4.93" y1="4.93" x2="9.17" y2="9.17" />
        <line x1="14.83" y1="14.83" x2="19.07" y2="19.07" />
        <line x1="14.83" y1="9.17" x2="19.07" y2="4.93" />
        <line x1="9.17" y1="14.83" x2="4.93" y2="19.07" />
      </svg>
    </span>
  );
}
