"use client";

import React, { useEffect, useState } from "react";
import {
  ACTIVITY_VISIBLE_CAP,
  type ActivityEntry,
} from "@/lib/chat-state-machine";

/**
 * feat-concierge-activity-trail (#9515): the in-turn step history rendered
 * INSIDE the consolidated status box. Prior steps render dimmed (fixed
 * muted token — the wireframe's 55% opacity fails WCAG AA against
 * `soleur-bg-surface-1`); the CURRENT step renders as the bright live line
 * with a pulsing dot + ticking elapsed. The trail is session-only —
 * terminalized bubbles never reach this component (render-gated by the
 * caller on live-ish states), so no persisted history and no strip mutation.
 *
 * a11y: `aria-live="polite"` on the region announces NEW steps; the elapsed
 * numbers are `aria-hidden` so the 1s ticker does not re-announce the whole
 * region every tick.
 */

export function formatElapsed(
  startedAt: number | undefined,
  now: number,
): string | null {
  if (startedAt === undefined) return null;
  const secs = Math.max(0, Math.round((now - startedAt) / 1000));
  if (secs < 60) return `${secs}s`;
  return `${Math.floor(secs / 60)}m ${secs % 60}s`;
}

export function ActivityTrail({
  activity,
  current,
  interrupted = false,
}: {
  /** Prior steps (oldest → newest), session-only. */
  activity: ActivityEntry[] | undefined;
  /** The live step: `{label, startedAt}` from the narration slot or toolLabel. */
  current: { label: string; startedAt: number | null | undefined } | null;
  /** Mid-flap marker — renders the honest "Interrupted" chip; the live line
   *  stays dark because no current step is provably running client-side. */
  interrupted?: boolean;
}) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const priors = activity ?? [];
  const hiddenCount = Math.max(0, priors.length - ACTIVITY_VISIBLE_CAP);
  const visible = priors.slice(-ACTIVITY_VISIBLE_CAP);
  const currentElapsed = current
    ? formatElapsed(current.startedAt ?? undefined, now)
    : null;

  return (
    <div
      className="mt-2 flex flex-col gap-1 border-t border-soleur-border-default/40 pt-2"
      aria-live="polite"
      data-testid="activity-trail"
    >
      {hiddenCount > 0 && (
        <div className="text-xs text-soleur-text-muted">
          …and {hiddenCount} more {hiddenCount === 1 ? "step" : "steps"}
        </div>
      )}
      {visible.map((entry, i) => {
        const elapsed = formatElapsed(entry.startedAt, now);
        return (
          <div
            key={`${entry.startedAt}-${i}`}
            className="flex items-center gap-1.5 text-xs text-soleur-text-muted"
          >
            <span className="min-w-0 [overflow-wrap:anywhere]">
              {entry.label}
            </span>
            {elapsed && (
              <span aria-hidden="true" className="shrink-0 tabular-nums">
                · {elapsed}
              </span>
            )}
          </div>
        );
      })}
      {interrupted ? (
        <div
          className="flex items-center gap-2 text-sm text-soleur-text-muted"
          data-testid="interrupted-chip"
          role="status"
        >
          <span
            aria-hidden="true"
            className="h-1.5 w-1.5 shrink-0 rounded-full bg-soleur-text-muted"
          />
          Interrupted
        </div>
      ) : current ? (
        <div
          className="flex items-center gap-2 text-sm"
          data-testid="live-narration"
        >
          <span
            aria-hidden="true"
            className="h-1.5 w-1.5 shrink-0 animate-pulse rounded-full bg-amber-500"
          />
          <span className="min-w-0 text-soleur-text-secondary [overflow-wrap:anywhere]">
            {current.label}
          </span>
          {currentElapsed && (
            <span
              aria-hidden="true"
              className="shrink-0 text-xs text-soleur-text-muted tabular-nums"
            >
              · {currentElapsed}
            </span>
          )}
        </div>
      ) : null}
    </div>
  );
}
