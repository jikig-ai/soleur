---
date: 2026-08-19
issue: 7545
pr: pending
category: workflow-patterns
tags: [test-runner, contention, advisory-lock, mutation-testing, measurement]
---

# The budget was shorter than the thing it was waiting for

#7545 was filed as "a session cannot tell before launching whether the box can absorb another full
gate", and asked for a pre-launch **decision** that declines an over-capacity run. The decision was
cut, the root cause turned out to be one constant, and the most expensive defect of the session was
in the test harness rather than the product.

## 1. The mechanism was a timeout, not a missing lock

`scripts/lib/test-contention.sh` already serialized every worktree of the repo through an advisory
lock. `TC_LOCK_TIMEOUT` was **900 s** against a **~45-minute (~2700 s)** uncontended full gate, with
observed sibling holds of 3,775 / 5,787 / 5,763 s.

A budget at roughly a third of the hold time **cannot serialize what it is waiting for**. It expires
by construction, `LOCK_CONTENDED_PROCEEDING` fires, and every queued run proceeds *at once*. That is
how six concurrent full gates land on one 16-core box — not because a lock is missing, but because
the lock's budget guarantees it will be waited out.

**Transferable:** before adding a mechanism to serialize something, check that the existing
mechanism's *timeout* exceeds the *hold time* of the thing it waits for. A wait budget below the
hold time is not a weak lock; it is a scheduled release of every waiter simultaneously. The tell is
that the contended banner fires *routinely* rather than rarely.

## 2. The decline was refuted by the ADR the issue rested on

The first design declined an over-capacity run with `exit 4`. Four reviewers converged against it,
and the decisive evidence was already in ADR-133: a run recorded as
`LOCK_ACQUIRED … after 616310ms` — a wait **redeemed at 616 s** behind two siblings. A `>= 1`
sibling decline refuses that exact run at t=0, converting a gate that **completed** into no coverage
at all.

The draft's "Pareto — never worse than the status quo" claim had reasoned only about the
missed-decline direction. Two further consumers it never swept: `lefthook`'s `pre-commit` hook runs
the runner, so a non-zero exit would have blocked `git commit` on any staged `.ts` while a sibling
ran; and `ship/SKILL.md` documents `rc=4` as "you are a spawned agent", whose documented remedy sets
`SOLEUR_ALLOW_FULL_GATE=1` — the exact override that re-creates the incident.

**Transferable:** when a plan cites an ADR as its *licence*, read that ADR for the datum that
**falsifies** the plan, not only the one that supports it. Here the licence and the refutation were
in the same file, four lines apart. And a "never worse" claim is a claim about *both* directions —
enumerate the direction you did not consider before writing it.

## 3. A degraded probe and a critical reading were the same number

`tc_avail_mb`, `tc_used_pct` and `tc_used_bytes` all degrade an unreadable or unparseable probe to
**`0`** — which is below every floor. So "could not read the filesystem" and "read a critically low
number" were indistinguishable, and a verdict consuming the value alone would have reported a broken
probe as a measured emergency.

The fix is a `0|1` **validity flag** promoted beside each value, with degraded readings rendering as
`?` rather than a digit, and uncertainty evaluated **per signal** so one dead probe does not suppress
a real finding from a live one.

**Transferable:** any probe with a "degrade to a sentinel number" contract silently converts *absence
of measurement* into *measurement of an extreme*. Grep for `|| { printf '0\n'; return 0; }`-shaped
fallbacks before consuming a probe in a decision, and carry validity separately from value.

## 4. The most expensive bug was a subshell increment in my own fixtures

The suite's fixture builder was called as `FX=$(make_fixture …)` — a **command substitution**, i.e.
a subshell — and used a counter to name its directory. The increment was discarded in the parent, so
every fixture landed in the same directory and **accumulated the previous arm's processes**. The
2-sibling fixture reported 5; the at-threshold tmpfs row read as contended.

This is the same trap the harness header already warned about for the `cases` counter, one construct
over. It did not fail loudly — it produced *plausible wrong numbers*, and 12 arms failed in a way
that pointed at the implementation rather than the fixtures.

**Transferable:** inside a function that will be called in `$( … )`, never carry state in a variable.
Mint uniqueness with `mktemp -d`, which works in a subshell. And when several arms fail together with
values that are *near* the expected ones rather than absent, suspect the fixture builder before the
system under test.

## 5. A hermetic suite cannot catch a "second non-atomic snapshot"

One mutation in the matrix — "have the verdict re-walk `/proc` instead of consuming the promoted
readings" — is **equivalent** against any fixed fake `/proc`: two walks over a directory nobody is
mutating return the same count. The defect it names is not a wrong number but a second snapshot that
can disagree on a *live* box, which is exactly the box no suite can fixture.

So the property was asserted where it is decidable: a structural arm grepping
`tc_capacity_line`'s body for a scan call, anchored on the call construct rather than a bare word so
a mention in a comment can neither satisfy nor break it.

**Transferable:** when a mutation row would survive as an equivalent mutant on a hermetic fixture,
say so and move the assertion to a surface where it can fail — do not leave the row in the matrix
implying coverage it does not have.

## 6. Measured, not asserted

- `TC_LOCK_TIMEOUT` raised 900 → 3600 (source: ADR-133's recorded ~2700 s baseline, **not** a fresh
  measurement — a fresh uncontended reading was unobtainable, since the box carried load 43.67 with
  two live sibling runs at implementation time, and taking one would have meant launching a seventh
  full gate onto a contended machine to measure contention). The source is stated in the addendum
  rather than left to look like a measurement.
- Relevance-gating's real ceiling: **4** gated suites of **167** top-level `run_suite` registrations
  (~2.4%), which tightened the operator's own "3 declines of 325" steer from the other direction and
  is why diff-justification shipped as a report rather than a fifth `*_PATHS` array.
- One suite run: **203 s**, 66 assertions.
