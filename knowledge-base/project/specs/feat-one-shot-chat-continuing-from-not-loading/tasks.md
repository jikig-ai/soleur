---
plan: knowledge-base/project/plans/2026-05-05-fix-kb-chat-continuing-banner-shows-but-messages-empty-plan.md
branch: feat-one-shot-chat-continuing-from-not-loading
created: 2026-05-05
---

# Tasks — fix: KB chat "Continuing from <ts>" banner fires but message list renders empty

## Phase 0 — Pre-Implementation Verification

- [ ] 0.1 — Run the four `grep` checks in §Pre-Implementation Verification.
      Confirm all four offsets match. If any drift, re-read the source files
      and update the plan offsets BEFORE coding.

## Phase 1 — RED Tests

Tests must be written and failing on `main` before any implementation code.

- [ ] 1.1 — Add H1 RED test (null Supabase session → empty placeholder
      suppressed + `reportSilentFallback` mirror with `op: "history-fetch-no-session"`).
      Use `mockImplementation(async () => ...)`, NOT `mockReturnValue`.
- [ ] 1.2 — Add H5 RED test (post-teardown WS `session_resumed` → no stale
      state setter calls + breadcrumb `ws-message-after-teardown`). Use
      real `MockWebSocket`, capture `onmessage`, call `unmount()`, then
      synchronously dispatch.
- [ ] 1.3 — Add H2 diagnostic test (abort-after-success → no fallback,
      one breadcrumb `abort-after-success` with `data.messageCount === 2`).
      Use `vi.useFakeTimers()` for this case only; reset in `afterEach`.
- [ ] 1.4 — Run `bun test apps/web-platform/test/kb-chat-resume-hydration.test.tsx`
      and confirm exactly the three new cases fail with the expected
      assertion messages. Do NOT proceed if any other test fails.

## Phase 2 — GREEN Implementation

Apply edits in this order so each step's test goes green individually.

- [ ] 2.1 — `apps/web-platform/lib/ws-client.ts` line ~24: add
      `import * as Sentry from "@sentry/nextjs";`. Confirm
      `bun run build` (or `tsc --noEmit`) still passes.
- [ ] 2.2 — `apps/web-platform/lib/ws-client.ts` line 725 (H1): add
      `reportSilentFallback(null, {...})` before the `return null`. Run
      H1 RED test → confirm GREEN.
- [ ] 2.3 — `apps/web-platform/lib/ws-client.ts` line 429 (H5): add
      `mountedRef.current` guard with breadcrumb. Run H5 RED test →
      confirm GREEN.
- [ ] 2.4 — `apps/web-platform/lib/ws-client.ts` line 822 (H2): split
      the guard, add abort-after-success breadcrumb. Run H2 diagnostic
      test → confirm GREEN.
- [ ] 2.5 — `apps/web-platform/server/api-messages.ts` line 105: change
      `level: "info"` → `level: "warning"` and add the H4-disambiguation
      TODO comment.

## Phase 3 — Regression & Lint

- [ ] 3.1 — Run `bun test apps/web-platform/test/` and confirm full
      kb-chat suite passes (`kb-chat-resume-hydration`, `kb-chat-trigger`,
      `kb-chat-sidebar`, `kb-chat-sidebar-banner-dismiss`,
      `api-messages-handler`).
- [ ] 3.2 — Run `bun run lint` and `tsc --noEmit` from
      `apps/web-platform/`. Both clean.
- [ ] 3.3 — Run `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`
      to verify no stale worktree state.

## Phase 4 — Capture Learning

- [ ] 4.1 — Write a learning file at
      `knowledge-base/project/learnings/ui-bugs/<topic>.md` (planner
      picks the date prefix at write time per
      `2026-04-23-do-not-prescribe-exact-learning-filenames-with-dates`)
      capturing the H1/H5 surfaces, the post-teardown `onmessage` quirk,
      and the `mockImplementation`-vs-`mockReturnValue` test rule
      reinforcement.
- [ ] 4.2 — Cross-reference the precursor learning at
      `knowledge-base/project/learnings/ui-bugs/2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md`
      and append a one-line "Same week, follow-up bug class" note to it.

## Phase 5 — Ship

- [ ] 5.1 — Run `skill: soleur:compound` to capture session learnings.
- [ ] 5.2 — Run `skill: soleur:ship` with semver label `patch` (no
      breaking changes, no new feature surface).
- [ ] 5.3 — PR body: `Ref #3241` (precursor closed issue). Do NOT use
      `Closes` — the precursor is already closed; this is a follow-up
      regression fix on the same surface.
