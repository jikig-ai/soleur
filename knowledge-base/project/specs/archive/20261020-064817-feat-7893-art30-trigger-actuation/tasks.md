# Tasks: Art. 30 re-verification trigger actuation

This checklist does not close #7893. The implementation pull request tracks #7893 and must not use a GitHub closing keyword for it.

## Phase 1: Setup

- [x] 1.1 Write `scripts/lint-art30-reverification.test.sh` before the script exists. The suite fails because `scripts/lint-art30-reverification.sh` is absent.
- [x] 1.2 Encode mutation rows 1 through 34 from the plan's Guard Contract. Include a real `git diff` of a NUL byte, symlink status `T`, token-file `diff` exit 2 captured as script exit 2, a duplicate key whose last value is still the approved shape, a `--log-driver` group that fires {4} only, a reorder that stays green, and the exact pointer-sentence assertion.
- [x] 1.3 Synthesize every fixture. Do not copy `cloud-init.yml`, `ci-deploy.sh`, `journald-soleur.conf`, or the live PA-8 section (f) cell. The pre-filled cell already contains bold ids 1 through 7, an old ISO date, and a letter-word.

## Phase 2: Core Implementation

- [x] 2.1 Add `scripts/lint-art30-reverification.sh` with `set -euo pipefail`. Initialize `base_rc`, `filter_rc`, and `diff_rc` to 0 in the main shell before each capture. Read `${EVENT_NAME:-}` and `${MERGE_GROUP_BASE_SHA:-}`. An unset variable is not an empty merge-group base.
- [x] 2.2 Add `knowledge-base/legal/art30-reverification-triggers.yml`. Parse it once with a loader that rejects duplicate keys. The shape check and the walker share that document. Reject a dropped path, an extra path, a `daemon.json` path, an actuated class on id 1, 3, 6, or 7, and any token-to-id group other than the approved groups.
- [x] 2.3 Compare blobs for the two flag files. Pass `--no-ext-diff` and `--no-color`. Do not pass `--exit-code`. A line that begins with the words Binary files, then a space, and ends with a space and the word differ exits 1 even when `git diff` exited 0.
- [x] 2.4 Fire trigger 5 on any non-empty `git diff --name-status --no-renames` row for `apps/web-platform/infra/journald-soleur.conf`, including `T`.
- [x] 2.5 Split the PA-8 section (f) cell on whitespace, one token per line, then run POSIX `diff`. Read added tokens only when `diff_rc` is 1. Exit 2 when `diff_rc` is 2. The ISO date string occurs zero times in the removed cell text. Do not switch to set subtraction.
- [x] 2.6 Print `::error::` with the watched path and the fired ids, or the measured resolver or diff failure. Strip CR and LF from the annotation. Do not echo a diff line or other file text.
- [x] 2.7 Add one step to job `enforce` in `.github/workflows/pr-quality-guards.yml`, after the legal-doc step and the backstop step. No `if:` on the job or the step. Do not put this check inside the legal-doc `run:` block. Do not add paths to `surface_patterns`. Set `EVENT_NAME` and `MERGE_GROUP_BASE_SHA` on the step.
- [x] 2.8 Register `scripts/lint-art30-reverification-unit` in `scripts/test-all.sh` beside the legal-scope-block unit line, and in `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh`. Do not add a live `run_suite`. Do not add the script to `REQUIRED_RUNNERS`.

## Phase 3: Testing

- [x] 3.1 Run the unit suite until the birth fixture exits 0 and every RED row fails for the reason that row names, including the `exit 0` stub.
- [x] 3.2 Add the runbook pointer sentence under `### Re-verification triggers` in `knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md`. Do not restate item predicates. Do not edit the register sentences or the compliance-posture row.
- [x] 3.3 Confirm deleting that exact sentence fails the suite assertion and does not fail the id census.
- [x] 3.4 Run `actionlint` on `.github/workflows/pr-quality-guards.yml`. Do not use `bash -n` on the YAML.
- [x] 3.5 Confirm the birth diff does not edit `apps/web-platform/infra/cloud-init.yml`, `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/journald-soleur.conf`, or a workflow that runs `terraform apply`.
