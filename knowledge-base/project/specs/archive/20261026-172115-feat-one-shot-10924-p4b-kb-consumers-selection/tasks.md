# Tasks: P4b select the kb-consumers suite when a new fixture names knowledge-base/

Plan: `knowledge-base/project/plans/2026-10-26-feat-p4b-select-kb-consumers-suite-for-new-fixtures-plan.md`
Branch: feat-one-shot-10924-p4b-kb-consumers-selection. Issue: #10924 (Ref only). Umbrella: #9757 (Ref only).

## Phase 0: RED first and measurement

- 0.1 Add contract-suite rows T1-T15, H1-H3 to `plugins/soleur/scripts/affected-tests.test.sh` (fixture repos, stub delegated runner, ledger with sequence numbers); spell the pattern string-joined.
- 0.2 Run the suite once and confirm RED for the right reason (no hook yet).
- 0.3 Pin `content_trigger_paths`: verify each candidate glob matches at least one tracked file; re-run the 150-commit rate measurement for the final set; keep it at or under 10 percent; record command and figure for the PR body.
- 0.4 Record the wall time of `bash scripts/test-affected-kb-consumers.test.sh` on this checkout (cold and warm derive cache) for the PR body; the manifest weight is 91 s and a cold run under sibling load is far higher.

## Phase 1: the lib

- 1.1 Create `plugins/soleur/scripts/lib/affected-tests/content-trigger.sh` with `affected_ct_scan` and `affected_ct_run` (local `_ct_` variables, results through globals, no command substitution around the scan).
  - 1.1.1 Base: `--base`, `origin/main`, `origin/master`, never upstream; `git merge-base`; one `git diff -U0` against the merge-base plus untracked files.
  - 1.1.2 awk state machine with `ENVIRON` pattern; header, path and removal lines never count.
  - 1.1.3 Untracked leg with `grep -IlF` over a file, each rc captured on its own line.
- 1.2 Edit `plugins/soleur/scripts/lib/affected-tests/common.sh`: initialise `AFFECTED_CT_ARMED`, `AFFECTED_CT_ELIGIBLE`, `AFFECTED_CT_EXPLAIN` to 0; add the `finish()` hook and the `content_trigger=` marker field (unarmed output byte-identical).

## Phase 2: config and gate wiring

- 2.1 Edit `plugins/soleur/scripts/affected-tests.sh`: source the lib; move `affected_glob_match` above the config block; parse and validate the three keys in `affected_load_config`; set the eligible and explain flags before the delegated, inert and adapter exits only; update the header.
- 2.2 Edit `.soleur-test-gate.json` with the three keys.

## Phase 3: docs

- 3.1 Edit `plugins/soleur/skills/ship/references/affected-gate-contract.md`: three key rows, marker field, order of evaluation, double-run note, trust note.

## Phase 4: verify (local, bounded, no credentials)

- 4.1 `bash plugins/soleur/scripts/affected-tests.test.sh` green; demonstrate mutations M1-M10 RED once each.
- 4.2 Run the repo-global ratchets explicitly: fixture-relative-assert, fixture-dir-operand-assert, fixture-cd-containment, fixture-env-adoption, guard-vacuity-floor, `scripts/test-affected-kb-consumers.test.sh` (a local SKIP is not evidence), `scripts/lint-orphan-test-suites.sh`.
- 4.3 Confirm `git diff --name-only origin/main...HEAD` has nothing under `apps/`, `.github/workflows/`, the registry-restore script, `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh`; run `--print-selection` detached and bounded and confirm `fallback=none`.
- 4.4 Dogfood `--explain` on a scratch synthesized fixture; confirm `CONTENT_TRIGGER armed=1`.

## Phase 5: ship

- 5.1 PR body: `Ref #9757`, `Ref #10924`, no closing keyword, `## Changelog`, link #11166. Stop and ask the operator if the diff touches `.github/workflows/apply-web-platform-infra.yml`.
- 5.2 Merge with `gh pr merge <N> --squash --auto` through the merge queue, never `--admin`.
- 5.3 After the merge tick the P4b checkbox on #10924; leave the issue open.
