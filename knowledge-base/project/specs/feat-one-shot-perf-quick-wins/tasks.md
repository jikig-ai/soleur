# Tasks — perf: frontend performance quick-wins bundle (2026-06-18 audit)

Plan: `knowledge-base/project/plans/2026-06-18-perf-frontend-quick-wins-bundle-plan.md`
Branch: `feat-one-shot-perf-quick-wins`
Lane: single-domain (no spec.md; single-app frontend refactor)

> The four fixes are independent. Order is convenience only. Each phase is behavior-preserving except M1 (deliberate: skeleton instead of blank screen).
> **Canonical commands (do NOT use `npm run -w` — repo root has no `workspaces` field):**
> typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
> lint: `cd apps/web-platform && npm run lint`
> test: `cd apps/web-platform && npm run test:ci`

## Phase 1 — H4: loading.tsx skeletons (NEW)

- [x] 1.1 Create `apps/web-platform/app/(dashboard)/dashboard/loading.tsx` — home: banner strip + ~6 conversation-row `animate-pulse` skeletons; mirror analytics `loading.tsx` idiom (`bg-soleur-bg-surface-2`). Server component, no `"use client"`.
- [x] 1.2 Create `apps/web-platform/app/(dashboard)/dashboard/chat/loading.tsx` — centered composer-card skeleton (streams while the chat layout's delegation/invite resolution runs).
- [x] 1.3 Create `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/loading.tsx` — transcript skeleton: ~5 alternating message bubbles + composer bar.
- [x] 1.4 Create `apps/web-platform/app/(dashboard)/dashboard/kb/loading.tsx` — sidebar-tree skeleton + content-area skeleton; INLINE the `animate-pulse` markup (do not import the `"use client"` `LoadingSkeleton`) to keep this a pure server component.
- [x] 1.5 Create `apps/web-platform/app/(dashboard)/dashboard/settings/loading.tsx` — ~3 stacked card-shell skeletons (`rounded-xl border border-soleur-border-default` + `animate-pulse` rows). This is the one true server-data-fetch streaming win.
- [x] 1.6 No tests (repo convention: `loading.tsx` untested; vitest `include` is `test/**/*.test.tsx` — co-located tests are never collected). Typecheck is the gate. (AC1, AC2)

## Phase 2 — H3: parallelize the pending-invites fetch

- [x] 2.1 In `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx`, move `getPendingInvitesForUser(user.id, user.email ?? "")` to start BEFORE the delegation branch (`const invitesPromise = getPendingInvitesForUser(...)`), then `await invitesPromise` after the delegation chain completes. Preserve the delegation chain's sequential awaits (`resolveCurrentOrganizationId` → `isByokDelegationsEnabled` → `resolveCurrentWorkspaceId` → `resolveGranteeDelegation` → `resolveGranteeAcceptanceStatus`) and the surrounding `try/catch` exactly.
- [x] 2.2 If `next lint`/biome flags `invitesPromise` as a floating promise, switch to the explicit `Promise.all([invitesPromise, <delegation-iife>])` form (precedent: `settings/page.tsx:31`). (AC3, AC8)
- [x] 2.3 Typecheck + full suite green (chat-page suites cover this layout indirectly). (AC7, AC9)

## Phase 3 — M4: explicit column list

- [x] 3.1 In `apps/web-platform/hooks/use-conversations.ts` (~line 231), replace `.select("*")` on the `conversations` query with the explicit list (EXACTLY the `Conversation` interface field set, verified against `lib/types.ts:580-603`):
      `"id, user_id, domain_leader, session_id, status, total_cost_usd, input_tokens, output_tokens, last_active, created_at, archived_at, context_path, repo_url, active_workflow, workflow_ended_at, workspace_id, visibility"`
- [x] 3.2 Add a one-line comment above the select: "explicit columns = Conversation interface field set; update both together if the type changes." Keep the existing `try/catch` (PostgrestBuilder is a thenable — do NOT use `.catch()`).
- [x] 3.3 Leave the sibling `.update(...)` calls (:538/:551/:570) untouched (mutations, not selects). (AC4)
- [x] 3.4 Full suite green — `use-conversations-limit`, `conversations-rail-*` (no test pins the `"*"` arg, verified). (AC9)

## Phase 4 — M1: ChatSurface context-pending state

- [x] 4.1 In `apps/web-platform/components/chat/chat-surface.tsx`: add `contextPending?: boolean` (default `false`) to the props interface; in the session-start effect (~:347), add `contextPending` to BOTH the early-return guard (`if (status !== "connected" || sessionStarted || contextPending) return;`) and the dep array. (Verified: `startSession` has exactly two call sites, both inside this one guarded effect.)
- [x] 4.2 In `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`: remove `if (contextLoading) return null;`; render `<ChatSurface variant="full" conversationId={params.conversationId} initialContext={initialContext} contextPending={contextLoading} />` unconditionally. Optionally show an `animate-pulse` placeholder in the context-pane region while pending (keep minimal; do not redesign ChatSurface).
- [x] 4.3 Add `apps/web-platform/test/chat-page-context-pending.test.tsx` (under `test/`, NOT co-located): assert (a) ChatSurface shell renders immediately while `/api/kb/content/<path>` is pending; (b) `startSession` is called with the resolved `initialContext` only after the fetch resolves, never with `undefined`. Precedents: `test/chat-surface-context-reset.test.tsx`, `test/chat-page*.test.tsx`. (AC5, AC6)
- [x] 4.4 Typecheck + lint + full suite green (existing `chat-surface-*` suites must stay green). (AC7, AC8, AC9)

## Phase 5 — Ship

- [x] 5.1 Run all three gates: typecheck (AC7), lint (AC8), `test:ci` (AC9) — all green.
- [x] 5.2 Open ONE PR. Body: reference the 2026-06-18 frontend perf audit; list #5531, #5532, #5533, #5534, #5535, #5536 as follow-ups with `Ref #N` (NOT `Closes`). (AC10)
- [x] 5.3 No post-merge operator step — `web-platform-release.yml` deploys on merge. (AC11)
