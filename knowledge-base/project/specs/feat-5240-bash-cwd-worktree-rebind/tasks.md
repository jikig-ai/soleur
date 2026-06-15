---
title: Tasks — Bash sandbox worktree-rebind guardrail (#5313)
spec: knowledge-base/project/specs/feat-5240-bash-cwd-worktree-rebind/spec.md
plan: knowledge-base/project/plans/2026-06-15-fix-bash-sandbox-worktree-rebind-guardrail-plan.md
issue: 5313
parent_epic: 5240
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks: Bash sandbox worktree-rebind guardrail

Runtime, compliance-independent bounded fail-loud guardrail + repro-verify. **No `allowWrite`/`denyRead`
change.** Test runner: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. Typecheck:
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 0 — Repro / root-cause confirmation (gates Phase 4 only)

- [ ] 0.1 (FR1.1) Confirm whether a mid-session worktree at `/workspaces/<uuid>/.worktrees/<b>` is
  `cd`/`ls`/`git -C`-able from the Bash sandbox under the current (post-#5256) resolver. Lightweight
  (read-through + targeted check, not a heavy bwrap harness). Record verdict.
- [ ] 0.2 (FR1.3) Select the decision-tree leaf from 0.1: (i) reachable → no-op, document "root cause
  fixed by #5256"; (ii) workspace_id drift → narrow companion fix in Phase 4; (iii) cwd-frozen-at-root →
  STOP, file follow-up (skip-worktrees re-scope), do NOT expand this PR; (iv) precedence → document + test.

## Phase 1 — Runtime detector (FR2.2, the durable core)

- [ ] 1.1 (RED, AC1) Write the failing round-trip test: feed 3 consecutive `cd <path> && pwd` Bash
  tool-results with mismatched `pwd` through the `extractBashToolResults` path
  (`soleur-go-runner.ts:696`); assert exactly one `worktree_enter_failed` `WorkflowEnd`. (`.test.ts`, node project.)
- [ ] 1.2 (RED) Counter-case test: 2 mismatched then 1 matching `pwd` → no termination.
- [ ] 1.3 (GREEN) Implement the N=3 near-identical-CWD-verify detector in the `extractBashToolResults`
  path. Counter modeled on `LEADER_MAX_TURNS` (`agent-on-spawn-requested.ts:323`). No cooperative marker.

## Phase 2 — Honest terminal status + wire + render (FR2.3; C2, C3)

- [ ] 2.1 (FR2.3) Add `worktree_enter_failed` to the `WorkflowEnd` status discriminator union
  (`lib/types.ts`; `soleur-go-runner.ts:748-762`); `_AssertWorkflowEndStatusMatches` (`:789`) forces
  exhaustiveness.
- [ ] 2.2 (**C2**, AC4) Add `worktree_enter_failed` to the hand-maintained `z.enum` duplicate in
  `ws-zod-schemas.ts` (precedent `:439-468`). **Grep the literal status members, not the type symbol.**
  Test: emitted status passes wire-schema validation.
- [ ] 2.3 (FR2.3 emit) Emit the status from the detector; mirror via `reportSilentFallback(err,
  {feature:"agent-sandbox", op:"worktree_enter", extra:{expectedPath, observedCwd, attempts}})` — NOT
  `mirrorP0Deduped`. Add the detection-rate metric (Observability).
- [ ] 2.4 (**C3**, AC7) Honest render: add the title branch at `chat-surface.tsx:699-711`; ensure
  `message-bubble.tsx:369-391` does NOT render "Agent stopped responding" for this status. Render test
  is `.test.tsx` in the **DOM project** (`setup-dom.ts`).
- [ ] 2.5 (**I2**, AC9) If the status surfaces in `ws-client.ts:883-931` (if-chain, `tsc`-blind), add the
  branch by hand.

## Phase 3 — Single-terminal invariant + genuine-hang preservation (FR2.4)

- [ ] 3.1 (AC8) On emit, call `clearTurnHardCap` (`soleur-go-runner.ts:1730`). Test: status emitted while
  the runaway timer is armed → exactly one `WorkflowEnd`.
- [ ] 3.2 (AC6) Test: a turn with NO CWD-verify-loop signal still terminates via the runaway breaker (no
  permanent suppression).

## Phase 4 — Prose gate (FR2.1, advisory) + conditional residual fix

- [ ] 4.1 (FR2.1, AC3) Bound the one-shot CWD gate prose to ≤3 (`one-shot/SKILL.md:70-76` only; no broad
  grep). Not load-bearing — the detector (Phase 1) is the enforcement.
- [ ] 4.2 (FR1.3(ii), conditional) ONLY if Phase 0.2 selected leaf (ii): the narrow workspace_id-tracking
  fix. Must NOT touch `allowWrite`/`denyRead`.

## Phase 5 — Verify + sign-off

- [ ] 5.1 (AC5) `agent-runner-helpers.test.ts` GREEN UNCHANGED; `git diff` touches no
  `allowWrite`/`denyRead`/seccomp/AppArmor/Docker-bind.
- [ ] 5.2 (AC9) `tsc --noEmit` clean (incl. `_AssertWorkflowEndStatusMatches` exhaustiveness).
- [ ] 5.3 (AC10) Full changed-test run green (node `.test.ts` + DOM `.test.tsx`).
- [ ] 5.4 security-sentinel + CTO sign-off (sandbox-adjacent change, `requires_security_signoff`); ADR
  only if 4.2 fired.
- [ ] 5.5 (AC11) PR body: `Ref #5240` + `Closes #5313`.
