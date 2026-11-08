# Tasks — feat-one-shot-12428-12444-ejections-corrob-classifier

Plan: `knowledge-base/project/plans/2026-11-08-ci-ejections-corrob-classifier-coverage-plan.md`
Issues: #12428 (ejections merge_group corroboration), #12444 (classifier not-evaluable coverage)

## 1. Setup

- [ ] 1.1 Re-read `scripts/ci-pr-affected-replay.py` regions before editing: `FAIL_LINE` (:224), `failing_jobs` (:503-518), `fail_suites` (:519-535), `suites_failed_in` (:538-565), `classify` (:579-621), `cmd_collect` pick/`cleared` seam (:691-708), `cmd_ejections` (:724-819), `check_complete` (:860-881), `gh_pages`/`gh_text` (:287-326), `corroborating_runs` (:449-475).
- [ ] 1.2 Re-verify the three `failed-job-without-fail-line` signatures against fresh reads (Sharp Edges: never trust this plan's enumeration) — jobs 124613574229, 126016312817, 125980654539, 127743275859, 128273594206.

## 2. Core Implementation — `scripts/ci-pr-affected-replay.py`

- [ ] 2.1 (#12428) `merge_group_runs_on(repo, sha)`: `commits/{sha}/check-suites?per_page=100` (paginated, `total_count` guard) → queue suite ids (`app.slug=="github-actions"` + `head_branch` startswith `gh-readonly-queue/`); `commits/{sha}/check-runs?per_page=100` → `details_url` run ids joined on `check_suite.id`; `actions/runs/{id}` filtered `event=="merge_group"`, `path==CI_WORKFLOW_PATH`, `head_sha==sha`. Fan-out cap + ReadError per the `corroborating_runs` contract.
- [ ] 2.2 `cmd_ejections`: compute window commits unconditionally; iterate `merge_group_runs_on` over them; union `listed + missing` (in-window `created_at` only); corroborated SUCCESS runs are `by_pr`/histogram/`cleared()` witnesses only — never units (CTO pin: a clean unit inflates n and dilutes cp95); corroborated non-success runs are units inside `refused`, tagged `runs_via="check-runs-window"`.
- [ ] 2.3 Queue oracle: per distinct `pr_of(head_branch)`, `issues/{N}/timeline?per_page=100` → `added`/`removed` counts in-window vs distinct branch names; `shortfall=max(0, added−observed)` → one synthetic unit per shortfall (`queue-oracle:pr-<N>-<i>` sha-field, `reason="queue-oracle-shortfall: …"`); failed reads → `corroboration-read:`/`queue-oracle-read:` units.
- [ ] 2.4 `ejections-window.json`: add `corroborated`, `queue_oracle`, `expected_units`; `check_complete` compares to `meta.get("expected_units", meta["refused"])`. Docstring updates (`ejections`, `not-evaluable`, declared residuals).
- [ ] 2.5 (#12444) `FAIL_LINE`: `([A-Za-z0-9._/+-]+)` → `([ -~]+?)`.
- [ ] 2.6 `fail_suites`/`suites_failed_in`: mid-termination signature (`The runner has received a shutdown signal` / `The operation was canceled`, + `Last suite started:` extraction) → job to unsettled, `unsettled_detail` recorded; log-read failure → `check-runs/{id}/annotations?per_page=100` probe for `hosted runner lost communication` → unsettled (`runner-comms-loss`).
- [ ] 2.7 `failing_jobs` (or sibling helper `run_leg_green`): per-attempt success-name read for witness checks.
- [ ] 2.8 `classify` unsettled arm: per-leg identical-tree witness → `flake-cleared`/`identical-tree-green`; `unit["unsettled_legs"]` recorded. `cmd_collect` same_tree closure = earlier-attempt + same-sha sibling witnesses (over `runs`); `cmd_ejections` `cleared` += attempt arm. Order unchanged: would_skip_hit → ne → unsettled-consult → unsettled-jobs.

## 3. Testing

- [ ] 3.1 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: fixture helpers for `check-suites`, `timeline`, `annotations` paths; all Phase-3 rows in the plan; `mutate` rows per Guard Contract matrices; `DECLARED_TOTAL` bump + `scripts/test-all.sh` registered `--rows` range re-split in the SAME commit.
- [ ] 3.2 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` → exit 0, all three `-a`/`-b`/`-c` arms.
- [ ] 3.3 `python3 -I scripts/ci-pr-affected-replay.py ratchet` → exit 0 (no new gap pairs from new literals).
- [ ] 3.4 Runbook §4 bullet rewrite (built semantics + THREE documented residuals — incl. the CTO AMEND: observed > in-window added at window edges masks a partial drop).
- [ ] 3.5 Live smoke: `ejections --out /var/tmp/s4-corrob-smoke --commits 20 --base origin/main` + `aggregate` → receipts under `receipts/` in the spec dir.

## 4. Out of scope (named)

The full §4 evidence re-run on a fresh 300-commit window, the go/no-go re-ruling,
`CI_PR_AFFECTED`, the activation lock, PR D (#10414) — budget-owner reservation.
