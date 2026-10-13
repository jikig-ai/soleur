---
title: "Tasks — fix stream-replay op=ownership-mismatch false-positive"
date: 2026-06-15
lane: single-domain
plan: knowledge-base/project/plans/2026-06-15-fix-stream-replay-ownership-mismatch-false-positive-plan.md
---

# Tasks — stream-replay ownership-mismatch false-positive fix

Derived from the finalized (deepened) plan. Execute with `skill: soleur:work`.

## Phase 0 — Preconditions (verify before editing)

- [ ] 0.1 Re-grep emit + helper line refs against current `main`-state (they may drift if #3280/#3374 land first): `git grep -n 'op: "ownership-mismatch"' apps/web-platform/server/ws-handler.ts` (expect 2); `git grep -n "sessionKind\|setSessionKind" apps/web-platform/lib/ws-client.ts`; confirm `auth_ok` handler + `connect` dep array `:1286` still excludes `sessionKind`.
- [ ] 0.2 Confirm `getCurrentRepoUrl(userId)` at `ws-handler.ts:1357` still has no `workspaceId` arg, and the upstream `tenant-mint` emit is still `reportSilentFallback` at `current-repo-url.ts:38-43`.
- [ ] 0.3 Confirm `.maybeSingle()` exists on the installed supabase-js (it does — used elsewhere in repo) and the resume_stream lookup currently uses `.single()` (`:1370`).

## Phase 1 — Server: severity-by-cause (contract-change first)

- [ ] 1.1 `ws-handler.ts handleResumeStream`: switch conversation lookup `.single()` → `.maybeSingle()` (`:1365-1370`). Add inline comment: sibling `resume_session :1788` deliberately keeps `.single()` (different contract).
- [ ] 1.2 Classify `convErr` (real DB error / RLS 42501) → `reportSilentFallback(op:"ownership-mismatch", extra:{cause:"db-error"}, message:"resume_stream: conversation not found or not owned")` at error.
- [ ] 1.3 Classify `!conv && !convErr` (row absent) → `warnSilentFallback(op:"ownership-mismatch", extra:{cause:"not-materialized"}, message:"resume_stream: conversation not found or not owned")` at warning.
- [ ] 1.4 Repo-scope guard (`:1386-1396`): if `currentRepoUrl === null` → NO handler mirror, just `fallback(verifiedConvId)` (upstream owns detection). If both non-null and differ → `reportSilentFallback(op:"repo-scope-mismatch", extra:{cause:"url-differs"}, message:"resume_stream: repo-scope mismatch")` at error.
- [ ] 1.5 `current-repo-url.ts:38-43`: downgrade the `RuntimeAuthError`/`read-current-repo-url.tenant-mint` emit `reportSilentFallback` → `warnSilentFallback`. Query-error path (`:57-63`) stays `reportSilentFallback` (error).

## Phase 2 — Client: gate resume_stream on sessionKind

- [ ] 2.1 `ws-client.ts`: add `sessionKindRef` (useRef) adjacent to `realConversationIdRef` (`:523`); set `"fresh"`@1067, `"resumed"`@1092, reset `null`@656 — paired with the existing state.
- [ ] 2.2 In the `auth_ok` reconnect branch (`:819-843`): positive-allowlist gate — send `resume_stream` only when `sessionKindRef.current === "resumed"`. Enumerate all three members (`null`→skip+live, `"fresh"`→skip+live, `"resumed"`→send). Do NOT use `!== "fresh"`.

## Phase 3 — Tests (RED before GREEN)

- [ ] 3.1 Extend `test/server/ws-handler-resume-stream.test.ts`: transient null (no handler mirror, fallback sent).
- [ ] 3.2 Deferred not-materialized (`.maybeSingle`→null/null) → warning `ownership-mismatch` `cause:not-materialized`.
- [ ] 3.3 Genuine DB error (generic + RLS 42501) → error `ownership-mismatch` `cause:db-error` + `pg_code` tag.
- [ ] 3.4 Genuine repo-scope mismatch (both non-null) → error `repo-scope-mismatch` `cause:url-differs`.
- [ ] 3.5 Client test: `"fresh"`/`null` reconnect → no `resume_stream`; `"resumed"` → sent. Place per vitest include globs (`test/**/*.test.ts` node, `lib/**/*.test.ts`) — verify the glob before choosing path.
- [ ] 3.6 `current-repo-url.ts` tenant-mint downgrade test (warning) + query-error stays error.
- [ ] 3.7 New `test/sentry-stream-replay-severity-op-contract.test.ts` (mirror `sentry-kb-db-error-alert-op-contract.test.ts`): pin genuine-error ops at error level, fail closed on downgrade.

## Phase 4 — Docs + deferral tracking

- [ ] 4.1 Update ADR-059 §"Failure mode on cap overflow / cursor-too-old / map-evicted" to document the severity-by-cause scheme (genuine→error, `cause:not-materialized`→warning, transient-null→upstream `feature=repo-scope` only).
- [ ] 4.2 File the owned-by-another deferral tracking issue with the observable re-eval criterion (≥90% warning-volume drop in 7 days post-gate); `Ref #<n>` in PR body.
- [ ] 4.3 Re-verify `git grep -n "ownership-mismatch\|stream-replay" apps/web-platform/infra/sentry/` returns 0.

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/ws-handler-resume-stream.test.ts` green; new op-contract test green.
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] 5.3 Walk all ACs (AC1-AC14) in the plan; Pre-merge ACs satisfied; Post-merge (AC13/AC14) recorded as Sentry-API read-only operator steps.
