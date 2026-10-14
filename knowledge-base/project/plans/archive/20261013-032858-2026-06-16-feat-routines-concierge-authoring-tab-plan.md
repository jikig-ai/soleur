---
title: Routines management PR-2 — Concierge authoring tab
type: feat
issue: 5402
follows: 5345
branch: feat-routines-concierge
worktree: .worktrees/feat-routines-concierge
draft_pr: 5400
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan — Routines management PR-2: Concierge authoring tab

## Overview

Turn the disabled "Draft a routine · v2" placeholder (PR-1) into a working Concierge chat tab. The operator can: (a) **draft/edit/remove** routines, where the agent authors the `cron-*.ts` handler + manifest + metadata entries and opens a **GitHub PR** (routines are code-only — no runtime CRUD); (b) **run & verify EXISTING** routines via the PR-1 `routine_run` (gated) → `routine_runs_list` test→verify→confirm loop.

The implementation reuses the entire existing chat + agent stack. Net-new surface is small: the Draft tab UI + a whitelisted `context.type` ("routine-authoring") that injects a system-prompt mode directive. No new DB table, no new MCP tool, no new runtime infra.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (file:line) | Plan response |
|-------|---------------------|---------------|
| "Concierge creates a routine" | Routines are code-only: `EXPECTED_CRON_FUNCTIONS` is a hard-coded array (`server/inngest/cron-manifest.ts:22-66`); no runtime CRUD, no routine-def table. | Create = **propose-as-PR** (agent drafts code + opens PR). Operator-approved direction. |
| Embed a chat panel | `ChatSurface` (`components/chat/chat-surface.tsx:171-178`) takes `conversationId` + `variant`; `variant="sidebar"` uses `h-full`, no header — built for embedding (`:573-576`). New convo = create-on-first-message over WS (`conversationId="new"` → `startSession` → `ws-client.ts:1720`). | Mount `<ChatSurface variant="sidebar" conversationId="new" resumeByContextPath="routines/draft">` in the tab. No `/api/conversations`, no new chat infra. |
| `context.type` already scopes agent behavior | **WRONG (net-new behavior).** `context.type` is accepted on the wire but read NOWHERE that selects a directive — even `"kb-viewer"` is inert (only a display string at `domain-router.ts:132`); the artifact directive gates on `context.content`/`.path`, never `.type`. Only `"kb-viewer"` passes `ALLOWED_CONTEXT_TYPES` (`context-validation.ts:18,42`). | Whitelist `"routine-authoring"` AND thread `context.type` to the **cc-dispatcher** prompt builder (see next row) to inject a real mode directive. This is NET-NEW behavior, not an established pattern. |
| Directive append seam = `agent-runner.ts:1304` | **WRONG / dead path (plan-review P1-1/P1-2).** A new leader-less conversation (`conversationId="new"`) materializes as `soleur_go_pending` and is dispatched via `ws-handler.ts:2215` `dispatchSoleurGoForConversation` → `dispatchSoleurGo` (cc-dispatcher) — the legacy `startAgentSession`/`agent-runner.ts:1304` is bypassed entirely. `dispatchSoleurGoForConversation` (`ws-handler.ts:1091-1251`) reads only `context.path`/`.content`, dropping `.type`. | Real seam: thread `context.type` through `dispatchSoleurGoForConversation` → `dispatchSoleurGo` → `buildSoleurGoSystemPrompt` (`cc-dispatcher.ts`), and append `ROUTINE_AUTHORING_DIRECTIVE` there. |
| `context.path="routines/draft"` for the mode flag | **WRONG (P1-3/P1-4).** `isSafePath` (`context-validation.ts:14`) requires a file extension; `validateContextPath` (for `resumeByContextPath`) requires `startsWith("knowledge-base/")` + extension. `"routines/draft"` fails both → session aborts. | Use `context.type` PURELY as the mode flag: send `initialContext={{ type: "routine-authoring" }}` with NO path/content; drop `resumeByContextPath`. Ensure `validateConversationContext` accepts a type-only context (no path) — relax if it requires a path. |
| GitHub PR authoring available | `buildGithubTools` is wired **only `if (installationId && repoUrl)`** (`agent-runner.ts:1500/1460`); `create_pull_request`/`github_push_branch` exist (`server/github-tools.ts:76,162`), both `gated`. Run/verify tools are registered UNCONDITIONALLY. | Create→PR works **only when a repo is connected** (two gated approvals: push + PR). The directive MUST condition the create-half on repo-connection — if github tools are absent, instruct the agent to tell the operator to connect a repo first, NOT to fabricate. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the Draft tab fails to author/verify routines, or — worse — the agent runs the *wrong* production routine off-schedule, or opens a malformed PR in the operator's name.
- **If this leaks / mis-acts, the user's workflow is exposed via:** an agent-initiated off-schedule run takes a real production action (content publish, legal audit, external egress) in the operator's name — mitigated by the `routine_run` review-gate (single human confirmation naming the routine, carried from PR-1); a proposed PR could carry bad code — mitigated by human PR review + CI.
- **Brand-survival threshold:** single-user incident. CPO sign-off carried from brainstorm (CPO assessment in `## Domain Review`); `user-impact-reviewer` runs at PR-review time.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Reuse merged agent-runner/cc-dispatcher/review-gate path + PR-1 routine tools + existing GitHub PR tools. Only net-new: Draft tab UI + a whitelisted `context.type` that appends a mode directive at the existing system-prompt seam. Routines being code-only is the load-bearing constraint; create = propose-as-PR.

