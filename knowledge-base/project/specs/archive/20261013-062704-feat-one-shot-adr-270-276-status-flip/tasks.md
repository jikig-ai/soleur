# Tasks: docs(adr): accept ADR-270 and flip ADR-276 to adopting (S3 precondition)

Plan: knowledge-base/project/plans/2026-10-09-docs-adr-270-accept-adr-276-adopting-plan.md
Branch: feat-one-shot-adr-270-276-status-flip

## Phase 1: ADR-270

- [x] 1.1 Assert exactly one line-start `status: adopting` (line 3); replace with `status: accepted`.
- [x] 1.2 Extract canary items 1, 3, 4, 5, 7, 8, 9, 10 verbatim from "Canary measurements" by script; assert 8 items.
- [x] 1.3 Append `## Amendment 2026-10-09 (accepted by operator direction)` at end of file with the verbatim blockquote.
- [x] 1.4 `git diff` against the merge-base: exactly 1 deleted line (the status line).

## Phase 2: ADR-276

- [x] 2.1 Assert exactly one line-start `status: proposed` (line 3); replace with `status: adopting`.
- [x] 2.2 Assert exactly one `- 2026-10-09 S2 amended` line; insert one dated status-flip bullet after it (do not add a second `S2 amended`).
- [x] 2.3 Append `## Amendment 2026-10-09 (status flip to adopting)` at end of file.
- [x] 2.4 `git diff` against the merge-base: exactly 1 deleted line (the status line).

## Phase 3: pre-push checks (direct, output to files)

- [x] 3.1 scripts/check-adr-ordinals.sh
- [x] 3.2 scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh
- [x] 3.3 scripts/test-affected-kb-consumers.test.sh
- [x] 3.4 .claude/hooks/grep-q-pipe-guard.test.sh
- [x] 3.5 scripts/guard-vacuity-floor.test.sh
- [x] 3.6 Real-file status parse prints `adopting` (ADR-276) and `accepted` (ADR-270).
- [x] 3.7 Claim sweep for statements made false by the flip; code-review overlap check.

## Phase 4: ship

- 4.1 Commit `docs(adr): ...` with the Co-Authored-By trailer; PR body per plan Phase 4 (docs-only first line, request operator confirmation by approving or commenting, no Closes, attribution last line).
- 4.2 Resolve a possible end-of-file conflict with draft PR #9862 by keeping both appended blocks.
