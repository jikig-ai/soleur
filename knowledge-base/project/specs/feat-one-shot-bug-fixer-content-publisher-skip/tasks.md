---
plan: knowledge-base/project/plans/2026-05-15-fix-bug-fixer-content-publisher-skip-plan.md
branch: feat-one-shot-bug-fixer-content-publisher-skip
lane: single-domain
created: 2026-05-15
---

# Tasks — fix(bug-fixer): skip [Content Publisher] operational notifications

## Phase 1 — Setup

- [ ] 1.1 Capture pre-edit `actionlint .github/workflows/scheduled-bug-fixer.yml` output as baseline (for AC6 delta comparison).
- [ ] 1.2 Re-run the Phase 4 regex test in the plan against the current (un-edited) regex — confirm baseline misses are exactly the 6 `[Content Publisher]` rows.

## Phase 2 — Core Implementation

- [ ] 2.1 Edit `.github/workflows/scheduled-bug-fixer.yml:142` — replace the jq `test(...)` regex with the new `^(\\[Content Publisher\\]|flaky|flake|test-flake|test)[: \\[(]` form.
- [ ] 2.2 Edit `.github/workflows/scheduled-bug-fixer.yml:122-128` — replace the rationale comment block with the expanded form covering BOTH the `[Content Publisher]` branch and the existing flaky/test branch (preserve the original flaky/test rationale verbatim; reference `scripts/content-publisher.sh` and run `25908353568`).
- [ ] 2.3 Edit `.github/workflows/scheduled-bug-fixer.yml:171` — append `--exclude-label content-publisher` to the `Run /soleur:fix-issue ...` prompt line.

## Phase 3 — Verification

- [ ] 3.1 Run the Phase 4 regex test (in plan) against the edited file's actual regex string — confirm all 6 `[Content Publisher]` rows AND all 5 flaky/test rows return `true`; confirm `fix(api):`, `feat:`, `bug(content-publisher):`, `review: content-publisher` return `false` (AC4 + AC5).
- [ ] 3.2 Run `actionlint .github/workflows/scheduled-bug-fixer.yml`; compare to Task 1.1 baseline; confirm zero new errors (AC6).
- [ ] 3.3 Run `grep -nE '\\\[Content Publisher\\\]' .github/workflows/scheduled-bug-fixer.yml` → returns ≥1 match in the jq line and ≥1 match in the comment block (AC1, AC3).
- [ ] 3.4 Run `grep -nE -- '--exclude-label content-publisher' .github/workflows/scheduled-bug-fixer.yml` → returns exactly 1 match on the prompt line (AC2).
- [ ] 3.5 Run `git diff main -- .github/workflows/scheduled-bug-fixer.yml` → diff is bounded to the three regions in plan Phases 1-3 (AC7).

## Phase 4 — Commit & PR

- [ ] 4.1 `git add .github/workflows/scheduled-bug-fixer.yml` (stage only the workflow file).
- [ ] 4.2 Commit with message body referencing run `25908353568` and issue #2738.
- [ ] 4.3 Open PR with `## Changelog` section per plan; labels: `semver:patch`, `domain/engineering`, `chore`, `priority/p2-medium`. Use `Ref:` not `Closes:` for the related Content Publisher issue list (AC8).
- [ ] 4.4 Mark PR as ready for human review (do NOT enable auto-merge — `.github/` workflow files require human review per task framing).

## Phase 5 — Post-Merge Verification

- [ ] 5.1 After merge, trigger `gh workflow run scheduled-bug-fixer.yml` (or wait for next 06:00 UTC schedule).
- [ ] 5.2 Verify the `Select issue` step's chosen issue is NOT a `[Content Publisher]` title via `gh run view <run-id> --log | grep "Selected issue"` (AC9).
- [ ] 5.3 If the run picks zero issues (because the entire bug-bus is currently exclusion-class), confirm the `No qualifying issues found at any priority level` log line is reached and the workflow exits cleanly.
