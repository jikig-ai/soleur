# Tasks: registry arch orientation guard (#7335)

Plan: `knowledge-base/project/plans/2026-10-13-test-registry-arch-orientation-guard-plan.md`
Single file edited: `apps/web-platform/infra/registry-boot-guard.test.sh`. Do NOT edit `cloud-init-registry.yml`, `zot-registry.tf`,
`registry-userdata-budget.sh` or any user_data source.

## Phase 1: Setup

- [ ] 1.1 Create a scratch git worktree at HEAD for sandbox mutation runs (never mutate the real tree; restore from a `cp` pristine copy, never `git checkout`/`git stash`).
- [ ] 1.2 Record baselines for the five suites (registry-boot-guard 128/0, zot-image-staleness 16/0, git-data-luks 154/0, registry-luks 34/0, registry-userdata-budget 28 checks/0 failed).

## Phase 2: Core Implementation (in `registry-boot-guard.test.sh`)

- [ ] 2.1 Add `MUT_DIR="$(mktemp -d)"` with `trap 'rm -rf "$MUT_DIR"' EXIT` in the same hunk (lint-trap-tempfile-ownership rule (c)); confirm the suite's exit status is unchanged.
- [ ] 2.2 Add `_mutant_verdict FN SED_EXPR` (SEDERR / NOLAND / RED / GREEN), called outside `assert`.
- [ ] 2.3 R3 arms: INVERT, DELETE, WIDEN prefix to `ca`, must-PASS reformat, NOLAND control (5 assertions); each sed anchored to the `registry_arch =` declaration line.
- [ ] 2.4 R4: `p_registry_amd64_only_precondition` (comment-stripped, block-scoped awk) + header comment (amd64-only boot image property; budget script dependency; A15 owns `doppler_sha256`) + baseline + DELETE, WEAKEN-to-true, COMMENT-OUT, RESOURCE-RENAME, must-PASS (6 assertions).
- [ ] 2.5 Refresh the R2/R3 comment block: remove "still uncovered - #7335", cite A15 and R4.
- [ ] 2.6 Raise `MIN_ASSERTIONS` 123 -> 134 (run becomes 139) and update the floor comment with the measured count.

## Phase 3: Testing and proof

- [ ] 3.1 `bash apps/web-platform/infra/registry-boot-guard.test.sh` -> 139 passed, 0 failed; confirm `git status` shows no `.tf` change.
- [ ] 3.2 Sandbox matrix: INVERT and DELETE `registry_arch` on the scratch worktree; five suites; expect registry-boot-guard RED, others green. Record in the PR body.
- [ ] 3.3 One-off: copy the suite, delete the `ca99` fixture from R3's loop, show the WIDEN arm no longer reports RED.
- [ ] 3.4 `bash apps/web-platform/infra/run-registered-suites.sh`; match `^RED`; record pre-existing reds by name.
- [ ] 3.5 `shellcheck`, `python3 scripts/lint-trap-tempfile-ownership.py`, `python3 scripts/lint-guard-contract.py`, `markdownlint-cli2` on plan artifacts.

## Phase 4: Ship reminders

- [ ] 4.1 PR body: `Closes #7335`, `Ref #10205`, `## Changelog`, the ARCHIVED plan path, note that R3 already landed in #7325, decision-challenges rows.
- [ ] 4.2 Re-check `BASELINE_DECLARED_PROBES` against `origin/main` before the final push (66 at plan time; no `credentials_required` declared here, so no bump expected).
- [ ] 4.3 Confirm `git diff --name-only origin/main` contains only the suite and `knowledge-base/project/{plans,specs}/` files.
