# Tasks: fix(hooks): the filing gate sees filings inside substitutions, `bash -c` and quotes

Plan: `knowledge-base/project/plans/2026-09-28-fix-filing-gate-shell-tokenizer-substitution-plan.md`.
Issue: #9089. Row IDs (D*, P*, F*, C*) and guard rows (G*) refer to the plan.

## Phase 0: Tests first

- [ ] 0.1 Pin gh's version (2.101.0) and its value-taking flag tables from
  `gh issue create --help` and `gh api --help`. These become the data header of
  `.claude/hooks/lib/filing-shape.pl`.
- [ ] 0.2 Create `.claude/hooks/lib/filing-shape-corpus.json`: at least 75 rows, all three shape
  classes, and every spelling listed in AC4.
- [ ] 0.3 Create `.claude/hooks/lib/filing-shape.test.sh`:
  - a header that says where each new row belongs;
  - corpus parity through `--classify`, with a literal floor;
  - lexer-record rows (exit 0, `OK`, exact fields);
  - a row for every P-row;
  - the bounds rows (AC6);
  - `perl -c`;
  - the flag-table staleness row, which skips when gh is absent;
  - the `--probe` and `--differential` modes.
- [ ] 0.4 Add the D, P and F rows to `.claude/hooks/guardrails.test.sh`:
  - put the row ID in each assert label;
  - add `assert_reason` twins;
  - tag base-denied rows `[base-deny]`;
  - rewrite the "quoted endpoints on both sides of &&" comment.
- [ ] 0.5 Add vitest rows:
  - the corpus `it.each` with a literal `>= 75` floor;
  - the `--input` refusal and its reorder row;
  - the two `decide()` pins for `$(…)` and `bash -c`;
  - a deny-marker `#fragment` row.
- [ ] 0.6 Confirm RED against a scratch copy of the whole `4170460eea:.claude/hooks/` tree (AC2).

## Phase 1: Cron mirror and shared predicate

- [ ] 1.1 In `cron-bash-allowlist-hook.mjs`:
  - export `ISSUES_COLLECTION_RE`;
  - implement `filingShape` per the predicate spec: POST_SIGNAL with `-i` clusters and the
    prefix-required `$` arm, root and group `--repo`/`-R` skipping, `issue new`, and `$`-only
    endpoints.
- [ ] 1.2 In `filingJustificationReason`, add the `--input` refusal before exits 0 and 1, using the
  hook's refusal text.
- [ ] 1.3 In `cron-filing-deny-marker.ts`, import `ISSUES_COLLECTION_RE`, delete `ENDPOINT_RE`, and
  cut the head at `[?#]`.
- [ ] 1.4 Get vitest green (AC3). Keep these as the first commits so they can be cherry-picked
  (DC-1).

## Phase 2: `filing-shape.pl --classify`

- [ ] 2.1 Implement `filing_shape` in Perl, using `\z` anchors. Follow the layout contract:
  `use strict; use warnings`, data tables at the top, and one sub per construct.
- [ ] 2.2 The corpus passes on both sides.

## Phase 3: Lexer

- [ ] 3.1 Build the recursive-descent lexer with a frame stack:
  - quoting, separators and redirections;
  - in-place substitution recursion, including substitutions inside `${…}` and `$((…))`, but never
    the `${…}` text itself;
  - comments;
  - a native heredoc queue (quoted bodies are data, unquoted bodies are scanned, `<<-` strips
    tabs).
- [ ] 3.2 Detect `gh` at any argv position, with basename normalization. Add string runners:
  `bash|sh|zsh|dash|ksh` with a `c` cluster, and `eval`.
- [ ] 3.3 Add the per-filing field parser (`head`, `repo`, `milestone`, `label`, `bodyfile`,
  `body`/`bodyvar`, `input`). A `$`-valued repo is never external.
- [ ] 3.4 Add bounds: depth 16, a character budget of 8 × input + 64 KiB, and `alarm 2`. Any of
  these exits 3; an unbalanced input exits 2.
- [ ] 3.5 Add output modes: NUL records followed by `OK`, `--trace`, and `--probe`.
- [ ] 3.6 Run the `--differential` oracle once, before wiring. It must show 0 misses and 0 prose
  filings. The oracle takes its ground truth from gh semantics in the shim, not from
  `--classify`.

## Phase 4: Wire `guardrails.sh`

- [ ] 4.1 Add a record reader: a `while IFS= read -r -d ''` loop with an appended `RC` record,
  parsing records by count.
- [ ] 4.2 Add `_gate_one_filing`, fed by the fields. Delete `xargs -n1` and the three token loops.
  Fall back to the `$COMMAND` body corpus only when `bodyvar` is set.
- [ ] 4.3 Keep the CLASS 1 grep and `_api_pl` as the union floor, commented as such (AC8).
- [ ] 4.4 Add the failure path in order: exit 2 → deny with `TOK_MSG`; else floor fires → deny;
  else ask. It applies only when the loose indicator matches. Emit one incident code,
  `guardrails-filing-lexer-failure`, with the cause.
- [ ] 4.5 Refusal text must include the head, the ctx and the in-command clause. Add the prose hint
  (backtick or unquoted heredoc) and the absolute-path hint.
- [ ] 4.6 Update the header comments that describe `$SCAN`-based detection.
- [ ] 4.7 Run `guardrails.test.sh` and `hook-input-contract.test.sh`, then
  `lint-shell-capture-exit.py` (AC1, AC7). Bump `MIN_ASSERTIONS` in the same commit as the rows.

## Phase 5: Record and verify

- [ ] 5.1 Add an ADR-157 addendum covering the fail direction, lex-not-grep, the corpus-bound
  parity, and the build-vs-buy alternatives.
- [ ] 5.2 Re-run `--differential` against the final tree. Put the flip table in the PR body (AC5).
- [ ] 5.3 Run `bash plugins/soleur/test/c4-count-parity.test.sh` and
  `python3 scripts/lint-guard-contract.py` on the plan (AC10).
- [ ] 5.4 Confirm `bash .claude/hooks/lib/filing-shape.test.sh --probe` prints `PROBE create` (AC11).

## Phase 6: Ship

- [ ] 6.1 File one residual follow-up issue listing the plan's Non-Goals, with the
  `meta/machinery` label and the `Post-MVP / Later` milestone.
- [ ] 6.2 Put `Closes #9089` in the PR body and link the follow-up issue. Render DC-1 through DC-4
  from `decision-challenges.md`.
