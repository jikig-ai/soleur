// feat-guided-tour — static step list. Pure data (no "use client").
//
// Two kinds of step:
//   • Nav/landing steps whose `target` is a sidebar <Link>'s `data-tour-id`
//     (equals the nav href — see app/(dashboard)/layout.tsx). These exist on
//     every dashboard route, so they need no `route`.
//   • Action steps that spotlight an in-page control (e.g. "start a conversation").
//     Those controls only mount on their own route, so the step carries a
//     `route` — TourProvider navigates there first, and the overlay polls for the
//     `data-tour-id` target to mount before drawing the spotlight (falls back to a
//     centered card if it never appears). Anchors are `action:<name>` data-tour-ids
//     added at each control's render site.
// The Welcome (first) and closing (last) steps have no target → centered card.

export interface TourStep {
  /** `data-tour-id` selector value, or null for a centered (no-spotlight) card. */
  target: string | null;
  title: string;
  body: string;
  /**
   * Route to client-navigate to before this step is shown. Omit to stay on the
   * current page (nav-link targets are present everywhere). The overlay waits for
   * `target` to mount after navigation.
   */
  route?: string;
}

export const TOUR_STEPS: readonly TourStep[] = [
  {
    target: null,
    title: "Welcome to Soleur",
    body: "Take a 60-second tour — we'll stop at each tab and point out the one thing you do there.",
  },
  {
    target: "action:new-conversation",
    route: "/dashboard",
    title: "Start a conversation",
    body: "The Dashboard is your home base. Tell your agents what you're building — type here and hit send to kick off a conversation.",
  },
  {
    target: "action:org-panel",
    route: "/dashboard",
    title: "Meet your organization",
    body: "These are your agents — CTO, CFO, CPO, CRO and more. Click any leader to talk to them directly and hand off work by function.",
  },
  {
    target: "action:inbox-triage",
    route: "/dashboard/inbox",
    title: "Triage your Inbox",
    body: "Email and signals from the outside world land here, already triaged. Open a row to act on it, or mark it done to clear it.",
  },
  {
    target: "action:new-issue",
    route: "/dashboard/workstream",
    title: "Hand off work",
    body: "Workstream tracks the work in flight. Hit “+ New Issue” to hand your agents something to move forward.",
  },
  {
    target: "action:kb-tree",
    route: "/dashboard/kb",
    title: "Feed the Knowledge Base",
    body: "Your organization's shared memory. Browse the tree and drop in docs and context every agent draws on to act for you.",
  },
  {
    target: "action:draft-routine",
    route: "/dashboard/routines",
    title: "Automate the recurring",
    body: "Routines make things happen on a schedule. Draft one with Concierge to run agent work every day, week, or month.",
  },
  {
    target: "/dashboard/releases",
    title: "Keep up with Releases",
    body: "New features and fixes land here — a running feed of what's changed in Soleur.",
  },
  {
    target: "/dashboard/settings",
    title: "Manage your workspace",
    body: "Settings is where you handle your account, team, billing, and the services your agents connect to.",
  },
  {
    target: null,
    route: "/dashboard",
    title: "You're all set",
    body: "That's the tour. You can relaunch it anytime from the “?” menu or the support panel.",
  },
] as const;

export const TOUR_STEP_COUNT = TOUR_STEPS.length;
