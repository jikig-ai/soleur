# Tasks — KB chat UI bundle (PR #2347 follow-ups)

Derived from `knowledge-base/project/plans/2026-04-17-fix-kb-chat-ui-bundle-2347-followups-plan.md`.

## 0. Preparation

- [ ] 0.1 Verify worktree clean, branch `feat-kb-chat-ui-bundle-2347-followups`.
- [ ] 0.2 Push branch to origin (`git push -u origin feat-kb-chat-ui-bundle-2347-followups`).
- [ ] 0.3 Capture GREEN baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-input-quote.test.tsx test/kb-chat-sidebar.test.tsx test/chat-input-attachments.test.tsx test/kb-chat-sidebar-a11y.test.tsx`.

## 1. Phase 1 — #2384 5A flashQuote timer leak

- [ ] 1.1 RED: add timer-leak test to `test/chat-input-quote.test.tsx` (AC1). Confirm it fails.
- [ ] 1.2 GREEN: add `flashTimerRef`, clear on re-invocation and unmount in `components/chat/chat-input.tsx`.
- [ ] 1.3 Commit: `fix(kb-chat): clean up flashQuote setTimeout on re-invocation and unmount`.

## 2. Phase 2 — #2384 5B focus via ref

- [ ] 2.1 RED: add stacked-dialog focus test (AC2). Confirm it fails.
- [ ] 2.2 GREEN: extend `ChatInputQuoteHandle` with `focus()`; swap `document.querySelector` for `quoteRef.current?.focus()` in `kb-chat-content.tsx`.
- [ ] 2.3 Commit: `fix(kb-chat): focus input via ChatInputQuoteHandle.focus instead of DOM query`.

## 3. Phase 3 — #2384 5C/5D extract upload helper

- [ ] 3.1 RED: create `test/upload-attachments.test.ts` (AC3 + AC4). Confirm it fails (module not found).
- [ ] 3.2 GREEN: create `lib/upload-attachments.ts` exporting `uploadPendingFiles(files, conversationId, opts?)` and/or `uploadPendingFile(file, conversationId, onProgress)`.
- [ ] 3.3 Wire `chat-surface.tsx` pending-files effect to call the helper; replace silent `catch {}` with `console.warn` + optional Sentry hook.
- [ ] 3.4 Wire `chat-input.tsx` `uploadAttachments` to reuse the singular primitive without changing its per-attachment state machine.
- [ ] 3.5 Commit: `refactor(kb-chat): extract upload helper, surface chat-surface upload failures`.

## 4. Phase 4 — #2385 kb.chat.opened consolidation

- [ ] 4.1 RED: add three double-fire test cases (AC5 + AC6). Confirm the first case fails.
- [ ] 4.2 GREEN: replace `openedEmitted` state with `emittedRef = useRef<Set<string>>(new Set())`; consolidate emit into one `useEffect` keyed on `(contextPath, hasRealConversation, hasResumed)` in `kb-chat-content.tsx`.
- [ ] 4.3 Reset `emittedRef.current.clear()` in the existing `prevContextPathRef` effect.
- [ ] 4.4 Commit: `fix(kb-chat): consolidate kb.chat.opened emit into single ref-guarded effect`.

## 5. Phase 5 — #2390 10A migration 024 comment

- [ ] 5.1 Prepend backfill-skip comment block to `apps/web-platform/supabase/migrations/024_add_context_path_to_conversations.sql`.
- [ ] 5.2 Re-read to verify DDL ordering preserved.
- [ ] 5.3 Commit: `docs(migrations): record intentional backfill skip on migration 024`.

## 6. Phase 6 — #2390 10C Supabase-migrations runbook

- [ ] 6.1 Create `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` with pre-deploy SQL verification, apply procedure, verification procedure, rollback SQL template, and post-merge verification steps.
- [ ] 6.2 Append cross-link to AGENTS.md rule `wg-when-a-pr-includes-database-migrations` (text append only — rule ID immutable per `cq-rule-ids-are-immutable`).
- [ ] 6.3 Run `npx markdownlint-cli2 --fix` against the two specific files only (per `cq-markdownlint-fix-target-specific-paths`).
- [ ] 6.4 Commit: `docs(ops): add supabase-migrations runbook with verification + rollback SQL`.

## 7. Phase 7 — #2390 10D regression test (no code change)

- [ ] 7.1 Write `test/ws-handler-context-path-23505.test.ts` asserting a non-matching 23505 error is re-thrown (AC9). Expect it to pass immediately (characterization test for #2382's landed guard).
- [ ] 7.2 Commit: `test(ws-handler): lock 23505 index-name disambiguation (regression for #2382/#2390)`.

## 8. Phase 8 — Verification & Ship

- [ ] 8.1 Run `./node_modules/.bin/vitest run` in `apps/web-platform/` — all tests green.
- [ ] 8.2 Run `./node_modules/.bin/tsc --noEmit`.
- [ ] 8.3 Run `./node_modules/.bin/next build` locally (route-file export regression check per `cq-nextjs-route-files-http-only-exports`).
- [ ] 8.4 Invoke `skill: soleur:review`.
- [ ] 8.5 Invoke `skill: soleur:compound`.
- [ ] 8.6 Invoke `skill: soleur:ship` with body containing `Closes #2384, #2385, #2390`.
- [ ] 8.7 Post-merge: verify release workflow green; no new Sentry issues.
