---
plan: knowledge-base/project/plans/2026-06-30-fix-cron-digest-dedup-sweep-7-crons-plan.md
issue: 5786
lane: cross-domain
---

# Tasks — #5786 cron digest dedup sweep (7 crons)

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Phase 1 — Widen shared matcher (contract change, RED first)
- [ ] 1.1 Add RED unit cases to `test/server/inngest/cron-shared.test.ts` for the new `isRealScheduledDigest(issue, date, titlePrefix, titleSuffix?)` signature, incl. campaign-calendar suffix true/false (AC4).
- [ ] 1.2 Update existing 6 `isRealScheduledDigest` + 4 `digestIssueExistsForDate` CM cases to pass `CM_PREFIX` explicitly; assert byte-identical outcomes (AC5).
- [ ] 1.3 Widen `isRealScheduledDigest` + `digestIssueExistsForDate` in `_cron-shared.ts`; keep `SCHEDULED_DIGEST_TITLE_PREFIX` exported; update doc-comment (Design Decision signatures).
- [ ] 1.4 `cron-community-monitor.ts:335` — pass `titlePrefix: SCHEDULED_DIGEST_TITLE_PREFIX` at existing call site. Phase 1 GREEN.

## Phase 2 — Wire the 6 suffix-free crons
For roadmap-review, content-generator, growth-audit, growth-execution, competitive-analysis, seo-aeo-audit:
- [ ] 2.1 Add `digestIssueExistsForDate` to each `./_cron-shared` import block.
- [ ] 2.2 Insert `dedup-digest-check` step after `run-started-at` (insert lines per plan table); early-return GREEN heartbeat on hit. Use each cron's `ensureScheduledAuditIssue` titlePrefix.
- [ ] 2.3 roadmap-review: drop `--search`, widen `--state open`→`all` (AC7). Other 5: add fresh `gh issue list --label scheduled-<slug> --state all` DEDUP RULE.
- [ ] 2.4 Add AC6 source-anchor assertions to each per-cron test file.

## Phase 3 — Wire cron-campaign-calendar (suffix variant)
- [ ] 3.1 Import + dedup block after l.167, passing `titleSuffix: " (heartbeat)"`, prefix `[Scheduled] Campaign Calendar -`.
- [ ] 3.2 Add in-prompt LIST rule matching the suffixed title.
- [ ] 3.3 Per-cron test asserts `titleSuffix: " (heartbeat)"` present in source.

## Phase 4 — Parametrized dedup regression test
- [ ] 4.1 Create `test/server/inngest/cron-cohort-dedup.test.ts` (fake octokit STORE + mocked spawn + frozen Date), modeled on `cron-community-monitor-dedup.test.ts`.
- [ ] 4.2 Parametrize 7 `{handler,label,titlePrefix,titleSuffix,cronName}` rows via `it.each`; cover AC1 (2→1), AC2 (fail-OPEN), AC3 (FAILED-stub no-suppress) through the REAL handler.

## Phase 5 — Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (AC8).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` green (AC9). Apply #5751 flake-isolation discipline if an untouched test fails under parallel workers.
