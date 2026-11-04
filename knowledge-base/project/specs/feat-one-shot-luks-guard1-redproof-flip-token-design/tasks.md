# Tasks: LUKS epic #9927 - Guard 1 red-proof, flip-token record reconciliation, Guard 1 CI wall time

Plan: `knowledge-base/project/plans/2026-11-04-docs-luks-guard1-redproof-and-flip-token-record-plan.md`
Branch: `feat-one-shot-luks-guard1-redproof-flip-token-design`. PR body: `Ref #9927` (never `Closes`).

## Phase 0 - Preflight (re-derive, never copy)

- [x] 0.1 `git fetch origin main`; record the base SHA; `gh issue view 9927 --json state` is OPEN
- [x] 0.2 Count recent `ci.yml` runs on main (`gh run list --workflow ci.yml --branch main -L 30`); record the real count
- [x] 0.3 `grep -n 'inngest-luks-sole-copy' scripts/test-all.sh scripts/suite-shard-legs.tsv`
- [x] 0.4 `gh variable list`: record `CI_DRAFT_LIGHT`
- [x] 0.5 Read every workflow `on:` block (push triggers, pull_request path filters); keep the output

## Phase 1 - AC1 red-proof (separate worktree and branches; nothing committed on this branch)

- [x] 1.1 Push disposable base `redproof-luks-guard1-base-20261104` from the recorded `origin/main` SHA
- [x] 1.2 `git worktree add -b redproof-luks-guard1-head-20261104 .worktrees/redproof-luks-guard1-head-20261104 <SHA>`
- [x] 1.3 In it, delete the single `delete_protection = true` line in `apps/web-platform/infra/inngest-redis-luks.tf`; diff is 1 file, 1 deletion, no `.github/` or `scripts/` path
- [x] 1.4 Commit with plain `git commit`; if the pre-commit gate refuses, record that as the local leg and spawn the CTO for the bypass fork, record its ruling in decision-challenges.md before committing
- [x] 1.5 Push head; `gh pr create --draft --base redproof-luks-guard1-base-20261104`, title "DO NOT MERGE: ...", body `Ref #9927`, no `Closes`
- [x] 1.6 `gh workflow run ci.yml --ref redproof-luks-guard1-head-20261104`; pin the run id via `gh run list --workflow ci.yml --event workflow_dispatch --branch <head> -L 1`; arm a Monitor watch on it
- [x] 1.7 Read evidence (baseline pending, see 1.10): `test-scripts (3/8)` job URL and conclusion, failing Guard 1 case text, `test` conclusion, other shards, green 3/8 baseline on the base SHA, Guard 1 per-suite elapsed if printed
- [x] 1.8 (not needed: dispatch path worked) If dispatch is blocked or unattributable: fallback A (ready path, then `gh pr ready --undo`); if both fail: fallback D (local mutation run, labelled "not the CI leg"; AC1 undischarged)
- [ ] 1.10 Record the baseline `test-scripts (3/8)` result of run 41915494979 (unmutated base) on #9927, then close the throwaway PR (see 5.2)
- [x] 1.9 Check `gh pr view <n> --json isDraft,baseRefName,autoMergeRequest` shows `true`, the base name, `null`

## Phase 2 - INNGEST_CUTOVER_FLIP ledger (grep-derived)

- [x] 2.1 Run the four `git grep` commands from the plan; keep raw output
- [x] 2.2 Classify each hit: reader or writer, host or CI, token; flag arm-write consumers as "move first at item 8"
- [x] 2.3 Add any consumer the greps find that the brief omitted

## Phase 3 - ADR-282 addendum (committed)

- [x] 3.1 Time the local Guard 1 run (`bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh`); quote command and printed summary (89 of 89 expected); note contention from sibling `test-all.sh` processes if present
- [x] 3.2 Append `## Addendum - 2026-11-04 (#9927 item 4 reconciliation, Guard 1 CI wall time)`: pointer to 2026-10-30/11-01/11-02 (no design copy), design recorded in 2026-10-30 (hold closing is the owner's call), CTO ruling F2 cited, ledger table, ordering constraint, wall-time paragraph with both sources and scopes, red-proof result paragraph
- [x] 3.3 Add the dated `Superseded` marker under the 2026-11-03 "recorded in a follow-up append" sentence
- [x] 3.4 Do not cite the 1,251 ms `floor` weight in `scripts/suite-durations.tsv` as a wall time
- [x] 3.5 Run `python3 scripts/lint-infra-no-human-steps.py`, `bash plugins/soleur/test/c4-count-parity.test.sh`; confirm the diff is additions only plus the one marker

## Phase 4 - Comments on #9927

- [x] 4.1 Comment A: red-proof record (PR number, base branch and SHA, head SHA, run URL, job URL, failing case, `test` conclusion, other shards, baseline, close-by statement)
- [x] 4.2 Comment B: the three "I checked" lines, each with its command or run id (ci.yml on main N of N, test-all.sh registration, item 8 finding)

## Phase 5 - Close handoff

- [ ] 5.1 Put `Throwaway red-proof PR #N (base <name>, head <name>): close it and delete both branches` in this branch's PR body as plain text
- [ ] 5.2 Final task (run once BOTH 1.10 is recorded AND this branch's PR exists; also `git worktree remove .worktrees/redproof-luks-guard1-head-20261104`; verify `gh pr view 12109 --json state` is CLOSED before this branch's PR merges) after this branch's PR exists: re-check `isDraft` true and `autoMergeRequest` null, `gh pr close <n>`, delete base and head branches and the head worktree, remove the board item if it persists (the owner may do it earlier)

## Not in this run

Revoking or scoping `doppler_service_token.inngest_arm_write`; removing the G2e pin; `apply_target=inngest-host-replace`; closing #9927; the A6 owner sentence; the off-project ciphertext copy; any `.github/**` or `scripts/**` edit.
