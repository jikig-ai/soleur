# Tasks: git-data go-live Phase A (flip pause precondition, overlay classification and ancestry guard, replication-success signal)

Plan: `knowledge-base/project/plans/2026-10-31-feat-git-data-flip-preconditions-overlay-classification-success-signal-plan.md`
Refs: #11704, #8211 (never closed by this PR). Draft PR: #11713. Deferrals: #11716, #11717.
Every task: failing test first, then the change. Scoped suites only.

## Phase 0: Base and bound-set guard

- 0.1 Rebase on current `origin/main`; re-check Files to Edit paths exist
- 0.2 Derive the rung-2 bound set via `git_data_rung2_bound_files` and keep the intersection command for Phase 5

## Phase 1: A, flip pause precondition

- 1.0 Run the exact SQL once read-only against Better Stack (live dry run); record shape only (row counts per leg, integer columns, newest age)
- 1.1 RED: PS1..PS13 executed-step rows in `git-data-cutover-access.test.sh` (PS1..PS9 at plan time), six `M-ps-*` mutants at plan time and 8 more from the review round, `wf.py` row (count pin 60 to 61), restate `FLOOR` and `MUTANT_FLOOR`
- 1.2 Implement the block last in `flip_preconditions` (`BS_DOPPLER_TOKEN`, SQL-side integers, 75 s newest bound, three reads, `|| rc=$?`, `pause_not_on` / `pause_unread` + `remedy:`), update the final echo and the header credential ledger comment

## Phase 2: B, overlay

- 2.1 RED: mocked rows in `ensure-workspace-repo.test.ts` (first-session info, descend, not-descendant with rescue branch first, branch-failure falls into level 50, merge-base 128)
- 2.2 RED: `ensure-workspace-repo-ancestry-real-git.test.ts` S1..S4 (real shallow clones and store, push after skip keeps old tip reachable)
- 2.3 RED: real thrown-shape classifier rows with a fake `ssh` on `PATH`, plus the wrapper-phrase grep
- 2.4 Implement `isFirstSessionStoreMiss`, the ancestry gate, the rescue branch in `ensure-workspace-repo.ts`
- 2.5 `git-data-stale-clone-push.test.sh` CH1..CH3 against the real bound hook (read-only); stop and report on any cross-namespace write

## Phase 3: C, success marker and read

- 3.1 RED: marker rows in `git-data-replication.test.ts` (exact message and fields, no identifiers, retry variant, no marker on failure/shed/pin fault, single occurrence in the server tree)
- 3.2 Implement the warn marker and the `retried` flag in `git-data-replication.ts`
- 3.3 Live dry run of the signal SQL, RED then implement `scripts/followthroughs/git-data-replication-signal.sh` and its test (per-host verdicts, worst-of, `NO_SESSIONS` exit 4)

## Phase 4: Docs and records

- 4.1 Runbook edits (refusals, Verdict map rows, R0/R1/R3 rows, "R3 first-session reading", Known latent behaviours, soak step, accepted gap)
- 4.2 ADR-068 addendum (2026-10-31)
- 4.3 C4 edge prose (`github -> betterstack`, `hetzner -> betterstack`), regenerate `model.likec4.json`
- 4.4 Confirm #11716 and #11717 are referenced from the runbook

## Phase 5: Ratchets and scoped runs

- 5.1 Run the scoped suites listed in the plan (access, flag-precheck, stale-clone, pre-receive, fanout parity, token drift, bearer sweep, signal test, terraform-target-parity, c4 tests, vitest files)
- 5.2 `python3 scripts/regenerate-shard-manifest.py --incremental --write`; `lint-orphan-test-suites`; `lint-guard-contract`; `lint-infra-no-human-steps`
- 5.3 `git grep -l 'git-data-cutover' -- '*.test.sh' '*.test.ts'` and run every hit
- 5.4 Bound-set intersection empty; wrapper untouched; secret-scan before every push

## Phase 6: Ship (no merge)

- 6.1 PR #11713 body: `Ref #11704`, `Ref #8211`, Generated-with line; mark ready, checks green, no auto-merge
- 6.2 Tick the matching Phase A items in the #8211 plan comment (via the API, body otherwise unchanged) and add the PR number

## Phase 7: Fix round (2026-10-31, CTO F20-F23)

- 7.1 Replication push: drop `--atomic` from the step-2 main push, keep it on step 1 (F20); delete the pushed local `soleur-store-tip-*` branches best-effort after step 1 with `update-ref -d <ref> <sha>` and a `timeout: 5000` listing (F21); real-git rows for both
- 7.2 Docs: ADR-068 addendum amendments (F20-F23, reserved prefix, retention, "Not measured" git >= 2.29, slot hold ~240 s vs 120 s, `--only-secrets` is hygiene); runbook Known latent behaviours, `pause_unread` `truncated` cause, R3 `git-data-overlay-not-descendant` read-and-record sentence (F23)
- 7.3 C4: restore the "exists only on images from the release carrying that change" caveat on the `hetzner -> betterstack` edge; regenerate `model.likec4.json`
- 7.4 Plan: dated Superseded note (heads not bounded by gc, PS1..PS13, current FLOOR/MUTANT_FLOOR, `git branch soleur-store-tip-<12 hex> <full sha>`, two-step push)
