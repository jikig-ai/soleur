"use client";

import type { ChatMessage } from "@/lib/chat-state-machine";

// Sunset 91 days after PR-B merge (2026-05-12 → 2026-08-11) — component
// returns null after this date; lazy-delete on next file touch. See #3603.
const COHORT_WINDOW_START = new Date("2026-05-05T00:00:00Z").getTime();
const COHORT_WINDOW_END = new Date("2026-05-12T00:00:00Z").getTime();
const COHORT_MARKER_SUNSET = new Date("2026-08-11T00:00:00Z").getTime();

export interface CohortMissingReplyMarkerProps {
  createdAt: string | null;
  messages: ChatMessage[];
  /** True while a turn is in flight (`streaming` or `stopping`). Suppresses
   *  the marker across the whole abort window so a Stop click on a cohort
   *  thread does not flash the note during `streaming → stopping → idle`. */
  isTurnInFlight: boolean;
}

export function CohortMissingReplyMarker({
  createdAt,
  messages,
  isTurnInFlight,
}: CohortMissingReplyMarkerProps) {
  // `Date.now()` is re-evaluated per render so a long-lived session that
  // crosses the sunset boundary hides the marker without requiring a reload.
  if (Date.now() >= COHORT_MARKER_SUNSET) return null;
  if (createdAt === null) return null;

  const startMs = Date.parse(createdAt);
  if (Number.isNaN(startMs)) return null;
  if (startMs < COHORT_WINDOW_START || startMs >= COHORT_WINDOW_END) return null;
  if (isTurnInFlight) return null;

  const textMessages = messages.filter((m) => m.type === "text");
  if (textMessages.length === 0) return null;
  if (!textMessages.every((m) => m.role === "user")) return null;

  // Reuse the validated `startMs` instead of re-parsing `createdAt` — both
  // guarantees the formatted output matches the value that passed the gate
  // and saves a second parse per render.
  const formattedDate = new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(new Date(startMs));

  return (
    <aside
      role="note"
      aria-label="Conversation history note"
      className="my-6 flex flex-col items-center gap-2 px-4 text-center text-sm text-soleur-text-secondary"
    >
      <p>Some assistant replies from this conversation (started {formattedDate}) weren&apos;t captured.</p>
      <p>New replies are saved normally.</p>
    </aside>
  );
}
