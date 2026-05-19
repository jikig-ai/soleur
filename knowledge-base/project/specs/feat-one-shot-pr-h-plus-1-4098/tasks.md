---
title: "PR-H+1 — Tasks"
issue: 4098
branch: feat-one-shot-pr-h-plus-1-4098
pr: 4100
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-19-feat-pr-h-plus-1-wire-send-edit-discard-octokit-audit-and-dashboard-plan.md
---

# Tasks — PR-H+1: Send/Edit/Discard wiring + audit writer + /dashboard/audit/github

> Derived from `2026-05-19-feat-pr-h-plus-1-wire-send-edit-discard-octokit-audit-and-dashboard-plan.md`. Plan is the source of truth; tasks are a breakdown only.

## 1. Phase 0 — Rebase gate + reconciliation

- [ ] 1.1 Verify upstream merged: `gh pr view 4066 --json state,mergeCommit` AND `gh pr view 4065 --json state,mergeCommit`. If either OPEN → halt and report (per Hard rule on stacked PRs).
- [ ] 1.2 `git fetch origin main && git rebase origin/main`. Resolve any conflicts manually.
- [ ] 1.3 Confirm tree contains:
  - [ ] `apps/web-platform/supabase/migrations/051_*.sql`
  - [ ] `apps/web-platform/server/action-sends/write-action-send.ts` (or PR-H'-final path)
  - [ ] `apps/web-platform/server/inngest/functions/github-on-event.ts`
  - [ ] `audit_github_token_use` RLS policy + `record_github_token_use` RPC
- [ ] 1.4 Probe GitHub-API-call wrapping surface (Octokit vs raw fetch):
  - [ ] `grep -nE "Octokit|octokit\.|@octokit" apps/web-platform/server/github/ 2>/dev/null`
  - [ ] `grep -nE "fetch\(.*api\.github\.com" apps/web-platform/server/github/ 2>/dev/null`
  - [ ] `grep -nE "fetchWithRetry" apps/web-platform/server/github/ 2>/dev/null`
- [ ] 1.5 Re-run Open-Code-Review-Overlap queries per plan Phase 1.7.5.
- [ ] 1.6 Verify `anonymise_action_sends` WORM-trigger bypass uses GUC-only (NOT role-check) per `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`. If broken, file a follow-up issue.
- [ ] 1.7 Record Phase 0 grep results in the PR body under `## Phase 0 reconciliation` (AC21).

## 2. Phase 1 — Typed-confirm modal + canonical-JSON helper

- [ ] 2.1 RED: write `test/components/dashboard/typed-confirm-modal.test.tsx` per Phase 1 (10 test cases: a-j).
- [ ] 2.2 GREEN: `components/dashboard/typed-confirm-modal.tsx`. Focus-trap mirrored from `sign-out-confirm-modal.tsx`. No `.trim()` / `.normalize()`.
- [ ] 2.3 RED: write `test/lib/canonical-json.test.ts` (shallow + nested key-order independence + non-finite rejection).
- [ ] 2.4 GREEN: `apps/web-platform/lib/canonical-json/index.ts` per the Phase 1 reference implementation.

## 3. Phase 2 — Server routes (Send / Edit / Discard)

- [ ] 3.1 RED: `test/server/dashboard/today/send.test.ts` per Phase 2 matrix.
- [ ] 3.2 GREEN: `apps/web-platform/app/api/dashboard/today/send/route.ts`.
- [ ] 3.3 RED: `test/server/dashboard/today/edit.test.ts`.
- [ ] 3.4 GREEN: `apps/web-platform/app/api/dashboard/today/edit/route.ts`.
- [ ] 3.5 RED: `test/server/dashboard/today/discard.test.ts`.
- [ ] 3.6 GREEN: `apps/web-platform/app/api/dashboard/today/discard/route.ts`.
- [ ] 3.7 Verify all three route through `writeActionSend(...)` boundary.
- [ ] 3.8 Verify each route exports only HTTP verb handlers (AC20).

## 4. Phase 3 — Wire today-card click handlers

- [ ] 4.1 RED: `test/components/dashboard/today-card.click.test.tsx`.
- [ ] 4.2 GREEN: edit `components/dashboard/today-card.tsx`. Add `"use client"`. Remove `disabled aria-disabled="true"`. Wire onClick to fetch the three routes; `approve_every_time` opens `TypedConfirmModal` first.
- [ ] 4.3 Verify `next build` clean (touch-target classes preserved).

## 5. Phase 4 — Per-GitHub-API-call audit writer

- [ ] 5.1 RED: `test/server/inngest/github-on-event-audit-writer.test.ts` (1-call, 3-call, throw-on-Nth, bypass sentinel).
- [ ] 5.2 GREEN: `apps/web-platform/server/github/audit-writer.ts` (`recordGithubApiCall` helper).
- [ ] 5.3 Wire into the GitHub-API wrap surface (per Phase 0 probe outcome).
- [ ] 5.4 Wire `github-on-event.ts` to call the wrapper inside `runWithByokLease(...)` scope.
- [ ] 5.5 AC15: sentinel sweep `git grep "fetch.*api.github.com"` returns only wrapper-internal hits.
- [ ] 5.6 AC16: live PostgREST integration test against DEV Supabase (NOT mock).

## 6. Phase 5 — `/dashboard/audit/github` surface

- [ ] 6.1 RED: `test/app/dashboard/audit/github.test.tsx`.
- [ ] 6.2 GREEN: `apps/web-platform/app/(dashboard)/dashboard/audit/github/page.tsx`.
- [ ] 6.3 GREEN: `apps/web-platform/components/audit/github-audit-table.tsx`.
- [ ] 6.4 Edit `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` to add discoverability link (AC19).

## 7. Phase 6 — Legal doc amendment

- [ ] 7.1 Edit `knowledge-base/legal/dpd-soleur.md` (canonical) — remove Article 30 PA-16 TOM-#10 caveat.
- [ ] 7.2 Edit `plugins/soleur/docs/legal/dpd-soleur.md` (mirror) — same edit.
- [ ] 7.3 Append HTML-comment change-log entry per PR-H Phase 7 convention.
- [ ] 7.4 Verify `grep -nE "TOM-#10|record_github_token_use no longer ships unpopulated"` returns 0 matches in both files (AC11).

## 8. Phase 7 — Full test sweep + push for CI

- [ ] 8.1 `bun run typecheck` clean.
- [ ] 8.2 `bun test apps/web-platform/test/` clean.
- [ ] 8.3 `git push` and wait for CI green.
- [ ] 8.4 Mark PR #4100 ready for review.

## 9. Post-merge (operator-automatable)

- [ ] 9.1 `gh issue close 4098 --comment "PR-H+1 merged via #<N>"` after CI green.
- [ ] 9.2 Verify `record_github_token_use` populates DEV ledger via `mcp__plugin_supabase_supabase__execute_sql`.
- [ ] 9.3 Confirm post-merge CI green via `gh workflow run wait-for-pr-checks.yml --ref main`.

## 10. Learnings (capture before ship Phase 5.5)

- [ ] 10.1 Write a learning if Phase 0 surfaces additional foundations-PR drift between #4066 / #4065 / this PR. Suggested directory: `knowledge-base/project/learnings/best-practices/`.
- [ ] 10.2 Write a learning if the WORM-trigger role-check bypass is found broken in `anonymise_action_sends` (cite `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`).
- [ ] 10.3 Compound any planning-side errors per `wg-every-session-error-must-produce-either`.
