# Tasks — feat-one-shot-4826-nav-rail-position-resume

lane: single-domain  
plan: knowledge-base/project/plans/2026-07-16-feat-nav-rail-position-resume-plan.md  
issue: #4826

## Phase 0 — Preconditions

- [x] 0.1 Confirm `safeSession` API + tests (`lib/safe-session.ts`, `test/safe-session.test.ts`)
- [x] 0.2 Confirm `isKbDocView` / `segmentToDrillLevel` (`hooks/segment-to-drill-level.ts`)
- [x] 0.3 Confirm chat index redirect stub (`app/(dashboard)/dashboard/chat/page.tsx`)
- [x] 0.4 Confirm tree scrollport (`components/kb/kb-sidebar-shell.tsx` overflow-y-auto)
- [x] 0.5 Note typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [x] 0.6 Note test runner: `./node_modules/.bin/vitest run` under `apps/web-platform` (not bun test)

## Phase 1 — Pure module (TDD)

- [x] 1.1 RED: `test/nav-resume.test.ts` for key shape, path/id parse, reject `new`, corrupt expanded, reject `..` / non-UUID
- [x] 1.2 GREEN: `lib/nav-resume.ts` implementing helpers (+ sanitize-on-read)
- [x] 1.3 Cap expanded list length on write (e.g. 200)
- [x] 1.4 Expanded seed one-shot latch documented in hook comments

## Phase 2 — Hook + persist

- [x] 2.1 Implement `hooks/use-nav-resume.ts` (workspace-gated read/write)
- [x] 2.2 Wire path + expanded persist/seed in `hooks/use-kb-layout-state.tsx`
- [x] 2.3 Wire chat id persist on `/dashboard/chat/<uuid>` (page or rail mount)
- [x] 2.4 Tests: `test/nav-resume-hook.test.tsx`

## Phase 3 — Restore entry points

- [x] 3.1 Dynamic KB main-nav href in `app/(dashboard)/layout.tsx`
- [x] 3.2 Client resume for bare `/dashboard/chat` in `chat/page.tsx` (`useEffect` + `router.replace` + wait for workspaceId; "Opening…" shell)
- [x] 3.3 Scroll persist/restore in `kb-sidebar-shell.tsx` (`data-testid="kb-tree-scrollport"`)
- [x] 3.4 Tests: scroll resume with instrumented scrollTop; nav href sticky

## Phase 4 — Fail-closed

- [x] 4.1 Clear chat key + land `/new` on stale/missing conversation
- [x] 4.2 Clear KB path key on confirmed not-found when appropriate
- [x] 4.3 Workspace A/B isolation tests

## Phase 5 — Verification

- [x] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/nav-resume.test.ts test/nav-resume-hook.test.tsx test/kb-tree-scroll-resume.test.tsx`
- [x] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [x] 5.3 Grep: resume module has no message-body / tree-dump persistence
- [x] 5.4 Manual dogfood: KB deep file → back → KB; chat thread → leave → bare chat

## Phase 6 — Ship hygiene

- [x] 6.1 PR body: `Closes #4826`; note prior infra PRs did not implement product scope
- [x] 6.2 Confirm wireframe path referenced in PR/spec
