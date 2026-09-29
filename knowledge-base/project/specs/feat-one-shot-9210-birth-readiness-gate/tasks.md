# Tasks: fix(git-data) birth-readiness-gate — pipe-fed `grep -q` predicates → herestring (S1 flake, #9210)

Plan: `knowledge-base/project/plans/2026-09-29-fix-birth-gate-grep-q-pipefail-plan.md`

## Phase 1: Setup

- [ ] 1.1 Re-read `tests/scripts/lib/git-data-birth-readiness-gate.sh` at the four target sites (the strict `templatefile` literal check in `git_data_rung2_bound_files` ~line 511; the rate-limit retry predicate ~line 1135; the `authorized_keys` outside-`write_files` sweep ~lines 2056–2057; the `ignore_changes` check ~line 2311) and the file's own "A HERESTRING, NOT A PIPE" convention comment at ~line 2260.
- [ ] 1.2 Census the lib for every remaining pipe-fed quiet-grep site: `grep -nE '\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q' tests/scripts/lib/git-data-birth-readiness-gate.sh` — the result list is the conversion set; confirm it matches the four planned sites before editing.

## Phase 2: Core Implementation

- [ ] 2.1 Site 1 (~line 511): replace `printf '%s\n' "$_shape_src" | grep -qE 'templatefile\("\$\{path\.module\}/[^"]+"'` with the herestring form; split `rc ≥ 2` (instrument failure → ABORT with could-not-evaluate wording) from `rc == 1` (shape violation → existing ABORT text kept byte-identical so suite needles still match).
  - [ ] 2.1.1 Verify the rc==1 ABORT needle substrings the suite asserts on (A15-family / `mutate_r2` needles) survive verbatim.
- [ ] 2.2 Site 2 (~line 1135): capture `_body="$(sed '$d' <<<"$_resp")"`, then `! grep -qiE 'rate limit' <<<"$_body"`; anonymous-retry semantics unchanged.
- [ ] 2.3 Site 3 (~lines 2056–2057): capture the filtered `authorized_keys` hits into a variable; `rc ≥ 2` → ABORT instrument-failure; non-empty → HOLD (may now name the offending `line:content`).
- [ ] 2.4 Site 4 (~line 2311): capture the flattened `tr` output, then herestring-grep the `ignore_changes` pattern.
- [ ] 2.5 `bash -n tests/scripts/lib/git-data-birth-readiness-gate.sh` clean; re-run the census grep — zero hits.

## Phase 3: Testing

- [ ] 3.1 Add W2 row (beside W1 ~line 2812): the suite asserts the comment-stripped `grep -nE '\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q'` sweep over `"$ROOT"/tests/scripts/lib/*.sh` is empty. Comment-strip because the lib's own ~line-2260 prose legitimately documents the banned shape.
- [ ] 3.2 Add W2-control row: a synthesized lib copy with a seeded `producer | grep -q` line is flagged by the same extraction (proves the detector fires — Guard Contract row 4); include the must-pass controls: `grep -q pat file` and `grep -q <<<"$x"` forms are NOT flagged.
- [ ] 3.3 Bump `_FLOOR` 252 → 254 at ~line 3057 and extend the itemised ledger comment; verify whether a `_expect_rows` pin needs adding/updating for the new rows.
- [ ] 3.4 Deterministic reproducer evidence for the PR: a `≥ ~150 KiB` `_shape_src` (module dir content) ABORTs under the old pipe form and passes under the new herestring form under `set -o pipefail`.
- [ ] 3.5 Stub-`grep`-rc-2 test: a PATH-injected `grep` exiting 2 at the `templatefile` check produces the instrument-failure ABORT, not the shape-violation text.
- [ ] 3.6 Full suite: `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → `0 failed` (≥254 assertions).
- [ ] 3.7 CI: `test-scripts (6/7)` shard green on this PR.

## Phase 4: Wrap-up

- [ ] 4.1 Deferred sweep already filed as #9217 (meta/machinery, Post-MVP / Later) — reference it in the PR body; do not widen this PR's scope.
- [ ] 4.2 Confirm no product/test-file edits escaped the planned set: `git diff --stat` shows only the two files in `tests/scripts/` plus KB artifacts.
