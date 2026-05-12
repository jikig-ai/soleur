import type { ChatMessage } from "@/lib/chat-state-machine";

// Sunset 90 days after PR-B merge — component returns null after this date; lazy-delete on next file touch.
const COHORT_WINDOW_START = new Date("2026-05-05T00:00:00Z").getTime();
const COHORT_WINDOW_END = new Date("2026-05-12T00:00:00Z").getTime();
const COHORT_MARKER_SUNSET = new Date("2026-08-11T00:00:00Z").getTime();

export interface CohortMissingReplyMarkerProps {
  createdAt: string;
  messages: ChatMessage[];
  isStreamingAssistant: boolean;
}

export function CohortMissingReplyMarker({
  createdAt,
  messages,
  isStreamingAssistant,
}: CohortMissingReplyMarkerProps) {
  if (Date.now() >= COHORT_MARKER_SUNSET) return null;

  const startMs = Date.parse(createdAt);
  if (Number.isNaN(startMs)) return null;
  if (startMs < COHORT_WINDOW_START || startMs >= COHORT_WINDOW_END) return null;
  if (isStreamingAssistant) return null;

  const textMessages = messages.filter((m) => m.type === "text");
  if (textMessages.length === 0) return null;
  if (!textMessages.every((m) => m.role === "user")) return null;

  const formattedDate = new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(new Date(createdAt));

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
