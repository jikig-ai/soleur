# Tasks: ci: S4 PR affected-only gating, e2e fallback fix, shard-totality gate

Plan: `knowledge-base/project/plans/2026-10-12-feat-ci-pr-affected-only-gating-plan.md`. Issue #9729. Landing order: PR A, then PR B, then PR C. B and C stay dark; activation is locked until PR C removes the sentinel.

## PR A — e2e fallback fix and shard-totality gate (independent, not dark)

- 1.1 Capture `git diff`/`git show` stderr in the `Classify e2e applicability` step; print stderr, `git --version`, workspace owner vs `id -u`, base SHA and file count in the `::warning::`
- 1.2 Read PR A's own run annotation; fix per the measured cause (H1 safe.directory, H4 no git in the image); keep unresolved cases fail-closed to `applicable=true`; state the cause in the PR body
- 1.3 Extend `detect-changes` with `shard_totality` (true on the non-PR early exit; true when the diff touches a path derived from what the battery mutates); add `&& needs.detect-changes.outputs.shard_totality != 'false'` to `shard-totality-mutations` `if:`
- 1.4 Update exact-text pins: `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`; add the executed pin (failing `git diff` fixture prints stderr, emits `applicable=true`); add a test pinning the derived subject-path list

## PR B — selection job, group gating, aggregator tolerance, ADR amendment (dark, locked)

- 2.1 Spike S-b: measure pre-pass dependencies and wall time; decide `pr-selection` job shape
- 2.2 Add `pr-selection` (PR-only, `continue-on-error`, `timeout-minutes: 10`, `fetch-depth: 0`); outputs `mode`, `skip_legs`, `active`, `head_sha`, `base_sha`; `active` computed once in bash (exactly `on`); literal activation-lock sentinel; `pr-affected-active` step
- 2.3 `scripts/ci-pr-selection.sh` driver (+ test): `git diff --name-status --no-renames` against the pinned base; widened full-battery trigger list derived from what `scripts/test-all.sh` sources plus `ci.yml`, the driver, `scripts/lib/**`, the baseline, `scripts/suite-shard-legs.tsv`, the heavy manifest, `scripts/ci-e2e-classify.sh`; any A/D/R outside doc paths is non-skippable
- 2.4 Group gating of `test-webplat`, `test-bun`, `test-scripts-heavy` (delimited `contains(format(',{0},', ...))`, event and head-SHA terms); `web-platform-build` and `e2e` unchanged
- 2.5 Aggregator: add `pr-selection` to `needs`, pass `SKIP_LEGS`/`ACTIVE`/`HEAD_SHA_OK` via `env:`, add the named `PR-AFFECTED-SKIP` tolerance; execute Guard 1 rows G1-1..G1-7 in `ci-test-aggregator-diagnosis.test.sh`; update the `ci-push-dedupe` and `ci-draft-light` pins
- 2.6 Guard 2 rows G2-1..G2-8 executed against the driver
- 2.7 ADR-276 `## Amendment 2026-10-12 (S4, #9729)`: `CI_PR_AFFECTED`, exit criterion, census link, S2/S3 census waiver, one baseline definition, kill criterion (replay escape over 12%), recorded reversals (no `[full]` marker, no base copy), stage-status line; pointer amendments and `amends:` on ADR-262 and ADR-183
- 2.8 Run `plugins/soleur/test/c4-count-parity.test.sh`; confirm `scripts/required-checks.txt` unchanged

## PR C — per-suite selection, reduced-run read, probe (dark until activation)

- 3.0 Go/no-go gate: spikes S-b/S-c measured and replay recorded; proceed only if replay escape is under 2% and the pre-pass does not erase the saving
- 3.1 Extend `scripts/ci-battery-gate-replay.sh` with the selector (300 first-parent commits vs suite failures)
- 3.2 Label-keyed `skip_labels` job output; runner consumer in `scripts/test-all.sh` (unknown label or PR-added suite runs; always-on ratchets never skipped); pass through `env:` to `test-scripts` and `test-scripts-heavy` legs
- 3.3 Shared full-verified read (jobs API: gated jobs not skipped, `pr-affected-active` not success, or a `merge_group` success); wire into `admin-merge-ready.sh` and `ci-head-verdict.sh`; audit `battery-owed.sh`, `monitor-pr-checks.sh`, ship Phase 7, `drain-prs`; Guard 3 rows G3-1..G3-6
- 3.4 `plugins/soleur/scripts/ci-full-battery-audit.sh` (+ test) as a step of `post-merge-monitor.yml`; `SOLEUR_FULL_BATTERY_ESCAPE` pages via Better Stack with a named responder; extend `scripts/ci-demand-census.sh` (PR job-min by mode, escapes, `--selftest`)
- 3.5 Verify with the API that `gh pr merge --admin` skips the merge queue before the ADR text asserts it; test that `web-platform-release.yml` keeps its `WR_EVENT == push` re-check
- 3.6 Record the pre-activation baseline census; remove the activation-lock sentinel in the last commit; run `soleur:engineering:review:user-impact-reviewer` at review

## Activation (separate authorized step, not part of any PR)

- 4.1 After PR C merges and AC6/Guard 3 hold, flip `CI_PR_AFFECTED` through the ADR-276 activation lane; measure AC12 over 6 hours
