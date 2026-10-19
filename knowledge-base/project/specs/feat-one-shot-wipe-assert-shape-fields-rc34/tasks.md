# Tasks: feat-one-shot-wipe-assert-shape-fields-rc34

Plan: knowledge-base/project/plans/2026-10-19-feat-wipe-assert-hooks-shape-fields-plan.md
Refs: #10138, #6897 (Ref only). Nothing in this task list dispatches a workflow or posts to #6897 / #9066.

## Phase 1 - RED first (apps/web-platform/infra/git-data-wipe-assert.test.sh)

- 1.1 Extend `RE_34` with the optional `hk_` group; leave `RE_ERR` unchanged.
- 1.2 Extend `line34_ok` with the five group invariants (group iff `has_hooks_d=1`; `hk_nonfile <= hk_entries`; `hk_pr_small <= hk_pr_f`; `hk_entries >= hk_nonfile + hk_pr_f`; `hk_pr_f=1` implies `hk_entries >= 1`).
- 1.3 Add the `hooks` worlds of the plan table (synthesized names only) with whole-line equality; give A120, A122, the `hooks` loop row, `caught_hookstenant`, `caught_hooksdir`, `L34` and arm H their group.
- 1.4 Add the new find-shim flag keyed on a path ending in `/hooks` (ordered before the generic `-printf %y` arm) and the rc-33 rows for the four fixed words.
- 1.5 Add the nine named mutants plus the content-read mutant; add the `line34_ok` harness rows (reject and accept).
- 1.6 Add the suite rows comparing the literals with `HOOKS_DIR` / `PRE_RECEIVE` in `git-data-bootstrap.sh` and the 4096 pin against the stripped HEAD hook size.
- 1.7 Extend the synthesized-names leak corpus; record every new row RED against the unchanged script.
- 1.8 Re-measure `EXPECTED_RC34_LINES`, `EXPECTED_INVARIANT_RUNS`, `MIN_ASSERTIONS` from an unprivileged, loopback-skipped run and annotate them.

## Phase 2 - script (apps/web-platform/infra/git-data-wipe-assert.sh)

- 2.1 Add `readonly WA_HK_PR=pre-receive` and `readonly WA_HK_PR_MAX=4096` with the bound rationale comment (stripped sizes; coarse bound; strip-render provenance unverified).
- 2.2 Add the guarded hooks reads in `wipe_listing` (after the lost+found block, before the `e1` read), globals not `local`, `die 33` with the four fixed words.
- 2.3 Append `$HK_TAIL` to the single rc=34 `say`; update the header comment. Do not edit `wl_classify`.
- 2.4 `bash -n`; run the unit suite to GREEN.

## Phase 3 - runbook (knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md)

- 3.1 Replace the closed posting list sentence with the CLO L3 sentence; add the two-grammar paragraph and the fallback.
- 3.2 Add the four field definitions (bound, derivation, "unverified"), the decode rows and the four rc-33 words.
- 3.3 Correct the "one fixed 0/1 field and two counts" sentence in-cell and add a dated Superseded marker; sweep siblings (`git grep -n "one fixed 0/1 field"`).
- 3.4 Add the dated status note and the Not proven line; apply the CPO wording guards.

## Phase 4 - hand-offs (dispatch nothing)

- 4.1 Show the CLO the L6 strings; record the verdict in decision-challenges.md; run `technical-ruling-gate.sh --branch`.
- 4.2 PR body: `Ref #10138`, `Ref #6897`, the merge condition, nothing dispatched, nothing about the next `wipe_check`.

## Phase 5 - local gate

- 5.1 Run git-data-wipe-assert.test.sh, git-data-wipe-access.test.sh, git-data-cutover-access.test.sh, .claude/hooks/grep-q-pipe-guard.test.sh.
- 5.2 markdownlint on every touched `.md`; lint-infra-no-human-steps.py and lint-guard-contract.py on the plan.
