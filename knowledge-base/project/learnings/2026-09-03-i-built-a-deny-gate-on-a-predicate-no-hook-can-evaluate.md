---
title: I built a deny gate on a predicate no hook can evaluate
date: 2026-09-03
category: workflow-issues
module: hooks, monitor, ship
issues: [7585]
pr: 7760
tags: [hooks, monitor-lifetime, deny-vs-report, mutation-testing, equivalent-mutants, vacuity, self-matching-probe]
---

# Learning: I built a deny gate on a predicate no hook can evaluate

## Problem

A session ran **three** monitors against `gh pr checks 7753` at once. Each re-scope of what
needed watching armed a new monitor and left the previous one running. The operator noticed;
no gate did. So I wrote a PreToolUse hook to deny the second arm.

The hook's central conjunct was *"the prior arm is still live"*. **A hook cannot evaluate that**,
and I shipped two versions before measuring it.

### Route 1 — infer liveness from the clock

A hook sees `Monitor` arms and `TaskStop`s. It never sees a completion. Monitors mostly end by
**early exit** (the poll loop breaks when the watched state goes terminal) or by **harness reap**
— neither writes a stop record. So "inside its declared `timeout_ms`" is not liveness; it is
*recency wearing liveness' name*, and the gap between them is most of a monitor's life.

The consequence was not theoretical. `ship` Phase 7 polls a PR, pushes a fix, and re-polls the
same PR: same session, same signature, well inside the window. The gate denied the pipeline's own
documented recovery path.

My first patch was a `LIVE_FRACTION` of 50% — deny only in the early part of the window, on the
observation that real layering happens fast. That is a true observation and it made the gate
quieter, but it does not make an unmeasurable predicate measurable. **Tuning a threshold on the
wrong variable buys silence, not correctness.**

### Route 2 — measure liveness from the process table

`pgrep -f <signature>` looks like the honest fix: stop inferring, go look. It is contaminated at
the source. The agent's own Bash commands routinely carry the PR number, so the probe matches
**the very command asking the question**. The control proved it — a probe for a signature with no
monitor running at all returned a hit:

```
$ pgrep -af '9999999'
2495164 /bin/bash -c ... pgrep -af '9999999' ...   # its own shell
```

This is the second self-matching-probe defect in one session; the first killed my own shell with
`pkill -f` matching its own command line. **A probe whose pattern appears in the probe is a
mirror, not a measurement.**

## Solution

Replace the deny with a `systemMessage` notice naming the prior arm, its age, and the remedy.
Delete `LIVE_FRACTION` and the `# gate-override:` marker — with nothing blocking there is nothing
to tune and nothing to escape.

The asymmetry is the whole argument. The audience for this hook is **an agent that reads tool
output**, so a message at the moment of the arm does the same work as a block. Only the block can
wedge a pipeline. A false notice costs a paragraph; the false deny cost a ship run.

`systemMessage` is the specific mechanism because Claude Code **discards a PreToolUse hook's
stderr on exit 0** — a stderr-only notice reaches nobody. `pre-merge-auto-close-scan.sh` had
already established that channel; I found it by looking for precedent instead of inventing one.

## Key Insight

**A gate whose central predicate is unmeasurable must not deny — and "unmeasurable" is a claim to
test, not to assume in either direction.** I assumed it was measurable (twice), then assumed
process inspection would settle it. Both took minutes to falsify. The order that works: name the
predicate, name the command that would evaluate it, run that command, *then* choose the
enforcement tier.

Corollary for enforcement generally: the repo's hierarchy is hook > skill instruction > prose,
and it is easy to read that as "always reach for the hook". The hierarchy ranks *strength*, not
*correctness*. When the predicate is soft, a hook that **reports** sits above a prose rule and
below a deny — and it is a real rung, not a consolation prize.

### Two fixes for one bug make each other's mutants survive

The mutation battery over three fixes returned `SURVIVED F2`. The reflex reading is "the guard is
untested". The actual reading needed one more question — *which of the two fixes does the test
reach?* Bug 2 had been fixed at both **write time** (`tr -d '\n\t'` on the description) and
**read time** (`head -1` before `cut`). The test drove the write path, so reverting the read-time
guard changed nothing.

Both readings existed and they resolve differently:

| Mutant | Reading | Resolution |
|---|---|---|
| read-time `head -1` | **fixture-inadequate** — no case could produce a poisoned record through the fixed hook | new case injects the record directly, as an older hook version would have written it |
| write-time `tr -d` | **genuinely equivalent** — `jq --arg` escapes the newline either way, so no verdict changes | recorded at the site with the proof; it affects message text, not the crash |

**When one bug gets two fixes, a surviving mutant is a question about test reach before it is a
question about the guard.**

### A fixture that reproduces the wrong failure passes for the right reason

My first attempt at the poisoned-record case used `printf` with `\n`, which put a **raw** newline
inside the JSON string — invalid JSON. The per-line parser correctly skipped it, so the case
exercised bug 1's fix and said nothing about bug 3's. It failed against the unmutated hook, which
is the only reason I looked. Had it passed, I would have shipped a case whose name described a
property it never touched.

## Session Errors

- **Shipped a deny gate on an unmeasurable predicate, then tuned it instead of re-deriving it.**
  Recovery: measured both evaluation routes and downgraded to a report. **Prevention:** before
  choosing `deny`, name the command that evaluates the gate's central conjunct and run it; if no
  such command exists, the tier is `report`.
- **Self-matching process probe** (`pgrep -f` matched its own shell); second instance this session
  after `pkill -f`. Recovery: control probe on a signature with no monitor. **Prevention:** any
  probe over a process table needs a negative control before its result is believed.
- **Fixture reproduced a different failure than the one it was named for** (raw vs escaped newline
  in JSON). **Prevention:** run every new regression case against the *unmutated* code first — a
  case that cannot fail before the fix is not a regression case.
- **The suite wrote four rows per run into the operator's real `.rule-incidents.jsonl`.** Recovery:
  pointed `CLAUDE_PROJECT_DIR` at a fixture root; verified a 0-line delta. Same class as
  [the deviation-ledger learning](2026-09-03-the-deviation-ledger-was-an-hour-of-my-own-test-fixtures.md),
  found independently.
- **Advertised a `ws://` signature form in the hook header with no test case.** **Prevention:**
  every capability a header enumerates needs a case, or the header is a claim.
- **Read a guard's `PASS` as coverage of my file.** `guard-vacuity-floor` excludes
  `.claude/hooks/` via `COVERED_DIRS` *and* does not recognise the `-ne` floor shape — two
  independent reasons it never examined my floor. Recorded on #7585. **Prevention:** before citing
  a guard as evidence, confirm your file is in its scope.

## Measurements

| Fact | Value |
|---|---|
| Monitors layered on one endpoint in the incident | 3 |
| Routes to evaluate "still live", both falsified | 2 |
| Time to falsify the process-probe route | one control command |
| Silent-disable bugs in the first hook version | 3 |
| Cases at the end (from 15) | 22 |
| Mutants surviving after resolution | 1, recorded as equivalent with proof |
| Tracked `*.test.sh` files vs directories the vacuity guard covers | 381 vs 2 |

## Related

- [The deviation ledger was an hour of my own test fixtures](2026-09-03-the-deviation-ledger-was-an-hour-of-my-own-test-fixtures.md) — same-day, independent: hook suites polluting the real incident ledger.
- #7585 — `guard-vacuity-floor` has no per-file promotion seam; `.claude/hooks/` measurement added there.
- `hr-monitor-not-run-in-background-for-polling` — governs *which* tool polls; this hook governs the tool's *lifetime*.
