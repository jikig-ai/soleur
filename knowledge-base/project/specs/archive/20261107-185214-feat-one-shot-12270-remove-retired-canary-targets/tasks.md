# Tasks: remove the retired egress-gw canary -target lines and census entries (#12270)

Plan: `knowledge-base/project/plans/2026-11-07-chore-remove-retired-egress-gw-canary-targets-plan.md`
Branch: `feat-one-shot-12270-remove-retired-canary-targets`. Authorization: prepare the PR only; stop before merge and ask for the per-command go-ahead. No `[ack-destroy]`, no apply, no dispatch, no Better Stack write, `Ref #12189` only.

## Phase 0 - Baseline and state re-read (read-only)

- 0.1 Re-read #12270, #12189, #12242 and apply run 42369320061 (`2 destroyed`); `git fetch origin main` and list `HEAD..origin/main` changes to the files below.
- 0.2 Re-run the read-only soak probe once (the runbook's `doppler run ... BETTERSTACK_API_TOKEN_READONLY` form); record the printed line; re-read the latest #12242 comment.
- 0.3 Freeze the census: `git grep -nE 'silent_canary|probe-silent-canary|egress-gw-probe-canary-absent' -- ':(top)' ':(top,exclude)knowledge-base/project'`.
- 0.4 Run the baseline suites in the worktree and record the printed counts (structure 110, ceiling 116, egress 128, send-failed 39, probe 429, census 422, luks 187, F7 pass).

## Phase 1 - Code and guards (one atomic commit, no `[ack-destroy]`)

- 1.1 `.github/workflows/apply-web-platform-infra.yml`: delete the two canary `-target` lines (659-660); nothing else.
- 1.2 `tests/scripts/test-infra-privileged-tier-census.sh`: delete the two `INTENDED_DESTROYS` entries and their 2-line comment; keep the four ghcr entries.
- 1.3 `apps/web-platform/infra/betterstack-alert-structure.test.sh`: rewrite the false comment block above `CENSUS_SH` to the end state; no code change; keep lines 14 and 98-99.
- 1.4 `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh`: shrink `EXPECTED_REFERRERS` to the re-derived set, update the two "#12270 shrinks it again" comments to past tense, set `MIN_ASSERTIONS` to the printed total (rehearsal: 427).
- 1.5 `scripts/followthroughs/egress-gw-probe-silent-12180.sh`: replace only the `#   STATUS after #12189:` comment line; keep header tokens; `APPLY_FLOOR_EPOCH` byte-identical.
- 1.6 Confirm unchanged-by-design files by run: egress suite, ceiling suite, send-failed suite, `betterstack-logs-alerts.tf`, `infra-validation.yml`, `betterstack-log-query.md`.

## Phase 2 - Documents (second commit, append-only)

- 2.1 Runbook `cron-egress-blocked.md`: append the dated `Update 2026-11-07 (#12270)` paragraph after the retirement record (observed facts only) and insert ONE standalone bracketed pointer line after the record paragraph; no existing word removed and no `-` line in the diff.
- 2.2 ADR-218: append `## Amendment 2026-11-07 (#12270, Ref #12189)` at the end of the file and ONE standalone bracketed pointer line after the 2026-11-06 amendment; no ordinal claimed.

## Phase 3 - Verification (local)

- 3.1 Run every suite by name: structure, ceiling, egress (full), send-failed, probe test, census, luks-monitor-install, `plugins/soleur/test/worktree-manager-bare-sync.test.sh`, terraform-target-parity, destroy-guard suites, `c4-count-parity`, `test-affected-kb-consumers`, every `*alert*.test.sh` under `apps/web-platform/test/infra`; compare each to its expectation; never edit a pin to fit.
- 3.2 `plugins/soleur/scripts/affected-tests.sh`, `scripts/pre-push-ratchet-lane.sh`; name anything left to CI.
- 3.3 Guard Contract scratch mutants (Guard 1 rows 1, 3, 4, 5 and Guard 2 rows 1, 3, 5; the rest are covered by committed batteries) on a scratch copy; record RED/GREEN in the PR body.
- 3.4 Lints: `lint-guard-contract.py` on the plan, `lint-infra-no-human-steps.py` on changed `.md`; if any `comm`/`join` was written, `LC_ALL=C` directly in front of it.
- 3.5 Sweep AC: only the expected survivors name the canary (neither the workflow nor the census).

## Phase 4 - Ship preparation (stop before merge)

- 4.1 Re-sync with `origin/main` before the first/final push; re-run 3.1 and re-derive the probe set and total on the merged tree (watch PR #12292).
- 4.2 Assert zero `[ack-destroy]` in the branch's commit messages.
- 4.3 Review, compound, ship up to CI green.
- 4.4 PR body: first line answers whether merging alone mutates production; `Ref #12189`, optional `Closes #12270`; closingIssuesReferences only #12270; record numbers, mutant results, the T6 post-merge condition.
- 4.5 Do not push during a merge-queue wait.
- 4.6 STOP and ask for the per-command merge go-ahead.
- 4.7 Report what is left for the owner and print the resume prompt.
