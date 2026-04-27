# Tasks — feat: typed `updateConversationFor` wrapper enforces R8 composite key

**Plan:** [`knowledge-base/project/plans/2026-04-27-feat-typed-conversation-writer-r8-wrapper-plan.md`](../../plans/2026-04-27-feat-typed-conversation-writer-r8-wrapper-plan.md)
**Issue:** #2956
**Branch:** `feat-one-shot-2956-conversation-writer`

## Phase 1 — Setup & Wrapper

### 1.1 Read & verify existing patterns

- [ ] 1.1.1 Re-read `apps/web-platform/server/observability.ts` to confirm `reportSilentFallback` signature and tag conventions.
- [ ] 1.1.2 Re-read `apps/web-platform/server/cc-dispatcher.ts:419-431` for the canonical R8 pattern this plan generalizes.
- [ ] 1.1.3 Re-read `apps/web-platform/test/cc-dispatcher-real-factory.test.ts:401-554` (T-AC4) for the supabase-mock capture pattern.

### 1.2 Create wrapper module

- [ ] 1.2.1 Write `apps/web-platform/server/conversation-writer.ts` with the `updateConversationFor` function and `ConversationPatch` interface per plan §"Wrapper Design".
- [ ] 1.2.2 Add module-level JSDoc explaining the R8 invariant, the bulk-update exclusion, the 0-rows-affected-is-success contract, and the deps-injection note.
- [ ] 1.2.3 Run `npx tsc --noEmit` in `apps/web-platform/` to verify the new module type-checks against existing imports.

### 1.3 Write wrapper unit tests

