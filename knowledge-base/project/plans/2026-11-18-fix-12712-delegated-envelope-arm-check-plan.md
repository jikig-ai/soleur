---
title: "Delegated-envelope gh pr merge --auto does not run the Review-Evidence arm check"
date: 2026-11-18
slug: fix-12712-delegated-envelope-arm-check
branch: feat-one-shot-12712
issue: 12712
---

## Overview

Issue #12712: the delegated-envelope grammar in `delegation-verify.sh` (`RE_MERGE`) accepts `gh pr merge <N> [--auto]`, and `standing-delegation.md` documents that grammar. Nothing in the delegation verifier enforces the Review-Evidence arm check from `review-evidence-comment.md` §"Arm check" before such a merge arms. As a result, a delegated production envelope can arm auto-merge on a PR whose head is not covered by a passing `Review-Evidence:` comment. The fix either requires the arm check's first statement to be present (and runnable) before an allowed `gh pr merge --auto` in a delegated envelope, or records an explicit exemption with rationale. This plan requires the arm check, and updates the test rows in `delegation-verify.test.sh`.

## Premise Validation

- Issue #12712 is OPEN (verified via gh issue view).
- `RE_MERGE='^gh pr merge ([0-9]+)( --squash| --merge| --rebase)?( --auto)?$'` confirmed in `delegation-verify.sh` line 273.
- `review-evidence-comment.md` §"Arm check" defines the first statement (EV/H/merge-base/rev-list) and the arm (`gh pr merge ... --match-head-commit`).
- Standing delegation format reference exists at `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`.

No stale premises found.

## Property List

1. A delegated `gh pr merge --auto` cannot arm auto-merge unless review evidence covers the PR head.
2. The verifier must not become the executor of the arm check (it has no PR state); instead the envelope must carry the arm check as a verifiable precondition.
3. The envelope format must make the arm check a required Verification entry for any merge-with-`--auto` command.

## Cut List

- Running the arm check inside `delegation-verify.sh`: the verifier is envelope-text-only and has no PR head; out of scope. Covered by requiring the statement in the envelope's Verification section.

## Research Insights

- `delegation-verify.sh` `ops_check` already parses Verification/Abort/Rollback/Stop conditions and runs denylist + readonly checks on each.
- The arm check's first statement is a multi-line shell expression; the envelope's Verification section is free text with backticked spans. The verifier can require that at least one backticked span in Verification equals (or contains) the arm check's first statement.
- `cmd_in_block` already does byte-identical full-line matching for commands; a similar exact-match helper can be added for the arm check statement.

## Files to Edit

- `plugins/soleur/scripts/delegation-verify.sh` — add an arm-check requirement for merge-with-`--auto` commands in `do_verify` (after `check_command` for each command, when `CMD_KIND=merge` and the command contains `--auto`, require the envelope's Verification section to contain the arm check's first statement as a backticked span).
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` — document that a delegated `gh pr merge --auto` requires the Review-Evidence arm check's first statement in the envelope's Verification section.
- `plugins/soleur/skills/review/references/review-evidence-comment.md` — add a one-line cross-reference that the arm check's first statement is the required precondition for delegated auto-merge.
- `plugins/soleur/scripts/delegation-verify.test.sh` — update test rows: add a valid envelope case containing the arm check, and an invalid case where a merge --auto envelope lacks it.

## Files to Create

(none)

## Acceptance Criteria

- [ ] A delegated envelope whose Command block contains `gh pr merge N --squash --auto` but whose Verification section does not contain the arm check's first statement is rejected by `delegation-verify.sh` with reason `scope-mismatch` or a new reason token `arm-check-missing`.
- [ ] A delegated envelope containing both the merge --auto command and the arm check's first statement in Verification verifies `valid`.
- [ ] `delegation-verify.test.sh` rows updated and passing.
- [ ] Standing delegation doc updated to state the requirement.

## Scope Check

Ask: require the Review-Evidence arm check before a delegated `gh pr merge --auto`, or record exemption.
Mapped items:
1. delegated merge --auto must not skip review evidence -> require arm check first statement in envelope Verification.
Provenance: issue. No inferred items.

## Domain Review

Engineering/CTO relevant (delegation governance). No UI impact (NONE). No other domains.

## Open Code-Review Overlap

None

## User-Brand Impact

- Threshold: none
- Scope-out: scripts and docs only (delegation-verify.sh, standing-delegation.md, review-evidence-comment.md, test file); no serving surface, no user-facing brand impact. Reason: governance fix to delegation verifier; no runtime change to user-facing product.

## Observability

- liveness_signal: none (CLI verifier, not a serving surface)
- error_reporting: none
- failure_modes: none
- logs: none
- discoverability_test:
  - command: "bash plugins/soleur/scripts/delegation-verify.sh verify --delegation https://github.com/x/y/issues/1#issuecomment-1"
  - expected_output: "delegation:"
  - credentials_required: none
