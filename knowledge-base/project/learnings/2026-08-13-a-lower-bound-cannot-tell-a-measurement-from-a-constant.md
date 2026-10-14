---
title: "A lower bound cannot tell a measurement from a constant"
date: 2026-08-13
category: test-failures
module: scripts/lib/test-contention.sh
issue: 7484
pr: 7483
tags: [mutation-testing, vacuous-assertions, locale, set-u, fail-open, guard-contract]
---

# A lower bound cannot tell a measurement from a constant

## Problem

PR #7483 exists to replace a false claim. `tc_acquire` printed
`LOCK_CONTENDED_PROCEEDING: '<name>' still held after ${timeout_s}s` on **any** non-zero return from
`acquire_lock` — including `rc=99` for "flock(1) is not installed", where no wait occurred at all.
The duration was the budget it was handed, not the time it waited, and `work/SKILL.md` instructs an
agent to grep that line to decide whether a RED is trustworthy.

The fix measured the elapsed and printed it. It shipped with:

- RED→GREEN at every step, 95 assertions passing
- a 7-row mutation battery, each row verified RED against a green sandbox baseline with a `diff -q`
  proof the mutation landed
- two full-gate runs, `shellcheck` clean, a consumer sweep, an AC sweep with 10/10 positive hits

A four-agent review panel then found that **the PR's headline claim was pinned by nothing**.
Replacing the arithmetic with `printf '%sms' 1500` — a constant, nothing measured anywhere — left
the suite **95 passed, 0 failed**.

## Root cause

All three elapsed predicates were **lower bounds sampled on one side**:

| arm | assertion | survives a constant `1500`? |
|---|---|---|
| free lock | `after ([0-9]+)ms` — no bound at all | yes |
| contended | `>= 1000` | yes |
| slow acquire | `>= 800` | yes |

The discriminating premise — *"arm 10 takes a FREE lock, so elapsed is single-digit ms"* — existed
as a **prose comment** in the slow-acquire arm and was never an assertion. It is the missing second
side, written down and not enforced.

And the battery could not have found it. Its 7 rows all perturbed the SUT's implementation bytes
**toward small or absent** (revert the text, substitute the budget, delete the elapsed, re-bare a
guard). Nothing perturbed toward a *plausible constant*, because a constant was not a mutation I
thought of. **N rows on one axis is one row.**

The same shape, one order worse: dropping the `/ 1000` printed

```
gave up after 2010205ms of 2s
```

— a claimed 33-minute wait against a 2-second budget, in the exact line the agent grep consumes, at
full green.

## Solution

Bound every numeric predicate on **both** sides, against a value the artifact itself reports:

```bash
# contended: the banner prints its own budget — use it as the ceiling
if [[ "$cont_line" =~ gave\ up\ after\ ([0-9]+)ms\ of\ ([0-9]+)s ]]; then
  _ms="${BASH_REMATCH[1]}"; _budget="${BASH_REMATCH[2]}"
fi
(( _ms >= 1000 && _budget > 0 && _ms <= _budget * 1000 + 3000 ))

# free lock: the ceiling its own comment already claimed
(( BASH_REMATCH[1] <= 500 ))
```

No single constant satisfies `<= 500` and `>= 1000` at once, so the pair is what makes the
measurement observable.

## Key insight

**A lower bound tests that something happened. It cannot test that the something is a function of
its inputs.** Any assertion of the form `value >= N` over a measured quantity — an elapsed, a count,
a byte size, a row total — passes identically against a hardcoded literal. The question to ask of
each one is not *"is this bound correct?"* but **"name a constant that satisfies this."** If you can,
the predicate is a shape check wearing a measurement's clothes.

The corollary for mutation batteries: **enumerate the AXES a battery edits, not the count it
reports.** This one reported 7/7 and had edited a single axis. The axes it never touched — fixture
direction, bound direction, harness dispatch, fixture cardinality — are where every surviving mutant
lived.

## Five more holes the same panel found, all green

1. **`local name="$1"`** — a zero-arg call is an unbound-variable ABORT under `set -u`, one line into
   the function whose entire contract (ADR-133 Decision 3) is that it cannot abort. `|| true` at the
   call site cannot suppress a `set -u` expansion error. I had just fixed this class for
   `$EPOCHREALTIME` and fixed only the **read** — the arity and the arithmetic *consuming* the read
   both stayed bare (`100.` and `x.1` passed a shape-only `*.*` guard and aborted the caller).
   *Fixing the instance is not fixing the class, and the instance you just fixed is where you stop
   looking.*

2. **Locale radix.** Bash renders `EPOCHREALTIME` using `LC_NUMERIC`'s decimal separator, so on a
   comma locale it is `1786573806,515545`. The `*.*` guard failed, every banner read `unknown` on a
   healthy bash 5 with a working clock, and the gate went **92/3**. This instrument, built to
   eliminate false REDs, manufactured one for every European operator. Measured under `fr_FR.utf8`.
   Nobody enumerated locale at plan, work, or self-review; two agents converged on it independently.

3. **A line-anchored return extractor.** The AC6 structural arm grepped `^[[:space:]]*return` — blind
   to `|| { …; return 1; }`, `&& return 1`, and bare `return`. Its `>= 6` floor against 7 real paths
   also absorbed the deletion of an entire exit branch, and the liveness line cheerfully reported the
   reduced number.

4. **A bare-token grep in my own arm.** The flock arm grepped `LOCK_UNAVAILABLE`, which **all three**
   branches emit. One dropped entry in the PATH shim made it pass via a different branch *and*
   re-opened the flock-precheck mutation. This is `cq-assert-anchor-not-bare-token` — a rule I know —
   violated in an arm I wrote to enforce rigour.

