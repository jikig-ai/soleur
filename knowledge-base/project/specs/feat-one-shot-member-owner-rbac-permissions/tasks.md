---
title: "Tasks — Member vs Owner RBAC Settings UI gating"
date: 2026-06-01
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-01-fix-member-owner-rbac-settings-gating-plan.md
---

# Tasks — fix: Member vs Owner RBAC Settings UI gating

## Phase 0 — Preconditions

- [ ] 0.1 `git grep -n "InviteMemberAction" apps/web-platform/app` — confirm sole render site at `team/page.tsx:68` with no `isOwner`.
- [ ] 0.2 `git grep -n "Remove member" apps/web-platform/components/settings/team-membership-list.tsx` — confirm button at `:207-213` outside any `isOwner` guard.
- [ ] 0.3 `git grep -n "inviteWorkspaceMember\b" apps/web-platform -- ':!*test*'` — enumerate production callers of the legacy direct-RPC invite path (AC6 finding).
- [ ] 0.4 Read `test/team-membership-list.test.tsx`; confirm all current cases pass `isOwner={true}`.
- [ ] 0.5 Confirm `vitest.config.ts:60` jsdom glob `test/**/*.test.tsx` covers the test file.

## Phase 1 — RED (failing tests)

- [ ] 1.1 Add `isOwner={false}` test: non-self row exposes NO "Remove member" action.
- [ ] 1.2 Add `isOwner={false}` test: non-self row exposes NO "Transfer ownership" action (regression-lock).
- [ ] 1.3 Add invite-trigger gating test (new `test/invite-member-action.test.tsx`): returns `null` for Members, renders for Owners.
- [ ] 1.4 Run `./node_modules/.bin/vitest run test/team-membership-list.test.tsx test/invite-member-action.test.tsx` → new cases FAIL.

## Phase 2 — GREEN (gate the two controls)

- [ ] 2.1 `team-membership-list.tsx`: change `showActions` to `!isCurrentUser && isOwner` (hides kebab trigger for Members) AND/OR wrap "Remove member" button in `{isOwner && (...)}`.
- [ ] 2.2 `invite-member-action.tsx`: add `isOwner: boolean` prop + `if (!isOwner) return null;`.
- [ ] 2.3 `team/page.tsx`: pass `isOwner={isOwner}` to `<InviteMemberAction>`; optional empty-state CTA copy gate.
- [ ] 2.4 Run changed-file tests → GREEN. Run `npx tsc --noEmit` → clean.

## Phase 3 — Defense-in-depth verification (no code change)

- [ ] 3.1 Confirm caller-owner gate LINE preserved verbatim in the 5 routes (do NOT use raw `grep -c` — invite-member has 2 `role !== "owner"` matches: caller gate + body validation).
- [ ] 3.2 Record AC6 finding in PR body: `inviteWorkspaceMember` had ZERO production callers at deepen time (verified `git grep -nw`, excl tests + def). Re-run at /work to catch any newly-introduced caller.

## Phase 4 — Optional copy reconciliation (gated by Decision #1)

- [ ] 4.1 If "billing personal" confirmed: fix misleading "share the same … billing" copy in `team/page.tsx:56-58` and `:90` (1-line) OR file deferral issue.

## Deferrals to file (if applicable)

- [ ] Follow-up: "Expose owner-gated change-role UI for workspace members" (if team wants it).
- [ ] Follow-up: "Resolve billing scope: personal vs workspace-shared + reconcile Team-page copy" (if Decision #1 → workspace-shared).
- [ ] Follow-up: "Remove unused inviteWorkspaceMember legacy path or pass p_caller_user_id" (if AC6 finds it unused).