### Product (CPO)
**Status:** reviewed (carry-forward) — sign-off recorded
**Assessment:** The test→verify→confirm loop on existing routines is the high-value core and is fully supported today; propose-as-PR keeps a human in the merge loop. Defer DB-backed runtime CRUD until demand exists. Mocks 05-08 approved by operator.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** Same posture as PR-1 — agent runs are gated by the single review-gate; no new data surface or DB table → no new DSAR/legal-doc lockstep. PR authoring is code authorship, not a data-processing change.

### Product/UX Gate
**Tier:** blocking (new user-facing chat surface)
**Decision:** reviewed — wireframes 05-08 approved by operator (mock sign-off 2026-06-16)
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55), spec-flow-analyzer (plan-review)
**Pencil available:** yes

## Observability

```yaml
liveness_signal:
  what: the existing chat/agent session telemetry (sentry-correlation middleware) covers the Draft-tab agent session — no new session type
  cadence: per agent session
  alert_target: Sentry (existing agent-session error rules)
  configured_in: server/inngest/middleware/sentry-correlation.ts (existing)
error_reporting:
  destination: Sentry (existing canUseTool / agent-runner capture sites)
  fail_loud: yes — agent tool failures surface in the chat as error bubbles + Sentry
failure_modes:
  - mode: context.type "routine-authoring" rejected by validation
    detection: start_session rejected; chat shows connection error
    alert_route: Sentry (context-validation throw path) + the component test asserting the whitelist
  - mode: mode directive not appended (system-prompt seam regression)
    detection: server unit test asserts the directive text appears when context.type==="routine-authoring"
    alert_route: CI test-webplat
  - mode: agent fabricates a run result for an un-merged routine
    detection: directive instructs against it; verified existing routines run through routine_run + read-back routine_runs_list (real run-log)
    alert_route: human review-gate (single confirmation) + run-log is the source of truth
logs:
  where: existing agent-session logs (Sentry + journald per sentry-correlation)
  retention: existing platform retention
discoverability_test:
  command: "grep -q routine-authoring apps/web-platform/server/context-validation.ts && grep -q ROUTINE_AUTHORING apps/web-platform/server/cc-dispatcher.ts && echo OK"
  expected_output: "OK (the whitelist entry + the cc-dispatcher directive append both present; no ssh)"
```

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
0.1 Confirm the cc-dispatcher routing claim: a `conversationId="new"`, leader-less conversation dispatches via `ws-handler.ts:2215` `dispatchSoleurGoForConversation` (not `startAgentSession`). Trace `context` from `dispatchSoleurGoForConversation` (`ws-handler.ts:1091-1251`) → `dispatchSoleurGo` → `buildSoleurGoSystemPrompt` and confirm `context.type` is NOT currently passed.
0.2 Confirm `validateConversationContext` accepts a type-only context (`{type:"routine-authoring"}`, no path). If it requires a path (`isSafePath`), the fix is to skip the path check when `path` is absent (the `content`/`path` resolution is already optional in `dispatchSoleurGoForConversation`).

