---
title: "Tasks — fix cron-roadmap-review output-contract (remove prompt DEDUP RULE + pin title date)"
branch: feat-one-shot-roadmap-review-dedup-output-contract
lane: single-domain
plan: knowledge-base/project/plans/2026-07-07-fix-cron-roadmap-review-dedup-output-contract-plan.md
---

# Tasks

Derived from `2026-07-07-fix-cron-roadmap-review-dedup-output-contract-plan.md` (post plan-review).
Runner: **vitest** (`apps/web-platform/node_modules/.bin/vitest`). Typecheck:
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 1 — Prompt fix (contract change first)

- [ ] 1.1 In `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`, delete the DEDUP
      RULE block (lines 165–167) from the prompt.
- [ ] 1.2 Rewrite the `## Output` section (169–172): drop the "If no recent duplicate exists"
      conditional and the comment-and-exit fallback; keep the exact verbatim substring
      `create a new issue with:`. The eval unconditionally creates the dated digest.
      `ROADMAP_REVIEW_PROMPT` stays a static const (no date-pin — Precedent-Diff / cohort
      consistency; the cross-midnight date-pin is deferred cohort-wide).
- [ ] 1.3 Preserve the four verbatim-extraction anchors (Part 1 / Part 2 / MILESTONE RULE /
      BIDIRECTIONAL RULE) and the safety guards (ISSUE CLOSURE SAFETY, ROADMAP.MD CONFLICT GUARD,
      CLONE DEPTH RULE, STAGING RULE); leave the header comment (113–116) intact.
- [ ] 1.4 Re-point the stale citation in `_cron-shared.ts:680–688` from "roadmap-review's DEDUP
      RULE" to "`cron-community-monitor`'s DEDUP RULE" (comment-only; do NOT touch the
      `updated_at`/`since` filter — community-monitor still needs it).

## Phase 2 — Tests (consumers of the contract)

- [ ] 2.1 In `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts`, remove the
      `["DEDUP RULE", …]` row (line 103) and the `["post your findings as a comment on the most
      recent existing issue", …]` `it.each` row (108–116). Update the file header comment (10–14).
- [ ] 2.2 Add a new `describe` block asserting on `SUT_SOURCE`: (i) **absence** of `DEDUP RULE`,
      `within the last 6 days`, `post your findings as a comment on the most recent existing
      issue`, `If no recent duplicate exists`; (ii) **presence** of the verbatim `create a new
      issue with:`.
- [ ] 2.3 Keep the four surviving verbatim-extraction anchors as **per-anchor** `it.each` presence
      assertions (NOT a summed `grep -c` — the header comment echoes three literals → count would
      be 6, not 4).
- [ ] 2.4 In `apps/web-platform/test/server/inngest/cron-shared.test.ts` (230–244), update the
      "credits a dedup-comment" test's rationale comment (231–234) and flip its fixture `label`
      from `scheduled-roadmap-review` to `scheduled-community-monitor`. Assertion outcome stays
      `true`.

## Phase 3 — Verify (ACs)

- [ ] 3.1 `grep -c -E 'DEDUP RULE|within the last 6 days|post your findings as a comment on the most recent existing issue|If no recent duplicate exists' apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` → `0` (AC1).
- [ ] 3.2 `git diff --name-only` does NOT list `cron-content-generator.ts` (AC10 scope guard).
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-roadmap-review.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-shared.test.ts` — all green (AC6/AC7/AC8).
- [ ] 3.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean (AC9).

## Phase 4 — Ship follow-ups

- [ ] 4.1 File a tracking issue for the identical `cron-community-monitor` DEDUP-RULE bug
      (deferral), noting the `updated_at`-filter + citation coupling (DHH F4). Milestone from
      `knowledge-base/product/roadmap.md`.
- [ ] 4.2 File a tracking issue for the **cohort-wide title-date pinning** deferral (DHH #2;
      deferred per deepen-plan Precedent-Diff — affects all 7 always-create cohort crons).
- [ ] 4.3 Ensure `/ship` renders `decision-challenges.md` into the PR body + an `action-required`
      issue.
