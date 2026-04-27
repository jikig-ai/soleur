"use client";

import React from "react";
import { LEADER_COLORS } from "@/components/chat/leader-colors";

/**
 * Stage 4 (#2886) — ToolUseChip component.
 *
 * Inline status chip for `tool_use` events on the `cc_router` / `system`
 * leaders — pre-bubble surface, before any real leader bubble exists.
 * Per-real-leader tool_use stays on `MessageBubble.toolLabel`; this chip is
 * scoped to the routing/system span only.
 *
 * Per `Risks` §6 (master plan): NO `@/server/tool-labels` import — `toolLabel`
 * arrives pre-built on the WS event. The Phase 6 sentinel grep enforces this.
 *
 * Test hook: `data-tool-chip-id` (a per-instance React key proxy).
 *
 * Bash command rendering safety: all text content rendered through standard
 * JSX (default React text-node escaping). No escape-hatch render APIs.
 */

interface ToolUseChipProps {
  toolName: string;
  toolLabel: string;
  /** Restricted union — chip is ONLY for these. Per-real-leader tool_use
   *  stays on `MessageBubble.toolLabel` (existing pattern). */
  leaderId: "cc_router" | "system";
}

export function ToolUseChip({ toolName, toolLabel, leaderId }: ToolUseChipProps) {
  // The base color class is `border-l-<color>`; we only need the right-side
  // border accent for the chip's neutral pill, but reuse the leader-color
  // entries to drive the visual cue (yellow for cc_router, neutral for system).
  const colorClass =
    leaderId === "cc_router"
      ? `border border-yellow-700/60 ${LEADER_COLORS.cc_router}`
      : `border border-neutral-700 ${LEADER_COLORS.system}`;

  return (
    <div
      data-tool-chip-id={`${leaderId}-${toolName}-${toolLabel}`}
      className={`inline-flex items-center gap-2 rounded-full bg-neutral-900/60 px-3 py-1 ${colorClass}`}
    >
      <span
        className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500"
        aria-hidden="true"
      />
      <span className="text-xs text-neutral-300">{toolLabel}</span>
    </div>
  );
}
