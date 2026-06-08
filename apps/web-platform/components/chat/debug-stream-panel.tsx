"use client";

import React, { useMemo, useState } from "react";
import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";
import type { ChatDebugEventMessage } from "@/lib/chat-state-machine";

/**
 * feat-debug-mode-stream — the SEPARATE collapsed debug drawer (FR1/FR3).
 *
 * Renders the workspace-scoped harness instruction stream APART from the
 * user-facing conversation (never inline). Render-only + ephemeral: the panel
 * imports NO `@/server/*` module (pino client-bundle trap — TR6) and re-redacts
 * every body at render via `redactCommandForDisplay` (dual-gate, mirroring
 * `message-bubble.tsx`). The dual-gate catches an emit-site WIRING bug (a path
 * that forgot to redact); it is the SAME redactor twice, so it is NOT
 * independent coverage for a redactor regex MISS — the server-side
 * DEBUG_REDACTION_PROBES superset is the real coverage backstop (Sharp Edge).
 *
 * Visibility is the `dev`-cohort `debug-mode` flag (`available`); the panel is
 * always READ-ONLY (the owner-gated flip lives in the settings toggle, so a
 * member/non-owner dev sees the stream with no control here). Emission is
 * server-gated independently — a flipped client flag can never unlock the
 * stream; this panel only renders what already arrived over the ephemeral WS.
 */

// The server DROP placeholder for a tool_use whose input tripped the redaction
// probe. Duplicated as a prefix check (not imported) because the source lives
// in `@/server/debug-event` and this client component must not pull `@/server/*`.
const WITHHELD_PREFIX = "[input withheld";

const KIND_LABEL: Record<ChatDebugEventMessage["debugKind"], string> = {
  tool_use: "tool",
  reasoning: "reasoning",
  result: "result",
};

export interface DebugStreamPanelProps {
  /** dev-cohort `debug-mode` flag — hide the whole panel when false. */
  available: boolean;
  /** Debug events filtered out of the main message list, in arrival order. */
  events: ChatDebugEventMessage[];
  /** WS connection liveness — drives the "disconnected" affordance. */
  connected: boolean;
  /** True once a turn has completed at least once — sharpens the empty hint
   *  (enabled-but-no-events vs gate-unavailable). */
  hadCompletedTurn?: boolean;
}

function DebugEventRow({ event }: { event: ChatDebugEventMessage }) {
  // Dual-gate: re-redact at render. Memoized on the raw body so redaction only
  // recomputes when the body changes.
  const body = useMemo(() => redactCommandForDisplay(event.body), [event.body]);
  const withheld = event.body.startsWith(WITHHELD_PREFIX);
  return (
    <li
      data-testid="debug-event-row"
      data-debug-kind={event.debugKind}
      data-withheld={withheld ? "true" : undefined}
      className="flex flex-col gap-0.5 border-b border-soleur-border-default/40 px-3 py-1.5 last:border-b-0"
    >
      <span className="flex items-center gap-2">
        <span className="rounded-sm bg-soleur-bg-surface-2 px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-wide text-soleur-text-muted">
          {KIND_LABEL[event.debugKind]}
        </span>
        {event.label && (
          <span className="font-mono text-[11px] text-soleur-text-secondary">
            {event.label}
          </span>
        )}
      </span>
      {body && (
        <pre
          className={`min-w-0 overflow-x-auto whitespace-pre-wrap [overflow-wrap:anywhere] font-mono text-[11px] ${
            withheld ? "italic text-soleur-text-muted" : "text-soleur-text-secondary"
          }`}
        >
          {body}
        </pre>
      )}
    </li>
  );
}

export function DebugStreamPanel({
  available,
  events,
  connected,
  hadCompletedTurn = false,
}: DebugStreamPanelProps) {
  const [expanded, setExpanded] = useState(false);

  // Visibility gate: non-dev (or flag-off) cohort never sees the panel.
  if (!available) return null;

  const withheldCount = events.filter((e) => e.body.startsWith(WITHHELD_PREFIX)).length;

  return (
    <section
      data-testid="debug-stream-panel"
      aria-label="Harness debug stream"
      className="mt-6 rounded-md border border-dashed border-soleur-border-default bg-soleur-bg-surface-1/30"
    >
      <button
        type="button"
        aria-expanded={expanded}
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left"
      >
        <span className="flex items-center gap-2">
          <span className="text-xs font-semibold text-soleur-text-primary">
            Debug stream
          </span>
          <span className="rounded-sm bg-soleur-bg-surface-2 px-1.5 py-0.5 font-mono text-[10px] text-soleur-text-muted">
            {events.length}
          </span>
          {!connected && (
            <span
              data-testid="debug-stream-disconnected"
              className="text-[10px] font-medium text-amber-500"
            >
              disconnected
            </span>
          )}
        </span>
        <span className="text-[10px] text-soleur-text-muted">
          {expanded ? "Hide" : "Show"} · not saved
        </span>
      </button>

      {expanded && (
        <div className="border-t border-soleur-border-default/40">
          <p className="px-3 py-1.5 text-[10px] text-soleur-text-muted">
            Internal harness events for this workspace. Secrets are redacted;
            this stream is <strong>not saved</strong> and visible only to the
            Soleur team.
          </p>
          {withheldCount > 0 && (
            <p
              data-testid="debug-stream-withheld"
              className="px-3 pb-1.5 text-[10px] text-amber-500"
            >
              {withheldCount} event{withheldCount === 1 ? "" : "s"} withheld
              (failed redaction probe)
            </p>
          )}
          {events.length === 0 ? (
            <p
              data-testid="debug-stream-empty"
              className="px-3 py-3 text-[11px] text-soleur-text-muted"
            >
              {hadCompletedTurn
                ? "Enabled, but no events this turn — or the gate is unavailable (check Sentry)."
                : "No harness events yet."}
            </p>
          ) : (
            <ul className="max-h-72 overflow-y-auto">
              {events.map((event) => (
                <DebugEventRow key={event.id} event={event} />
              ))}
            </ul>
          )}
        </div>
      )}
    </section>
  );
}
