"use client";

import React from "react";
import type { WorkflowLifecycleState } from "@/lib/chat-state-machine";

/**
 * Stage 4 (#2886) — WorkflowLifecycleBar component.
 *
 * Sticky context bar above the message list. Three states:
 *   - idle    → render nothing (return null)
 *   - active  → workflow name + phase + cumulative cost + Switch workflow CTA
 *   - ended   → completion summary + outcome badge + Start new conversation CTA
 *
 * Review F9: the `routing` state was dropped because the reducer never
 * produced it and there's no reliable signal source for `skillName`
 * pre-`workflow_started`. The legacy "Routing to the right experts" chip
 * in `chat-surface.tsx` continues to cover the routing UX during the gap
 * before `workflow_started` fires.
 *
 * Test hook: `data-lifecycle-state` (idle returns null and emits no element).
 */

interface WorkflowLifecycleBarProps {
  lifecycle: WorkflowLifecycleState;
  onSwitchWorkflow?: () => void;
  onStartNewConversation?: () => void;
}

export function WorkflowLifecycleBar({
  lifecycle,
  onSwitchWorkflow,
  onStartNewConversation,
}: WorkflowLifecycleBarProps) {
  switch (lifecycle.state) {
    case "idle":
      return null;
    case "active":
      return (
        <div
          data-lifecycle-state="active"
          className="flex items-center gap-3 border-b border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-2"
        >
          <span className="rounded-full bg-amber-900/30 px-2 py-0.5 text-[10px] font-semibold text-amber-300">
            {lifecycle.workflow}
          </span>
          {lifecycle.phase ? (
            <span className="text-xs text-soleur-text-secondary">{lifecycle.phase}</span>
          ) : null}
          {typeof lifecycle.cumulativeCostUsd === "number" ? (
            <span className="text-xs text-soleur-text-muted">
              ~${lifecycle.cumulativeCostUsd.toFixed(4)}
            </span>
          ) : null}
          {onSwitchWorkflow !== undefined ? (
            <div className="ml-auto">
              <button
                type="button"
                onClick={onSwitchWorkflow}
                className="rounded-md border border-soleur-border-default px-2 py-1 text-xs text-soleur-text-secondary hover:border-soleur-border-emphasized"
              >
                Switch workflow
              </button>
            </div>
          ) : null}
        </div>
      );
    case "ended":
      return (
        <div
          data-lifecycle-state="ended"
          className="flex flex-col gap-2 border-b border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-3"
        >
          <div className="flex items-center gap-2">
            <span className="rounded-full bg-soleur-bg-surface-2 px-2 py-0.5 text-[10px] font-semibold text-soleur-text-primary">
              {lifecycle.workflow}
            </span>
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                lifecycle.status === "completed"
                  ? "bg-emerald-900/40 text-emerald-300"
                  : "bg-red-900/40 text-red-300"
              }`}
            >
              {lifecycle.status}
            </span>
            {lifecycle.summary ? (
              <span className="truncate text-xs text-soleur-text-secondary">{lifecycle.summary}</span>
            ) : null}
          </div>
          <div>
            <button
              type="button"
              onClick={onStartNewConversation}
              className="rounded-md bg-amber-600 px-3 py-1 text-xs text-soleur-text-on-accent hover:bg-amber-500"
            >
              Start new conversation
            </button>
          </div>
        </div>
      );
    default: {
      const _exhaustive: never = lifecycle;
      void _exhaustive;
      return null;
    }
  }
}
