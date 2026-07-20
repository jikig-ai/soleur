# Tasks — feat-one-shot-6143-cron-dedup-cohort-followups

Derived from `knowledge-base/project/plans/2026-07-07-fix-cron-community-monitor-dedup-and-cohort-title-date-pin-plan.md`.
Lane: single-domain. Closes #6143. Locate every line reference by `grep` at implementation time — line numbers drift.

## Phase 0 — Preconditions (grep, don't trust line numbers)

- [x] 0.1 `grep -n 'DEDUP RULE' apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — confirm the **three** locations (SHAPE-DIFF header, prompt block, `#5751` code comment).
- [x] 0.2 `git grep -l digestIssueExistsForDate apps/web-platform/server/inngest/functions/cron-*.ts` — confirm the cohort is exactly 9 (arch-diagram-sync, campaign-calendar, community-monitor, competitive-analysis, content-generator, growth-audit, growth-execution, roadmap-review, seo-aeo-audit).
- [x] 0.3 `git grep -n '{{' apps/web-platform/server/inngest/functions/cron-*.ts` — confirm no `{{`-collision with the `{{RUN_DATE}}` sentinel (expected: none in cohort).
- [x] 0.4 Confirm `runStartedAt` is captured via `step.run("run-started-at", …)` in each of the 9 crons (replay-stable; injected date == dedup key).

## Phase 1 — Part 1: community-monitor DEDUP-RULE removal + citation

- [x] 1.1 `cron-community-monitor.ts`: delete the prompt DEDUP RULE block (`~:229–234`).
- [x] 1.2 `cron-community-monitor.ts`: delete the SHAPE-DIFF header line `//   - DEDUP RULE uses 24h window …` (`~:45`).
- [x] 1.3 `cron-community-monitor.ts`: reword the `#5751` code comment (`~:324–328`) to drop the literal `DEDUP RULE` (e.g. "…stale-search-index in-prompt dedup fallback").
- [x] 1.4 `cron-community-monitor.test.ts`: remove the three `it.each` rows asserting `"DEDUP RULE"`, `"within the last 24 hours"`, `"post your findings as a comment on the most recent existing issue"` (`~:156–171`); update the file-header comment (`~:11`).
- [x] 1.5 `cron-community-monitor.test.ts`: add a regression-guard `describe` (mirror `cron-roadmap-review.test.ts:128–144`) asserting `SUT_SOURCE.not.toContain` for the three removed strings; keep the prefix anchor `"[Scheduled] Community Monitor"` (no trailing dash).
- [x] 1.6 `cron-community-monitor.test.ts`: assert registration still contains `{ scope: "fn", limit: 1 }` (mirror `cron-roadmap-review.test.ts:152`).
- [x] 1.7 `_cron-shared.ts` (`~:680–688`): re-point the `verifyScheduledIssueCreated` rationale to campaign-calendar's comment-bump path, citing the stable markers `counts via updated_at` / `Do NOT create a new issue` (NOT "STEP 2(b)"). Do NOT touch the `since`/`updated_at` filter body (`~:715–733`).
- [x] 1.8 `cron-shared.test.ts` (`~:239`): surgically flip the dedup-comment test's fixture label to `scheduled-campaign-calendar` + update its rationale; assertion stays `toBe(true)`.
- [x] 1.9 `cron-shared.test.ts`: add a coupling-invariant assertion that `cron-campaign-calendar.ts` source still contains `Do NOT create a new issue` (+ `counts via updated_at`).

## Phase 2 — Part 2: shared injector (contract first)

- [x] 2.1 `_cron-shared.ts` (`~:781`): add `RUN_DATE_SENTINEL = "{{RUN_DATE}}"` + `injectRunDate(prompt, runStartedAt)` that **throws** if the sentinel is absent, else `replaceAll(sentinel, runStartedAt.slice(0,10))`.
- [x] 2.2 Write `cron-cohort-title-date-pin.test.ts` RED first (before wiring call sites): discovery-based drift-guard (`readdirSync` + `digestIssueExistsForDate` filter → each has `{{RUN_DATE}}` + `injectRunDate(`) + `injectRunDate` unit test (multi-sub + throw-on-absent). Precedent: `sentry-monitor-iac-parity.test.ts:53`.

## Phase 3 — Part 2: pin the 9 cron titles (title line → sentinel; call site → injectRunDate)

For each: swap the ISSUE-TITLE date placeholder to `{{RUN_DATE}}` (title line ONLY) and wrap the `spawnClaudeEval` prompt arg with `injectRunDate(X_PROMPT, runStartedAt)`.

- [x] 3.1 `cron-community-monitor.ts` — title (`~:220`, anchor on the FULL literal `[Scheduled] Community Monitor - YYYY-MM-DD`, NOT the bare token — `:196` digest-file `YYYY-MM-DD-digest.md` must stay); call site (`~:417`).
- [x] 3.2 `cron-roadmap-review.ts` — title (`~:164`); call site (`~:311`).
- [x] 3.3 `cron-architecture-diagram-sync.ts` — title (`~:107`); call site (`~:255`); **reconcile `~:87`** ("use `<today>` throughout") to scope to file-body dates / mark the title platform-pinned.
- [x] 3.4 `cron-campaign-calendar.ts` — STEP 2.5 title (`~:103`, keep ` (heartbeat)` OUTSIDE the sentinel); call site (`~:275`).
- [x] 3.5 `cron-competitive-analysis.ts` — title (`~:141`); call site (`~:316`).
- [x] 3.6 `cron-content-generator.ts` — BOTH title occurrences (`~:107`, `~:124`); leave `publish_date: <today>` (`~:115`); add inline coexistence marker; call site (`~:303`).
- [x] 3.7 `cron-growth-audit.ts` — title (`~:105`); leave the 4 audit-path `<today>` (`~:93–102`); add inline coexistence marker; call site (`~:263`).
- [x] 3.8 `cron-growth-execution.ts` — title (`~:131`); call site (`~:298`).
- [x] 3.9 `cron-seo-aeo-audit.ts` — title (`~:130`); call site (`~:292`).

## Phase 4 — Verify

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts test/server/inngest/cron-community-monitor-dedup.test.ts test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-shared.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-cohort-title-date-pin.test.ts test/server/inngest/cron-roadmap-review.test.ts` — all green.
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] 4.3 AC sweep: AC1 whole-file grep → 0; AC7 three `git grep -l` sets equal + count 9; AC9 secondary-date greps present; AC13 `git diff --name-only` scope.

## Acceptance Criteria

See plan `## Acceptance Criteria` (AC1–AC13). Load-bearing Part-2 gates: AC6 (injector throw+multisub),
AC7 (discovery-based cohort completeness), AC8 (campaign-calendar canary). AC1 (all 3 DEDUP RULE
literals scrubbed) is the Part-1 must-pass.
