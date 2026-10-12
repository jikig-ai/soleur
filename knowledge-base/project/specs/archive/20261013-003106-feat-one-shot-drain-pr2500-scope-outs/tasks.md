# Tasks: Drain PR #2500 scope-out backlog (#2510 + #2511 + #2512)

Derived from `knowledge-base/project/plans/2026-04-18-refactor-drain-pr2500-scope-outs-plan.md`.

Execution order mirrors the plan's dependency graph: Phase 1 (helper) → Phase 2 (apply) → Phase 3 (query collapse) → Phase 4 (MCP tool).

## Phase 1 — `withUserRateLimit` helper (#2510)

- 1.1 RED — author `apps/web-platform/test/with-user-rate-limit.test.ts` covering 7 scenarios: unauth bypass, under-quota, at-boundary, over-quota, Sentry mirror tag, per-user key isolation, per-feature counter isolation. Test file must fail against an empty stub before Phase 1.2.
- 1.2 GREEN — create `apps/web-platform/server/with-user-rate-limit.ts` exporting `withUserRateLimit(handler, { perMinute, feature })`. Use existing `SlidingWindowCounter` + `startPruneInterval`; key on `user.id`; return 429 + `Retry-After: 60` on over-quota.
- 1.3 Decide Sentry tier: use `warnSilentFallback` (warning) not `reportSilentFallback` (error) for over-quota events — rule `cq-silent-fallback-must-mirror-to-sentry` exempts rate-limit hits. Flag divergence in PR body.
- 1.4 Confirm helper has ONLY two options (`perMinute`, `feature`) — no timeouts, no custom key fns, no onReject callbacks. Code-simplicity sanity check.
- 1.5 Run `./node_modules/.bin/vitest run test/with-user-rate-limit.test.ts` from `apps/web-platform` — green.

## Phase 2 — Apply helper to routes + audit neighbors

- 2.1 RED — extend `test/api-conversations.test.ts` with an over-quota case (61st GET → 429).
- 2.2 RED — create `test/api-chat-thread-info.test.ts` covering 401, 200 hit, 200 miss (messageCount=0 fallback), 500 helper error, 429 over-quota.
- 2.3 RED — similar route-level tests for `kb/tree` and `kb/search` if not already covered.
- 2.4 GREEN — wrap GET in `app/api/chat/thread-info/route.ts` via `withUserRateLimit(getHandler, { perMinute: 60, feature: "kb-chat.thread-info" })`. Do NOT export the inner handler (rule `cq-nextjs-route-files-http-only-exports`).
- 2.5 GREEN — same wrap for `app/api/conversations/route.ts` with `feature: "kb-chat.conversations"`.
- 2.6 GREEN — same wrap for `app/api/kb/tree/route.ts` with `feature: "kb.tree"`.
- 2.7 GREEN — same wrap for `app/api/kb/search/route.ts` with `feature: "kb.search"`.
- 2.8 Add one-line exemption comment above GET handler in `app/api/flags/route.ts`.
- 2.9 Run full vitest suite in `apps/web-platform`; confirm no regressions.

## Phase 3 — Collapse 2-query lookup (#2511)

- 3.1 Preflight: verify PostgREST embedded-resource `messages(count)` syntax against local dev DB. Run `doppler run -p soleur -c dev -- node -e '...'` snippet from plan Phase 3 step 9. Confirm response shape is `messages: [{ count: N }]`.
- 3.2 RED — extend `test/api-conversations.test.ts` with a mock that returns the embedded shape and assert `messageCount` via `.toBe(7)` — NOT `.toContain` (rule `cq-mutation-assertions-pin-exact-post-state`).
- 3.3 RED — add a mock-call-count assertion: `mockSelect.mock.calls.length === 1` per request (verifies collapse).
- 3.4 GREEN — rewrite `server/lookup-conversation-for-path.ts` to use `.select("id, context_path, last_active, messages(count)")` with `.maybeSingle()`.
- 3.5 Remove the `"count_failed"` variant from `LookupConversationResult`. Grep every caller (two routes) and confirm none branched on the removed discriminant.
- 3.6 Run `./node_modules/.bin/vitest run test/api-conversations.test.ts` — green.

## Phase 4 — `conversations_lookup` MCP tool (#2512 P2 slice)

- 4.1 RED — author `apps/web-platform/test/conversations-tools.test.ts` covering: builder returns 1 tool, name is `conversations_lookup`, null on miss, full shape on hit, `isError: true` on helper error, Zod requires `contextPath`.
- 4.2 GREEN — create `apps/web-platform/server/conversations-tools.ts` exporting `buildConversationsTools({ userId })` returning exactly one `tool(...)` — the `conversations_lookup` registration. Mirror the shape in `server/kb-share-tools.ts`.
- 4.3 Wire into `agent-runner.ts`:
  - 4.3.1 Import `buildConversationsTools` alongside `buildKbShareTools`.
  - 4.3.2 Push `...buildConversationsTools({ userId })` into `platformTools` immediately after the `kbShareTools` block.
  - 4.3.3 Append `"mcp__soleur_platform__conversations_lookup"` to `platformToolNames`.
- 4.4 Extend the system prompt in `agent-runner.ts` with a `## KB-chat thread discovery` section (sibling to `## Knowledge-base sharing`) announcing the tool, returns-null semantics, and the resume-existing-thread guidance.
- 4.5 Run `./node_modules/.bin/vitest run test/conversations-tools.test.ts` — green.

## Phase 5 — Defer P3 follow-ups

- 5.1 Draft a follow-up GitHub issue body: P3 items (`conversations_list`, `conversation_archive`) + missing HTTP endpoints + design concerns (pagination, soft-delete) + re-evaluation trigger (first multi-thread agent caller).
- 5.2 After PR is opened, file the issue with labels `priority/p2-medium`, `code-review`, `deferred-scope-out` milestoned to `"Phase 4: Validate + Scale"`. Verify label names first via `gh label list --limit 100`.
- 5.3 Cross-link in PR body: "P3 items split to #<new-number>."

## Phase 6 — Review + QA + ship

- 6.1 Run full `apps/web-platform` vitest suite + TypeScript check. Confirm green.
- 6.2 Run `npx markdownlint-cli2 --fix` on any new/changed `.md` files.
- 6.3 Push branch + use `skill: soleur:review` for multi-agent review (security-sentinel, performance-oracle, agent-native-reviewer, code-simplicity-reviewer).
- 6.4 Run `skill: soleur:qa` for functional QA.
- 6.5 Run `skill: soleur:compound` to capture learnings (PostgREST embedded aggregate syntax, rate-limit warn-vs-error tier decision).
- 6.6 Run `skill: soleur:ship` with PR body template from plan. Verify PR body contains three `Closes #` lines and references PR #2486 and PR #2497.
- 6.7 Post-merge: verify Phase 4 operator acceptance criteria — smoke test, Sentry event shape, follow-up issue filed, roadmap refreshed if needed.
