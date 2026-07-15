// feat-support-interface — static copy + persona config for the support shell.
// Pure data (no "use client" needed). Keep all user-facing support copy here so
// the canned-responder seam and the UI read from one source.

export const SUPPORT_NAME = "Soleur Support";

export const SUPPORT_GREETING =
  "Hi! I'm Soleur Support. I can help you find your way around the app — ask me anything, or pick a question below to get started.";

// Honest "interface preview" framing — surfaced in the empty state and as a
// composer footnote so a confused user is never misled into expecting live answers.
export const SUPPORT_PREVIEW_NOTE =
  "This is a preview — live support chat is coming soon. Replies below are samples for now.";

export const SUPPORT_COMPOSER_FOOTNOTE = "Responses are previews for now.";

export const SUPPORT_PANEL_SUBTITLE = "Preview · live chat coming soon";

// feat-wire-concierge-support-chat (ADR-113) — LIVE copy, shown when the
// `support-live` flag is ON (the real Concierge backend answers). The persistent
// "AI-generated, may be wrong" disclosure is retained so the honest framing
// survives the flip (never silently dropped).
export const SUPPORT_LIVE_NOTE =
  "I'm an AI assistant — I can help you find your way around Soleur. I may not be perfect; for anything I can't answer, browse your knowledge base.";

export const SUPPORT_COMPOSER_FOOTNOTE_LIVE = "Answers are AI-generated.";

export const SUPPORT_PANEL_SUBTITLE_LIVE = "AI app help · always on";

// Where a stuck user can actually get help today (the escape hatch baked into
// every canned reply). Keep relative so it works in dev and prd.
export const SUPPORT_KB_HREF = "/dashboard/kb";

export interface SupportStarterChip {
  /** Stable key used by the canned-responder lookup. */
  key: string;
  /** Label shown on the chip and sent as the user's message. */
  label: string;
}

// The 3 starter questions from the approved wireframes. Each maps to a keyed
// canned answer in canned-responder.ts.
export const SUPPORT_STARTER_CHIPS: readonly SupportStarterChip[] = [
  { key: "routines", label: "How do I create a routine?" },
  { key: "knowledge-base", label: "Where's my knowledge base?" },
  { key: "workstream", label: "What is the Workstream?" },
] as const;
