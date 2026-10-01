# Tasks — feat-one-shot-8884-lint-capture-exit-s34

Plan: `knowledge-base/project/plans/2026-09-25-fix-lint-capture-exit-s34-blind-spots-plan.md`
Issue: #8884 — lint-shell-capture-exit S3/S4 residual blind spots (deferred from PR #8836)

## Phase 1: quote model (cross-line quote state + quote-aware `;` split)

- [ ] 1.1 Write failing fixtures FIRST in `scripts/lint-shell-capture-exit.test.sh`
  (they must fail against the unmodified linter):
  - must-fire: `set -e` + multi-line `bash -c '…\nset +e\n…'` + `worker` +
    `rc=$?` (the quoted clear must NOT disarm the real read — m12 shape);
    `echo 'a;b'` + `rc=$?` fires S3 and names `echo 'a;b'` as antecedent.
  - must-not-fire: `set -uo pipefail` + `bash -c '…\nset -e\n…'` +
    `x=$(grep p f)` (quoted arm cannot arm — m5 shape); a `rc=$?` text inside
    a multi-line `bash -c '…'` literal produces no finding.
- [ ] 1.2 Add `quote_at[]` (open-quote char at each logical line's start) to the
  pass-1 state loop in `scan()` (`scripts/lint-shell-capture-exit.py`
  :533-559); skip `set_verdicts` contributions on lines that start inside an
  open quote, and skip S1/S2/S3 evaluation for them in pass 2. Escape rule:
  adopt the sibling precedent
  `scripts/lint-workflow-errexit-capture.py::_heredoc_opener` (:170-201) —
  `\` escapes the next char unless single-quoted (also fixes unquoted `\'`);
  a quote still open at EOF re-judges the skipped tail as code (fail-closed,
  mirroring the sibling's unterminated-heredoc rule :158-165) — pin with a
  fixture.
- [ ] 1.3 Make `_segments` (:373-400) quote-aware (same `'`/`"` tracking as
  1.2's tracker): a `;` inside quotes accumulates instead of splitting.
- [ ] 1.4 Move paren `depth` counting onto quote-masked text so `(`/`)` inside
  literals stop skewing depth (closes the "parens in literals" documented
  limit).
- [ ] 1.5 Raise `MIN_ASSERTIONS` in the same edit that lands these fixtures.

## Phase 2: S3 compound-closer antecedents

- [ ] 2.1 Write failing fixtures FIRST:
  - must-fire: multi-line `if/fi`, `while/done < f`, `for/done`,
    `case/esac`, `{ … }` group, each followed by `rc=$?`; same-line
    `if c; then w; fi; rc=$?` (segment-level closer).
  - must-not-fire: multi-line `if cmd; then rc=0; else rc=$?; fi`
    (the canonical fix — the `fi` closer must not sweep it);
    `f() { worker; }` then `rc=$?` (function DEFINITION close is not an
    execution — stays silent).
- [ ] 2.2 In the antecedent resolver (`scan()` :695-739) + protection pair
  `is_protected`/`_s3_exempt_command` (:426-479): reclassify a resolved
  candidate that is a closer (`fi`/`done`/`esac` + optional redirect/`;`, or
  `}` closing a group — never a function-definition `}`) as "the just-closed
  compound": unprotected, judged armed at the closer's position.

## Phase 3: S4 function-shape coverage

- [ ] 3.1 Write failing fixtures FIRST:
  - must-fire: `name()` newline `{` tail; `name() (` … `)` tail;
    `name() {` … `test && act; }` mid-line closer; `}; rest` close after a
    `test && act` line; pending `name()` newline `(`.
  - must-not-fire: `{a,b}` brace expansion and `${x}` inside bodies do not
    perturb the group counter; predicate-named functions exempt under every
    new opener shape; `cmd || { a; b; }` one-line inner group does not
    mis-pop the function.
- [ ] 3.2 Implement pending-opener state (a bare `name()`/`function name`
  head line records a pending function; the next non-blank line leading with
  `{` or `(` opens the body; anything else discards it).
- [ ] 3.3 Add the `name() (` paren-bodied opener + `)`-initial closer shape.
- [ ] 3.4 Per-segment standalone-brace bookkeeping on quote-masked text (a
  token that IS exactly `{`/`}` — excludes `${…}`, `{a,b}`, quoted braces):
  mid-line `{` bumps the inner-group counter, mid-line `}` pops it or the
  function; S4 tail for a mid-line `}` is the prior segment on that line,
  else `last_nonempty`.

## Phase 4: literal-prefix status reads

- [ ] 4.1 Fixture FIRST: `worker` + `x=pre$?` fires S3; `x=pre$?` under
  `set +e` silent; `x='$?'` literal stays silent (control).
- [ ] 4.2 Widen `READ_RE`/`_STATUS` (:194-195) to admit a literal prefix in
  the value (chars excluding `$`, quotes, whitespace, operators before the
  status token).

## Phase 5: docstring, live triage, baseline

- [ ] 5.1 Docstring: remove/rewrite the five closed HEURISTIC LIMITS entries;
  document surviving residuals (`$'…'` strings, `name() cmd` bodies, `;;`
  fragments, reads after a function-definition `}`); extend THE RULE.
- [ ] 5.2 Run the REGISTERED invocation
  `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt` over the full tree; triage
  every newly-visible finding: real defect → fix in this PR; benign
  pre-existing → keep for baseline. Record the disposition list in the PR.
- [ ] 5.3 Only after triage: `--write-baseline` regeneration; commit the
  regenerated baseline; diff shows new keys only for the newly-covered
  shapes and all prior keys persist.
- [ ] 5.4 Verify `bash scripts/lint-shell-capture-exit.test.sh` →
  `ALL TESTS PASSED` with the raised floor, and `MIN_ASSERTIONS` equals the
  final assertion count.
