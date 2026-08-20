---
module: git-data rehearsal harness
date: 2026-08-16
problem_type: test_failure
component: shell_script
symptoms:
  - "T5 MUTATION: without set -e the chain still did not reach chmod — T5's check is vacuous"
  - "S1 MUTATION: S1 is no longer reproducing the measured failure"
  - "a capture-integrity precondition that rc=0 plus one apt warning line defeats"
root_cause: unverified_inherited_claim
severity: high
tags: [assert-vs-measure, mutation-testing, stale-inherited-number, guard-vacuity, set-e, concur-gate]
synced_to: [work]
related: [7291, 7510, 7565, 7572, 7574, 7501, 7535, 7540]
---

# Every number I inherited was stale, and the panel found the defect class inside my own fix

## Problem

`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` guards a supply-chain property: a wrong
`DOPPLER_SHA256` must abort the runcmd chain before an unverified tarball is `chmod +x`'d and run as
root on the host storing users' bare git repos. Its T5 **mutation** arm proves the `CHMOD_RAN`
marker is *reachable*, so the primary arm's green means "the abort happened" rather than "nothing
ever prints".

That arm's design comment stated its premise: *"curl SUCCEEDS (real network, genuine tarball), so
the checksum is the ONLY thing that can stop the chain."* Under a degraded network the chain aborts
**earlier**, `CHMOD_RAN` never prints, and the arm reported itself vacuous — a false FAIL on a
required check (#7291).

The fix was small and the verification was not. What makes this worth writing down is not the fix.

## Solution

The arm gained a third verdict, reachable only past a capture-integrity precondition and a
deterministic-fixture test, plus a counted ceiling and a floor that includes declared skips. The
mechanism is recorded in ADR-188. Verified on final bytes: control `47 passed, 0 failed, Skipped: 0`
(rc 0); skip path `46 passed, 0 failed, Skipped: 1` (rc 0) with the degraded-run NOTE.

## Key Insight

**Every substantive defect in this session — including the P1 a review panel found inside the fix —
was an inherited claim I never re-derived.** Not one required new information to catch. Each was
falsifiable by a command I could have run in seconds and did not, because the claim arrived already
looking established.

| Inherited claim | Source | Reality | Cost of checking |
|---|---|---|---|
| "4 of 6 arms discard rc, including R4" | my own plan | **2** — R4's capture landed in #7501 after the plan was written | one `grep` |
| "`git-data-emit.test.sh` carries the identical floor, so a count alone does not identify the suite" | my own plan | false twice: each line already opens with its own suite name, **and** the floors had diverged 44 vs 45 | one `grep` |
| "ADR-186 is free across all 67 origin refs" | my own plan-time check | taken by an unrelated PR before implementation | one `git ls-tree` |
| floor `45` written as a literal | my own implementation | #7501 moved main's base 44 → 46 mid-session | `git show origin/main:<file>` |
| "#7507 touches my ADR, plan and spec" | my own **two-dot** `git diff HEAD..origin/main` | it touches none of them — two-dot lists the symmetric difference, so my own files appeared | use three-dot |
| commit subject *"correct the ADR's axis"* | my own commit | it corrected the ADR and left the in-file B5 block stating the refuted axis | read the diff |

The sharpest instance was in the fix itself. My capture-integrity precondition read:

```bash
if [ "$_t5m_rc" -eq 0 ] && [ ! -s "$TMP/out/stdout" ]; then   # harness defect
```

It tests **file emptiness**. But `2>&1` merges stderr into that capture, so `rc=0` plus a single
`WARNING: apt does not have a stable CLI` line defeats it and the run falls through to a SKIP — a
container reporting *success* with no execution marker, silently classified as an environment
problem. Measured by `test-design-reviewer`: one byte from never firing. My own matrix row 5 had to
synthesize an exactly-empty capture to reach it at all, which is the tell — a fixture built to hit
the branch rather than a branch built to catch the input.

Gating on **marker absence** subsumes emptiness and closes it:

```bash
if [ "$_t5m_rc" -eq 0 ] && ! grep -q "$_T5_MARKER" "$TMP/out/stdout" 2>/dev/null; then
```

The PR existed to stop a missing signal being read as a verdict. Its own precondition read a
missing signal as a verdict.

### A shell fact worth carrying

`set -e` does **not** fire on a failing **non-final** member of an AND-OR list. Measured:

```
$ bash -c 'set -e; sh -c "exit 100" && true; echo reached'
reached
```

So `apt-get update && apt-get install …` let a failed *update* fall through into the driver with no
python3/curl, the capture server could not bind, and the arm emitted a `FIXTURE:` **hard FAIL
asserting a deterministic fixture defect that had not occurred** — #7291's own defect, half-fixed,
now naming an unmeasured cause. Split into two statements, either failure aborts with its own rc.

### Two agent remedies would have reverted the fix

Both diagnoses were correct and both prescriptions were destructive:

1. *"Widen the capture-integrity precondition to fire regardless of rc"* — matrix row 2, the only
   real skip, recorded `rc=100` with an **empty** capture. Widening turns it back into the false
   FAIL.
2. *"Reserve the skip for stdout that positively shows the driver started"* — marker-present without
   `CHMOD_RAN` **is** the genuine-vacuity FAIL.

A finding is a hypothesis with evidence attached. Trace the prescription against the recorded
verdicts before applying it.

### The CONCUR gate earned its cost twice

Round 1 killed `cross-cutting-refactor` (the callsites live in *the file the linked issue names*, so
"≥3 materially unrelated files" is definitionally unmet). Round 2 killed the replacement
`pre-existing-unrelated` on the gate's own sibling-asymmetry bullet: `arm_skip`,
`SKIPPED_ASSERTIONS` and `_SKIP_CEILING` have **zero** occurrences on `main`, so the asymmetry
between T5-has-it and the sibling arms is *created by this PR*. Verified before accepting.

Net effect: six proposed tracker rows became **three filings and three resolved decisions** — the
`-ne` floor and the `INCONCLUSIVE` rename rejected with reasons recorded in the code and the ADR
rather than deferred into a backlog.

Symmetrically, the gate's own "530 added lines, out-of-scope AC15/TMPDIR/forensics additions" rested
on #7501's diff counted as mine (real: 232 insertions). It withdrew that on re-derivation. **Both
sides of a review can inherit a stale number; both should re-measure before restating.**

## Prevention

- **Before implementing any plan-quoted number or premise, run the command that would falsify it.**
  The plan is authoritative for *intent*, never for counts, paths, ordinals or premises. A plan
  written days or hours earlier observes a moving target.
- **Write floors and budgets as deltas from a measured base, not literals.** `main + 1` survives a
  sibling PR moving the base; `47` does not. This one moved twice in a day.
- **Three-dot for "what did I change", two-dot never.** `git diff A..B` lists the symmetric
  difference, so your own files appear as if the other side touched them.
- **Re-derive a provisional ordinal against freshly fetched refs immediately before merge**, not at
  plan time. ADR-186 was free at plan time and taken by implementation.
- **When a check's fixture had to be synthesized to reach the branch, ask what real input reaches
  it.** If the answer is "almost none", the predicate is wrong, not the fixture.
- **Read your own commit subject against your own diff** before pushing.

## Session Errors

**Planning subagent killed by the stream watchdog before emitting its Session Summary** — Recovery:
the skill's plan-artifact-recovery block; the `## Acceptance Criteria` predicate was present, so
planning had finished and only the emission was lost; planning was NOT re-invoked. — **Prevention:**
bound a delegate's read scope; the wide-read shape is what stalls.

**Three review agents stalled identically at "I'll start by reading the file"** — Recovery: resumed
(not respawned) with exact line ranges and one-item-at-a-time reporting. — **Prevention:** never
hand an agent a 1500-line file with a multi-part brief; scope to ranges and stage the reporting.

**`pkill -f 'scratchpad/orchestrate.sh'` matched its own command line and killed my shell** (exit
144) — Recovery: re-ran with a bracketed pattern (`'[o]rchestrate\.sh'`). — **Prevention:** already
a documented trap; bracket the first character of every `pkill -f` pattern, always.

**A monitor gate required zero foreign runners on a box running 17 sessions** — a gate that could
never open, which is a stall dressed as a safety property. — **Prevention:** gate on the resource
that actually causes the failure (load, container count), not on the existence of other processes.

**`tail -f` held a deleted inode after I recreated the log** — the monitor would have stayed silent
through the entire run, and silence is indistinguishable from "still running". — **Prevention:**
`tail -F` whenever the watched file can be recreated.

**Quoted "4 of 6 arms discard rc" from my own plan while correcting a reviewer for a stale count** —
Recovery: re-measured (2). — **Prevention:** the rule applies to your own artifacts first.

**Commit subject claimed an axis correction the commit did not make** — Recovery: fixed in the next
commit. — **Prevention:** grep the diff for the thing the subject claims.

**`git commit -m` with embedded double quotes broke shell parsing** — Recovery: `--file`. —
**Prevention:** always `--file` for multi-paragraph messages; the backtick trap has a quote sibling.

**A Python edit script with a malformed tuple threw before writing, applying nothing** — Recovery:
the per-edit asserts made the miss loud. — **Prevention:** keep assert-once semantics; a silent
no-op edit is worse than a crash.

**My own AC15 checker matched the file's own prohibition comment** (`cq-assert-anchor-not-bare-token`
committed by the checker) — Recovery: confirmed pre-existing on main and outside the diff. —
**Prevention:** anchor a checker on syntax a comment cannot produce.

