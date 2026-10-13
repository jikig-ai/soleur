---
title: Tasks — fix(cc-concierge) prefill 400 on resume (#3250)
date: 2026-05-05
status: ready
plan: knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md
issue: 3250
branch: feat-one-shot-fix-concierge-prefill-3250
---

# Tasks — Concierge prefill-guard

Derived from `2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md`. Hierarchical numbering. TDD ordering enforced (RED before GREEN per AGENTS.md `cq-write-failing-tests-before`).

## 1. Setup

- 1.1 Read the plan in full before starting. Re-read after any context compaction (AGENTS.md `hr-always-read-a-file-before-editing-it`).
- 1.2 Confirm worktree branch is `feat-one-shot-fix-concierge-prefill-3250` and is current with `origin/main`.
- 1.3 Skim `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` to understand the existing `mock.module("@anthropic-ai/claude-agent-sdk", ...)` and DB-deps mocking pattern. The new test file reuses this scaffolding.

## 2. RED — write failing regression tests

- 2.1 Create `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts`.
- 2.1.1 Mock `@anthropic-ai/claude-agent-sdk`: stub both `query` (return a minimal `Query` shape — async iterable that yields a synthetic `result` message and ends) and `getSessionMessages` (per-test stub).
- 2.1.2 Mock `./observability` so `warnSilentFallback` is a spy whose calls can be asserted.
- 2.1.3 Mock `fetchUserWorkspacePath` / `getUserApiKey` / `getUserServiceTokens` and `patchWorkspacePermissions` (reuse the pattern from `cc-dispatcher-real-factory.test.ts`).
- 2.1.4 Implement test scenario 1: `drops resume when persisted session ends with assistant message`.
- 2.1.5 Implement test scenario 2: `preserves resume when persisted session ends with user message`.
- 2.1.6 Implement test scenario 3 (deepen-pass refined): `emits prefill-guard-empty-history warn and preserves resume when getSessionMessages returns []`. The non-empty `resumeSessionId` + empty history case is observability-gated, not silent.
- 2.1.7 Implement test scenario 4: `preserves resume when getSessionMessages throws` (probe-failed warn under distinct op `prefill-guard-probe-failed`).
- 2.1.8 Implement test scenario 5: `no-op when resumeSessionId is undefined` — `getSessionMessages` not called.
- 2.1.9 Implement test scenario 6: `uses workspacePath as the dir argument to getSessionMessages` (drift-guard).
- 2.2 Run `cd apps/web-platform && bun test test/cc-dispatcher-prefill-guard.test.ts`. ALL six MUST FAIL (no guard yet → `getSessionMessages` is never called and `resume:` always reaches `sdkQuery`).
- 2.3 Commit RED: `test: add failing prefill-guard regression for cc-concierge resume (#3250)`.

## 3. GREEN — implement the thread-shape guard

- 3.1 Open `apps/web-platform/server/cc-dispatcher.ts`.
- 3.2 Extend the `@anthropic-ai/claude-agent-sdk` import to also bring `getSessionMessages`.
- 3.3 Extend the `./observability` import to also bring `warnSilentFallback`.
- 3.4 Inside `realSdkQueryFactory`, after `await patchWorkspacePermissions(workspacePath)` and before the `try { return sdkQuery({ ... }) }` block, add the guard block as specified in plan Phase 2: declare `safeResumeSessionId`, probe `getSessionMessages(args.resumeSessionId, { dir: workspacePath })`, then branch:
   - `history.length === 0` → emit warn with `op: "prefill-guard-empty-history"`, pass-through.
   - `last.type === "assistant"` (positive match, not negated) → emit warn with `op: "prefill-guard"`, set `safeResumeSessionId = undefined`.
   - probe throws → emit warn with `op: "prefill-guard-probe-failed"`, pass-through.
- 3.5 Replace `resumeSessionId: args.resumeSessionId` in the `buildAgentQueryOptions` call with `resumeSessionId: safeResumeSessionId`.
- 3.6 Re-run the prefill-guard test file: all six scenarios must pass.
- 3.7 Commit GREEN: `fix(cc-concierge): drop resume on assistant-terminated thread (#3250)`.

## 4. REFACTOR — verify drift-guards + legacy audit

- 4.1 Run the full cc-related suite: `bun test test/cc-dispatcher.test.ts test/cc-dispatcher-real-factory.test.ts test/agent-runner-query-options.test.ts test/soleur-go-runner.test.ts test/cc-dispatcher-prefill-guard.test.ts` — all green.
- 4.2 `cd apps/web-platform && bun run typecheck` — green.
- 4.3 `cd apps/web-platform && bun run build` — green.
- 4.4 Phase 3 legacy audit: query Sentry over 90d for `error.type=invalid_request_error message:*prefill*`. Capture count + breakdown by feature tag. Paste the result into the PR description.
- 4.4.1 If hits found on legacy paths (feature `agent-runner` or unset), extract `applyPrefillGuard` to `apps/web-platform/server/agent-prefill-guard.ts` with signature `(args: { resumeSessionId, workspacePath, userId, conversationId, feature }) => Promise<{ safeResumeSessionId: string | undefined }>`. Apply at both call sites (`realSdkQueryFactory` and legacy `startAgentSession`). Add a parallel test file for the legacy call site.
- 4.4.2 If zero hits, file a GitHub issue (`audit: legacy startAgentSession resume-prefill guard parity`) milestoned to `Post-MVP / Later` per `wg-when-deferring-a-capability-create-a`. Defer the fold-in.
- 4.5 Commit any refactor as `refactor(cc-concierge): <change>`.

## 5. Ship

- 5.1 Run compound (`skill: soleur:compound`) BEFORE final commit per `wg-before-every-commit-run-compound-skill`.
- 5.2 Push branch: `git push -u origin feat-one-shot-fix-concierge-prefill-3250`.
- 5.3 Run `skill: soleur:review` — review pipeline MUST include `user-impact-reviewer` per the brand-survival threshold and `hr-weigh-every-decision-against-target-user-impact`.
- 5.4 Resolve all review findings inline per `rf-review-finding-default-fix-inline`.
- 5.5 Open PR with `Closes #3250` in the body. Title: `fix(cc-concierge): drop resume on assistant-terminated thread (#3250)`. Apply `priority/p1-high`, `bug`, `semver:patch` labels.
- 5.6 Run `skill: soleur:ship`. Phase 5.5 user-impact gate fires (single-user threshold). Phase 6 preflight Check 6 verifies the User-Brand Impact section exists and is non-empty.
- 5.7 After CI green, `gh pr merge <number> --squash --auto`; poll until MERGED; run `cleanup-merged`.
- 5.8 Post-merge: query Sentry 24h for `feature:cc-concierge op:prefill-guard` (expect non-zero — guard firing in prod) AND for `error.message:*prefill*` from cc-concierge (expect ~zero, validating the fix).
- 5.9 Capture session learning under `knowledge-base/project/learnings/<topic>.md` (date picked at write time per `cq` sharp edge).
