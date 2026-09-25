# Tasks — feat-one-shot-8784-capture-exit-plain-call

Plan: `knowledge-base/project/plans/2026-09-25-chore-capture-exit-dead-rc-read-plan.md`
Issue: #8784 — lint-shell-capture-exit: cover the fn-arg-then-rc-$? errexit shape

## Phase 1: errexit-model fix + S3 (dead status read)

- [ ] 1.1 Write failing fixtures FIRST in `scripts/lint-shell-capture-exit.test.sh`
  (they must fail against the unmodified linter):
  - must-fire: `fn "$x"` + `rc=$?`; `out=$(cmd)` + `rc=$?`; `cmd; rc=$?`
    same-line; `local rc=$?` mid-function; `rc=${PIPESTATUS[0]}`;
    `cmd` / `set +e` / `rc=$?` mis-fix; `declare -i rc=$?`
  - must-not-fire: `cmd || rc=$?`; read inside a protected operand;
    function-head `local rc=$?`; `name=$?` inside `$( … )`; `set +e` region;
    `set -uo pipefail # deliberately NOT -e` + `cmd; rc=$?`; `cmd && rc=$?`;
    no `set -e` at all
- [ ] 1.2 Strip the unquoted `#` tail from `set` args in `errexit_after`
  (`scripts/lint-shell-capture-exit.py`); confirm live-run output on the real
  tree is byte-identical before/after.
- [ ] 1.3 Restructure `scan()` to the two-pass model (state-before-each-line +
  paren `depth`), porting `scan_body()` semantics from
  `scripts/lint-workflow-errexit-capture.py`: `READ_RE` anchor, `before`-text
  `||`/`&&` protection, back-walk to the previous non-`set` logical line,
  `is_protected` (control lines, `!`-negation).
- [ ] 1.4 Add shell-specific exclusions: resolved command is a function opener,
  `{`/`}`/`fi`/`done`/`esac`/case-arm head; read inside unclosed `$( )`/`( )`
  group; S1/S2 dedupe on the same command line.
- [ ] 1.5 S3 report at the read's line; fingerprint = normalized *command*
  text + read (never the bare `rc=$?` text).

## Phase 2: S4 (status-leaking test tail)

- [ ] 2.1 Write failing fixtures FIRST:
  `(( skipped > 0 )) && echo` tail fires; `[[ -f f ]] && grep -q` tail fires;
  bare `[[ cond ]]` tail silent; `test && act || fallback` silent;
  `is_ready() { [[ c ]] && notify; }` silent; `[[ c ]] && return 1` silent;
  tail in a `set +e` file silent.
- [ ] 2.2 Function-boundary tracking in `scan()` (`name() {` / `function name`
  opens; `}`-only line closes); flag `test-builtin && action` tails with the
  exclusion set (inside-bracket `&&`, `||` arm, `return`/`exit`/`break`/
  `continue` actions, predicate-named functions).
- [ ] 2.3 Docstring: new `THE RULE` paragraphs for S3/S4 — the two
  context arms note, the `cmd && rc=$?` exclusion, heuristic limits.
- [ ] 2.4 Raise `MIN_ASSERTIONS` to the new assertion count.

## Phase 3: baseline regeneration + triage

- [ ] 3.1 Run the linter WITHOUT baseline over the tree; print and triage
  every S3/S4 finding: benign idiom → baselined; suspected live bug → fix in
  this PR instead of baselining.
- [ ] 3.2 `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt --write-baseline`; diff the
  file — new keys exclusively `S3`/`S4`, all prior `S1`/`S2` keys persist.
- [ ] 3.3 Optional comment touch-up in `scripts/test-all.sh` naming the new
  classes (comment-only).

## Testing / Verification

- [ ] 4.1 `bash scripts/lint-shell-capture-exit.test.sh` → `ALL TESTS PASSED`.
- [ ] 4.2 `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt` → `[OK]`, exit 0.
- [ ] 4.3 Touched-shard exit gate: `scripts/test-all.sh` shard covering
  `scripts/` is green.
