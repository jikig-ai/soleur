# Resume Prompt — fix the issue-flow structurally

Self-contained. Paste into a fresh session; every number below is measured, so
do not re-derive before starting.

## The measurement (2026-09-10)

| | |
|---|---|
| open issues | **1,456** |
| last 8 weeks | opened **1,134**, closed **563**, net **+571** |
| ratio | ~2 filed : 1 closed, every week without exception |
| older than 60 days | **841** (58%) |
| zero comments ever | **330** |
| `domain/engineering` | **626** of a 1,000 sample |
| `domain/product` | **39** of the same sample |
| PRs carrying the net-issue-flow override | **98** |

## Diagnosis: this is not tech debt

Tech debt is the cost of shortcuts taken. This is **audit exhaust** — the
byproduct of running adversarial review agents over the project's own
verification machinery. Representative open titles:

- "guard checks assertion SHAPE, not that a rehearsal passed"
- "the live-arm ledger records reachability, not emission"
- "guards that infer state from content fire on documentation about themselves"

These are findings about the *guards*, not about anything a user of Soleur
receives. That is why `domain/product` is 39 and `domain/engineering` is 626.

## Why it compounds (four mechanisms, all structural)

1. **Cost asymmetry ~3 orders of magnitude.** Filing is one `gh issue create`.
   Closing is plan -> work -> review -> ship.
2. **The drain is also a source.** Every closing PR runs the same review
   pipeline over itself and files new findings.
3. **The gate cannot drain.** `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`
   is real and blocking (exit 1 when NET > 0), but it is **per-PR net-zero**.
   Perfectly enforced it holds 1,456 forever. It also fails open on API error
   (deliberately, with telemetry) and has been overridden 98 times.
4. **Some filings are mandated.** `wg-block-pr-ready-on-undeferred-operator-steps`
   carries `[mandates-filing]`, so obeying one rule forces a filing.

## What was PROVEN to work, on 2026-09-10, in PR #7990

That PR started net **+1** (closing #7931, #5806; filing #8006, #8007, #8020)
and ended net **-2** (closing #7931, #5806, #8020, #7091; filing #8006, #8007).
Three moves did it, and none required new tooling:

1. **Re-test the filing decision against MEASURED size.** #8020 was deferred as
   "a separate change with its own blast radius". Measured: **19 lines, 1 file** —
   inside the existing `<=100 lines / <=4 files` inline threshold. The rule was
   already correct; it was applied to an estimate instead of a measurement.
2. **Derive inputs instead of inventing them.** The stated blocker was "choosing
   19 timeout values". Ten successful `main` runs gave every job's real duration
   (all under 4.2m against a 360m default) in about two minutes.
3. **Check whether OPEN issues are already closed by the work in hand.** #7091
   described exactly the failure #5806 removes. It cost one verification pass
   and one comment, and closed a 6-week-old issue with zero code.

**Generalisation:** the filing decision is usually wrong on *measurement*, not on
judgment. A pre-filing gate that forces "measure the fix size and check whether
the inputs are derivable" is cheap and would have caught this one.

## The four levers, in priority order

1. **Separate the ledgers.** Findings about Soleur's own verification machinery
   are not user issues. They need a distinct store, or a label excluded from
   every user-facing view and from `/drain`'s default scope. Today they are
   indistinguishable, which is why the 39 product issues are invisible.
   *This is first because it makes the other three measurable.*
2. **Move the lever to filing time.** Require a named user-visible consequence
   before filing. "The guard is imperfect" does not qualify. Add the
   measure-the-fix-size check from the section above.
3. **Expire by default.** 841 items >60d, 330 never touched. Auto-close
   guard-imperfection findings after ~90 quiet days with a note. Highest volume,
   lowest risk, fully automatable, needs no judgment.
4. **Make the gate net-NEGATIVE on a cadence.** Per-PR net-zero preserves the
   backlog; a weekly closing budget drains it. Consider making `/drain` scheduled
   rather than operator-invoked.

## Open questions for the operator (needed before lever 1)

1. **Where do machinery findings go?** A separate repo/project, a label, or
   `knowledge-base/` as a rolling audit log rather than issues at all?
2. **Is auto-expiry acceptable at 90 days**, and does it apply to
   `domain/engineering` only, or to any zero-comment issue?
3. **Does the drain get a budget?** e.g. "one `/drain` run per week, closing >= 20"
   — this is the only lever that reduces rather than holds.

## Do NOT

- Do not file an issue for this work. That would be the defect demonstrating
  itself. Carry it in a plan or this prompt.
- Do not mass-close without reading. 330 zero-comment issues include real ones —
  #7091 sat untouched for 6 weeks and was legitimate.
