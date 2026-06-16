# Brainstorm — Routines management PR-2: Concierge authoring tab (#5345 follow-up)

**Date:** 2026-06-16
**Branch:** feat-routines-concierge · **Draft PR:** #5400
**Brand-survival threshold:** single-user incident (inherited from PR-1; an agent that runs production routines off-schedule and opens code PRs is the same risk class)

## What We're Building

The third tab of the routines dashboard — the working **"Draft a routine"** Concierge chat (PR-1 shipped it as a disabled `v2` placeholder). A chat panel wired to the Concierge agent that lets the operator author and operate Inngest routines by delegation.

## Why This Approach (Key Architectural Finding)

**Routines are code-only.** All 43 routines are hard-coded Inngest cron functions in `EXPECTED_CRON_FUNCTIONS` (`server/inngest/cron-manifest.ts`); there is **no runtime CRUD** and no DB table for routine definitions. So "create a routine" cannot literally add a running cron without a code change + deploy.

**Chosen direction (operator decision 2026-06-16): Propose-as-PR + run/verify.**
- **Create / edit / remove** → the Concierge designs the routine and opens a **GitHub PR** (generates the `cron-*.ts` handler + `EXPECTED_CRON_FUNCTIONS` + `ROUTINE_METADATA` entries), reusing the existing GitHub MCP tools. Human merges → CI deploys → it appears in the Routines tab.
- **Review / run / verify EXISTING routines** → the spec's core loop: run off-schedule via the PR-1 `routine_run` gated tool (the review-gate IS the single confirmation), read back the run via `routine_runs_list`, verify status/output, then confirm correctness to the operator.
- The **test→read-output→verify→confirm** loop applies to *runnable* (existing) routines. For a freshly-**proposed** routine the agent cannot run it pre-merge, so it verifies the *generated code* (matches existing cron patterns, typechecks) and states clearly that the live run happens after merge+deploy.

No new runtime infrastructure, no new DB table, ships as ~1 PR. Reuses PR-1's tools + the existing agent-runner / cc-dispatcher / review-gate chat path.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Create/edit/remove = **propose-as-PR** (not runtime CRUD) | Routines are code-defined; no runtime authoring surface exists. Honest within today's architecture. |
| 2 | Run/verify existing routines = the **test→verify→confirm loop** via PR-1 `routine_run` + `routine_runs_list` | The loop the original spec emphasized; fully supported today. |
| 3 | Reuse the **existing chat surface** components (MessageBubble + ChatInput + review-gate cards) for the tab | Parity with the main Concierge; the review-gate is the single confirmation for `routine_run`. Wireframe decides full `<ChatSurface>` embed vs. a lighter embedded panel. |
| 4 | Agent **system-prompt guidance**: there is NO `create_routine` tool — "create" means draft code + open a PR | Prevents the agent hallucinating a non-existent tool; binds creation to human PR review + CI. |
| 5 | No new DB table / dispatcher (DB-backed dynamic routines deferred) | YAGNI; runtime CRUD is a separate, much larger effort (own migration + generic dispatcher + security pass). |
| 6 | Visual design | Wireframe: `knowledge-base/product/design/routines/` (Phase 3.55) — TO LINK |

## User-Brand Impact

- **If this lands broken, the user experiences:** the Draft tab chat fails to author/verify routines, or — worse — the agent runs the *wrong* production routine off-schedule, or opens a malformed PR in the operator's name.
- **If this leaks / mis-acts:** an agent-initiated run takes a real production action (content publish, legal audit, external egress) — mitigated by the `routine_run` review-gate (single human confirmation naming the routine) carried over from PR-1; a proposed-PR could carry bad code — mitigated by human PR review + CI.
- **Brand-survival threshold:** single-user incident.

## Open Questions

1. **Chat UI weight** — full `<ChatSurface>` embed (max parity, heavier; needs a per-draft `conversationId`) vs. a lighter embedded chat panel scoped to routine authoring. → wireframe to propose; lean lighter-but-reusing-components.
2. **Conversation scoping** — does the Draft tab open its own conversation, or reuse the operator's main Concierge thread with routine context? → wireframe + plan.
3. **PR-proposal UX** — how the agent surfaces "I opened PR #NNNN" in chat (link card? the existing tool-use bubble?).

## Domain Assessments

**Assessed:** Engineering, Product, Legal (CTO/CPO/CLO triad — user-brand-critical). Marketing, Operations, Sales, Finance, Support: not relevant (internal operator tool).

### Engineering (CTO)
**Summary:** Reuse the merged agent-runner/cc-dispatcher/review-gate path + PR-1 routine tools + existing GitHub PR tools; no new runtime infra. The only net-new code is the Draft tab UI + agent system-prompt guidance binding "create" to propose-as-PR. Routines being code-only is the load-bearing constraint.

### Product (CPO)
**Summary:** The test→verify→confirm loop on existing routines is the high-value core and is fully supported today; propose-as-PR is an honest "create" that keeps a human in the merge loop. Defer DB-backed runtime CRUD until there's demand.

### Legal (CLO)
**Summary:** Same posture as PR-1 — agent runs of production routines are gated by the single review-gate confirmation; no new data surface or table, so no new DSAR/legal-doc lockstep. PR-proposal is code authorship, not a data-processing change.
