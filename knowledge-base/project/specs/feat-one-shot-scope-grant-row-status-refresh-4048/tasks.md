---
title: "Tasks: fix scope-grant row status refresh (#4048)"
date: 2026-05-19
issue: 4048
plan: knowledge-base/project/plans/2026-05-19-fix-scope-grant-row-status-refresh-plan.md
lane: single-domain
---

# Tasks — fix scope-grant row status refresh after Authorize/Revoke (#4048)

## Phase 0 — Preconditions

- [ ] 0.1 Confirm CWD is the worktree `.worktrees/feat-one-shot-scope-grant-row-status-refresh-4048/` and branch matches.
- [ ] 0.2 Verify `apps/web-platform/components/scope-grants/scope-grant-row.tsx:1` still has `"use client";` and lines 127-136 still contain the `committedTier && grantedAt` conditional that motivates this fix. (Drift check before editing.)
- [ ] 0.3 Verify `apps/web-platform/test/` is the test-file directory (sibling `tool-use-chip.test.tsx` exists and runs).
- [ ] 0.4 Verify `next/navigation` mock convention by reading `apps/web-platform/test/settings-page.test.tsx:9-12`.

## Phase 1 — RED (write failing tests first)

- [ ] 1.1 Create `apps/web-platform/test/scope-grant-row.test.tsx` with the four FR tests (FR1 Authorize, FR2 Revoke, FR3 Update, FR4 Authorize-failure) plus the FR5 regression test (auto-tier ack gating unchanged). Use the module-scoped `refresh = vi.fn()` mock for `next/navigation`. Mock `global.fetch` per test.
- [ ] 1.2 Run `bun run --filter=web-platform test:ci -- scope-grant-row` and confirm all four FR tests FAIL with the expected symptom (FR1: status text doesn't update; FR2/FR3 similar; FR4: tests refresh-not-called assertion). The auto-tier regression test (FR5) MUST already PASS — it asserts current behavior.

## Phase 2 — GREEN (minimal fix)

- [ ] 2.1 Edit `apps/web-platform/components/scope-grants/scope-grant-row.tsx`:
  - Add `import { useRouter } from "next/navigation";` after the existing react import.
  - Inside `ScopeGrantRow` component, after the existing `useState`/`useTransition` calls (around line 49), add `const router = useRouter();`.
  - In the `onGrant` success path (after `setCommittedTier(selectedTier); setAcked(false);` at lines 86-87), add `router.refresh();`.
  - In the `onRevoke` success path (after `setCommittedTier(null); setSelectedTier(null); setAcked(false);` at lines 111-113), add `router.refresh();`.
- [ ] 2.2 Re-run `bun run --filter=web-platform test:ci -- scope-grant-row` → all five tests now pass.

## Phase 3 — Verify QGs

- [ ] 3.1 `bun run --filter=web-platform exec tsc --noEmit` → no new errors in the edited file.
- [ ] 3.2 Diff inspection: `git diff apps/web-platform/components/scope-grants/scope-grant-row.tsx` shows exactly the 4 additions enumerated in QG3 — no other changes.
- [ ] 3.3 Confirm `"use client";` directive at line 1 is intact (QG4).

## Phase 4 — Commit

- [ ] 4.1 `git add apps/web-platform/components/scope-grants/scope-grant-row.tsx apps/web-platform/test/scope-grant-row.test.tsx`
- [ ] 4.2 Run `/soleur:compound` per `wg-before-every-commit-run-compound-skill`.
- [ ] 4.3 Commit with message: `fix: refresh scope-grant row status after Authorize/Revoke (#4048)`. Include `Closes #4048` in the PR body (NOT the commit subject) per `wg-use-closes-n-in-pr-body-not-title-to`.

## Phase 5 — Review

- [ ] 5.1 Push branch and open PR.
- [ ] 5.2 Run `/soleur:review` (multi-agent).
- [ ] 5.3 Resolve P1/P2/P3 findings inline.

## Phase 6 — QA (delegated to /soleur:qa)

- [ ] 6.1 Playwright: navigate to `/dashboard/settings/scope-grants`, click Authorize on an unauthorized class, assert status paragraph updates to "Active at <tier-label> since <date>" within ~200ms without page reload.
- [ ] 6.2 Playwright: click Revoke on a now-authorized row, assert status paragraph updates to "Not authorized — Soleur will not act on this class." within ~200ms.

## Phase 7 — Ship

- [ ] 7.1 `/soleur:ship` post-merge — closes #4048 via PR body, no terraform / no migration / no operator post-merge step.
