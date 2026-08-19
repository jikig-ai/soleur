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
lock. `TC_LOCK_TIMEOUT` was **900 s** against a **~45-minute (~2700 s)** uncontended full gate. (An
earlier draft of this file also cited "sibling holds of 3,775 / 5,787 / 5,763 s". Those runs were
*concurrent*, the figures elapsed-at-probe-time, and at most one held the lock — and citing them as
hold times makes the argument self-defeating, since it condemns 3600 too. The claim that survives is
narrower: 3600 is a bounded improvement over 900, not a value proven sufficient.)

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

## 6. Ten review agents found what a green suite and a 24-row battery could not

The implementation reached review with 66 green assertions, a mutation battery reporting 24/24 RED,
and a green `scripts` shard. Review found **~37 findings, 10 of them P1** — and not one was
reachable by mutating the implementation, which is what the battery did. They lived in:

- **the environment it ships into.** The suite was `66/0` locally and `58/8` under `CI=1` — and it
  is registered in `test-all.sh`, which CI's required check runs. Green for the author, red on
  merge. Found by running it under `CI=1`, not by reading it.
- **the entry point, not the function.** `tc_capacity_line` consumed one `/proc` walk exactly as
  designed; the `--capacity` *branch* then walked again for the detail rows, and printed
  `CAPACITY_OK measured_runs=0` directly above three enumerated siblings. The structural arm guarding
  "one walk" grepped the function's body, so the feature's own entry point walked past its guard.
- **the axis the fixtures never varied.** No fixture crossed two thresholds at once, so the reason
  accumulator only ever ran at one member and overwriting instead of joining survived. No fixture
  asserted the *rendering* of a degraded value, so `measured_runs=0` for an unmeasurable procfs
  survived — the exact collapse the validity flags exist to prevent, one field over from the
  mutation that did catch it.
- **the suite's own exit decision.** Inserting `fails=0` before the summary printed
  `59 passed, 0 failed (66 assertions)` and exited 0. Conservation ran upstream on true counters;
  the floor read an intact `cases`. The fix is that the exit reads an **append-only** failure log,
  so silencing it means deleting evidence rather than moving a number.
- **the baseline.** AC9 compared against `origin/main`, so it self-destructs on merge into `X == X`.
  Demonstrated by pointing `origin/main` at the branch's own content with a regression injected into
  both sides: green. Now pinned to an immutable SHA.

**Transferable:** a mutation battery measures the axes it edits. Before crediting one, enumerate the
axes — SUT content, fixture shape, fixture *direction*, member cardinality, harness dispatch, stub
fidelity, the baseline's own freshness, and the environment — and say which ones it never touched.
N mutations of one shape is one mutation.

## 7. Simplification retired more findings than fixing would have

Two components caused most of the damage, and neither survived: a diff-justification report that
could not change a decision under either `TEST_GROUP` value (~7 findings), and a heartbeat that
identified the lock holder by taking `head -1` of a `/proc` walk — naming a fellow *waiter* ~83% of
the time while costing ~313 CPU-seconds and ~154,000 forks per wait, on a box whose failure mode is
fork starvation (~5 findings). Deleting the first and reducing the second to *"which lock, and how
long have I waited"* removed twelve findings without patching any of them.

**Transferable:** when review returns a long list, sort it by *component* before sorting by
severity. A component with many findings is often one that has not earned its place, and the cheapest
fix for a mechanism that cannot change a decision is deletion.

## 8. Measured, not asserted

- `TC_LOCK_TIMEOUT` raised 900 → 3600 (source: ADR-133's recorded ~2700 s baseline, **not** a fresh
  measurement — a fresh uncontended reading was unobtainable, since the box carried load 43.67 with
  two live sibling runs at implementation time, and taking one would have meant launching a seventh
  full gate onto a contended machine to measure contention). The source is stated in the addendum
  rather than left to look like a measurement.
- Relevance-gating's real ceiling: **4** gated suites against
  **170** `run_suite` registrations
  (`grep -cE '^[[:space:]]*run_suite[[:space:]]' scripts/test-all.sh`) — ~2.4%. **The command is
  published because the first draft of this line said "167" and no counting rule reproduces it**;
  review measured 165/164 and 170/169 depending on the predicate. A number without its command is
  exactly the unverifiable claim the rest of this file is about, and it was the one figure here a
  reader could check.
- Diff-justification shipped as **nothing**: it was cut on review. A report that cannot change a
  decision under either `TEST_GROUP` value is not a smaller version of the feature, it is a fifth
  hand-written path list to keep in sync — and it was already wrong on `.github/`, `CLAUDE.md` and
  four `apps/web-platform` subtrees.
- One suite run: **~190 s**, 73 assertions.
