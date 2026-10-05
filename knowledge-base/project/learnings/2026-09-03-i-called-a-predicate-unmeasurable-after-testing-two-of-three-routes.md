---
title: I called a predicate unmeasurable after testing two of three routes
date: 2026-09-03
category: workflow-issues
module: hooks, monitor, ship
issues: [7585]
pr: 7760
tags: [hooks, monitor-lifetime, deny-vs-report, mutation-testing, equivalent-mutants, self-matching-probe, enforcement-tier]
---

# Learning: I called a predicate unmeasurable after testing two of three routes

## Problem

A session ran **three** monitors against `gh pr checks 7753` at once. Each re-scope of what
needed watching armed a new monitor and left the previous running. The operator noticed; no
gate did. So I wrote a PreToolUse hook to deny the second arm.

The hook's central conjunct was *"the prior arm is still live"*. I shipped three revisions of
it, and the interesting failure is not any one of them — it is that I wrote a document
asserting a **negative capability** and then used that assertion to justify a design.

### Route 1 — infer liveness from the clock

A hook sees `Monitor` arms and `TaskStop`s. Monitors mostly end by early exit or harness reap,
and neither writes a stop record. So "inside its declared `timeout_ms`" is not liveness; it is
*recency wearing liveness' name*. It denied `ship` Phase 7's own re-poll-after-fix path.

My first patch was a `LIVE_FRACTION` of 50%. **Tuning a threshold on the wrong variable buys
silence, not correctness** — and note the second-order error: when I later moved to a report
tier, I deleted that fraction reusing the deny-era rejection, without re-deriving it. Under a
deny, blunting a wrong predicate is unprincipled. Under a report, *quieter is the entire
remaining design problem*. The mitigation was removed exactly when it became the right tool.

### Route 2 — measure liveness from the process table

`pgrep -f <signature>` looks like the honest fix. It is contaminated at the source: the agent's
own Bash commands carry the PR number, so the probe matches **the command asking the question**.
The control proved it — a probe for a signature with no monitor at all returned a hit on its own
shell.

### Route 3 — the one I never enumerated, which works

I concluded "a hook cannot observe a monitor finishing", wrote that into four places, and
labelled it *"the load-bearing part, and the thing to re-read before anyone restores the deny."*
A review agent falsified it in one pass, and I confirmed it by measurement:

- `transcript_path` is in every hook payload.
- A Monitor's PostToolUse response carries `toolUseResult.taskId`.
- A task's end is recorded as a `<status>completed</status>` notification keyed to that id.

Liveness is observable. The design conclusion (report, not deny) survived — but on a *different*
argument: the transcript's shape is an undocumented harness internal, so if it changes every task
reads not-dead, which for a report means noise and for a deny would mean blocking every re-arm in
the repo. **Fail-open is only available at the report tier.**

## Key Insight

**A negative capability claim is the most expensive kind to get wrong, because it terminates
inquiry — including your own.** "X cannot be measured" is not a finding; it is an *unfinished
search* presented as one. Mine was asserted after testing two channels of three, and its wording
actively discouraged the next reader from looking for the third.

The test is cheap and I already knew it, because I wrote it into the previous version of this
same document: *name the predicate, name the command that would evaluate it, run that command.*
I ran two. The rule needs a second half — **enumerate the channels before declaring the set
exhausted, and say how many you checked.** "I found no way to measure this" and "there is no way
to measure this" differ by exactly the work not done.

### The self-matching probe, three times in one session

`pkill -f` matched its own command line and killed my shell. `pgrep -f` matched its own shell.
Then the *transcript* probe — the fix for the first two — matched **my own command text**,
because the transcript records the agent's tool calls verbatim, so grepping for a task id and
the word "completed" finds the grep. A live monitor read as finished.

**Any probe whose pattern can appear inside the probe is a mirror, not a measurement.** The fix
is structural, not textual: filter to records that are not the agent's own (`.type != "assistant"`),
and keep a negative control — a signature with nothing running must come back empty.

### Two fixes for one bug make each other's mutants survive

A mutation battery returned `SURVIVED`. The reflex reading is "untested guard". The real question
is *which of the two fixes does the test reach?* One bug had been fixed at both write time and
read time; the test drove the write path only.