**Mutation-harness anchors went stale after my own edits and two rebases** (rows 2, 5, 6) —
Recovery: the harness asserted rather than silently no-opping, so each was caught and fixed. —
**Prevention:** re-run the harness's dry-verify after every edit to the SUT.

**Ended a turn on "still to settle" instead of settling it** — the operator had to prompt. —
**Prevention:** a forward-looking sentence is not a handoff; the next tool call in the same turn
must be the successor step.

### The remaining eight, recorded here for completeness

These are the session's other errors. They are not restated in prose because each is the *subject*
of a section above — duplicating them would create two copies that can drift.

| Error | Where it is analysed | Prevention |
|---|---|---|
| Quoted a stale rc count from my own plan | Key Insight table, row 1 | run the falsifying command before quoting a plan number |
| Built `_suite_rel` on a plan premise that was false twice over | Key Insight table, row 2 | check the premise, not just the instruction |
| ADR ordinal free at plan time, taken at implementation | Key Insight table, row 3 | re-derive against fetched refs immediately before merge |
| Floor written as a literal `45`; base moved to 46 | Key Insight table, row 4 | write budgets as deltas from a measured base |
| Two-dot `git diff` misread as a sibling collision | Key Insight table, row 5 | three-dot for "what did I change" |
| Capture-integrity tested emptiness, not marker absence (the P1) | Key Insight, "The sharpest instance" | if the fixture had to be synthesized to reach the branch, the predicate is wrong |
| Did not know `set -e` skips non-final AND-OR members | Key Insight, "A shell fact worth carrying" | measure the shell's behaviour rather than assuming it |
| Claimed the wrong scope-out criterion twice | Key Insight, "The CONCUR gate earned its cost twice" | quote the criterion verbatim and count the files before claiming it |

