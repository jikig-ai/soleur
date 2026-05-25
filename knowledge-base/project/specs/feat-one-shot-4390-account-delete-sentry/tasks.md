---
title: "Tasks: obs route account-delete.ts anonymise failures through Sentry"
issue: 4390
branch: feat-one-shot-4390-account-delete-sentry
lane: single-domain
plan: knowledge-base/project/plans/2026-05-25-obs-account-delete-sentry-mirror-plan.md
spec: knowledge-base/project/specs/feat-one-shot-4390-account-delete-sentry/spec.md
last_updated: 2026-05-25
---

# Tasks: feat-one-shot-4390-account-delete-sentry

## Phase 0 — Preconditions

- 0.1 Verify helper signatures via `grep -nE "^export function (reportSilentFallback|warnSilentFallback)" apps/web-platform/server/observability.ts`.
- 0.2 Verify Sentry mock pattern exists: `grep -l 'vi.mock("@sentry/nextjs"' apps/web-platform/test/ -r | head -1`.
- 0.3 Verify step 3.86 is `log.warn` (non-fatal), not `log.error` — `sed -n '345,368p' apps/web-platform/server/account-delete.ts`.
- 0.4 Verify pino formatter rename hook still covers `extra.userId` — `grep -n "formatters\|renameUserIdToHash" apps/web-platform/server/logger.ts`.

## Phase 1 — Tests First (RED)

Mocking strategy (deepen-pass correction): mock `@/server/observability` to capture helper invocations directly. Hoisted mocks: `mockReportSilentFallback`, `mockWarnSilentFallback`, plus a `hashUserId: (id) => "hash:" + id` stub for the orphan-org probe. Pattern matches `apps/web-platform/test/api-accept-terms-ledger.test.ts:50-68`. Do NOT mock `@sentry/nextjs` directly — that strategy double-asserts the helper's pseudonymisation behavior, which lives in `observability.test.ts`.

- 1.1 Extend `apps/web-platform/test/server/account-delete-template-authorizations-cascade.test.ts` with `vi.mock("@/server/observability", ...)` + per-failure-arm assertion on `mockReportSilentFallback`.
- 1.2 Extend `apps/web-platform/test/server/account-delete-workspace-member-actions-cascade.test.ts` likewise.
- 1.3 Extend `apps/web-platform/test/server/account-delete.cascade.integration.test.ts` likewise.
- 1.4 Add `apps/web-platform/test/server/account-delete-sentry-mirror.test.ts` — `test.each([...])` parametrised over all 11 stages (10 reportSilentFallback + 1 warnSilentFallback for step 3.86) + 1 happy-path case = 12 tests.
- 1.5 Confirm RED: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/account-delete-sentry-mirror.test.ts` fails. **Test runner is vitest** — `bunfig.toml` blocks `bun test` discovery per #1469.

## Phase 2 — Implementation (GREEN)

- 2.1 Widen import on line 6 of `apps/web-platform/server/account-delete.ts` to add `reportSilentFallback, warnSilentFallback`.
- 2.2 Migrate 9 FATAL anonymise steps (3.82, 3.83, 3.84, 3.85, 3.90, 3.905, 3.91, 3.92, 3.93) — 18 emit arms total. Each preserves the original message string verbatim.
- 2.3 Migrate step 3.86 (`anonymise-audit-github-token-use`) to `warnSilentFallback` — 2 emit arms.
- 2.4 Migrate the terminal `auth-delete` failure on line 553 to `reportSilentFallback`.
- 2.5 Confirm GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/account-delete` — all four files pass.

## Phase 3 — Cross-check & sweeps

- 3.1 Grep AC1: `grep -nE "log\.(error|warn)" apps/web-platform/server/account-delete.ts | grep -cE "anonymise|auth-delete|Failed to delete auth"` returns 0.
- 3.2 Grep AC2: `grep -cE '^\s*(report|warn)SilentFallback\(' apps/web-platform/server/account-delete.ts` returns 21 (call-sites only; excludes import line at L6).
- 3.3 Grep AC3: `grep -cE 'feature: "account-delete"' apps/web-platform/server/account-delete.ts` returns 21.
- 3.4 Grep AC4: all 11 op slugs present.
- 3.5 Grep AC5: `grep -cE "^\s*message:" apps/web-platform/server/account-delete.ts` returns 21.
- 3.6 Grep AC6: `grep -cE "Sentry\.(captureException|captureMessage)" apps/web-platform/server/account-delete.ts` returns 0.
- 3.7 `cd apps/web-platform && bun run test` — full suite green.
- 3.8 `cd apps/web-platform && bun run typecheck` clean.
- 3.9 `cd apps/web-platform && bun run lint apps/web-platform/server/account-delete.ts apps/web-platform/test/server/account-delete*.ts` clean.

## Phase 4 — Ship

- 4.1 Commit, push, PR with `Closes #4390`.
- 4.2 `/soleur:review` multi-agent (`user-impact-reviewer` enabled via `requires_cpo_signoff: true` frontmatter on plan).
- 4.3 Address review findings inline.
- 4.4 Mark ready, auto-merge.
