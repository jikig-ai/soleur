# Tasks — feat-one-shot-10902-agentic-verification-epilogue

Plan: `knowledge-base/project/plans/2026-10-26-feat-agentic-verification-epilogue-plan.md`

## Phase 1 — Re-verify shipped state (read-only)

- [x] 1.1 `for i in 10397 10636 10694 10730 10737 10739 10902 11078 11003 10736; do gh issue view $i --json state --jq "#$i \(.state)"; done` — expect all CLOSED except #10902, #11078, #11003, #10736 (OPEN). Abort #10902 close-out if any child reopened.
- [x] 1.2 `grep -o 'blog/[a-z0-9-]*/' plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md | sort -u` — all seven spoke slugs present.
- [x] 1.3 Occupied-set re-check: `grep -H "^publish_date:" knowledge-base/marketing/distribution-content/*.md` — confirm 2026-10-28, 2026-11-03, 2026-11-05, 2026-11-10, 2026-11-12, 2026-11-17 are absent from other files. If any is taken, pick the next free day and update `decision-challenges.md` in the same commit.

## Phase 2 — Pin the six distribution drafts

- [x] 2.1 `knowledge-base/marketing/distribution-content/2026-10-29-property-test-cannot-fail-teaches-nothing.md`: `publish_date: 2026-10-28`, `status: scheduled` (unquoted date, corpus convention).
- [x] 2.2 `…/2026-11-03-first-property-test-found-real-bug.md`: `publish_date: 2026-11-03`, `status: scheduled`.
- [x] 2.3 `…/2026-11-05-map-that-cant-drift.md`: `publish_date: 2026-11-05`, `status: scheduled`.
- [x] 2.4 `…/2026-11-10-test-the-migration-not-just-the-schema.md`: `publish_date: 2026-11-10`, `status: scheduled`.
- [x] 2.5 `…/2026-11-12-map-that-only-records-what-the-agent-saw.md`: `publish_date: 2026-11-12`, `status: scheduled`.
- [x] 2.6 `…/2026-11-17-flaky-test-passed-on-retry-quarantine.md`: `publish_date: 2026-11-17`, `status: scheduled`.
- [x] 2.7 Do NOT touch `2026-11-04-six-questions-before-recurring-job.md`, `plugins/soleur/docs/blog/2026-11-04-before-your-ai-team-takes-a-recurring-job.md`, or `campaign-calendar.md`.
- [x] 2.8 Validate: `bash scripts/lint-distribution-content.sh <each edited file>` exit 0; `bun test plugins/soleur/test/distribution-content-format.test.ts` green.
- [x] 2.9 Double-book check: `grep -h "^publish_date:" knowledge-base/marketing/distribution-content/*.md | sort | uniq -d` → empty.

## Phase 3 — Issue operations

- [x] 3.1 `gh issue comment 10902` + `gh issue close 10902` — completion comment: children #10636 #10694 #10730 #10737 #10739 + epic #10397 CLOSED; hub published 2026-10-24 (`status: published`); seven spoke links verified; squash `5a284d137b`.
- [x] 3.2 `gh issue comment 11078` + `gh issue close 11078` — resolution comment: post shipped `date: 2026-10-29` (default held for the post); the 10-29 distribution slot was occupied by the guardrails spoke's scheduled slot; draft resolved via explicit pin `publish_date: 2026-10-28`; reversal = reopen + edit the date before the next publisher run.
- [x] 3.3 `gh issue comment 11003` + `gh issue close 11003` — shipped slot (scheduled 2026-10-29) supersedes the recorded 2026-10-27 default; no action needed.
- [x] 3.4 `gh issue comment 10736` (leave OPEN) — roster-free verification: zero `ux-audit`/`reproduce-bug`/`consumer` matches in `2026-11-12-map-that-only-records-what-the-agent-saw.md` post + draft; cites the 2026-10-25 CTO ruling (`specs/archive/20261025-214638-feat-one-shot-10902-arc-spokes/decision-challenges.md`); no post or doc change required by either resolution.

## Phase 4 — Artifacts & close-out

- [x] 4.1 Confirm `decision-challenges.md` property-test row names the shipped pin date (update if AC9 moved it).
- [x] 4.2 Commit plan + tasks + decision-challenges + the six frontmatter edits; push.
- [x] 4.3 If a rebase was needed: `GIT_EDITOR=true git rebase --continue`; `LEFTHOOK=0` for replay; `pgrep -a git` for orphan children before retrying (learning 2026-10-25).
