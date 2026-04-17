# Plan: KB chat UI bundle — PR #2347 follow-ups (issues #2384, #2385, #2390)

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** 6 (AC, Test Scenarios, Phase 1, Phase 3, Phase 4, Phase 6)
**Research inputs:** institutional learnings (module-scope → async state, unapplied-migration), codebase verification (Sentry wiring, existing test idioms, ws-handler current state), React patterns for timer refs and ref-guarded effects.

### Key Improvements from Deepen Pass

1. **Sentry IS wired on the client** (`@sentry/nextjs` installed + `sentry.client.config.ts` + existing call sites in `app/api/kb/upload/route.ts`, `app/api/kb/file/[...path]/route.ts`). AC4 can therefore mandate `Sentry.captureException` rather than treating it as optional. Standard import: `import * as Sentry from "@sentry/nextjs";`.
2. **Exhaustive-deps hazard flagged** — learning `2026-04-16-module-scope-to-async-state-deps-mismatch.md` warns that converting module-scope to state/ref silently breaks existing `useEffect` deps. For Phase 4 (removing `openedEmitted` state), we MUST grep every consumer of the old state and verify the new `useRef<Set<string>>`-driven effect captures the same fan-out.
3. **Timer-ref cleanup pattern verified** — `useRef<ReturnType<typeof setTimeout> | null>` is the correct type (NOT `number | null`; in Node-compatible environments `setTimeout` returns `NodeJS.Timeout | Timer` depending on config). The existing `server/ws-handler.ts:254-263` uses `clearInterval` + `.unref()` as reference.
4. **23505 disambiguation guard already verified in-file** — `server/ws-handler.ts:295-300` has the index-name check AND the comment cites "See review #2390," confirming the code change was scoped into #2382. Regression test (AC9) is the correct disposition per `rf-review-finding-default-fix-inline`.
5. **Runbook template grounding** — existing runbook format (`cloudflare-service-token-rotation.md` ~150 lines, step-by-step headers + `bash` code blocks) is tight, ops-focused, and copyable. Phase 6 will mirror it exactly.
6. **Post-apply verification path** — learning `2026-03-28-unapplied-migration-command-center-chat-failure.md` is the load-bearing justification for the runbook: a committed-but-unapplied migration is a silent failure mode. The runbook's "Verification procedure" section MUST include the REST API probe (`GET /rest/v1/<table>?select=<new_col>&limit=1` returns 200 if applied, 400 if not). This is codified anti-pattern prevention, not theoretical.

### New Considerations Discovered

- **No `logError` wrapper exists** in the web-platform codebase. Direct `Sentry.captureException(err)` call is idiomatic here. Don't invent a wrapper.
- **Existing test file already uses `vi.useFakeTimers()`** in its `beforeEach` (line 47 of `chat-input-quote.test.tsx`). The new timer-leak case slots in naturally; no new timer-harness boilerplate needed.
- **`ChatInputQuoteHandle` interface is defined in `chat-input.tsx`** but the test file (line 11-13) defines its own structural duplicate `QuoteHandle`. When we add `focus()` to the public interface, the test's local interface must also gain the method OR the test harness should import the exported type directly (preferred — fewer duplicate types).
- **AGENTS.md append must not change rule ID** per `cq-rule-ids-are-immutable`. Only the body text changes; the `[id: wg-when-a-pr-includes-database-migrations]` stays.

---

**Branch:** `feat-kb-chat-ui-bundle-2347-followups`
**Worktree:** `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-kb-chat-ui-bundle-2347-followups`
**Parent PR:** #2347 (merged — `feat(kb-chat): in-context KB chat sidebar`)
**Parent plan:** `knowledge-base/project/plans/2026-04-15-feat-kb-chat-sidebar-plan.md`
**Closes:** #2384, #2385, #2390
**Type:** bug-fix bundle (3 themes, 1 PR) — P2/P3 severity

## Overview

Consolidated cleanup pass for three review-origin issues opened against PR #2347. All findings are legitimate post-merge follow-ups that meet the `deferred-scope-out` criterion (batch of UI correctness nits + ops docs) and were explicitly deferred for a single themed PR rather than multiple tiny ones.

