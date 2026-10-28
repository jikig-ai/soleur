# Tasks: fix the S4 observation-window probe (merged-PR resolution)

Plan: `knowledge-base/project/plans/2026-10-28-fix-observation-window-probe-merged-pr-resolution-plan.md`. Rulings: `decision-challenges.md` in this directory. PR text uses `Ref #10865` only (never a closing keyword). Post nothing to #10865.

## 1. Setup and failing tests first

- 1.1 Stub `gh` heredoc in `plugins/soleur/test/ci-pr-affected-replay.test.sh`: add `ERR422_<key>` and `ERR_ONCE_<key>` handlers; change the stub's own `sleep` calls to `command -p sleep`.
- 1.2 Add the no-op logging `sleep` stub directory and prepend it to PATH inside `ow_probe` and `ow_probe_split` only.
- 1.3 Extend `ow_write` cleanup globs (`*_commits_*_pulls_*`, `ERR422_*`, `ERR_ONCE_*`); add helpers `ow_commit_pulls`, `ow_pr_obj`, `ow_u_resolved`.
- 1.4 Add rows: `row_ow_resolve_merged`, `row_ow_resolve_unresolvable` (table loop incl. 404/422), `row_ow_resolve_errors` (incl. gh exit 4), `row_ow_resolve_scope`, `row_ow_zero_pr_units` (incl. `prs=5` on the base fixture), `row_ow_retry` (incl. flagged-run and 502-then-403 cases); update `row_ow_quota` (127/126, `planned=`), `row_ow_static`, `row_ow_argv`.
- 1.5 Add the mutants listed in the plan's Test Scenarios; run the suite and record the new rows RED on the unmodified probe.

## 2. Probe (`scripts/followthroughs/ratchet-observation-window-10865.sh`)

- 2.1 `gh_get`: return 44 (HTTP 404) / 45 (HTTP 422) from `$errf` before removal; `transient_err` helper; one retry after fixed `sleep 2`, skipped under `$RL_FLAG`; add `sleep` to the tools loop.
- 2.2 `raw_baseline` through `gh_get -H 'Accept: application/vnd.github.raw'` (path last): 0 read, 4 absent only on rc 44, else `fail_api`.
- 2.3 Resolver in `read_unit` (scope test, `commits/$sha/pulls?per_page=2`, identity jq on stdin with `.head.repo.full_name == $repo and .base.repo.full_name == $repo`, 44/45 unresolved, other failure `fail_api`, non-array `fail_api (parse)`).
- 2.4 `pr_unattributed_runs` appended at the END of the status line; zero-distinct NOT YET suffix; stderr `phase=facts-done prs=$facts_prs green_pr_rows=$G`; `facts_prs=0` before the loop; remove `${#PR_EXCLUDED[@]}`.
- 2.5 Quota formula `(3*to_read+1)/2 + (res_cands+1)/2 + 3*pr_est + 100` with `planned=` on the `quota:` line; `FACTS_BUDGET` default 180.
- 2.6 Header and comment wording (criterion (a), WHAT A PASS CERTIFIES, PASS echo, old `prn != 0` comment, quota-guard comment); keep the xtrace refusal directly below `set -uo pipefail`.

## 3. Runbook

- 3.1 Rewrite the "Reads are bounded and oldest-first" and "Forgery bound" bullets in `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`; state the time arithmetic once; add the dated 2026-10-28 observation-log entry.

## 4. Local gates and live verification

- 4.1 Replay suite; `fixture-relative-assert.test.sh`; `lint-shell-trace-credential-refusal.py` (positional path) and its test; `lint-guard-contract.py` on the plan; `python3 -I scripts/ci-pr-affected-replay.py ratchet`; `bash -n` / `shellcheck`.
- 4.2 ONE live read-only run (token via `read -r`, no command substitution); gate: exit 0 or 2, `green_pr_units_distinct_prs > 0`, `green_pr_rows > 0`, `pr_unattributed_runs * 4 < green_pr_rows`; record `quota: used_delta` vs `planned`.
- 4.3 Confirm no ORACLE input, baseline or accept file changed (`git diff origin/main...HEAD --name-only`).

## 5. Ship

- 5.1 Run `prepush-secret-scan.sh` before every push; PR uses `Ref #10865` only; comment the F4 deferral on #11306 (not #10865); merge-queue mode, never hand-sync.
