---
date: 2026-08-04
pr: 7196
issue: 6808
category: workflow-patterns
tags: [review, gate-2a, mutation-testing, fixture-cardinality, cross-gate-exemption, contention]
---

# A 0-of-11 review hid 14 P1s, and two of my own fixes reproduced the class they were fixing

## What happened

PR #7196 (schedule + alarm the `/workspaces` LUKS at-rest verification) reached the ship gate with
`Reviewed-Coverage: inline-fallback 0/11 agents` — every review agent had died on a session API
limit. Implementation was genuinely complete: `test-all` 253/253, the new 664-line gate suite 75/75,
a self-run 14-mutation battery reporting all-RED against a GREEN baseline, `terraform plan` 0
destroys. `session-state.md` correctly refused to ship and named the re-run as the resume point.

The re-run with 12 agents found **45 findings, 14 of them P1**, on a branch that was **already red**
on a pre-existing guard nobody had run.

## The numbers that matter

The degraded pass is not "a review with fewer opinions". It is measurably a different artifact:

| | degraded (0/11) | full panel (12) |
|---|---|---|
| Findings | 5, all self-found inline | 45 |
| P1 | 0 | 14 |
| Mutants surviving the gate suite | (unmeasured) | 20, all at full green |
| Suite deletable while reporting success | (unmeasured) | 45% |

This is the second recorded instance of the #7146 shape and it reproduced the ratio. **Gate 2a's
refusal to mark ready at `single-user incident` on zero agents is load-bearing, not ceremony.**

## The defects worth generalising

**A `NEGATIVE` gate on the class that carries a legal consequence.** `drift` — the only class that
files p0 `type/security` and asserts the published Article 32 claim FALSE — was reached by "anything
not probe-integrity". So every unmodelled non-zero rc earned it, including `rc=2`, which **bash
returns on a syntax error**. `luks-monitor.sh` refuses exit 2 for readiness on exactly that
reasoning, one layer down; the layer above undid it. Inverted to a positive allowlist, with a
cross-file parity assertion so a new upstream reason fails loudly instead of being under-reported.

**A width bound is a third axis a character-class check cannot see.** The baseline guard validated
`''|0|*[!0-9]*`. POSIX `[` exits 2 above INT64_MAX, and inside an `if` under `set -uo pipefail` with
no `-e` that reads as "not less than" — so a >19-digit baseline SKIPPED the shortfall comparison and
a total wipe reported PASS. The comment three lines below claimed "BOTH operands guarded".

**Severity that rides a dedupe key it does not own.** `labels` was consumed only by
`gh issue create`. A `workspace_count_shortfall` (irreversible sole-copy data loss) arriving onto an
already-open p1 readiness issue took the comment path and never received `priority/p0-critical`.
Whether user data loss was labelled p0 was a property of **arrival order**.

**Fixture DIRECTION and the set an assertion quantifies over.** The truth-table grid sampled 22 of
≥192 cells and its `CLASSES` list omitted `selftest`, a real enum member, under an assertion named
"the FULL outcome x class grid". The cadence check read `f[2]` and `f[3]` but never `f[4]`, so
`41 4 * * 1` — weekly — passed an assertion named "runs at least daily".

## The part I got wrong, twice

**Both of my own fixes initially reproduced the class I was fixing.** This is the transferable
lesson, because it is not a knowledge gap — I had just finished writing about each class.

1. **Body capture.** I fixed the fail-closed default and asserted it by title identity and labels.
   Mutating `*) class=unavailable` → `class=drift` **SURVIVED at 121/0**: title and labels are
   assigned separately, and only the issue BODY moves. I had asserted the two surfaces that did not
   change. Fixed by capturing `--body-file` in the `gh` stub.

2. **Lookback scoping.** I added the exit-site map with a fixed 6-line lookback for `emit_class`.
   Stripping `emit_class` from an inline `|| { echo …; exit 1; }` **SURVIVED**, because the window
   reached the *previous* guard's `emit_class`. That is the documented over-permissive-block-scoping
   class, committed by the guard written to close a coverage gap. Fixed with inline-vs-block
   discrimination and a depth-tracked walk to the matching `if` requiring EVERY arm to emit.

**Rule: after fixing a defect class, run the mutation for that same class against your own fix.**
A green suite after a fix says the fix compiles, not that it binds. Both of these were caught only
because I re-ran the battery against the patched tree instead of trusting the passing count.

## A cross-gate exemption can vanish from under a branch

The session's recorded premise was "2 of 3 filings are mandated, so net-issue-flow passes". Four
commits before ship, `#7194` untagged `[mandates-filing]` from
`wg-when-deferring-a-capability-create-a`, leaving exactly one mandating rule on `main`. The
exemption the plan counted on no longer existed, and nothing on the branch would have said so.

**Re-derive corpus-derived exemptions from `main` at ship time** (`scripts/lint-rule-bodies.py`,
or grep the marker on a real body line) rather than inheriting the plan's premise. ADR-155 makes
these markers cross-gate; that is exactly what makes them decay silently.

## Sweep by CLAIM, not by file — including the record outside the repo

The Inngest correction was applied to four in-repo sites and cited **#5450**, which ADR-100 names
verbatim as the *same-host* framing it supersedes (#6178 is correct). And `#6808`'s own closure
condition still read as a **disjunction** — the conjunction correction had landed only in the
counsel-audit KB file, so on merge the record a future closer actually reads would have licensed
closing the issue with the heartbeat dead. Rec 2's own instruction was "Record that on the issue."

**The authoritative record is often not a file in the diff.** Enumerate the propositions a change
falsifies, then find every place each one lives — issue bodies and PR bodies included.

## Instrument hygiene

A `test-all` run wedged for **10.3 hours**, outliving its own `timeout 3000` wrapper, while its
output file was reclaimed by `/tmp` pressure. "No output file" was indistinguishable from "still
running" and from "passed" — and a second run started alongside it, producing exactly the sibling
contention the repo blames for false reds. Kill the wedge and run ONE, rather than reading a result
from an instrument you have not verified is alive.

Related: `grep -c` prints `0` **and exits 1**, so `$(grep -c … || echo 0)` yields `"0\n0"` and every
downstream `-eq` comparison errors. Hit twice this session.

## See also

- [[2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path]]
- [[2026-08-01-i-shipped-a-gate-my-own-tests-could-not-see]]
- [[2026-08-02-a-guard-that-derives-authority-must-use-the-authoritys-own-parser]]
- [[2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim]]