- **Theme 1 — UI correctness bundle (#2384, P2):** four small `components/chat/` defects — a `setTimeout` with no cleanup, a brittle `document.querySelector` for focus, a duplicated presign+upload flow, and a `catch {}` that swallows upload failures.
- **Theme 2 — `kb.chat.opened` double-fire race (#2385, P2):** `openedEmitted` is a `useState` string, not a ref. Two callbacks (`handleThreadResumed` + `handleRealConversationId`) both read the stale value in the same tick on resume → Plausible goal double-counted. Consolidate to a single `useEffect` with `useRef<Set<string>>` guard.
- **Theme 3 — pre-merge ops prep (#2390, P3):** the migration-file backfill decision was not documented on-file; there is no migrations runbook per `wg-when-a-pr-includes-database-migrations`; verification/rollback SQL exists only in the review comment. Codify it.

**Intentionally out of scope:** #2390 item 10D (tighten 23505 disambiguation by index name) — already landed in `server/ws-handler.ts:295-300` as part of the #2382 fix. Plan will **verify** and cross-reference rather than re-implement.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim                                                                                                 | Codebase reality                                                                                                                                                                                            | Plan response                                                                                                                |
| ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| #2384 5A references `chat-input.tsx:144-151`                                                                     | File moved slightly; relevant block is now `chat-input.tsx:146-167` around the `quoteRef`-exposed `insertQuote`. `setTimeout(() => setFlashQuote(false), 400)` is on line 164 with no cleanup.              | Fix in-place; no structural move.                                                                                            |
| #2384 5B references `kb-chat-sidebar.tsx:39-48`                                                                  | Post-merge refactor (resizable-panels work, #2433-#2455) split the component: state + focus effect now live in `components/chat/kb-chat-content.tsx:37-46`. `kb-chat-sidebar.tsx` is a thin `<Sheet>` wrap. | Fix in `kb-chat-content.tsx`, not `kb-chat-sidebar.tsx`. Update issue cross-reference accordingly in PR body.                |
| #2385 references `kb-chat-sidebar.tsx:23, 63-66, 76-97`                                                          | Same refactor — the two handlers and the `openedEmitted` state now live in `kb-chat-content.tsx:23, 62-68, 77-99`. Same race logic, same fix applies.                                                       | Fix in `kb-chat-content.tsx`. Test file is `test/kb-chat-sidebar.test.tsx` (covers composed behaviour); may need co-location check. |
| #2390 10B says "append SQL verification + rollback to PR #2347's body before marking ready"                      | PR #2347 is already merged. Editing the merged PR body retroactively is low-leverage — the runbook (10C) is the durable artifact.                                                                            | Skip 10B as a PR-body edit; fold the SQL snippets into the new runbook (10C) where they will actually be found by future operators. |
| #2390 10D says "tighten 23505 disambiguation in `ws-handler.ts:262`"                                             | Already implemented in `server/ws-handler.ts:295-300` via the `isContextPathUniqueViolation` guard (message-includes check on `conversations_context_path_user_uniq`). Landed as part of #2382.             | **No code change.** Add a regression test in `test/ws-handler-context-path.test.ts` (or existing ws-handler test file) asserting that a non-matching 23505 does NOT fall through, to lock the behaviour. |
| #2384 5C says `uploadPendingFiles(files, conversationId, onProgress?)` belongs in `lib/upload-attachments.ts`    | `lib/upload-with-progress.ts` already exists with the primitive XHR helper. Natural home for the higher-level helper is a sibling file or an extension of the existing one.                                 | Create `lib/upload-attachments.ts` (new) with `uploadPendingFiles()`; it calls into `upload-with-progress.ts`. Keeps layers clean. |
| #2390 10C says "create `knowledge-base/project/runbooks/supabase-migrations.md`"                                 | Existing runbook convention is `knowledge-base/engineering/ops/runbooks/` (`cloudflare-service-token-rotation.md`, `disk-monitoring.md`).                                                                    | Use the established path: `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`. Cross-link from AGENTS.md line-cite to that path. |

## Goals

1. Close #2384 by fixing all four UI-correctness findings; add tests to lock behaviour.
2. Close #2385 by consolidating the double-fire race into a single `useRef`-guarded `useEffect`; add a test that triggers both callbacks in one `act()` batch.
3. Close #2390 by documenting the backfill decision in migration 024, writing a reusable Supabase-migrations runbook (including the SQL verification + rollback snippets from 10B), and adding a regression test for the 23505 disambiguation that already shipped.
4. Ship as a single themed PR with all four test additions passing and no regression in the existing KB-chat suite.

## Non-Goals

- Do NOT alter the public API of `ChatInput`, `ChatSurface`, `KbChatSidebar`, or `KbChatContent` beyond adding `focus()` to `ChatInputQuoteHandle`.
- Do NOT re-fix the 23505 disambiguation in `ws-handler.ts` (already landed). A regression test is sufficient.
- Do NOT retroactively edit the merged PR #2347 body. The runbook is the durable replacement.
- Do NOT introduce toast UI for upload failures beyond a minimal no-op TODO if a reusable toast primitive does not already exist — `console.warn` + Sentry breadcrumb is the minimum viable fix per #2384 5D.
- Do NOT touch `MarkdownRenderer`, `SelectionToolbar`, or any non-chat component.
- Do NOT add backfill SQL for pre-migration un-badged rows (decision locked per parent plan section 2.1).

## Acceptance Criteria

- [ ] **AC1 (#2384 5A):** `insertQuote()` stores its flash-reset `setTimeout` in a `useRef<number | null>`, clears any existing timer on each new call, and clears on unmount via the cleanup return of the `useEffect` that registers the handle.
- [ ] **AC2 (#2384 5B):** `ChatInputQuoteHandle` gains a `focus()` method. `kb-chat-content.tsx` focus-effect calls `quoteRef.current?.focus()` instead of `document.querySelector("[data-kb-chat] textarea")`.
- [ ] **AC3 (#2384 5C):** New file `lib/upload-attachments.ts` exports `uploadPendingFiles(files, conversationId, opts?)` returning `Promise<AttachmentRef[]>`. Both `chat-surface.tsx` pending-files effect and `chat-input.tsx` `uploadAttachments` use it (or a shared primitive). Duplication eliminated; chat-surface variant now reports progress and exposes errors.
- [ ] **AC4 (#2384 5D):** `chat-surface.tsx` pending-files catch logs to `console.warn("[kb-chat] pending upload failed", { err })` AND calls `Sentry.captureException(err)`. Sentry is already wired in this codebase (`@sentry/nextjs` in `package.json`, configs at `sentry.client.config.ts` + `sentry.server.config.ts`; existing usage pattern: `import * as Sentry from "@sentry/nextjs"` then `Sentry.captureException(err)` — see `app/api/kb/upload/route.ts:70,221,249`). Do NOT invent a `logError` wrapper — it does not exist and would duplicate the library API.
- [ ] **AC5 (#2385):** `kb-chat-content.tsx` removes `openedEmitted` state; replaces with a `useRef<Set<string>>` cleared on `contextPath` change. A single `useEffect` keyed on `(contextPath, resumedFrom, realConversationId)` emits `kb.chat.opened` at most once per (mount-session, contextPath).
- [ ] **AC6 (#2385):** When both `onThreadResumed` and `onRealConversationId` fire in the same `act()` batch, `track("kb.chat.opened", ...)` is called **exactly once** (asserted by test).
- [ ] **AC7 (#2390 10A):** `apps/web-platform/supabase/migrations/024_add_context_path_to_conversations.sql` has a leading comment block explicitly stating: (a) no backfill is performed, (b) pre-migration KB threads remain un-badged in the inbox, (c) decision recorded in parent plan section 2.1, (d) reference to AC18 of parent plan.
- [ ] **AC8 (#2390 10C):** New file `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` contains: pre-deploy SQL verification queries (baseline counts, dup detection, column/index existence), an apply procedure, a verification procedure (`gh` + REST API), and a rollback SQL template. Runbook cross-linked from `AGENTS.md` rule `wg-when-a-pr-includes-database-migrations`.
- [ ] **AC9 (#2390 10D — verify-only):** A regression test in `test/ws-handler-context-path-23505.test.ts` (or added to existing ws-handler test file) asserts that a 23505 error whose message does NOT contain `conversations_context_path_user_uniq` is re-thrown rather than falling through to the lookup.
- [ ] **AC10:** All new tests RED-before-GREEN: write failing tests first per `cq-write-failing-tests-before`. Each fix lands in its own commit with the failing test from the prior commit.
- [ ] **AC11:** Existing `test/kb-chat-sidebar.test.tsx`, `test/chat-input-quote.test.tsx`, `test/chat-input-attachments.test.tsx`, `test/chat-surface-sidebar.test.tsx`, and `test/chat-surface-sidebar-wrap.test.tsx` continue to pass unchanged.
- [ ] **AC12:** `tsc --noEmit` clean; `next build` clean (no route-file export regressions — per `cq-nextjs-route-files-http-only-exports`, confirm no new non-HTTP exports in route files).

## Test Scenarios

1. **chat-input-quote timer-leak test (AC1)** — in `test/chat-input-quote.test.tsx`, add a case under `vi.useFakeTimers()`:
   - Call `insertQuote("a")` 5 times in rapid succession.
   - Assert `vi.getTimerCount()` equals 1 between calls (only one pending reset timer).
   - Unmount the component before the 400ms reset fires.
   - Assert `vi.getTimerCount()` returns to 0 after unmount (no leaked timer).
2. **kb-chat focus-via-ref test (AC2)** — in `test/kb-chat-sidebar-a11y.test.tsx` (or new variant `kb-chat-sidebar-a11y-stacked-dialog.test.tsx`):
   - Render `<KbChatContent visible>` inside a wrapper that also renders a second `[role="dialog"]` overlaying it (simulates a modal stack).
   - Assert `document.activeElement` equals the sidebar's textarea (not the overlay dialog's focusable).
3. **shared upload util test (AC3)** — new `test/upload-attachments.test.ts`:
   - Mock `fetch` (presign) and the XHR primitive.
   - Call `uploadPendingFiles([fileA, fileB], "conv-1")`; assert two presign POSTs with the correct body shape and two `AttachmentRef`s returned.
   - Simulate one presign 500: assert the helper returns only the successful ref and does NOT throw.
4. **upload-failure telemetry test (AC4)** — in the same file or a sibling `upload-attachments-errors.test.ts`:
   - Spy on `console.warn`; force `uploadPendingFiles` to throw.
   - Assert `console.warn` was called with a message containing `[kb-chat]`.
5. **kb-chat double-fire test (AC5, AC6)** — new `test/kb-chat-sidebar-opened-once.test.tsx` OR add case to `test/kb-chat-sidebar.test.tsx`:
   - Mock `track` from `@/lib/analytics-client`.
   - Render `<KbChatContent>`; within a single `act(() => { ... })` batch, invoke both `handleThreadResumed(...)` and `handleRealConversationId(...)`.
   - Assert `track("kb.chat.opened", ...)` called exactly 1 time.
   - Second case: close → reopen same `contextPath` (simulate remount) → assert `track("kb.chat.opened")` fires again (new mount-session).
   - Third case: same mount, switch `contextPath` then back → assert two emits total across the two paths (one per path).
6. **23505 non-matching regression test (AC9)** — new or extended test in `test/ws-handler-context-path-23505.test.ts`:
   - Inject a mocked supabase client that returns `{ error: { code: "23505", message: "duplicate key value violates unique constraint \"conversations_pkey\"" } }` from the initial insert.
   - Call `createConversation(userId, undefined, idCollision, "knowledge-base/doc.md")`.
   - Assert the function throws (does NOT fall through to the context_path lookup) — proving the index-name disambiguation guard still works.
7. **Migration 024 comment smoke test (AC7)** — not a vitest; covered by the file diff in review. Optional `grep` in a pre-commit sanity step in the PR description if we want to mechanize it.
8. **Runbook presence (AC8)** — a markdownlint pass on the new file + an AGENTS.md link check confirming the rule cites the runbook path.

## Implementation Phases

### Phase 0 — Preparation

- [ ] Verify branch is `feat-kb-chat-ui-bundle-2347-followups` and worktree is clean.
- [ ] Push branch to origin (`rf-before-spawning-review-agents-push-the`) so review subagents see current state.
- [ ] Confirm `apps/web-platform/node_modules/.bin/vitest` is resolvable — use it directly (not `npx`) per `cq-in-worktrees-run-vitest-via-node-node`.
- [ ] Run baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-input-quote.test.tsx test/kb-chat-sidebar.test.tsx test/chat-input-attachments.test.tsx` to capture GREEN baseline before changes.

### Phase 1 — #2384 5A: flashQuote timer-leak fix (TDD)

1. **RED:** Add the timer-leak test to `test/chat-input-quote.test.tsx` (AC1 scenario). The file already uses `vi.useFakeTimers()` in `beforeEach` (line 47) — piggyback on that. Example shape:
   ```ts
   it("does not leak setTimeout on rapid reinsertion or unmount", () => {
     let handle: QuoteHandle | null = null;
     const { unmount } = render(
       <Harness onSend={vi.fn()} onReady={(h) => { handle = h; }} />,
     );
     screen.getByTestId("ready").click();
     for (let i = 0; i < 5; i++) {
       act(() => { handle!.insertQuote("line " + i); });
     }
     // Exactly one pending flash-reset timer, not five.
     expect(vi.getTimerCount()).toBe(1);
     unmount();
     // Timer cleared on unmount — no unmounted-setState warning possible.
     expect(vi.getTimerCount()).toBe(0);
   });
   ```
   Confirm it FAILS (`getTimerCount()` grows past 1, AND/OR remains >0 after unmount).
2. **GREEN:** In `components/chat/chat-input.tsx` (currently lines 146-167, the `useEffect` that wires `quoteRef.current`):
   - Add `const flashTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);` near the other refs at the top of the component (keep the `ReturnType<typeof setTimeout>` form — it's the TS-idiomatic choice that works across both Node and browser lib targets; the same pattern is used in `server/ws-handler.ts:257`).
   - Inside `insertQuote`, before the new `setTimeout`, clear any existing timer:
     ```ts
     if (flashTimerRef.current !== null) clearTimeout(flashTimerRef.current);
     flashTimerRef.current = setTimeout(() => {
       setFlashQuote(false);
       flashTimerRef.current = null;
     }, 400);
     ```
   - Extend the `useEffect` that assigns `quoteRef.current` to return a cleanup:
     ```ts
     return () => {
       if (flashTimerRef.current !== null) {
         clearTimeout(flashTimerRef.current);
         flashTimerRef.current = null;
       }
       if (quoteRef) quoteRef.current = null;
     };
     ```
3. **REFACTOR:** Read the file back after edits; verify the two `useEffect` blocks (`insertRef` at line 120 and `quoteRef` at line 146) remain syntactically distinct — don't let a copy-paste consolidate them.
4. Commit: `fix(kb-chat): clean up flashQuote setTimeout on re-invocation and unmount`

### Phase 2 — #2384 5B: focus-via-ref (TDD)

1. **RED:** Add the stacked-dialog focus test (AC2 scenario). Confirm it FAILS (focus lands in the overlay dialog's textarea, not the sidebar's).
2. **GREEN:**
   - In `components/chat/chat-input.tsx`, extend `ChatInputQuoteHandle`: `interface ChatInputQuoteHandle { insertQuote: (text: string) => void; focus: () => void; }`
   - In the `useEffect` that assigns `quoteRef.current`, also assign `focus: () => { textareaRef.current?.focus(); }`.
   - In `components/chat/kb-chat-content.tsx`, replace the `document.querySelector<HTMLTextAreaElement>("[data-kb-chat] textarea")` block with `quoteRef.current?.focus()`. Preserve the `requestAnimationFrame` wrapping and cleanup (`cancelAnimationFrame`).
3. Commit: `fix(kb-chat): focus input via ChatInputQuoteHandle.focus instead of DOM query`

### Phase 3 — #2384 5C: extract upload-attachments helper (TDD)

1. **RED:** Create `test/upload-attachments.test.ts` with the scenarios from AC3 + AC4. Confirm it FAILS (module does not exist).
2. **GREEN:**
   - Create `apps/web-platform/lib/upload-attachments.ts` exporting:
     ```ts
     export async function uploadPendingFiles(
       files: File[],
       conversationId: string,
       opts?: { onProgress?: (fileIndex: number, percent: number) => void },
     ): Promise<AttachmentRef[]>
     ```
   - Logic: for each file, POST `/api/attachments/presign`, call `uploadWithProgress(uploadUrl, file, file.type, percent => opts?.onProgress?.(idx, percent))`, push `AttachmentRef` on success, swallow-and-log (not throw) per-file failures.
   - Update `components/chat/chat-surface.tsx` pending-files `useEffect` (lines 205-241) to call `uploadPendingFiles(files, realConversationId, { onProgress: (i, p) => { /* reserved */ } })`.
   - Add `import * as Sentry from "@sentry/nextjs";` at the top of `chat-surface.tsx` if not already imported.
   - Replace the silent `catch {}` with:
     ```ts
     catch (err) {
       console.warn("[kb-chat] pending upload failed", { err });
       Sentry.captureException(err);
     }
     ```
   - Sentry is already bundled + configured — verified via `app/api/kb/upload/route.ts:13,70,221,249` and `sentry.client.config.ts`. No new dependency.
   - Update `components/chat/chat-input.tsx` `uploadAttachments` to reuse the same primitive. Two options: (a) call `uploadPendingFiles` and map state by index; (b) leave the richer per-attachment state machine in place and extract only the presign+upload inner block into `uploadPendingFile(file, conversationId, onProgress)` (singular). **Prefer (b)** — it minimizes risk, preserves the existing error-state-per-attachment UX, and still dedupes the 30-line presign+upload block. AC3 remains satisfied.
3. **REFACTOR:** Confirm both call sites now go through the helper; grep `apps/web-platform/components/chat/` for the string `/api/attachments/presign` — should match only the helper + the test files.
4. Commit: `refactor(kb-chat): extract uploadPendingFile helper, add telemetry on chat-surface failures`

### Phase 4 — #2385: kb.chat.opened consolidation (TDD)

**Institutional hazard — read before implementing:** learning `2026-04-16-module-scope-to-async-state-deps-mismatch.md`. When we migrate `openedEmitted` from `useState<string | null>` to `useRef<Set<string>>`, every current consumer of `openedEmitted` in `kb-chat-content.tsx` must be audited:

- `handleThreadResumed` useCallback (line 77-89) reads `openedEmitted` and has it in deps — deps list changes when we remove the state.
- `handleRealConversationId` useCallback (line 91-99) — same.
- The `prevContextPathRef` effect (line 62-68) calls `setOpenedEmitted(null)` — becomes `emittedRef.current.clear()`.

Refs don't appear in dep arrays (stable reference). After removing the state, run `grep -n 'openedEmitted' components/chat/kb-chat-content.tsx` to verify zero residual references before committing. This is the exact failure mode the learning documents.

1. **RED:** Add the three double-fire test cases from AC5/AC6 scenario 5. Confirm the first case FAILS (2 calls observed).
2. **GREEN:** In `components/chat/kb-chat-content.tsx`:
   - Remove `const [openedEmitted, setOpenedEmitted] = useState<string | null>(null);` (line 23).
   - Add `const emittedRef = useRef<Set<string>>(new Set());`
   - Remove the conditional-emit blocks in `handleThreadResumed` (lines 82-86) and `handleRealConversationId` (lines 93-96).
   - Wire it through `ChatSurface`'s callback data:
     - Option A (leaner): extend the existing `handleThreadResumed` and `handleRealConversationId` to record a scalar `hasRealConversation` / `hasResumed` in state, then have a single `useEffect` keyed on `(contextPath, hasRealConversation, hasResumed)` do the guarded emit.
     - Option B (closer to issue): expose both signals via refs + state; one `useEffect` keyed on `(contextPath, realConversationId, resumedFrom)`. **Choose Option A** — requires minimal `ChatSurface` prop surface change.
   - The guarded effect body:
     ```ts
     useEffect(() => {
       if (!hasRealConversation && !hasResumed) return;
       if (emittedRef.current.has(contextPath)) return;
       emittedRef.current.add(contextPath);
       void track("kb.chat.opened", { path: contextPath });
       if (hasResumed) void track("kb.chat.thread_resumed", { path: contextPath });
     }, [contextPath, hasRealConversation, hasResumed]);
     ```
   - Reset `emittedRef.current.clear()` in the existing `prevContextPathRef` change effect (lines 62-68) — or leave the set accumulating (once per mount-session, per path, consistent with the parent-plan semantic of "at most once per mount per path"). Prefer **clear on contextPath change** to keep the once-per-path-per-mount contract tight.
3. **REFACTOR:** Confirm `kb.chat.selection_sent` path (unchanged) still fires via `handleBeforeSend`.
4. Commit: `fix(kb-chat): consolidate kb.chat.opened emit into single ref-guarded effect`

### Phase 5 — #2390 10A: migration 024 comment

1. Edit `apps/web-platform/supabase/migrations/024_add_context_path_to_conversations.sql`.
2. Prepend a comment block:
   ```sql
   -- Backfill intentionally skipped: pre-migration KB threads remain
   -- un-badged in the conversation inbox (AC18 of the parent plan).
   -- Decision recorded in `knowledge-base/project/plans/
   -- 2026-04-15-feat-kb-chat-sidebar-plan.md` section 2.1 — the cost of a
   -- best-effort content_path derivation outweighs the display benefit for
   -- a small historical window.
   --
   -- If a future operator needs to backfill, the pattern is:
   --   UPDATE public.conversations
   --      SET context_path = <derived-from-first-user-message>
   --    WHERE created_at < '<cutoff>' AND context_path IS NULL;
   -- but note that the partial UNIQUE index will reject duplicates.
   ```
3. Re-read to verify the comment is above the `ALTER TABLE` without shifting the DDL.
4. Commit: `docs(migrations): record intentional backfill skip on migration 024`

### Phase 6 — #2390 10C: Supabase-migrations runbook

1. Create `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` with these sections (match the tone of `cloudflare-service-token-rotation.md`):
   - **Purpose** — when to use this runbook (any PR touching `apps/web-platform/supabase/migrations/`).
   - **Pre-deploy checklist** — confirm migration file is numbered correctly, has a header comment, is idempotent (`IF NOT EXISTS`), has no implicit transactional assumptions that break in the Supabase runner.
   - **Baseline capture (pre-apply SQL)** — the three queries from issue #2390 10B:
     ```sql
     -- Baseline counts
     SELECT COUNT(*) AS total, COUNT(DISTINCT user_id) AS users FROM <table>;
     -- Detect any pre-existing dup keys
     SELECT <key_cols>, COUNT(*) FROM <table>
       WHERE <key_cols> IS NOT NULL
       GROUP BY <key_cols> HAVING COUNT(*) > 1;
     -- Confirm column/index don't pre-exist
     SELECT column_name FROM information_schema.columns
       WHERE table_name='<t>' AND column_name='<col>';
     SELECT indexname FROM pg_indexes
       WHERE tablename='<t>' AND indexname LIKE '%<pattern>%';
     ```
   - **Apply procedure** — `npx supabase db push` (or Supabase Management API as used in PR #2347 pre-merge), including the Doppler token fetch (`doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain`).
   - **Verification procedure** — two-stage:
     1. **Supabase REST API probe** (fastest, no auth beyond anon key): `curl -s "$SUPABASE_URL/rest/v1/<table>?select=<new_col>&limit=1" -H "apikey: $SUPABASE_ANON_KEY"`. Returns `[]` or rows with HTTP 200 if the column exists; HTTP 400 with body `{"code":"42703","message":"column <table>.<col> does not exist"}` if the migration was NOT applied. This is the exact failure mode captured in learning `2026-03-28-unapplied-migration-command-center-chat-failure.md` — a committed-but-unapplied migration is a silent deployment failure until the code path executes.
     2. **Management API (detailed)**: confirm column nullability, index predicate, and CHECK constraints by running `SELECT column_name, is_nullable, data_type FROM information_schema.columns WHERE table_name='<t>'` and `SELECT indexname, indexdef FROM pg_indexes WHERE tablename='<t>'` via the Management API SQL endpoint (requires `SUPABASE_ACCESS_TOKEN` from Doppler `prd`).
   - **Rollback SQL** — generic template:
     ```sql
     -- Rollback template (example for migration 024)
     DROP INDEX IF EXISTS public.conversations_context_path_user_uniq;
     DROP INDEX IF EXISTS public.idx_conversations_context_path;
     ALTER TABLE public.conversations DROP COLUMN IF EXISTS context_path;
     ```
     + note that rollbacks are destructive; capture a `pg_dump --data-only` of affected rows beforehand for any migration that drops a column with values.
   - **Post-merge verification** — per `wg-when-a-pr-includes-database-migrations`, poll the production DB until the column/index is confirmed applied; close the issue only after that.
   - **Cross-references** — link to `AGENTS.md` rule and to PR #2347 as the worked example.
2. Update `AGENTS.md` rule `wg-when-a-pr-includes-database-migrations` to append `See runbook: knowledge-base/engineering/ops/runbooks/supabase-migrations.md.`
3. Run `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/supabase-migrations.md AGENTS.md` (per `cq-markdownlint-fix-target-specific-paths` — target-specific, not a repo-wide glob).
4. Commit: `docs(ops): add supabase-migrations runbook with verification + rollback SQL`

### Phase 7 — #2390 10D: regression test (no code change)

1. **RED:** Write `test/ws-handler-context-path-23505.test.ts` per AC9. Confirm it PASSES (since the guard already exists) — this is a characterization test, not TDD in the traditional sense. Document in the test file preamble that this locks behaviour from #2382.
2. *(No GREEN step — code already present.)*
3. Commit: `test(ws-handler): lock 23505 index-name disambiguation (regression for #2382/#2390)`

### Phase 8 — Verification & Ship

1. Run the full web-platform test suite: `cd apps/web-platform && ./node_modules/.bin/vitest run`. All tests green.
2. Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
3. Run `cd apps/web-platform && ./node_modules/.bin/next build` locally (per `cq-nextjs-route-files-http-only-exports` — this class of failure only surfaces at `next build` time).
4. Invoke `skill: soleur:review` across the change set.
5. Invoke `skill: soleur:compound` to capture any learnings (timer-leak pattern, focus-via-ref pattern, runbook template).
6. Invoke `skill: soleur:ship` with `Closes #2384, #2385, #2390` in the body (per `wg-use-closes-n-in-pr-body-not-title-to`).
7. Post-merge: verify `next build` succeeded in CI; verify no new Sentry issues fire on the deployed path.

## Files to Touch

**Modify:**

- `apps/web-platform/components/chat/chat-input.tsx` — add `flashTimerRef`, clear on re-invocation + unmount; extend `ChatInputQuoteHandle` with `focus()`; optionally use a shared `uploadPendingFile` primitive inside `uploadAttachments`.
- `apps/web-platform/components/chat/chat-surface.tsx` — replace inline presign+upload in pending-files effect with `uploadPendingFiles()` call; log failures.
- `apps/web-platform/components/chat/kb-chat-content.tsx` — replace `document.querySelector` focus with `quoteRef.current?.focus()`; remove `openedEmitted` state and consolidate emit logic into one `useEffect` with `useRef<Set<string>>`.
- `apps/web-platform/supabase/migrations/024_add_context_path_to_conversations.sql` — prepend backfill-skip comment.
- `AGENTS.md` — append runbook cross-link to `wg-when-a-pr-includes-database-migrations` (text append only; rule ID is immutable per `cq-rule-ids-are-immutable`).
- `apps/web-platform/test/chat-input-quote.test.tsx` — add timer-leak case.
- `apps/web-platform/test/kb-chat-sidebar-a11y.test.tsx` — add stacked-dialog focus case (or new file if cleaner).
- `apps/web-platform/test/kb-chat-sidebar.test.tsx` — add three double-fire cases (or new file `kb-chat-sidebar-opened-once.test.tsx`).

**Create:**

- `apps/web-platform/lib/upload-attachments.ts` — shared helper.
- `apps/web-platform/test/upload-attachments.test.ts` — unit test for helper.
- `apps/web-platform/test/ws-handler-context-path-23505.test.ts` — regression test.
- `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` — new runbook.

**Do NOT touch:**

- `apps/web-platform/server/ws-handler.ts` (10D already implemented).
- `apps/web-platform/supabase/migrations/025_context_path_archived_predicate.sql`.
- Any `MarkdownRenderer` / `SelectionToolbar` files.

## Research Findings

### Local repo research

- `apps/web-platform/lib/upload-with-progress.ts` already exists with the low-level XHR primitive. Clean insertion point for `uploadPendingFiles()` sibling at `lib/upload-attachments.ts`.
- `kb-chat-sidebar.tsx` was split post-#2347 during the resizable-panels rollout (commits `#2433-#2455`). The race and focus logic from issues #2384 5B and #2385 now live in `components/chat/kb-chat-content.tsx` — same semantics, new path. **Update issue cross-references in PR body.**
- Existing runbook convention is `knowledge-base/engineering/ops/runbooks/` (two files). Using this over a fresh `knowledge-base/project/runbooks/` avoids fragmenting the runbook index.
- 23505 disambiguation already landed in `server/ws-handler.ts:295-300` — confirmed by reading the file. The comment even references "See review #2390." Issue #2390 10D is effectively a verify-only item; a regression test is the right artifact.
- Existing test patterns (`test/chat-input-attachments.test.tsx`, `test/kb-chat-sidebar.test.tsx`, `test/api-analytics-track.test.ts`) establish the idioms for mocking `fetch`, `XMLHttpRequest` / `uploadWithProgress`, and the `track()` helper.

### Relevant institutional learnings

- `cq-vite-test-files-esm-only` — no `require()` in test files. Use top-level `import` in the new `upload-attachments.test.ts`.
- `cq-nextjs-route-files-http-only-exports` — none of our changes touch route files, but confirm via grep before ship (`lib/upload-attachments.ts` is a lib, not a route).
- `cq-in-worktrees-run-vitest-via-node-node` — use `./node_modules/.bin/vitest` directly from `apps/web-platform`, not `npx vitest`.
- `cq-write-failing-tests-before` — RED-before-GREEN is mandatory here (plan includes explicit Test Scenarios).
- `hr-when-in-a-worktree-never-read-from-bare` — already in a worktree, all file I/O via absolute worktree paths.
- `wg-when-a-pr-includes-database-migrations` — the new runbook is the directly-cited artifact for this rule; AGENTS.md edit is the enforcement hook.
- **`knowledge-base/project/learnings/2026-04-16-module-scope-to-async-state-deps-mismatch.md`** — directly applies to Phase 4. When removing `openedEmitted` state, every `useEffect`/`useCallback`/`useMemo` that previously listed it in deps must be re-examined. Refs don't go in dep arrays, so the conversion changes dependency shape. Mitigation baked into Phase 4 with a pre-commit grep.
- **`knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md`** — directly applies to Phase 6. The runbook's REST API probe (HTTP 200 vs 400 with `42703`) is the lightweight signal this learning recommends as the merge-time verification step. Without it, a committed migration silently diverges from the deployed schema.

### External research

Skipped per Phase 1.6 decision: codebase has strong local patterns, topic risk is low (bug-fix bundle — no security/payments/external API surface), user is familiar (direct follow-up to a PR they shipped). The only external-leaning item (runbook structure) has two in-repo templates to copy from.

## Domain Review

**Domains relevant:** none

This is a pure bug-fix bundle with no product/UX/marketing/legal/financial/security implications. No new user-facing surface, no new data captured, no new external dependency, no pricing/positioning change. The runbook is an internal ops artifact. Per `hr-new-skills-agents-or-user-facing`, CPO/CMO involvement is gated on "new skills, agents, or user-facing capabilities" — none apply. The UX changes are invisible (timer cleanup, ref-based focus, analytics deduplication) and preserve the existing contract validated during PR #2347 Product/UX Gate.

## Rollout

1. Merge via `/ship` (squash).
2. Post-merge: CI runs `next build`, Docker build, deploy webhook.
3. Verify on prd:
   - Open a KB doc, open chat panel, observe Plausible `kb.chat.opened` count increments by exactly 1 (not 2) when resuming a thread.
   - Open a KB doc with a selection-to-quote, observe no React "state update on unmounted component" warnings in console after rapid panel close.
   - Upload a file via the pending-files path (e.g., reload during upload); confirm no silent failure — any failure produces a `[kb-chat] pending upload failed` console warning and a Sentry breadcrumb if Sentry is wired.
4. No feature-flag flip required (no flagged behaviour).
5. No migration required (024/025 already applied per parent PR).

## Risk & Mitigation

| Risk                                                                                          | Likelihood | Mitigation                                                                                                |
| --------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------- |
| Ref-based focus misses a case the DOM query handled (e.g., SSR, Suspense boundary)            | Low        | AC2 test covers the stacked-dialog case; manually verify on desktop + mobile sheet before merge.          |
| Consolidating the `openedEmitted` state breaks the `kb.chat.thread_resumed` paired emit       | Medium     | AC5 test asserts both `opened` and `thread_resumed` fire together on resume; review diff against #2385 fix sketch. |
| `uploadPendingFile` extraction changes progress-reporting semantics in `chat-input.tsx`       | Medium     | Keep chat-input's per-attachment state machine intact; extract only the inner presign+upload block (plan Option b). Existing `test/chat-input-attachments.test.tsx` acts as the safety net. |
| Timer-leak test is flaky under fake timers                                                    | Low        | Use `vi.getTimerCount()` (stable API); explicit `vi.useRealTimers()` in `afterEach`.                      |
| `next build` fails on a route-file export regression introduced incidentally                  | Low        | We don't touch route files; still run `next build` locally per `cq-nextjs-route-files-http-only-exports`. |
| Migration-024 comment edit is treated as a schema change by a migrations-diff tool            | Very low   | Comments do not alter DDL behaviour; Supabase migration runner treats them as inert.                      |
| Review-origin issues re-spawn because fix-inline pattern is not followed                      | Low        | Per `rf-review-finding-default-fix-inline`, these are fix-inline (already have `deferred-scope-out` label on the source issues, batched here by intent). |

## Open Questions

- *(none)* — research phase answered all initial ambiguities (refactor moved files, 10D already landed, runbook path convention, test harness pattern).

## References

- Issue #2384 — UI correctness bundle (P2).
- Issue #2385 — kb.chat.opened double-fire race (P2).
- Issue #2390 — pre-merge ops prep (P3).
- PR #2347 — merged parent feature.
- Parent plan: `knowledge-base/project/plans/2026-04-15-feat-kb-chat-sidebar-plan.md` (section 2.1 backfill decision, AC18).
- `AGENTS.md` rule `wg-when-a-pr-includes-database-migrations`.
- `AGENTS.md` rule `rf-review-finding-default-fix-inline`.
- `AGENTS.md` rule `cq-write-failing-tests-before`.
- Existing runbooks: `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md`, `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`.

## Plan Review Hooks

Run `/plan_review knowledge-base/project/plans/2026-04-17-fix-kb-chat-ui-bundle-2347-followups-plan.md` before implementation. Expected feedback angles:

- **DHH:** Is Phase 3's "Option (b) singular `uploadPendingFile`" overengineered? Could both call sites share the full `uploadPendingFiles` plural helper without the per-attachment state machine? Answer: the chat-input UX needs per-attachment error/progress; preserving that state machine is non-negotiable.
- **Kieran:** Does AC5 guarantee both `opened` and `thread_resumed` fire atomically on resume? Yes — both go through the single consolidated effect.
- **Simplicity:** Is the runbook overkill for a single migration? No — `wg-when-a-pr-includes-database-migrations` mandates verification for **every** migration PR; the runbook pays off on the next one.
