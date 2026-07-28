---
title: "My AC verified four paths while CI verified five, and the fifth was red"
date: 2026-07-28
category: workflow-patterns
module: qa-gates
issues: [7003, 7024]
pr: 7018
tags: [verification-scope, vacuous-ac, decision-recording, drift-guards]
---

# My AC verified four paths while CI verified five, and the fifth was red

## Problem

PR #7018 recorded two operator decisions. Its AC11 asserted the infra lint was clean, and the
recorded result was `OK: no human-run infra steps in 4 scanned file(s)` — exit 0, quoted verbatim,
with the file count deliberately asserted because the plan knew the script "drops non-existent paths
silently and still exits 0."

CI ran the same script differently:

```bash
python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main
```

The PR changed **five** documents under `SCAN_DIRS`. My AC named four. The fifth —
`session-state.md` — was **red**, and had been red since the commit that created it.

The AC was not wrong about what it measured. It measured the wrong set.

## Root cause

The plan hardened the AC against one vacuity (a typo'd path silently scanning zero files) by
pinning the file **count**. It never asked the prior question: *does the set this AC enumerates
equal the set the CI gate enumerates?* A count assertion over a hand-written path list proves the
list was fully scanned. It cannot prove the list is the right list.

The failing line is the part worth keeping. It was an Errors-log entry documenting an *earlier*
instance of this same lint firing — and it reproduced the trigger tokens verbatim in order to
explain them. The post-mortem re-committed the offence. (The linter reads raw lines; backticks are
not stripped, which its own header states.)

## Solution

Run the gate's **own invocation**, not a reconstruction of it:

```bash
# Wrong — a hand-enumerated set that can drift from the gate's set
python3 scripts/lint-infra-no-human-steps.py <path1> <path2> <path3> <path4>

# Right — the invocation CI actually runs
python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main
```

Then the count assertion becomes meaningful, because the set is derived rather than restated:
`OK: no human-run infra steps in 5 scanned file(s)`.

Fix for the offending line: reword so the prose describes the trigger without reproducing it. An
`<!-- lint-infra-ignore -->` region also clears the gate, but it suppresses rather than fixes, and
the sentence survives fine without the quoted tokens.

## Key insight

**An acceptance criterion that enumerates its own inputs is pinned to a snapshot of the work; the
CI gate is pinned to the diff. The moment those diverge, a green AC and a red gate are consistent
with each other.**

Ask of every AC that shells out to a checker: *does the scope of my command equal the scope of the
gate whose result I am claiming?* If the gate derives its input set (`--changed`, `git diff`,
`--staged`, a glob), the AC must derive it the same way. Restating the set is the same failure
class as restating a count — both replace a derivation with a transcription that goes stale.

This is the input-side twin of a class this repo already documents on the output side
(`cq-assert-anchor-not-bare-token`, and the `--state merged` collision-probe fix where a filter was
pinned in two places and disagreed).

## Three companions from the same PR

Recorded because they share one root — **asserting a property of my own work instead of deriving
it.**

1. **An option's ambiguous wording hardened into an instruction.** When putting the decision to the
   operator I wrote "the cloud-init grep is deleted", meaning the grep *of* cloud-init. Three
   artifacts downstream rendered it as "delete the cloud-init text sentinel" — pointing at the
   `${sentry_dsn}` interpolation that a *different* checklist item mandates, whose deletion would
   un-wire the DSN and recreate the exact dark-host condition the gate exists to close. A phrase
   that is merely ambiguous at decision time becomes an instruction at implementation time. When
   recording a decision, name the artifact by path or resource, never by a possessive that could
   bind to either side ("the X grep").

2. **"Strictly more precise" was a claim, and it was false.** I characterised the replacement
   mechanism as strictly more precise than the one it replaces. Two independent reviewers showed
   the replacement asserts a *different* fact, not a superset — so the old guarantee is retired,
   not absorbed. A comparative ("stricter", "strictly more", "a superset of") between two
   assertions is a claim about their extensions; verify it entails the old one before writing it
   into a mandate.

3. **Removing a drift class in one form and reintroducing it in another.** The PR's stated purpose
   included eliminating a checklist size stated as a count in three places. It did — and then
   introduced the same class as an **ordinal** (`item 7`) in four places, two of them destined for
   GitHub issue bodies where no `git grep` can ever reach them. Cite by content anchor (the item's
   title) rather than position. Fixing a drift class means asking what *else* now pins the same
   fact, not just deleting the instances you came for.

## Session Errors

- **AC verified 4 paths; CI verified 5, and the 5th was red.** Recovery: reworded the offending
  line; re-ran CI's exact invocation, green over 5. **Prevention:** the Key Insight above; routed
  to `plan/SKILL.md`.
- **"delete the cloud-init text sentinel" named the wrong artifact.** Recovery: corrected in the
  ADR, the gate header and the HOLD note, with the carve-out stated explicitly. **Prevention:**
  companion 1 above.
- **"Strictly more precise" mischaracterised the replacement in the option text.** Recovery: the
  ADR now records the retired guarantee as an accepted consequence. **Prevention:** companion 2.
- **Four passages of drafter advocacy in a PR whose stated goal was "nothing re-opens, re-weighs,
  or softens either one".** Recovery: cut; one of them re-weighed a finding from an option the
  operator did *not* pick, and one was independently proven false. **Prevention:** in a recording
  PR, every sentence is either the decision, the operator's rationale, or the accepted cost —
  anything else is advocacy, including a synthesis that merely *sounds* like summary.
- **Count mirrors removed, ordinal mirrors introduced.** Recovery: content anchors. **Prevention:**
  companion 3.
- **RELEASED message dropped its enumeration**, losing the one item the ADR says nearly shipped a
  birth. Recovery: restored count-free. **Prevention:** universal quantification replaces a *count*,
  not the *content*.
- **Wrong first hypothesis on the phase-16 flake** ("live session telemetry bleeding into the
  fixture"). Recovery: reading the fixture showed `mktemp -d` isolation; the real cause is `grep -q`
  on a pipe under `pipefail` failing OPEN on SIGPIPE. **Prevention:** read the fixture's setup before
  theorising about contamination; the failure message printed the very string it claimed was missing,
  which was the tell.
- **Full-suite `test-all.sh` exceeded the 10-minute foreground ceiling** (exit 143). Recovery:
  backgrounded with an explicit rc file + a Monitor. **Prevention:** already documented — the
  notification reports the wrapper's exit, so the rc file is the signal.
- **Push rejected non-fast-forward** after a rebase rewrote commits the draft-PR step and planning
  subagent had already pushed. Recovery: verified every remote commit was rebase-superseded, then
  `--force-with-lease`. **Prevention:** rebase before the first push, or expect the force.
- **AC9b invalidated by my own review fix.** Recovery: re-pinned to the new text with the rationale
  recorded inline. **Prevention:** amend an AC explicitly; never quietly satisfy a looser one.
- *(forwarded)* `iac-plan-write-guard` blocked the first plan write on a quoted `systemctl` string;
  `lint-infra-no-human-steps.py` failed on a Research Reconciliation row. Both resolved at plan time
  by rewording rather than by opting out of the gate.
- **Created a scratch dir inside the worktree** during a full-suite run. Recovery: removed.
  **Prevention:** session scratchpad lives outside the repo.

## Related

- `#7024` — the `grep -q`-under-`pipefail` SIGPIPE flake found by this PR's full-suite run, filed
  rather than bundled (different subsystem).
- `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`
  — the documented form of that class.
- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
  — sibling: a check that cannot fail reads identically to one that passed.
