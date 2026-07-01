// feat-guided-tour — static step list. Pure data (no "use client").
//
// Each nav step's `target` is the `data-tour-id` value on the sidebar <Link>
// (which equals the nav item's href — see app/(dashboard)/layout.tsx). The
// Welcome step has no target (centered card, no spotlight cutout).

export interface TourStep {
  /** `data-tour-id` selector value, or null for a centered (no-spotlight) card. */
  target: string | null;
  title: string;
  body: string;
}

export const TOUR_STEPS: readonly TourStep[] = [
  {
    target: null,
    title: "Welcome to Soleur",
    body: "Take a 60-second tour — we'll point out the six places you'll spend your time.",
  },
  {
    target: "/dashboard",
    title: "Dashboard",
    body: "Your home base — a live overview of what your organization is building and what needs your attention right now.",
  },
  {
    target: "/dashboard/inbox",
    title: "Inbox",
    body: "Email and signals from the outside world land here, triaged so nothing important slips past you.",
  },
  {
    target: "/dashboard/workstream",
    title: "Workstream",
    body: "Track the work in flight — the conversations and tasks your agents are actively moving forward.",
  },
  {
    target: "/dashboard/kb",
    title: "Knowledge Base",
    body: "Your organization's shared memory: vision, docs, and context every agent draws on to act on your behalf.",
  },
  {
    target: "/dashboard/routines",
    title: "Routines",
    body: "Schedule recurring agent work so the things that should happen every day, week, or month just happen.",
  },
] as const;

export const TOUR_STEP_COUNT = TOUR_STEPS.length;
