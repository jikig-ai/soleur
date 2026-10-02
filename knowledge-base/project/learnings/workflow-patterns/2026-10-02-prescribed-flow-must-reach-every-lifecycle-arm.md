---
title: "The prescribed flow must reach every lifecycle arm a write path promises"
date: 2026-10-02
category: workflow-patterns
module: plugins/soleur/scripts, plugins/soleur/skills/ship
tags: [sentinel-lifecycle, dead-code-in-practice, review-convergence, disposition-table, probe-design]
issue: 9402
pr: 9407
---

# Learning: a write-path arm nobody prescribes is dead code that still makes promises

## Problem

`check-red-on-main.sh --report` implements a full sentinel lifecycle: file on
`red-on-main`, dedupe, and auto-close the check's own trackers on
`green-on-main`. The ship reference doc prescribed `--report` only as a
follow-up **on a red verdict** ("re-run the probe with `--report`"), and the
monitor annotation path never passes it. Result: the green-close arm was
unreachable through any prescribed flow — a tracker filed today would stay open
forever, while the filed issue body literally promised "auto-closed when the
check goes green on main again." Undelivered contract, shipped and tested only
in the suite.

Three review seats (architecture-strategist, code-simplicity-reviewer,
agent-native-reviewer) converged on the same defect from different lenses —
the strongest convergence signal of this panel.

The same session produced two smaller instances of the same class:

- **`--durations-out` became its own read source.** `dur_src = args.durations
  or durations_path` where `durations_path` was already biased to
  `args.durations_out` — so `--incremental --durations-out X` alone priced
  every leg from the (nonexistent) output path AND skipped the delta write.
  A redirect flag must never be reachable as the *read* source; source and
  target are different roles.
- **A vacuous input could wipe a committed table.** `--incremental` trusted
  `registered` unconditionally: an empty `--registered-file` or a broken
  `--enumerate` would write a zero-row manifest and drop every durations row —
  exactly when a regen should refuse.

## Solution

- Prescribe `--report` on the ONE probe call at the decision point, not as a
  second call on a subset of verdicts: it files/dedupes on red, closes own
  sentinels on green, no-ops on no-evidence/error — and halves the API budget
  while removing the TOCTOU window between two probes.
- Compute the read source from the manifest-pairing rule only
  (`args.durations or <paired>`); `--durations-out` enters only at the write
  target.
- `die` on an empty registered set before any row construction.

## Key Insight

When a mechanism has lifecycle arms, ask: **which prescribed invocation reaches
each arm?** A branch that only the test suite exercises isn't wired — and if
its output promises a lifecycle (the issue body, the doc's own failure-mode
table), the promise outlives the PR while the path to keep it doesn't. For
flags: keep the read-source and write-target derivations disjoint at the
assignment site; conflation at `a or b` is where redirect bugs live.

**Prevention:** for every verdict- or mode-gated write path in a new probe,
list each arm and name the caller line that reaches it; any arm reachable only
from tests is a wiring defect. For regen-style writers, refuse on vacuous
input sets (empty registered/incumbent-can't-parse) — destructive output from
nothing-shaped input is the wipe class.

## Session Errors (from #9402 pipeline)

Forwarded from `session-state.md` and this session:

1. `gh issue view --json merged` → "Unknown JSON field" (planning probe; queried
   the PR side instead). **Prevention:** check `gh <cmd> --json` field lists
   before assuming a field exists.
2. First `git push` returned `remote rejected (failed)`; retry succeeded.
   **Prevention:** retry once before treating a push rejection as real.
3. Plan-review fan-out ran sequential-fallback (no spawn tool in subagent
   context). **Prevention:** disclosed via `Reviewed-Coverage`; the normal
   review phase supplied the independent seats.
4. Scanner findings on new fixture code (`rm-rf`/redirect roots under mktemp).
   **Prevention:** `assert_fixture_dir` at every new fixture root before
   writes; keep redirect targets inside guarded dirs.
5. Fixture floor expectation 450 vs measured median 350. **Prevention:**
   compute medians from the fixture, don't eyeball.
6. Fixture W's leg assertion assumed legs 3+ unused; then the corrected pin
   still didn't discriminate because floor-pricing left the same argmin.
   **Prevention:** an assertion that must distinguish a fix from its bug needs
   a fixture where the two paths DIVERGE — construct until they do.
7. SKILL.md edit overshot the byte ceiling by 10 B. **Prevention:** measure
   `wc -c` before+after on near-ceiling files; draft tighter first.
8. T23b stub double-escaped JSON (`printf '%s'` inside single quotes needs
   none). **Prevention:** when generating stubs, write the literal and let
   single quotes carry quotes.
9. `_min_cases` asserted one above the true count (31 actual, floor set 32).
   **Prevention:** set the floor to the MEASURED count after adding arms.