| Mutant | Reading | Resolution |
|---|---|---|
| read-time guard | **fixture-inadequate** — no case could produce the poisoned input through the fixed code | inject the record directly, as an older version would have written it |
| write-time guard | **genuinely equivalent** — no verdict changes | recorded at the site with the proof |

### A claim and its test, written together, agree with each other

The hook documented "a torn line costs one record, not the whole gate", and a case asserted it
with the fixture `CORRUPT NOT JSON`. Both were right about *unparseable* lines and blind to
lines that **parse to the wrong type**: a bare `12345` cleared `fromjson?` and then killed the
next stage, disarming the gate permanently and silently. A disarmed report gate is
indistinguishable from a quiet session, so nothing would ever have surfaced it.

**When the same author writes a claim and the case that checks it in one sitting, the case
inherits the claim's blind spot.** The four one-line fixtures that would have caught this
(`12345`, `"hello"`, `[1,2,3]`, a string `ts`) are now cases.

### Scoping a battery narrowly is fine; describing it broadly is not

A previous version of this file reported **"mutants surviving after resolution: 1"**. That was
true of the battery I ran, which covered three bug-fixes. A review panel found **nine** survivors
across the hook's load-bearing predicates. The measurement was honest and the sentence was not:
state what a battery covered, not just what it found.

## Solution

Split into a PostToolUse recorder that captures the task id and a PreToolUse reporter that reads
it. That single change resolved four findings at once, which is the sign the earlier design was
fighting its own shape: exact liveness (route 3), exact per-task stop records (complying with the
notice no longer blinds the session), an actionable remedy (`TaskStop <id>` instead of "the prior
one"), and silence on the dominant false-positive case (an early-exited monitor now reads dead).

## Session Errors

- **Asserted a negative capability after a partial search, and wrote it into four files.**
  **Prevention:** enumerate the channels, state how many were checked, and never phrase a
  not-found as a cannot-exist.
- **Re-used a deny-era rejection to justify a report-era deletion.** **Prevention:** when the
  enforcement tier changes, re-derive every decision the old tier justified — they can flip sign.
- **Third self-matching probe of the session.** **Prevention:** negative control before belief.
- **Shipped a corruption claim whose own test shared its blind spot.** **Prevention:** for a
  robustness claim, enumerate the input *classes* (unparseable / wrong-type / wrong-shape),
  not one example.
- **Broke a script with an apostrophe in a comment.** The comment went inside a single-quoted
  `jq` program, so `sink's` closed the program and bash parsed the rest as shell. **Prevention:**
  when commenting inside a quoted heredoc or program string, run `bash -n` before believing it.
- **Re-polluted the operator's incident ledger while fixing pollution.** Switching to
  `BASH_SOURCE`-relative sourcing bypassed the `CLAUDE_PROJECT_DIR` redirect, because
  `_incidents_repo_root()` does not read that variable — `INCIDENTS_REPO_ROOT` is the override.
  19 rows leaked. **Prevention:** assert a zero-line delta on the real sink as a test case, not
  as a one-off check.
- **Read a guard's `PASS` as coverage of my file.** `guard-vacuity-floor` skipped it on two
  independent counts: `.claude/hooks/` is outside `COVERED_DIRS`, and the `-ne` floor shape is
  not one it matches. **Prevention:** before citing a guard as evidence, confirm your file is in
  its population.

## Measurements

| Fact | Value |
|---|---|
| Monitors layered on one endpoint in the incident | 3 |
| Routes to evaluate "still live": claimed exhausted / actually enumerated | 2 / 3 |
| Places the false negative-capability claim was written | 4 |
| Self-matching probes in one session | 3 |
| Silent-disable defects in the hook, across revisions | 4 |
| Mutants surviving the original 3-fix battery / found by the panel | 1 / 9 |
| Cases, before the rebuild and after | 22 / 30 |
| Real Monitor commands yielding an extractable signature | 21.4% |

## Related

- [The deviation ledger was an hour of my own test fixtures](2026-09-03-the-deviation-ledger-was-an-hour-of-my-own-test-fixtures.md) — same-day, independent: hook suites polluting the real incident ledger.
- #7585 — `guard-vacuity-floor` scope; the `.claude/hooks/` measurement is recorded there.
- `hr-monitor-not-run-in-background-for-polling` — governs *which* tool polls; this pair governs the tool's *lifetime*.
