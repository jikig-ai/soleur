---
title: "A classified edge that pointed at itself read as coverage — three guards whose assembly was tested and whose property was wrong"
date: 2026-09-20
category: test-failures
module: scripts/test-all.sh affected-gate
issues: [8322, 8270, 8231]
---

# A classified edge that pointed at itself read as coverage

## Problem

Building the `--affected` local gate for `test-all.sh` (#8322), three separate
defects survived a heavily mutation-tested implementation because each test
verified the *assembly* of a guard while the *property* the guard existed to
provide was never pinned:

1. **`edge:derived` self-edge = dishonest classification.** The derivation
   pass extracted SUT edges from each suite file, but its arms only covered
   literal `source path`, `bash path`, and quoted Python imports. The repo's
   dominant conventions — `source "$VAR"`, `bash "$VAR"`, unquoted
   `import x` / `from x import y`, `node`/`bun` subprocesses, `$(dirname …)`
   idioms — produced NO edges. A suite whose derived set contained only its
   own file still counted as `edge:derived` — *classified* — so a diff that
   touched only the real SUT got the suite **declined**. The unsafe
   direction, and invisible: the census only rejected `unclassified`, so a
   wrong edge looked identical to a right one.

2. **Enumerate/dispatch ordinal map with no identity check.** The selection
   map was built by a nested `--enumerate-commands` walk and consumed by the
   dispatch walk keyed on ordinal position. A `.test.sh` created or removed
   mid-run shifts every ordinal after it; a suite the diff reached could be
   declined behind a green summary. Two reviewers found it independently.

3. **`SCRIPTS_SHARD` inherited by the nested enumerate child.** The child's
   stream packed shard-selected records 1..k while the parent's ordinal walk
   ran 1..N — the same misalignment as (2), deterministic rather than
   racy.

A fourth, cheaper defect of the same family: the ADR, hook comments, and
spec all claimed the affected gate runs in "under five minutes". The repo's
own `baseline-timing.tsv` refuted it — the 130 always-on receipts alone sum
to 22.5 min, so the honest claim is ~46 → ~25 min. Nobody had summed the
floor the claim depended on.

## Solution

- **Demote self-only derivation.** If the derived edge set contains only the
  suite's own file, classify `unclassified` — which *selects* the suite
  (fail toward coverage) and surfaces it in the census as needing a real
  edge. 84 suites initially demoted; broadening derivation (unquoted
  imports, `$VAR`-valued invocation targets resolved from same-file
  assignments, `$(cd "$(dirname …)" && pwd -P)` composites, `$VAR/path`
  tokens in any argv position, `test_*.py`/`lib/`/`test→scripts` stem
  conventions) rescued most; the rest got mined `AFFECTED_*_PATHS`
  declarations whose arrays were re-verified to carry real edges.
- **Label-guard the ordinal map.** The map stores each record's label beside
  its selection bit; the dispatch walk compares the map's label to the live
  label at every ordinal and, on mismatch, drops the whole map and runs
  everything remaining — `AFFECTED_DIVERGENT` receipt, fail toward coverage.
- **`env -u SCRIPTS_SHARD` on the nested enumerate child**, with a sandbox
  mutation pair proving it load-bearing (s1: aligned run; s2: refusal
  neutralized + `env -u` stripped → divergence fires → all run).
- **Falsify prose claims against the repo's own baseline** before they ship:
  `awk` the always-on receipt labels against `baseline-timing.tsv`.

## Key Insight

For any selection/classification mechanism, ask two separate questions:
"does every member get a class?" (the census question) and "does the class
point at the right thing?" (the coverage question). A census that counts
classifications cannot see a classification that is *wrong* — and the wrong
direction is always the one that *narrows* coverage, because the fail-safe
class is the expensive one. The fix pattern that recurred three times in one
session: **when uncertain, select.** Self-only edge → unclassified → runs.
Ordinal mismatch → drop map → all run. Shard leak → would have silently
mis-declined. Every uncertain state must resolve toward more coverage, and
the test suite must exercise each transition, not just the happy path.

Companion insight: **two walks keyed on the same ordinal must tick
identically and must consume the same stream.** If either walk can tick on a
record the other skips (here: `run_suite` vs `skip_suite` via
`_shard_selects`), or if a nested producer inherits a filter the consumer
doesn't apply (`SCRIPTS_SHARD`), the positions diverge and every downstream
lookup is silently wrong. Position-keyed maps always need an identity check.

## Session Errors

1. **Phrasing-keyed correction sweep rewrote markdown link targets.** A
   `s|/(ship|work)\b|soleur:\1|` pass fixing canonical-name census failures
   rewrote `](../work/SKILL.md)` to `](..soleur:work/SKILL.md)` — inside a
   link target, outside the intended scope. Recovery: manual revert of the
   corrupted targets, verified by re-running `harness-parity-tree.test.ts`
   (116/116). Prevention: sweep the *subject*, then grep the result for
   `](`+replacement patterns before declaring the sweep clean; the
   residual-zero count certified nothing about sites the pattern matched
   incidentally. (Same class as #7162/#7539/#7826 — now observed on a
   *correction* sweep, not just a rename.)

2. **Editing a running bash script corrupts its execution — twice.** Bash
   reads script files lazily by byte offset; mid-run edits shifted the
   offsets and produced `flight: command not found` (rc=127) in a detached
   watcher and a corrupted mid-run failure in `test-all-affected` row d.
   Recovery: clean reruns after the edit window closed. Prevention: never
   edit a file that a live process may be executing; re-arm watchers *after*
   the commit lands, and treat any `rc=127`/syntax failure observed during
   an edit window as edit corruption until proven otherwise by a clean
   rerun.

3. **`set -e` silent abort on a loop-condition exit status.**
   `_affected_resolve_vars` ended with a `while read` loop whose final
   failed `[[ =~ ]]` condition left exit status 1; under `set -e` the whole
   `--print-affected-set` walk died emitting nothing — no error, no output.
   Recovery: explicit `return 0`. Prevention: a function consumed under
   `set -e` must not end on a construct whose exit status is control flow,
   not success; an empty-success-output walk is itself a finding.

4. **`producer | grep -q` under `pipefail` is SIGPIPE roulette.** The
   enumerate-stream assertion row failed because `grep -q` exited on the
   first match and the producer died on SIGPIPE (141) — the exact trap the
   runner documents at its own chokepoint. Recovery: capture the stream
   once into a variable, then grep the variable. Prevention: under
   `pipefail`, never pipe a multi-record producer into a short-circuit
   consumer.

5. **ADR ordinal collision surfaced by a required check, not by any local
   signal.** `ADR-229` was claimed on `main` by #8301 between branch start
   and review; the collision was caught only when `adr-ordinals` ran.
   Recovery: renumbered to 230 with a subject-scoped citation sweep.
   Prevention: treat a branch-picked ordinal as provisional and re-check
   against freshly-fetched `origin/main` immediately before merge (same
   lesson as #7162, third recurrence).

## Tags

category: test-failures
module: scripts/test-all.sh
principles: [fail-toward-coverage, census-vs-coverage, position-keyed-maps-need-identity]
