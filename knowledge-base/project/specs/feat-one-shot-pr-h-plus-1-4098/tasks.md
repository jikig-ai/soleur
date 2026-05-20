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

- [x] 1.1 Verify upstream merged: `gh pr view 4066 --json state,mergeCommit` AND `gh pr view 4065 --json state,mergeCommit`. If either OPEN → halt and report (per Hard rule on stacked PRs).
- [x] 1.2 `git fetch origin main && git rebase origin/main`. Resolve any conflicts manually.
- [x] 1.3 Confirm tree contains:
  - [x] `apps/web-platform/supabase/migrations/051_*.sql`
  - [x] `apps/web-platform/server/action-sends/write-action-send.ts` (or PR-H'-final path)
  - [x] `apps/web-platform/server/inngest/functions/github-on-event.ts`
  - [x] `audit_github_token_use` RLS policy + `record_github_token_use` RPC (migration 052)
- [x] 1.4 Probe GitHub-API-call wrapping surface — PR-H uses `@octokit/app` at `server/github/app-client.ts:21`; the audit writer wraps the Octokit factory (NOT raw `fetchWithRetry`).
- [x] 1.5 Re-run Open-Code-Review-Overlap queries — zero matches against new files.
- [x] 1.6 `anonymise_action_sends` bypass uses GUC-only (`SET LOCAL session_replication_role = 'replica'` at migration 051:224) — SAFE per the WORM-trigger learning.
- [x] 1.7 Phase 0 reconciliation recorded in PR #4100 body.

> **Scope-revision note (2026-05-20):** PR-H (#4066) + PR-H' (#4065) landed FURTHER than the deepened plan assumed. Already on `main`: `TypedConfirmModal` (components/ui/typed-confirm-modal.tsx), all three `/api/dashboard/today/[id]/{send,edit,discard}/route.ts`, StripeCard wiring in `today-card.tsx`, write-action-send.ts with inline canonical-JSON signature, `/dashboard/audit/github/page.tsx`. Phases 1, 2, 3, and 5 of the original plan are SATISFIED by upstream code. PR-H+1's remaining credible scope is the per-Octokit audit writer + audit-page copy + parent-page discoverability link + legal-doc TOM-#10 update. The GitHub/KbDrift "Spawn agent" button wiring (still `disabled title="Wires in PR-H+1"`) is deferred to follow-up #4124 because it requires the full spawn-agent Inngest + Anthropic SDK flow, a multi-week feature not specified in #4098.

## 2. Phase 1 — Typed-confirm modal + canonical-JSON helper

- [x] **Satisfied by PR-H**: `components/ui/typed-confirm-modal.tsx` shipped with all 10 test cases at `test/components/ui/typed-confirm-modal.test.tsx`. Canonical-JSON inlined in `server/action-sends/write-action-send.ts` (separate lib helper not extracted — single call site).

## 3. Phase 2 — Server routes (Send / Edit / Discard)

- [x] **Satisfied by PR-H**: all three `/api/dashboard/today/[id]/{send,edit,discard}/route.ts` shipped with full grant re-check, approve_every_time gate, hash echo, writeActionSend boundary, exhaustive tier dispatch, and HTTP-only exports (AC20).

## 4. Phase 3 — Wire today-card click handlers

- [x] **Satisfied by PR-H for StripeCard variant**: `components/dashboard/today-card.tsx` `StripeCard` has full Send/Edit/Discard wiring + TypedConfirmModal on `approve_every_time`. `"use client"` directive at line 1.
- Deferred to #4124: `GitHubCard` + `KbDriftCard` variants still have `disabled title="Wires in PR-H+1"` because the full spawn-agent flow is out of #4098 scope.

## 5. Phase 4 — Per-GitHub-API-call audit writer (the actual #4098 deliverable)

- [x] 5.1 RED: `test/server/github/audit-writer.test.ts` — 12 tests covering recordGithubApiCall, extractEndpoint, extractRepoFullName, RPC error path, non-blocking on throw, Sentry mirror tags.
- [x] 5.2 GREEN: `apps/web-platform/server/github/audit-writer.ts` — `recordGithubApiCall`, `extractEndpoint`, `extractRepoFullName` helpers. Non-blocking on failure with Sentry mirror per AC8.
- [x] 5.3 Wire at the Octokit FACTORY boundary (not per-call site): `server/github/app-client.ts` `createGitHubAppClient(installationId, founderId)` now attaches `octokit.hook.after("request", ...)` + `octokit.hook.error("request", ...)` so every Octokit response from any future call site writes one audit row automatically. AC15 sentinel sweep is structural via factory enforcement.
- [x] 5.4 Audit writer attached to factory; downstream Inngest functions (e.g., `github-on-event.ts` when its SDK call ships per #4124) automatically inherit audit-writing via the factory's per-installation Octokit client.
- [x] 5.5 AC15: bypass via raw `fetch(api.github.com)` does NOT exist outside `server/github-app.ts:152` (`/app` install metadata, called by `getInstallationOctokit` internals — not a per-installation call site).
- [ ] **Deferred** 5.6 AC16 live PostgREST integration test — DEV Supabase write smoke is a post-merge operator verification step (AC-PM2 below); the unit-test mock layer asserts the RPC shape + parameter names. Per-call live integration would require synthetic founder + installation rows; deferred to follow-up.

## 6. Phase 5 — `/dashboard/audit/github` surface

- [x] **Satisfied by PR-H** plus this PR's copy update: page existed at `app/(dashboard)/dashboard/audit/github/page.tsx`; empty-state copy updated to remove the "(tracking #4098)" forward-reference.
- [x] 6.4 Discoverability link added on parent `/dashboard/audit/page.tsx` with `data-testid="audit-github-link"` + test in `test/server/dashboard/audit-page-github-link.test.tsx` (AC19).

## 7. Phase 6 — Legal doc amendment

- [x] 7.1 Updated `knowledge-base/legal/article-30-register.md` line 299 PA-17 TOM-#10 to reflect the populated ledger (writer location, RPC call, Sentry mirror).
- [x] 7.2 No mirror at `plugins/soleur/docs/legal/` exists (verified via find); the knowledge-base copy is canonical.
- [x] 7.3 Updated `knowledge-base/legal/audits/2026-05-counsel-review-4066.md` line 31 to mark the TOM-#10 caveat resolved by PR-H+1.

## 8. Phase 7 — Full test sweep + push for CI

- [x] 8.1 `npx tsc --noEmit` clean (vitest pinned to project's local binary per `2026-05-04-plan-precedent-search-must-include-lib-helpers.md`; bun is NOT the test runner — `package.json` declares `vitest`).
- [x] 8.2 Affected-path sweep clean: `./node_modules/.bin/vitest run test/server/github/ test/server/dashboard/ test/server/scope-grants/ test/server/action-sends/` = 46 passed / 9 skipped (integration-only).
- [ ] 8.3 `git push` (next).
- [ ] 8.4 Mark PR #4100 ready for review (handled by /soleur:ship).

## 9. Post-merge (operator-automatable)

- [ ] 9.1 `gh issue close 4098 --comment "PR-H+1 merged via #<N>"` after CI green.
- [ ] 9.2 Verify `record_github_token_use` populates DEV ledger via `mcp__plugin_supabase_supabase__execute_sql`.
- [ ] 9.3 Confirm post-merge CI green via `gh workflow run wait-for-pr-checks.yml --ref main`.

## 10. Learnings (capture before ship Phase 5.5)

- [ ] 10.1 Write a learning if Phase 0 surfaces additional foundations-PR drift between #4066 / #4065 / this PR. Suggested directory: `knowledge-base/project/learnings/best-practices/`.
- [ ] 10.2 Write a learning if the WORM-trigger role-check bypass is found broken in `anonymise_action_sends` (cite `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`).
- [ ] 10.3 Compound any planning-side errors per `wg-every-session-error-must-produce-either`.
