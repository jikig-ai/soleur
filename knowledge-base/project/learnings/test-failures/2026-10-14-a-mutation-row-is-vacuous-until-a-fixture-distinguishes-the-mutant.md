# Learning: a mutation row is vacuous until a fixture distinguishes the mutant — inject synthetic state or build a scratch repo

## Problem

During #10117's PR-B review, two seats independently found mutation rows that
could never discriminate because the live repo's index can't produce the
distinguishing shape:

- A member-boundary mutant (`f.startswith(p + "/")` → `f.startswith(p)`)
  survives every live-tree fixture — no `legal-x/` sibling dir exists in the
  index, so nothing ever leaks into the enumeration.
- A recursion mutant (`f.startswith(pre)` → `os.path.dirname(f) == p`)
  survives because no tracked dir has all-matching direct children with a
  declining NESTED member.
- A dispatch mutant (index-dirs vs on-disk dirs) needs an index dir with no
  filesystem presence — impossible on a full checkout.

All three mutations were "covered" by rows that could never see them fail —
the same false-confidence class as fixture-space cardinality gaps.

## Solution

Two escapes, both used in `test-affected-kb-consumers.test.sh` k6 rows:

1. **Inject synthetic state into the memoized census** — the probes exec a
   scratch copy of the oracle via importlib anyway, so
   `o._TRACKED = (o._tracked()[0] | {"knowledge-base/legal-x/evil.sh"}, ...)`
   fabricates the sibling dir for exactly the process under test.
2. **Build a scratch repo under TESTROOT** — `git init` + `git add` populates
   a synthetic index (no commit or identity needed), then `rm -rf` produces
   the index-dir-absent-on-disk shape; probes `cd` there so `ls-files` and
   `os.path.isdir` both resolve against the fixture.

Also folded in: a stale-expectation harness guard must assert the vector the
OLD rule actually emits — a hand-extended "stale" string that no rule
produces is a chimera that can never match (and a `!=` check on it passes
vacuously on empty output). Shape-pin the emitted vector (`^([01] ){22}[01]$`)
instead.

## Key Insight

Before writing a mutation row, ask: *what fixture makes the mutant's verdict
differ?* If no live repo state can produce it, the row is decoration —
fabricate the state (module-global injection or scratch index) or drop the
row. "Mutant lands and emits the same vector" is the quietest green.

## Tags
category: test-failures
module: affected-suite-selection
