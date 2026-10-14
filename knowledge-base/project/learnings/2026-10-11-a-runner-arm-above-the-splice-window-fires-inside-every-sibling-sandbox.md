# Learning: a runner arm above the splice window fires inside every sibling sandbox — and the env var that opts out is the opposite of what you expect

## Problem

#9814 added a `TEST_TIMING_LOG` default arm to `scripts/test-all.sh` (~:4340) that
auto-creates `$_durable_log_dir/suite-timings.tsv` on local affected-shaped runs.
The design-validity pass caught the exported-variable leak (nested runner children
would inherit the path and append fixture rows into the parent's log — fixed by
assigning in-shell, never exporting). The 10-seat panel then found a second,
distinct escape that the env-scrub reasoning had missed: **the arm sits above the
`tc_acquire`-to-`tc_epilogue` splice window, so it survives into EVERY sandboxed
runner copy the runner-SUT suites build.** Those suites copy `test-all.sh`
wholesale and splice only the lock-to-epilogue window; everything above —
including any new default side-effect — rides along.

Concretely: `test-all-orphan-log-retention`'s clean arm asserts its durable dir is
empty (`find "$DURABLE_C" -type f` → zero). The default arm fired inside its
sandbox, wrote `suite-timings.tsv`, and reddened the suite deterministically on
every local run — while CI stayed green (`-z CI` declines the arm), the worst
red-local/green-CI split, on exactly the runner-touching diff class that degrades
to the full battery locally. Two more sandboxed suites had the same latent
exposure (litter, no red). The fix was fleet-wide: `TEST_TIMING_LOG=/dev/null` on
every sandbox env line — 12 sites across three files, plus the subtle one: a
`TEST_TIMING_LOG=""` (set-EMPTY) default in `killed-classification` still fires
the arm, because `-z` treats empty identically to unset; the opt-out must be a
non-empty discard path, not the empty string.

## Solution

- Any new default-armed side-effect in `test-all.sh` must be checked against the
  full fleet of runner-SUT sandboxes, not only the suite built for the feature:
  `grep -ln 'cp .*test-all.sh\|build_sandbox' scripts/*.test.sh` enumerates them,
  and every sandbox env line needs the documented opt-out.
- `TEST_TIMING_LOG=/dev/null` is the opt-out BY CONSTRUCTION: non-empty so `-z`
  declines the default arm, `>>` discards appends, and `[[ -s /dev/null ]]` is
  false so the emit gate's lib-absent note stays silent. Set-empty (`""`) does
  NOT work — `-z` reads empty as unset.
- When a new emit-side note is added (the elif lib-absent decline), it must
  decline for `/dev/null` and for an empty file — the note means "rows exist
  unreported", so gate it on `-s`, not `-r`: `test-all-killed-classification`'s
  AC8 byte-shape-vs-main arm is the fixture that reddens on any stray line.
- The probe ladder that survived review: `mkdir -p` + `[[ -w && -O ]]` (dir
  creation + co-tenant-ownership) then `: >` truncate (file-level probe AND the
  bash-3.2 PID-reuse stale-row fix) — a non-writable leaf declines the arm
  instead of letting the first `>>` abort the run mid-suite. Two probes, each
  with a different load-bearing role; a splice mutation pins each.
- Guard-2 coverage holes the mutation matrix missed until named: a conjunct is
  only pinned if SOME arm observes the artifact it protects — the enumerate
  conjunct was "covered" by an arm that asserted on the file it could never
  produce (the dir was the observable), and the all-group `_AFFECTED` disjunct —
  the dominant bare-invocation path — had zero executing arms.

## Key Insight

The sandbox recipe that makes the runner testable (copy the file, splice the
lock-to-epilogue window) is also a delivery channel for every default arm placed
above the window: a feature that "only affects local affected runs" is not
bounded by its predicate — it is bounded by its position in the file. When
adding runner machinery, ask "which fixture inherits this?" before asking
"which env var disables it?", and treat the opt-out's emptiness semantics as
load-bearing (non-empty discard ≠ empty string ≠ unset).

## Session Errors

1. **Apostrophe inside a single-quoted awk program's comment** terminated the
   program (`syntax error near 'next'`) — Recovery: removed the apostrophe;
   the suite's bash -n gate caught it — Prevention: no possessives in
   single-quoted program text; this suite now syntax-checks the lib.
2. **`$split` vs `$_split` naming drift** broke C9 under `set -u` — Recovery:
   renamed the sites — Prevention: read the emitted file after heredoc-driven
   rewrites; a `python -c 'print(body[:N])'` preview would have caught the
   literal-escape class too (`\\n` vs `\\\n` in embedded python strings).
