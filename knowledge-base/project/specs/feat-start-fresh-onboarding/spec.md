# Spec: Start Fresh Onboarding

**Feature:** Guided first-run experience for new projects
**Branch:** `feat-start-fresh-onboarding`
**Brainstorm:** [2026-04-07-start-fresh-onboarding-brainstorm.md](../../brainstorms/2026-04-07-start-fresh-onboarding-brainstorm.md)

## Problem Statement

When a founder creates a new project via "Start Fresh," they land on a static dashboard with generic suggested prompts and no context about their business. The AI team knows nothing about the startup, and the founder has no guidance on where to begin. The 2026-03-03 onboarding audit rated the "first 5 minutes" flow as FAIL.

## Goals

- G1: Capture the founder's startup idea on their first dashboard interaction
- G2: Surface 4 contextual foundation cards that guide founders through core bootstrapping (brand, validation, legal)
- G3: Cards work as smart prompts that pre-fill the chat input, leveraging tag-and-route for routing
- G4: Card completion state derived from KB file existence — no new DB schema
- G5: Dashboard transitions from first-run → foundations → full Command Center

## Non-Goals

- Gamification (badges, points, streaks, progress bars)
- Sequential/locked wizard steps
- Full bootstrap orchestration (auto-running multi-step workflows)
- Changes to the "Connect Existing Project" flow (handled naturally — existing KB files mark cards as done)
- New database schema for progress tracking
- Changes to the connect-repo onboarding wizard

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Dashboard renders a `first-run` state when no `vision.md` exists in the KB: welcome message + "What are you building?" focused prompt |
| FR2 | First chat message on a fresh project creates `knowledge-base/overview/vision.md` server-side (guaranteed, not LLM-dependent). CPO agent enhances it with structured sections. |
| FR3 | After vision capture, dashboard renders `foundations` state: 4 smart prompt cards + chat input + leader strip |
| FR4 | Each foundation card pre-fills the chat input with a static contextual prompt (no vision.md content fetch needed — agent reads KB during chat) |
| FR5 | Card completion state is derived from KB file existence checks via API |
| FR6 | When all 4 foundation KB files exist, dashboard transitions to `command-center` state (existing Command Center design) |
| FR7 | Cards have no enforced order — founders pick freely |
| FR8 | "Connect Existing Project" users see foundations state with already-complete cards if KB files exist |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Rebase onto main — dependency branch already merged as `54a727ee` |
| TR2 | KB file existence checks use existing `/api/kb/tree` or similar endpoint — no new API routes for simple existence checks |
| TR3 | Dashboard state logic lives in a single hook or component — `useDashboardState()` or similar |
| TR4 | Smart prompt pre-fill uses the chat input's existing API (no new input mechanism) |
| TR5 | Vision.md write triggered as a side-effect of the first chat response — integrated with the agent response pipeline |
| TR6 | No changes to the tag-and-route system — cards produce prompts, routing handles the rest |

## Acceptance Criteria

- [ ] New "Start Fresh" project lands on dashboard showing first-run state (no generic prompts)
- [ ] Founder's first message produces `vision.md` in the KB
- [ ] After first message, 4 foundation cards appear with Vision marked as complete
- [ ] Clicking a card pre-fills the chat input with a contextual prompt
- [ ] Completing a card's associated task (producing the KB file) updates the card to complete on next dashboard load
- [ ] All 4 cards complete → dashboard shows full Command Center
- [ ] "Connect Existing Project" with existing brand-guide.md shows that card as already complete
