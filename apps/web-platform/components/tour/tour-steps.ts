// feat-guided-tour — static step list. Pure data (no "use client").
//
// Each section is taught in TWO steps: first its SIDEBAR TAB (target = the nav
// <Link>'s `data-tour-id`, which equals its href — see app/(dashboard)/layout.tsx),
// then the primary IN-PAGE ACTION on that section (target = an `action:<name>`
// anchor at the control's render site). Both carry the section's `route` so
// TourProvider navigates there — the tab step highlights the now-active sidebar
// tab, the action step then spotlights the control. The overlay polls for the
// `data-tour-id` target to mount after navigation (centered-card fallback if it
// never appears, e.g. an empty/loading surface). Releases and Settings are
// tab-only (no in-page action). The Knowledge Base tab step is the one exception
// that carries NO `route` (see its note below). Welcome (first) + closing (last)
// have no target.

import { NEW_ISSUE_DIALOG_EVENT } from "@/components/workstream/new-issue-dialog-event";
import { ROUTINE_DRAFT_TAB_EVENT } from "@/components/routines/routine-draft-tab-event";

export interface TourStep {
  /** `data-tour-id` selector value, or null for a centered (no-spotlight) card. */
  target: string | null;
  title: string;
  body: string;
  /**
   * Route to client-navigate to before this step is shown. The overlay waits for
   * `target` to mount after navigation. Omit only for the centered Welcome step.
   */
  route?: string;
  /**
   * Window event dispatched with `{ open: true }` when this step becomes active
   * and `{ open: false }` when the tour leaves it (to a step that doesn't share
   * the same `reveal`). Lets a step open a component-owned modal so its in-modal
   * `target` can be spotlit (e.g. the New Issue dialog). Handled in TourProvider.
   */
  reveal?: string;
}

export const TOUR_STEPS: readonly TourStep[] = [
  {
    target: null,
    title: "Welcome to Soleur",
    body: "Take a quick tour — for each section we'll show you the sidebar tab that opens it, then the one thing you do there.",
  },

  // ── Dashboard ──────────────────────────────────────────────────────────────
  {
    target: "/dashboard",
    route: "/dashboard",
    title: "Your sidebar",
    body: "The sidebar on the left is how you move around — click any tab to switch sections. This one is your Dashboard: home base.",
  },
  {
    target: "action:new-conversation",
    route: "/dashboard",
    title: "Start a conversation",
    body: "Tell your agents what you're building — type here and hit send to kick off a conversation.",
  },
  {
    target: "action:org-panel",
    route: "/dashboard",
    title: "Meet your organization",
    body: "These are your agents — CTO, CFO, CPO, CRO and more. Click any leader to talk to them directly and hand off work by function.",
  },
  {
    target: "action:conversation-composer",
    route: "/dashboard/chat/new",
    title: "Inside a conversation",
    body: "This is a conversation with your agents. Type here to reply or follow up — @-mention a leader to hand the thread to them.",
  },

  // ── Inbox ───────────────────────────────────────────────────────────────────
  {
    target: "/dashboard/inbox",
    route: "/dashboard/inbox",
    title: "Open your Inbox",
    body: "Click the Inbox tab to jump here — email and signals from the outside world, already triaged.",
  },
  {
    target: "action:inbox-triage",
    route: "/dashboard/inbox",
    title: "Triage your Inbox",
    body: "Open a row to act on it, or mark it done to clear it. Nothing important slips past you.",
  },

  // ── Workstream ───────────────────────────────────────────────────────────────
  {
    target: "/dashboard/workstream",
    route: "/dashboard/workstream",
    title: "Open Workstream",
    body: "Click the Workstream tab to track the work in flight — everything your agents are moving forward.",
  },
  {
    target: "action:new-issue",
    route: "/dashboard/workstream",
    title: "Hand off work",
    body: "Hit “+ New Issue” to hand your agents something to move forward. Let's open it.",
  },
  // These two steps open the New Issue dialog (via `reveal`) and spotlight the two
  // ways to file work. Both carry the same `reveal` so the dialog stays open across
  // them; leaving to the next (KB) step dispatches `{ open: false }` to close it.
  {
    target: "action:issue-create-manual",
    route: "/dashboard/workstream",
    reveal: NEW_ISSUE_DIALOG_EVENT,
    title: "Write it yourself",
    body: "Give the issue a title and description, then Create issue — it lands in your Backlog for an agent to pick up.",
  },
  {
    target: "action:concierge-draft",
    route: "/dashboard/workstream",
    reveal: NEW_ISSUE_DIALOG_EVENT,
    title: "Or let Concierge draft it",
    body: "Prefer to describe the outcome? Concierge will draft and route the issue for you. This one's coming soon.",
  },

  // ── Knowledge Base ────────────────────────────────────────────────────────────
  // Special case: opening the KB SWAPS the sidebar rail for its file tree, so the
  // "Knowledge Base" nav tab only exists while you're OUTSIDE the KB. This tab step
  // therefore has NO `route` — it highlights the sidebar button from the previous
  // section's page (Workstream); the NEXT (content) step is what navigates in.
  {
    target: "/dashboard/kb",
    title: "Find the Knowledge Base",
    body: "This tab in the sidebar opens your organization's shared memory — click it to go in.",
  },
  {
    target: "action:kb-tree",
    route: "/dashboard/kb",
    title: "Feed the Knowledge Base",
    body: "Here's the KB — browse the tree and drop in the docs and context every agent draws on to act for you.",
  },

  // ── Routines ──────────────────────────────────────────────────────────────────
  {
    target: "/dashboard/routines",
    route: "/dashboard/routines",
    title: "Open Routines",
    body: "Click the Routines tab to set up recurring agent work.",
  },
  {
    target: "action:draft-routine",
    route: "/dashboard/routines",
    title: "Automate the recurring",
    body: "Open “Draft a routine with Concierge” to set up agent work that runs every day, week, or month.",
  },
  // Opens the "Draft a routine" tab (via `reveal`) and spotlights the Concierge
  // composer; leaving to the next step dispatches `{ open: false }` to switch back.
  {
    target: "action:draft-routine-composer",
    route: "/dashboard/routines",
    reveal: ROUTINE_DRAFT_TAB_EVENT,
    title: "Create a routine",
    body: "Describe the recurring work in plain language. The Concierge drafts and tests the routine, then opens a PR you approve — it goes live on merge.",
  },

  // ── Releases + Settings (tab-only) ────────────────────────────────────────────
  {
    target: "/dashboard/releases",
    route: "/dashboard/releases",
    title: "Keep up with Releases",
    body: "Click the Releases tab for a running feed of new features and fixes in Soleur.",
  },
  {
    target: "/dashboard/settings",
    route: "/dashboard/settings",
    title: "Manage your workspace",
    body: "Click the Settings tab to handle your account, team, billing, and the services your agents connect to.",
  },

  {
    target: null,
    route: "/dashboard",
    title: "You're all set",
    body: "That's the tour. You can relaunch it anytime from the “?” menu or the support panel.",
  },
] as const;

export const TOUR_STEP_COUNT = TOUR_STEPS.length;
