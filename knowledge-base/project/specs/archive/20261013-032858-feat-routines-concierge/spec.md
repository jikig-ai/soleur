---
feature: routines-concierge
lane: cross-domain
brand_survival_threshold: single-user incident
follows: 5345
branch: feat-routines-concierge
draft_pr: 5400
---

# Spec — Routines management PR-2: Concierge authoring tab

## Problem Statement

PR-1 (#5345, merged) shipped the routines dashboard visibility-first: Routines + Recent Runs tabs, with a disabled **"Draft a routine · v2"** placeholder. Operators still cannot author or operate routines by delegation. This PR makes that third tab a working Concierge chat.

## Goals

- A working **"Draft a routine"** chat tab wired to the Concierge agent.
- **Run / verify existing routines** through the test→read-output→verify→confirm loop (the behavior the original spec emphasized), reusing PR-1's `routine_run` (gated) + `routine_runs_list` tools.
- **Author new routines via propose-as-PR**: the agent drafts the `cron-*.ts` handler + `EXPECTED_CRON_FUNCTIONS` + `ROUTINE_METADATA` entries and opens a GitHub PR (reusing existing GitHub MCP tools). Edit/remove likewise as code-change PRs.

## Non-Goals

- **Runtime routine CRUD / DB-backed dynamic routines** (no `custom_routines` table, no generic dispatcher) — deferred; routines remain code-defined.
- No new data surface / DB table → no new DSAR or legal-doc lockstep.
- No changes to PR-1's run-log schema or the `runRoutine` chokepoint contract.

## Functional Requirements

- **FR1** — Add a third tab "Draft a routine" to `components/routines/routines-surface.tsx` (expand tab union `"routines"|"runs"` → `+"draft"`; replace the disabled placeholder with an active `TabButton`). Wireframe: `knowledge-base/product/design/routines/screenshots/05-draft-tab-intro-empty-state.png`.
- **FR2** — Intro/empty state: two capability cards (draft-new→PR vs run/verify-existing) + suggestion chips + composer with the "ships as code; approve the PR" hint. (screen 05)
- **FR3** — Chat panel reuses the existing Concierge chat patterns (MessageBubble / ChatInput / review-gate card) and the existing agent path (agent-runner / cc-dispatcher / review-gate). Plan decides full `<ChatSurface>` embed vs. a lighter embedded panel.
- **FR4** — Run-&-verify loop (screen 07): operator asks to run/verify an existing routine → the gated `routine_run` review-gate is the single confirmation → agent reads back the run via `routine_runs_list` → assistant message verifies status/output and confirms correctness, linking to Recent Runs.
- **FR5** — Protected-routine confirmation variant (screen 08): heightened warning + side-effects + Deny as safe default for `manualTrigger:"confirm"` routines (carried from PR-1 metadata).
- **FR6** — Create flow (screen 06): agent drafts a routine and opens a GitHub PR; surfaces "Opened PR #NNNN" with a link + the "goes live after merge & deploy" note. The agent must NOT claim it created a live routine.
- **FR7** — Agent system-prompt guidance: there is no `create_routine` tool; "create/edit/remove" = author code + open a PR. For a freshly-proposed routine the agent verifies the generated code (matches existing cron patterns, typechecks) and states the live run happens post-merge — it does not fabricate a run result.

## Technical Requirements

- **TR1** — Reuse PR-1 tools (`routine_run`, `routines_list`, `routine_runs_list`) and existing GitHub MCP tools; no new MCP tool unless the plan shows a gap.
- **TR2** — `routine_run` stays `gated`; the review-gate is the single confirmation (no double-gate). No change to `run-routine.ts` or `tool-tiers.ts` tiers.
- **TR3** — UI is operator-session-gated (same auth as the other dashboard routes). No new API surface beyond what the existing chat path provides.
- **TR4** — Tests: component tests for the new tab + states; verify the agent system-prompt guidance is present; no regression to PR-1 tabs.
- **TR5** — `.pen` wireframe committed under `knowledge-base/product/design/routines/` (extends PR-1's file).

## User-Brand Impact

- **If broken:** the Draft tab fails to author/verify routines, or the agent runs the wrong production routine off-schedule / opens a malformed PR in the operator's name.
- **If it leaks / mis-acts:** an agent-initiated run takes real production action — mitigated by the `routine_run` review-gate (single human confirmation naming the routine); a proposed PR could carry bad code — mitigated by human PR review + CI.
- **Brand-survival threshold:** single-user incident.
