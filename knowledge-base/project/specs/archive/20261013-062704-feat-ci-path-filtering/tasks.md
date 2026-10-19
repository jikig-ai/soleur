# Tasks: ci: S4 PR affected-only gating, e2e fallback fix, shard-totality gate

Plan: `knowledge-base/project/plans/archive/20261013-062704-2026-10-12-feat-ci-pr-affected-only-gating-plan.md`. Issue #9729. Landing order: PR A, then PR B, then PR C. B and C stay dark; activation is locked until PR C removes the sentinel.

## PR A — e2e fallback fix and shard-totality gate (independent, not dark)

- 1.1 Capture `git diff`/`git show` stderr in the `Classify e2e applicability` step; print stderr, `git --version`, workspace owner vs `id -u`, base SHA and file count in the `::warning::`
- 1.2 Read PR A's own run annotation; fix per the measured cause (H1 safe.directory, H4 no git in the image); keep unresolved cases fail-closed to `applicable=true`; state the cause in the PR body
- 1.3 Extend `detect-changes` with `shard_totality` (true on the non-PR early exit; true when the diff touches a path derived from what the battery mutates); add `&& needs.detect-changes.outputs.shard_totality != 'false'` to `shard-totality-mutations` `if:`
- 1.4 Update exact-text pins: `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`; add the executed pin (failing `git diff` fixture prints stderr, emits `applicable=true`); add a test pinning the derived subject-path list

## PR B — selection job, group gating, aggregator tolerance, ADR amendment (dark, locked)

Authoritative text: the plan's "PR B contract after plan review (2026-10-14)". Rulings: `decision-challenges.md`.

- 2.1 Spike S-b: measure the selector pre-pass on a cold hosted runner (dependencies, wall time) from real doc-only PR runs via the dark `sel_s` field; record the number in the plan
- 2.2 `scripts/ci-pr-selection.sh` (+ `.test.sh`): defaults first; merge-ref assertions (`HEAD == GITHUB_SHA`, two parents, `HEAD^2 == PR head`); fork, `run_attempt > 1`, empty and over-500-file diffs mean full; `git diff -z --raw --no-renames --no-abbrev HEAD^1 HEAD` to a file; stage-1 positive allowlist plus widened trigger list (and a test that every file `test-all.sh` sources matches it); stage 2 selector under `the workflow passes timeout 90 (driver default 120)`; group rule; lock literal; one final output write
- 2.3 `pr-selection` job in `ci.yml` (PR-only, `continue-on-error`, `timeout-minutes: 3` alone on its line, no `needs:`, `contents: read`, `fetch-depth: 0`, no tooling setup); outputs `head_sha`, `base_sha`, `skip_legs`, `active` only; `SOLEUR_PR_SELECTION` notice and step summary
- 2.4 Group gating of `test-webplat`, `test-bun`, `test-scripts-heavy` (`needs: pr-selection`, delimited `contains(format(...))`, event, `active` and head-SHA terms; existing terms verbatim); `web-platform-build`, `e2e`, `test-scripts` unchanged
- 2.5 Aggregator: `pr-selection` in `needs` only, env `SKIP_LEGS`/`ACTIVE`/`HEAD_SHA_OK`/`ATTEMPT`, `PR-AFFECTED-SKIP` before `fail=1`, hard-coded allowlist, format validation; execute G1-1..G1-14 as synthetic triples in `ci-test-aggregator-diagnosis.test.sh` with mutants; update `ci-push-dedupe` (extend its evaluator for `contains`/`format`, re-measure `AGG_DIGEST`, classify `pr-selection`) and `ci-draft-light` pins
- 2.6 Guard 2 rows G2-1, G2-2, G2-5..G2-15 executed against the driver; executed pin running the release workflow's `run_declared_path` awk against `ci.yml` (73, and red on a 10-minute mutant)
- 2.7 ADR-276 `## Amendment` (S4, `CI_PR_AFFECTED`, 12% kill criterion and rollback, locked status, activation prerequisites, one baseline definition, dark cost, escape responder, supersessions, S2/S3 census waiver, stage-status line, `amends:`); ADR-262 and ADR-183 `amended_by:` plus matching `## Amendment` sections; `--admin` queue-skip sentence verified by API or omitted
- 2.8 Run the pin suites (every suite from `git grep -l 'ci\.yml' -- '*.test.sh'`), `plugins/soleur/test/c4-count-parity.test.sh`, the orphan lint; register new suites in the affected-paths index and the KB-consumer baseline; confirm `scripts/required-checks.txt` unchanged
- 2.9 Canary: draft PR based on the PR B branch with one `knowledge-base/**` markdown file; compare job conclusions with a plain run; record the verdict in the PR body

## PR C — per-suite selection, reduced-run read, probe (dark until activation)

- 3.0a Moved from PR B: `pr-affected-active` step, label/artifact Guard 2 rows (G2-3/G2-4), soak probe and `SOLEUR_FULL_BATTERY_ESCAPE`, PR C pre-merge assertion that `CI_PR_AFFECTED` is unset when the lock is removed
- 3.0 Go/no-go gate: spikes S-b/S-c measured and replay recorded; proceed only if replay escape is under 2% and the pre-pass does not erase the saving
- 3.1 Extend `scripts/ci-battery-gate-replay.sh` with the selector (300 first-parent commits vs suite failures)
- 3.2 Label-keyed `skip_labels` job output; runner consumer in `scripts/test-all.sh` (unknown label or PR-added suite runs; always-on ratchets never skipped); pass through `env:` to `test-scripts` and `test-scripts-heavy` legs
- 3.3 Shared full-verified read (jobs API: gated jobs not skipped, `pr-affected-active` not success, or a `merge_group` success); wire into `admin-merge-ready.sh` and `ci-head-verdict.sh`; audit `battery-owed.sh`, `monitor-pr-checks.sh`, ship Phase 7, `drain-prs`; Guard 3 rows G3-1..G3-6
- 3.4 `plugins/soleur/scripts/ci-full-battery-audit.sh` (+ test) as a step of `post-merge-monitor.yml`; `SOLEUR_FULL_BATTERY_ESCAPE` pages via Better Stack with a named responder; extend `scripts/ci-demand-census.sh` (PR job-min by mode, escapes, `--selftest`)
- 3.5 Verify with the API that `gh pr merge --admin` skips the merge queue before the ADR text asserts it; test that `web-platform-release.yml` keeps its `WR_EVENT == push` re-check
- 3.6 Record the pre-activation baseline census; remove the activation-lock sentinel in the last commit; run `soleur:engineering:review:user-impact-reviewer` at review

## Activation (separate authorized step, not part of any PR)

- 4.1 After PR C merges and AC6/Guard 3 hold, flip `CI_PR_AFFECTED` through the ADR-276 activation lane; measure AC12 over 6 hours
