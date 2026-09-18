---
title: "Every defect was in my verification, not the feature — and the probe that falsified the plan cost four minutes"
date: 2026-09-18
category: workflow-patterns
tags: [compaction, hooks, mutation-testing, verification, review, ci, plugin-scope, prompt-injection]
issue: 8323
pr: 8320
branch: feat-compaction-aware-session-hooks
---

# Learning: every defect was in my verification, not the feature

## Problem

Shipping a compaction-aware session hook (#8323). The feature itself is ~200 lines of
bash. Across a two-lens design pass, a ten-seat review panel and two CTO rulings, the
panel found roughly thirty findings. **Almost none were in the feature.** They were in
the Phase 0 probe's conclusions, in the guards I wrote to protect the feature, in the
tests I wrote to prove the guards, and in the records I wrote to describe all three.

## Solution

### 1. Probe the WRITE ORDERING, not just the record's existence

The plan's whole design was "read the compaction count from the session transcript at
`SessionStart:compact`". A blocking Phase 0 probe measured that the just-fired
`compact_boundary` is **not on disk** at that moment — twice (0-of-1, then 1-of-2). The
record's own `timestamp` *precedes* the hook fire, so it exists in memory and flushes
after the hook returns. Separately, `PreCompact` fires on **no-op** compactions (3 fires,
2 boundaries), so counting those over-counts.

The probe needed no operator step: a scratch project under `/var/tmp` with its own
`.claude/settings.json` binding a marker hook, driven by
`claude -p --continue "/compact" --model haiku`. Four minutes, and it falsified the
design before a line of it was written.

**Generalizable:** when a design depends on a harness having *written* something by the
time a hook fires, treat the write ORDERING as a claim separate from the record's
existence, and probe it. "The record exists and has the right shape" and "the record is
readable at the instant I need it" are different properties, and only the second one
matters to a hook.

### 2. A surviving mutant on an operand has TWO causes

A mutation showed the `trigger == "auto"` conjunct in `trigger == auto AND count_auto >= N`
was untested. I assumed weak tests and wrote the killing test. The CTO ruled the operand
out entirely: `count_auto` rises only on a committed `auto` line, so the first crossing
always had `trigger=auto` and fired either way — the conjunct's only behavioural delta
was **retracting** a recommendation already issued, at the moment the model could least
reconstruct it.

Writing the killing test promoted an accidental behaviour to a specified one.

**Rule: when a mutant survives on an operand, try DELETING the operand first. Only write
the killing test if deletion changes behaviour you can defend.**

### 3. The assertion helper is the layer no control sees

> **This class recurred on the SAME DAY in an independent session.** PR #8272's
> nine-seat review found the identical shape — `expect()`, `assert()` and
> `assert_emit()` are *verdict-owning* helpers, and that suite's positive control
> also drove `pass()`/`fail()`, proving dispatch while the deciders decided
> nothing. See
> `knowledge-base/project/learnings/2026-09-18-every-p1-was-in-my-verification-and-a-failed-edit-batch-looks-exactly-like-a-landed-one.md`.
> Two independent measurements of one class in one day is a **propagation
> failure**, not two defects: `scripts/guard-vacuity-floor.test.sh` (ADR-193)
> already walks every suite for floors that dispatch through `fail()`, and it
> does not model a helper that keeps the counters honest while discarding the
> condition. Escalated to a mechanical gate rather than a third write-up.


The suite had an instrument self-test that drove `pass()` and `fail()` and reconciled
three counters. It could never see `assert()` — the only layer that *adjudicates* — because
it bypassed it. Measured: replacing `assert()`'s body with `eval "$2" >/dev/null 2>&1;
pass "$1"` reported **115 passed, 0 failed, ALL TESTS PASSED** with every row asserting
nothing.

Two things made it invisible: the self-test bypassed the helper, and `CASES` was
incremented **inside** `assert()` on the line above the verdict — so neutering the verdict
while keeping the increment let `MIN_CASES` reconcile exactly.

Fix: give `assert()` a two-directional control, and add a conservation check
(`passes + fails == CASES`) reported with `printf` + `exit` rather than through the
helpers it backstops. It immediately caught a real divergence-by-one from a
double-increment.

**And my first attempt at that fix was wrong in a way the repo's own gate already
forbids.** I moved the `CASES` increment *into* `pass()`/`fail()`, reasoning that a
counter above the verdict is what lets a gutted dispatcher reconcile the floor. That is
true, and it makes the conservation identity **tautological** — `passes + fails == CASES`
cannot fail when every increment happens inside the two helpers being summed.
`scripts/guard-vacuity-floor.test.sh` asserts exactly this ("no CASE counter is
incremented inside a verdict helper"). The counter belongs in the **dispatcher**; the hole
it leaves is closed by the *control*, not by relocating the counter. Both properties then
hold at once, verified: the identity is non-tautological, and the gutted-`assert()` mutant
still dies.

The generalisable half: when you fix a vacuity by moving a counter, check what the move
does to every *other* invariant reading that counter. I traded a detectable hole for an
undetectable one and would have shipped it if the gate had not already encoded the rule.

### 4. Run every suite under the environment it SHIPS into

Assertion `14g` pinned the literal branch name. CI checks out a **detached HEAD** on
`pull_request`, where `git rev-parse --abbrev-ref HEAD` returns the string `HEAD`, no plan
glob matches, and the branch name appears nowhere. Measured from a detached worktree:
**109 passed, 1 failed**. Green for me, red on the required check.

The hook had the same defect one level down — it asserted `Branch: HEAD.` to the model.
The repo's own precedent (`ship-unpushed-commits-gate.sh`) uses
`symbolic-ref --short -q HEAD`, which exits non-zero on detach so a fallback works.

Two rows I added *in the same round* repeated the coupling and were caught only by
re-running detached.

### 5. A guard added at review is as unpinned as the blind spot it closed

Every hardening this session — the symlink refusal, `umask 077`, the lossy-session-id
refusal, `sanitize_display`, the threshold sanitizer, the pending clear on reset — was
deletable with the whole suite green. As one seat put it: *the hardening reflex is strong
here, the accompanying-row reflex is not.* A review-driven fix is written after the tests
and nothing forces coverage for it.

### 6. A snippet is not the subject

I measured the `set -u` exit code with `bash -c 'set -uo pipefail; trap "exit 0" ERR;
printf "%s" "$nope"'` and got **127**, twice, and wrote it into two records. Measured on
the actual hook through its own seam: **1**. A `bash -c` whose fault is the last statement
exits 127; a script with statements after it exits 1. The conclusion (the `EXIT` arm is
load-bearing) was right both times; the evidence cited for it was wrong both times.

### 7. A deletion round must sweep §Verification and ticked checkboxes SPECIFICALLY

Nine of seventeen code-quality findings were in one of those two surfaces. They are where
a deletion is least likely to be swept and most likely to be believed, because they assert
**delivery** rather than intent — `- [x]` and "evidence:" are read as facts. My deletion
round landed perfectly in the code and left the ADR's §Verification citing a deleted
canary's "four driven arms" eleven lines above the amendment recording its deletion.

### 8. A scope guard can be too narrow and too wide at once

Two seats hit the same predicate from opposite directions and both were right. Requiring a
`plugins/soleur` directory excluded **every marketplace install** (`claude plugin install`
puts the plugin under `~/.claude/plugins`, never in the user's repo), while remaining
forgeable by any repo that ships two directories. The CTO ruled: gate on the Soleur
artifact alone, and state in the ADR that this is **relevance control, not a security
boundary** — no cheap filesystem predicate can distinguish "my project" from "a clone that
looks like one", and the platform baseline already exceeds it because `CLAUDE.md` reaches
the model unconditionally with no guard at all.

The merge-blocking part was the *combination*: shipping the narrow guard alongside this
PR's retirement of the unconditional `/clear` prose would have removed working advice from
a population the feature could not serve.

## Key Insight

**The feature is the part you think about; the verification is the part you write while
thinking about the feature.** That asymmetry is why nearly every defect this session lived
in a guard, a test, a floor, or a record — each written fast, immediately after the real
work, under the belief that it was bookkeeping rather than authorship.

Three habits follow, and they are cheap:

1. **Grade a fix's new assertions before its new code.** On a fix PR the assertions
   inherit the defect's framing — they pin the shape of the bug rather than the property.
2. **Mutate every guard you add, in the same commit.** If reverting it leaves the suite
   green, it pins nothing, and you will believe it does.
3. **Run the suite in the environment it ships into, not the one you develop in.** A
   pass-count delta between environments is a finding, not noise.

And one about instruments: **verify the instrument against a known answer before reading
its verdict.** Six separate measurements I took to check my own work this session were
themselves wrong, each producing a confident answer rather than an error.

## Session Errors

1. **Applied fixes to the worktree while ten report-only agents were reading it.** The
   review skill's own sharp edge forbids this at panel scale; two seats reported the tree
   shifting under them and one had to re-run its battery. Recovery: none possible
   mid-flight; the reports were reconciled against HEAD afterwards.
   **Prevention:** spawn the panel, then do NOTHING to the tree until every seat returns.
   The sharp edge says "report-only" — that constrains the agents; it also has to
   constrain the lead.

2. **Recalibrated an assertion-count floor after a drop without checking which case
   dropped.** A scenario-17 rewrite sliced up to the scenario-18 anchor and silently took
   scenario 19 with it; I attributed the whole drop to a scenario I had deleted
   deliberately. The CTO found the absence. Recovery: restored scenario 19 (inverted, per
   the ruling). **Prevention:** diff per-case verdicts across runs, never totals — a floor
   tells you a count moved, never which member left.

3. **Measured an exit code with a `bash -c` one-liner instead of the subject, twice, and
   wrote the wrong value into two records.** Recovery: re-measured on the hook through its
   own seam (1, not 127) and corrected the ADR and tasks.md with the reason.
   **Prevention:** when a record will carry a measured value, measure the SUBJECT. A
   snippet reproducing the mechanism is evidence about the snippet.

4. **Wrote a killing test for a surviving mutant without asking whether the operand
   deserved to exist.** Recovery: CTO ruled the operand out; the scenario was restored
   inverted as the regression test against re-introducing it. **Prevention:** see Key
   Insight — deletion first, killing test second.

5. **Shipped every review-round guard with no covering row.** Recovery: scenarios 26 and
   27 added one row per guard, each mutation-proven. **Prevention:** no new guard operand
   merges without a mutation showing which named case reds.

6. **Left §Verification sections and ticked checkboxes asserting deleted work** after the
   canary deletion. Recovery: swept indexed by CLAIM rather than by file; zero live
   references remain. **Prevention:** after any deletion round, grep the deleted names
   across §Verification sections and `- [x]` lines first, because those assert delivery.

7. **Did not run the suite under `CI=1` / `SOLEUR_SUBAGENT=1` / detached HEAD before
   review**, despite planning to. The panel found the CI-only failure.
   **Prevention:** make the environment sweep part of the Phase 2 exit, not an intention.

8. **A `git rm -rf` was blocked by the protected-path guard** because a trailing `cd` into
   the worktree sat in the same command; the guard resolved the whole command string onto
   a protected location. Recovery: split into separate calls. One-off.

9. **Broke the C4 parse twice with my own edits** — once with escaped quotes inside a
   description (the grammar has no escape), once with a python slice that ate a closing
   quote. Recovery: `regenerate-c4-model.sh` correctly REFUSED to overwrite the JSON both
   times, which is the guard working. One-off.

10. **A `grep -c "\$VAR"` check briefly read a used variable as unused** because the real
    use was `${VAR:-0}`. Recovery: grepped the bare name. One-off — but the same
    anchor-vs-token shape as the rule the repo already has.