## Cross-references

- `2026-08-11-i-measured-the-issues-remedy-then-asserted-my-own-without-measuring.md` — the same
  class, one level up: measuring an issue's proposed remedy and then asserting your own.
- `2026-08-13-the-guards-i-wrote-to-prove-the-fixes-had-the-defects-the-fixes-were-about.md` — the
  fix-contains-its-own-class shape.
- `2026-08-13-a-lower-bound-cannot-tell-a-measurement-from-a-constant.md` — floors and what they
  can and cannot detect.
- ADR-188 — the verdict taxonomy and its two accepted residuals.
- #7565 (P1, vacuous PASS with the checksum never evaluated), #7572 (the S1 instance), #7574
  (persistence bound), #7535 (pre-baked image, sibling session).

---

## Sequel — 2026-08-19 (the rebase onto #7565, PR #7510)

This branch was rebased onto #7567 (closing #7565), which had merged into the same function, and a
7-agent panel reviewed the composition. The defect class named above — asserting an inherited claim
instead of re-measuring it — recurred in four new shapes, all in prose or code this branch authored:

- The header's "WHAT THIS DOES NOT CLOSE" paragraph asserted a hole #7565 had already closed.
- The rung-reorder justification asserted a state that cannot occur, contradicting a note 25 lines
  above it in the same file.
- A retracted universal survived at the third of three sites, one commit after the retraction.
- A commit deleted a mechanism and left the sentence describing it.

And the instrument built to catch the rebase's own losses had the blind spot it was built for.
Full account, with the mechanical falsifier that found it:
[[2026-08-19-i-hardened-my-verifier-twice-and-its-sample-was-still-a-sample]]
