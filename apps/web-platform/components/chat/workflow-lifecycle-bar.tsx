"use client";

import React from "react";
import type { WorkflowLifecycleState } from "@/lib/chat-state-machine";

/**
 * Stage 4 (#2886) — WorkflowLifecycleBar component.
 *
 * Sticky context bar above the message list. Four states:
 *   - idle    → render nothing (return null)
 *   - routing → amber pulse + "Routing your message…" or "Routing to {skill}…"
 *   - active  → workflow name + phase + cumulative cost + Switch workflow CTA
 *   - ended   → completion summary + outcome badge + Start new conversation CTA
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
    case "routing":
      return (
        <div
          data-lifecycle-state="routing"
          className="flex items-center gap-2 border-b border-neutral-800 bg-neutral-900/40 px-4 py-2"
        >
          <span
            className="h-2 w-2 animate-pulse rounded-full bg-amber-500"
            aria-hidden="true"
          />
          <span className="text-xs text-neutral-300">
            {lifecycle.skillName
              ? `Routing to ${lifecycle.skillName}…`
              : "Routing your message…"}
          </span>
        </div>
      );
    case "active":
      return (
        <div
          data-lifecycle-state="active"
          className="flex items-center gap-3 border-b border-neutral-800 bg-neutral-900/40 px-4 py-2"
        >
          <span className="rounded-full bg-amber-900/30 px-2 py-0.5 text-[10px] font-semibold text-amber-300">
            {lifecycle.workflow}
          </span>
          {lifecycle.phase ? (
            <span className="text-xs text-neutral-400">{lifecycle.phase}</span>
          ) : null}
          {typeof lifecycle.cumulativeCostUsd === "number" ? (
            <span className="text-xs text-neutral-500">
              ~${lifecycle.cumulativeCostUsd.toFixed(4)}
            </span>
          ) : null}
          <div className="ml-auto">
            <button
              type="button"
              onClick={onSwitchWorkflow}
              className="rounded-md border border-neutral-700 px-2 py-1 text-xs text-neutral-300 hover:border-neutral-500"
            >
              Switch workflow
            </button>
          </div>
        </div>
      );
    case "ended":
      return (
        <div
          data-lifecycle-state="ended"
          className="flex flex-col gap-2 border-b border-neutral-800 bg-neutral-900/40 px-4 py-3"
        >
          <div className="flex items-center gap-2">
            <span className="rounded-full bg-neutral-800 px-2 py-0.5 text-[10px] font-semibold text-neutral-200">
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
              <span className="truncate text-xs text-neutral-400">{lifecycle.summary}</span>
            ) : null}
          </div>
          <div>
            <button
              type="button"
              onClick={onStartNewConversation}
              className="rounded-md bg-amber-600 px-3 py-1 text-xs text-white hover:bg-amber-500"
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