### Phase 1 — RED (tests first, per cq-write-failing-tests-before)
1.1 `test/components/routines/routines-surface.test.tsx` (extend): Draft tab is active (not disabled); clicking it shows the intro state (two capability cards + suggestion chips + composer hint); mounts the chat container with `initialContext.type === "routine-authoring"`. Assert the existing Routines/Recent Runs tabs still work (no regression).
1.2 `test/server/context-validation.test.ts` (extend or create): `"routine-authoring"` passes validation (with NO path); an unknown type still throws; `"kb-viewer"` still passes.
1.3 `test/server/cc-dispatcher.routine-authoring-directive.test.ts` (create): assert `buildSoleurGoSystemPrompt` includes the `ROUTINE_AUTHORING_DIRECTIVE` text when invoked with the routine-authoring mode flag, and does NOT when absent. Import the `ROUTINE_AUTHORING_DIRECTIVE` constant directly. Fold the append into the existing prompt-builder rather than inventing a `selectDirective()` abstraction (per simplicity review — no YAGNI seam). Also assert the directive contains NO "auto-approve / run without asking / skip confirmation" phrasing (security nit).

### Phase 2 — GREEN
2.1 Create `server/routine-authoring-directive.ts` exporting `ROUTINE_AUTHORING_DIRECTIVE` — instructs the agent: (a) there is NO `create_routine` tool; to create/edit/remove a routine, author the `cron-*.ts` handler **including its `{ cron: "..." }` schedule literal**, add the id to `EXPECTED_CRON_FUNCTIONS` (`cron-manifest.ts`), add a `ROUTINE_METADATA` entry (`routine-metadata.ts`), **AND register the function in the Inngest client** — then open a GitHub PR via the gated tools (enumerate ALL FOUR edits, else the routine passes parity but never schedules); (b) **if the github PR tools are not available (no connected repo), tell the operator to connect a repo first — do NOT improvise or claim a PR was opened**; (c) a newly-proposed routine cannot run until merged+deployed — say so explicitly, do NOT fabricate a run result; (d) to verify an EXISTING routine, use `routine_run` (gated; the review-gate is the single confirmation — do NOT seek a second confirmation) then read back the result via `routine_runs_list` and report status/output.
2.2 `server/context-validation.ts`: add `"routine-authoring"` to `ALLOWED_CONTEXT_TYPES`; allow a type-only context (no path) per Phase 0.2.
2.3 `server/ws-handler.ts` + `server/cc-dispatcher.ts`: thread `context.type` from `dispatchSoleurGoForConversation` → `dispatchSoleurGo` → `buildSoleurGoSystemPrompt`; append `ROUTINE_AUTHORING_DIRECTIVE` when `type === "routine-authoring"`. (`lib/types.ts` `ConversationContext.type` is `string` — no union edit needed; `ws-zod-schemas.ts` `type` is `z.string()` — no schema edit.)
2.4 `components/routines/routines-surface.tsx`: expand tab union `"routines"|"runs"` → `+"draft"`; replace the disabled placeholder with an active `TabButton` ("Draft a routine", sparkles, "new" tag); add `DraftRoutineTab` rendering the intro overlay (cards + chips + composer hint per mock 05) that, on first interaction, mounts `<ChatSurface variant="sidebar" conversationId="new" initialContext={{ type: "routine-authoring" }} />` inside an `h-full min-h-0` container (NO `path`, NO top-level `resumeByContextPath` — sidebar-only props go under `sidebarProps`). Create/run-verify/protected-confirm flows (mocks 06/07/08) are produced by the existing ChatSurface review-gate + tool-use rendering; no new card components.

### Phase 3 — Verify
3.1 `./node_modules/.bin/tsc --noEmit` clean.
3.2 Feature tests green; full `test-webplat` locally for the touched server files.
3.3 Browser QA (soleur:qa): Draft tab loads, intro renders, a run-verify request shows the gate → run-log read-back; a create request opens a PR (gated).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Draft tab is active (replaces the disabled v2 placeholder); Routines + Recent Runs tabs unaffected.
- [ ] Intro state matches mock 05 (two capability cards, suggestion chips, composer hint).
- [ ] `context.type === "routine-authoring"` (no path) passes validation; unknown types still throw.
- [ ] `buildSoleurGoSystemPrompt` (cc-dispatcher path) appends `ROUTINE_AUTHORING_DIRECTIVE` iff the routine-authoring mode flag is set, threaded from `dispatchSoleurGoForConversation` (unit-tested) — NOT the bypassed `agent-runner.ts` path.
- [ ] The directive: enumerates all FOUR create edits (handler+cron literal / EXPECTED_CRON_FUNCTIONS / ROUTINE_METADATA / Inngest client registration); instructs propose-as-PR; the run/verify loop for existing; "never fabricate a run result for an un-merged routine"; conditions create on repo-connection (tell operator to connect a repo if github tools absent); contains NO gate-bypass phrasing.
- [ ] No-repo path: with no connected GitHub repo, the create flow degrades gracefully (agent instructs the operator to connect a repo) rather than improvising — run/verify still works (routine tools are unconditional).
- [ ] `routine_run` remains `gated` (no tier change); the review-gate is the single confirmation (no double-gate).
- [ ] ChatSurface mount uses valid props (`variant="sidebar"`, top-level `initialContext`; sidebar-only props under `sidebarProps`); tsc clean; CI green.
- [ ] `Closes #5402` in PR body.

