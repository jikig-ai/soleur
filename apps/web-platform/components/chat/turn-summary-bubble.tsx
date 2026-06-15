"use client";

import { useMemo } from "react";
import { formatAssistantText } from "@/lib/format-assistant-text";

/**
 * feat-reasoning-chat-boxes (#5370) — the DURABLE per-turn summary box.
 *
 * Renders an agent-authored plain-language summary ("Fixed the side panel — it
 * now stays where you left it") as a confirmed (emerald checkmark + left-accent
 * rail) box in the MAIN conversation. Distinct from the team-only debug stream.
 *
 * SECURITY (deepen-plan C-1): rendered as PLAIN TEXT inside a
 * `whitespace-pre-wrap` <p>, NEVER through `MarkdownRenderer`. The summary is
 * LLM-authored and prompt-injection-steerable; routing it through markdown would
 * turn a persisted, replayed string into a stored-XSS sink the moment a future
 * change adds `rehype-raw`, and would autolink attacker-influenced URLs. Plain
 * text + React's default escaping keeps any `<script>` / `<img onerror>` inert.
 * `formatAssistantText` is the render-time path/jargon scrub (belt-and-suspenders
 * over the server-side redaction the content was persisted with).
 *
 * Only emitted on a successful turn (the `summarize` MCP tool drop-guards
 * aborted/stopping conversations server-side), so the "Done" treatment never
 * asserts a false completion — an aborted/errored turn simply has no summary box.
 */
export function TurnSummaryBubble({ content }: { content: string }) {
  const text = useMemo(() => formatAssistantText(content), [content]);
  return (
    <div
      data-testid="turn-summary"
      data-message-type="turn_summary"
      className="flex items-start gap-2 rounded-xl border-l-2 border-soleur-border-default border-l-emerald-500 bg-soleur-bg-surface-1/40 px-4 py-3"
    >
      <span
        aria-hidden="true"
        className="mt-0.5 shrink-0 text-emerald-500"
        // Inline SVG checkmark; no icon-lib dependency, matches the
        // confirmed-outcome treatment in wireframe frame 06.
      >
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
          <path
            d="M13.5 4.5 6.5 11.5 3 8"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </span>
      <p className="min-w-0 whitespace-pre-wrap [overflow-wrap:anywhere] text-[15px] font-medium text-soleur-text-primary">
        {text}
      </p>
    </div>
  );
}