5. **`await_held` had no coverage.** The helper I added earlier in the same session *to remove a
   race* passed with its body replaced by `return 0`. A one-sided test believes a no-op that claims
   success absolutely.

## The residue, recorded rather than implied

The precheck removes the **dominant** `rc=99` source, not all three. An unwritable lock dir still
reports `LOCK_CONTENDED_PROCEEDING` — measured `gave up after 5ms of 900s`. So the Guard Contract's
second clause ("no non-timeout failure reported as a timeout") is enforced for one cause, not all.
What changed is that the case is now **self-diagnosing**: 5 ms against a 900 s budget reads as a
precondition failure, where the old text printed the identical flat lie regardless.

The structural-enumeration seat's verdict is the honest summary: **the guard's assembly is narrower
than the property it names.** That is now written in ADR-133 instead of implied by a claim of
completeness.

## A recommendation declined, with the reason measured

`code-simplicity-reviewer` rated P1 a swap from `EPOCHREALTIME` to the `SECONDS` builtin: −68 lines,
deletes the bash-3.2 hazard outright, deletes the `unknown` branch and its whole arm. Its critique of
the duplication comment was also correct — the "dependency cycle" justification ruled out an option
nobody proposed (the de-duplicating direction is script→lib, which already exists).

Declined, because at the contended arm's 2-second timeout the measured elapsed and the budget are
**both `2`** in whole seconds — so the mutation that substitutes the budget for the measurement
becomes undetectable. **Millisecond precision is not for the operator; it is what makes the sneakiest
mutation observable.** The duplication stayed and the comment was rewritten to the real reason
(`test-all.sh` degrades this lib to a silent noop stub, so routing `run_suite`'s required timing
through it buys a new silent-zero failure mode).

## What the instrument then measured

Three real readings from the same lock on the same machine:

| Run | Banner | Outcome |
|---|---|---|
| queued behind 2 siblings | `gave up after 899122ms of 900s` | abandoned at budget |
| lock free | `after 12ms` | uncontended floor |
| queued behind 2 siblings | `after 616310ms` | **redeemed at 616 s** |

The third is uncensored — it acquired rather than timing out — so the plan's honest question ("does
the wait ever pay off, and what is the longest wait that was redeemed?") has a first answer: yes, at
least 616 s. Its consequence points *away* from lowering the timeout, which a censored reading had
suggested. Before this change, rows 2 and 3 printed the identical duration-free line.

## Session Errors

- **A mutation battery that reported 7/7 while editing one axis.** Recovery: the panel's
  test-design seat found 6 survivors; round-2 battery is 12/12 across five axes.
  **Prevention:** before crediting any battery, enumerate the axes it edits (SUT / fixture shape /
  fixture direction / bound direction / harness dispatch / member cardinality) and treat N rows on
  one axis as one row.

- **Every numeric predicate a lower bound.** Recovery: two-sided bounds derived from the artifact's
  own reported budget. **Prevention:** for each numeric assertion ask "name a constant that
  satisfies this" — if you can, it is a shape check.

- **Fixed the `$EPOCHREALTIME` read and left the arity and the arithmetic bare.** Recovery: guarded
  all four sites plus a digits-only regex. **Prevention:** when a fix closes an unguarded-expansion
  instance, grep the whole function for every other expansion before closing the finding.

- **Locale never enumerated.** Recovery: radix-agnostic regex + a unit-driven radix table needing no
  locale installed. **Prevention:** any code parsing a shell-rendered number must state which locale
  category formats it.

- **`pkill -f '<pattern>'` killed my own Monitor** because the pattern appeared in the monitor's own
  command line (exit 144). Recovery: resolved `/proc/<pid>/cwd` per match and killed by PID.
  **Prevention:** already documented; never `pkill -f` on a pattern your own invocation contains.

- **Gate log and rc written to the session scratchpad; the session boundary wiped both**, so a
  ~50-minute run produced no verdict and had to be re-run from scratch. Recovery: moved to
  `$(git rev-parse --git-dir)/gate-7484.log`, which is per-worktree and survives.
  **Prevention:** any artifact a LATER session must read by name belongs under the git dir, not the
  scratchpad — `mktemp` is right for within-session logs and wrong for cross-session evidence.

- **A verification grep matched my own explanatory prose** (`"1206 bytes"` inside the clause telling
  readers not to use a byte count) and I briefly read it as a surviving stale claim.
  **Prevention:** the same anchor-not-bare-token discipline applies to verification greps, not just
  to committed assertions.

- **Scoped hook incidents on `.ts` when the field is `.timestamp`**, got an empty result, and nearly
  reported "the strongest deviation-evidence class is unscopable" as a finding. Recovery: checked
  `jq 'keys'` before believing the empty output. **Prevention:** an instrument returning nothing must
  be shown to return *something* on a known-positive before its silence counts as evidence.

- **A typo shipped into an ADR edit** (`the 12 s… — the 12 ms —`). Recovery: fixed immediately on
  re-read. **Prevention:** re-read prose edits before committing; they have no compiler.

- **Committed `gh issue list --state all --search …` with no `--limit`** at plan time, which caps at
  30 rows and truncates silently. The gate caught it. **Prevention:** the repo's own probe-shape lint
  covers this — it fired correctly.

## Related

- ADR-133 — the advisory lock; third addendum records this change and its residue
- `2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md`
- `2026-07-19-my-own-mutation-battery-was-the-false-confidence.md`
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