### Post-merge (operator/agent)
- [ ] Browser QA on dev confirms the run-verify loop + a create→PR flow (soleur:qa during ship).
- [ ] No prd migration (no DB change) — N/A.

## Files to Edit
- `apps/web-platform/components/routines/routines-surface.tsx` — Draft tab + DraftRoutineTab + ChatSurface mount (`variant="sidebar"`, `initialContext={{type:"routine-authoring"}}`, no path).
- `apps/web-platform/server/context-validation.ts` — whitelist `"routine-authoring"`; allow type-only context (no path).
- `apps/web-platform/server/ws-handler.ts` — thread `context.type` through `dispatchSoleurGoForConversation` → `dispatchSoleurGo`.
- `apps/web-platform/server/cc-dispatcher.ts` — accept the mode flag in `buildSoleurGoSystemPrompt`; append `ROUTINE_AUTHORING_DIRECTIVE`.
- (NOT `agent-runner.ts` — that path is bypassed for leader-less convos; NOT `lib/types.ts`/`ws-zod-schemas.ts` — `type` is already `string`/`z.string()`.)

## Files to Create
- `apps/web-platform/server/routine-authoring-directive.ts` — the `ROUTINE_AUTHORING_DIRECTIVE` constant (importable by the unit test; this is its earned justification).
- `apps/web-platform/test/server/cc-dispatcher.routine-authoring-directive.test.ts`
- (extend) `apps/web-platform/test/components/routines/routines-surface.test.tsx`, `apps/web-platform/test/server/context-validation.test.ts`

## Open Code-Review Overlap
None — checked open `code-review` issues; no body references `routines-surface.tsx`, `agent-runner.ts` system-prompt seam, or `context-validation.ts` for this scope.

## Sharp Edges
- **The directive seam is the cc-dispatcher, NOT `agent-runner.ts` (plan-review P1).** A leader-less `conversationId="new"` convo routes via `dispatchSoleurGoForConversation` → `dispatchSoleurGo` → `buildSoleurGoSystemPrompt`; the legacy `startAgentSession`/`agent-runner.ts:1304` path is bypassed. Threading `context.type` there is INERT. This is net-new behavior — `context.type` (incl. `kb-viewer`) is read nowhere that selects a directive today.
- **Mode flag must NOT be a fake path.** `context.path="routines/draft"` fails `isSafePath` (needs an extension) and `resumeByContextPath` needs `knowledge-base/…ext`. Send `{type:"routine-authoring"}` with NO path; do not invent a `routines/draft.md` (the cc-dispatcher would try to resolve it as a KB doc and find nothing).
- **GitHub PR tools are conditional on a connected repo** (`if installationId && repoUrl`). The create-half is dead without one — the directive must tell the operator to connect a repo, not improvise. Run/verify tools are unconditional.
- **A created routine needs FOUR edits** (handler+`{cron}` literal / `EXPECTED_CRON_FUNCTIONS` / `ROUTINE_METADATA` / Inngest client registration). Three edits pass the parity test but the routine never schedules — enumerate all four in the directive.
- **`context.content` is framed "treat as data, not instructions"** — do NOT smuggle the directive through it (weak steering); use the trusted system-prompt append.
- **`variant="full"` hardcodes `h-[100dvh]` + its own header** — use `variant="sidebar"` (`h-full`, no header) for the tab.
- **Two gated approvals** in the create flow (push branch + open PR) — mock 06 should not imply a single click.
- `routine_run` stays gated; do NOT add a second confirmation (the review-gate IS the confirmation — avoid the double-gate PR-1 resolved). The gate is structural (`canUseTool` tier check); the directive cannot bypass it — and must contain no gate-bypass phrasing.
