# Tasks: feat-one-shot-wipe-assert-shape-fields-rc34

Plan: knowledge-base/project/plans/2026-10-19-feat-wipe-assert-hooks-shape-fields-plan.md (deepened 2026-10-19)
Refs: #10138, #6897 (Ref only). Nothing in this list dispatches a workflow or posts to #6897 or #9066.

## Phase 1 - RED first (apps/web-platform/infra/git-data-wipe-assert.test.sh)

- 1.1 Extend `RE_34` with the optional `hk_` group; leave `RE_ERR` unchanged.
- 1.2 Split the check: `line34_ok` (strict emit: group iff `has_hooks_d=1`, the four group invariants, cut `n=${n%% *}` after the `offlist_n` parse) and `line34_grammar_ok` (posting grammar, also accepts the already-printed eight-field line).
- 1.3 Give the existing `hooks` rows (A120, A122, the `hooks` loop row, `caught_hookstenant`, `caught_hooksdir`, `L34`, arm H) their group; rows with `has_hooks_d=0` keep their tails.
- 1.4 Add the nine `hooks` worlds of the plan table plus the symlinked-`hooks` world (synthesized names; symlinked `pre-receive` points at a live file outside `hooks`; basic world is a 0-byte file; one world holds the stripped HEAD hook).
- 1.5 Shim: per-call flags keyed on the `/hooks` path (ordered before the generic `-printf %y` arm), the `hooks_ht` type-string override loop (`fsdcbpDUl`, plus an unknown character), the `errors_count` bump flag; rc-33 rows for the four fixed words and the `errors_count_changed_by_listing` row.
- 1.6 Mutants of the Guard Contract matrix (rows 1 to 12), `line34_is` in mutant rows also checking every stderr line against `RE_ERR` and the corpus grep.
- 1.7 File-never-opened detector: PATH allowlist (unlisted readers exit 127) plus the closed-set check of the hooks block; label it structural.
- 1.8 Suite rows: `wl_classify` literal equals `WA_HK_DIR`; bootstrap basenames equal the constants; `WA_HK_PR` has no glob characters; no trailing slash; stripped HEAD hook size at most `WA_HK_PR_MAX` and the literal pinned to 4096; two `timeout 30 find` on the hooks path.
- 1.9 Leak corpus: add one tenant-shaped name; do not add `pre-receive`; size digits checked against stdout and stderr only.
- 1.10 Re-measure `EXPECTED_RC34_LINES`, `EXPECTED_INVARIANT_RUNS`, `MIN_ASSERTIONS` from an unprivileged, loopback-skipped run; add the exact `HK_GROUP_LINES_CHECKED` counter. Record every new row RED against the unchanged script.

## Phase 2 - script (apps/web-platform/infra/git-data-wipe-assert.sh)

- 2.1 Add `readonly WA_HK_DIR=hooks`, `WA_HK_PR=pre-receive`, `WA_HK_PR_MAX=4096` with the bound rationale comment (stripped sizes; coarse bound; strip-render provenance unverified; value changes return to the CLO).
- 2.2 Add the guarded hooks reads in `wipe_listing` (after the lost+found block, before the `e1` read): one `budget` call, one `%y` find with linear counting, one fixed-letter `pre-receive` find, `die 33` with the four fixed words, one statement per line; no trailing slash, no `-L`/`-H`, no `%f`/`%p`, no new fd, no `2>&1`.
- 2.3 Append `$HK_TAIL` to the single rc=34 `say`; update the header comment; check how the suite derives the die-word set. Do not edit `wl_classify`.
- 2.4 `bash -n`; run the unit suite to GREEN.

## Phase 3 - runbook (knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md), five edit sites

- 3.1 Posting list (CLO L3 sentence verbatim plus "not measured") and the two-grammar paragraph with the fallback.
- 3.2 Field bullets (bound, derivation, unverified provenance) and the decode rows, with the CPO wording guards.
- 3.3 The four rc-33 words, with "no `hk_` evidence".
- 3.4 In-cell correction plus dated Superseded marker under "What a run can claim"; sweep siblings with `git grep -n "one fixed 0/1 field"`.
- 3.5 Dated status note and the Not proven line.

## Phase 4 - hand-offs (dispatch nothing)

- 4.1 Show the CLO the L6 strings; record the verdict in decision-challenges.md; run `technical-ruling-gate.sh --branch`.
- 4.2 PR body: `Ref #10138`, `Ref #6897`, the merge condition, nothing dispatched, nothing about the next `wipe_check`.

## Phase 5 - local gate

- 5.1 Run git-data-wipe-assert.test.sh, git-data-wipe-access.test.sh, git-data-cutover-access.test.sh, .claude/hooks/grep-q-pipe-guard.test.sh.
- 5.2 markdownlint on every touched `.md`; lint-guard-contract.py on the plan.
