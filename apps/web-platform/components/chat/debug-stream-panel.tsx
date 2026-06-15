"use client";

import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
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

// Sticky-autoscroll bottom tolerance: distance (px) from the bottom within
// which the list still counts as "pinned". Absorbs sub-pixel rounding plus the
// height of a partially-visible last row.
const STICK_TO_BOTTOM_THRESHOLD_PX = 32;

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

/**
 * Serialize all events to clipboard text using the SAME redaction the render
 * path applies (`DebugEventRow`). NEVER serialize raw `event.body` — that would
 * copy to the clipboard the secrets the UI withholds on screen. Withheld bodies
 * ("[input withheld…") are already placeholders; `redactCommandForDisplay`
 * returns them unchanged, so they copy as-is. An empty body emits just the
 * header line (mirrors the render path's `{body && …}` gate).
 */
export function serializeDebugEvents(events: ChatDebugEventMessage[]): string {
  return events
    .map((event) => {
      const header = event.label
        ? `${KIND_LABEL[event.debugKind]} · ${event.label}`
        : KIND_LABEL[event.debugKind];
      const body = redactCommandForDisplay(event.body); // dual-gate, NOT raw
      return body ? `${header}\n${body}` : header;
    })
    .join("\n\n");
}

export function DebugStreamPanel({
  available,
  events,
  connected,
  hadCompletedTurn = false,
}: DebugStreamPanelProps) {
  const [expanded, setExpanded] = useState(false);
  const [copied, setCopied] = useState(false);
  const copyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Clear the transient-"Copied" timer on unmount (the panel unmounts when
  // `available` flips false) to avoid a setState-after-unmount warning.
  useEffect(() => {
    return () => {
      if (copyTimer.current) clearTimeout(copyTimer.current);
    };
  }, []);

  const copyAll = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(serializeDebugEvents(events));
      setCopied(true);
      if (copyTimer.current) clearTimeout(copyTimer.current);
      copyTimer.current = setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard unavailable (insecure context / permission denied). This is a
      // dev-cohort, same-origin panel (always a secure context in practice), so
      // no execCommand fallback is warranted — mirrors components/kb/share-popover.tsx.
    }
  }, [events]);

  // Sticky autoscroll-to-bottom. The list is a nested `overflow-y-auto`, so we
  // scroll the `<ul>` directly (`scrollTop = scrollHeight`) rather than
  // `scrollIntoView` — the latter would also scroll ancestor containers and
  // yank the whole page to surface the last row. `stickToBottom` is a ref (NOT
  // state) so a scroll event never re-renders and the effect always reads the
  // latest value without a stale closure.
  const listRef = useRef<HTMLUListElement>(null);
  const stickToBottom = useRef(true);

  // Re-pin to the newest entry only when the operator is already at the bottom.
  // Keyed on `events.length` so it fires on each new arrival, not on body edits;
  // also keyed on `expanded` so opening a pre-populated panel lands at the
  // newest entry rather than scrolled to the top (the `<ul>` only mounts while
  // expanded, so the ref is fresh on that transition).
  useEffect(() => {
    const ul = listRef.current;
    if (ul && stickToBottom.current) {
      ul.scrollTop = ul.scrollHeight;
    }
  }, [events.length, expanded]);

  // Visibility gate: non-dev (or flag-off) cohort never sees the panel.
  if (!available) return null;

  const withheldCount = events.filter((e) => e.body.startsWith(WITHHELD_PREFIX)).length;

  return (
    <section
      data-testid="debug-stream-panel"
      aria-label="Harness debug stream"
      className="mt-6 rounded-md border border-dashed border-soleur-border-default bg-soleur-bg-surface-1/30"
    >
      {/* Header row: the expand/collapse toggle and the Copy control are
          SIBLING buttons (never nested — a <button> inside a <button> is
          invalid HTML), so clicking Copy can never toggle the panel. */}
      <div className="flex w-full items-center justify-between gap-3 px-3 py-2">
        <button
          type="button"
          aria-expanded={expanded}
          onClick={() => setExpanded((v) => !v)}
          className="flex flex-1 items-center gap-2 text-left"
        >
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
          {/* The "Show"/"Hide" word is the affordance the user reads as the
              control, so it MUST live inside the toggle button — clicking it
              has to toggle the panel. #5241 moved it into an inert sibling
              span next to Copy, which broke clickability. `ml-auto` pins it to
              the button's right end so its visual position is preserved. */}
          <span className="ml-auto text-[10px] font-medium text-soleur-text-secondary">
            {expanded ? "Hide" : "Show"}
          </span>
        </button>
        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            data-testid="debug-stream-copy"
            onClick={copyAll}
            disabled={events.length === 0}
            title={
              events.length === 0
                ? "No events to copy"
                : "Copy all debug events (redacted) to clipboard"
            }
            // resting -text (gold) not -fg: -fg fails AA 4.5:1 at 10px on this surface (3.66:1 light).
            // hover -primary (not a gold brighten): contrast INCREASES on hover both themes (SC 1.4.3, no transient exemption).
            className="rounded-sm border border-soleur-accent-gold-text/30 px-1.5 py-0.5 text-[10px] font-medium text-soleur-accent-gold-text transition-colors hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:text-soleur-text-muted disabled:opacity-40"
          >
            {copied ? "Copied" : "Copy"}
          </button>
          <span className="text-[10px] text-soleur-text-muted">not saved</span>
        </div>
      </div>

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
            <ul
              ref={listRef}
              onScroll={(e) => {
                const ul = e.currentTarget;
                stickToBottom.current =
                  ul.scrollHeight - ul.scrollTop - ul.clientHeight <
                  STICK_TO_BOTTOM_THRESHOLD_PX;
              }}
              className="max-h-72 overflow-y-auto"
            >
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