- [ ] 1.3.1 Write `apps/web-platform/test/conversation-writer.test.ts` with T1-T4 (happy path, error path, feature/op tag override, 0-rows-affected). Mirror the `mockSupabaseFrom` capture pattern from `cc-dispatcher-real-factory.test.ts:425-450`.
- [ ] 1.3.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run conversation-writer.test.ts` and confirm all 4 tests pass (per `cq-in-worktrees-run-vitest-via-node-node`).

## Phase 2 — Migrate Call Sites

### 2.1 `agent-runner.ts` — 3 sites + signature change

- [ ] 2.1.1 Migrate `updateConversationStatus` at `agent-runner.ts:345-360`: add `userId: string` first parameter, tighten `status: string → status: Conversation["status"]`, delegate body to `updateConversationFor`.
- [ ] 2.1.2 Update all 4 internal callers (`:1099, :1138, :1188, :1420`) to pass `userId` (already in scope at every site — verified during deepen pass).
- [ ] 2.1.3 Migrate session_id persist (first-message handler in `runAgentSession`, around `:937-948`) to call the wrapper directly.
- [ ] 2.1.4 Migrate clear-stale-session_id (SDK-resume catch around `:1471-1481`) to call the wrapper directly.
- [ ] 2.1.5 Run `npx tsc --noEmit` — must pass; T8 covers this.

### 2.2 `ws-handler.ts` — 3 sites

- [ ] 2.2.1 Migrate `:194` (supersede-on-reconnect, fire-and-forget multi-line chain). Convert `.then(...)` shape to `void updateConversationFor(...)`.
- [ ] 2.2.2 Migrate `:523` (active_workflow persist — already R8-compliant; normalize through wrapper for symmetry).
- [ ] 2.2.3 Migrate `:892` (close-on-supersede). Preserve ordering: `await updateConversationFor(...)` before `void releaseSlot(...)`.

### 2.3 `cc-dispatcher.ts` — 1 closure migration

- [ ] 2.3.1 Migrate the `updateConversationStatus` closure at `:417-431` to delegate to `updateConversationFor`. Closure shape `(convId, status) => Promise<void>` is preserved — `permission-callback.ts` callers do not change.
- [ ] 2.3.2 Remove the inline `reportSilentFallback` call from the closure body (now owned by the wrapper).

### 2.4 Update existing tests

- [ ] 2.4.1 Update `apps/web-platform/test/cc-dispatcher.test.ts`: add `vi.mock("@/server/conversation-writer", ...)` and assert on the wrapper mock instead of the inline `reportSilentFallback`. (Option A from plan §"Test impact for cc-dispatcher.test.ts".)
- [ ] 2.4.2 Verify `cc-dispatcher-real-factory.test.ts` (T-AC4) passes UNCHANGED — the supabase-chain capture works through the wrapper.
- [ ] 2.4.3 Add T9 (transitive coverage via deps) to `cc-dispatcher-real-factory.test.ts`: assert `ccDeps.updateConversationStatus(...)` produces a supabase update with both `.eq("id",...)` AND `.eq("user_id",...)`.

## Phase 3 — CI Detector

### 3.1 Detector script

- [ ] 3.1.1 Write `scripts/lint-conversations-update-callsites.sh` per plan §"CI Detector Design" with the `rg -U --multiline --pcre2` invocation that tolerates broken-across-lines chains.
- [ ] 3.1.2 Make executable: `chmod +x scripts/lint-conversations-update-callsites.sh`.
- [ ] 3.1.3 Run locally against the post-migration tree — should pass (only allowlisted bulk sites match).
- [ ] 3.1.4 Run locally against a synthetic violation (temp file with bare `from("conversations").update(...)`) — should fail with exit code 1.

### 3.2 Detector unit tests

- [ ] 3.2.1 Write `apps/web-platform/test/conversations-update-grep-detector.test.ts` with the four fixture shapes from plan §"Negative test for the detector itself".
- [ ] 3.2.2 Per `cq-mutation-assertions-pin-exact-post-state`: assert exit code is exactly `1` for fail cases, exactly `0` for pass cases.

### 3.3 Wire to CI + lefthook

- [ ] 3.3.1 Read `.github/workflows/ci.yml` and `lefthook.yml` to find the `lint-bot-statuses` shape.
- [ ] 3.3.2 Add a `lint-conversations-update-callsites` job to `.github/workflows/ci.yml` mirroring `lint-bot-statuses`.
- [ ] 3.3.3 Add the same script invocation to `lefthook.yml`'s `pre-commit` block. Verify it runs unconditionally (not glob-filtered by `{staged_files}`).

### 3.4 Allowlist the bulk sites

- [ ] 3.4.1 Add `// allow-direct-conversation-update: bulk status sweep — no per-user composite key` immediately above `agent-runner.ts cleanupOrphanedConversations` `.update(...)` (currently around `:417`).
- [ ] 3.4.2 Add `// allow-direct-conversation-update: bulk timeout sweep — no per-user composite key` immediately above `agent-runner.ts startInactivityTimer` `.update(...)` (currently around `:441`).
- [ ] 3.4.3 Re-run `bash scripts/lint-conversations-update-callsites.sh` — must pass with exit 0.

## Phase 4 — Verification

### 4.1 Local verification

- [ ] 4.1.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite must pass.
- [ ] 4.1.2 `cd apps/web-platform && npx tsc --noEmit` — must pass.
- [ ] 4.1.3 `bash scripts/lint-conversations-update-callsites.sh` — must pass.
- [ ] 4.1.4 Confirm the detector regex matches the migration's "before" state by temporarily reverting one migrated site — script must exit 1, then re-apply migration.

### 4.2 Code review prep

- [ ] 4.2.1 Verify no callsite was missed: `rg -U --multiline --pcre2 'from\("conversations"\)\s*\.update\(' apps/web-platform/server/ --glob '!conversation-writer.ts' --glob '!*.test.ts'` returns ONLY the 2 allowlisted bulk sites.
- [ ] 4.2.2 PR body uses `Closes #2956` (not `Ref #2956` — this PR fully resolves the issue).

### 4.3 Compound learning

- [ ] 4.3.1 If the migration surfaces any non-trivial gotcha (closure-capture surprise, mock-chain regression, etc.), record in `knowledge-base/project/learnings/best-practices/<topic>.md`. If nothing notable, skip.
- [ ] 4.3.2 Run `skill: soleur:compound` before commit.
