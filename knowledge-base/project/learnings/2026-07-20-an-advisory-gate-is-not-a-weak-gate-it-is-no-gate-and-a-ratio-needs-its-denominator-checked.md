---
date: 2026-07-20
issue: 6769
pr: 6785
tags: [gates, measurement, telemetry, workflow, self-review]
category: workflow-patterns
---

# An advisory gate is not a weak gate — it is no gate; and a ratio needs its denominator checked

## The measurement error that nearly set the wrong threshold

A diagnosis of runaway issue growth circulated as **"36 merged PRs in 7d → 7.4
issues filed per PR, net +3.9 per PR."** The issue counts were right (267 vs a
re-measured 269 created; 125 vs 125 closed). The **PR denominator was wrong by
~3.7x** — two independent methods (`search/issues` with `is:pr is:merged` and a
paginated `gh pr list` filtered on `mergedAt`) both returned **132**.

Corrected: **2.04 filed per PR**, not 7.4.

The qualitative diagnosis survived intact — filing per PR was still up 1.67x and
queue growth up 2.9x versus the prior 23 days. But the *magnitude* drove the
design, and two decisions would have been wrong:

1. **The proposed threshold `NET > +1`** was chosen against "7.4 filed per PR",
   where +1 looks strict. At the real 132 PRs/week, a +1 allowance authorizes
   **+132 issues/week against an observed +144/week** — an ~8% reduction that
   would have shipped wearing the authority of a passing gate. The correct
   threshold is `NET > 0`.
2. **The verification target "filed-per-PR ≤ 3.5"** was already met at 2.04 —
   and had been met at 1.22 throughout the entire period the queue grew to
   1,024. A success criterion that was never violated cannot detect the problem
   it was written for. Flat queue at the real throughput needs ≤ 0.95.

**Rule.** When a diagnosis is expressed as a ratio, re-derive **both** terms
before building against it, by two independent methods. A wrong numerator gets
noticed because it is the thing being discussed; a wrong denominator silently
rescales every threshold and target downstream. The tell here was that
`gh pr list` defaults to `--limit 30` — a paginated count and a search count
disagreeing by ~4x is the signature.

## Advisory surfaces do not degrade gracefully — they are inert

The net-issue-flow surface existed and computed `CLOSING`/`FILED`/`NET`
correctly for three months. It was advisory. It was skipped, including on the
PR immediately preceding this work, which filed 3 and closed 0.

The instinct "it's advisory, so it at least helps a bit" is wrong. An advisory
gate in an autonomous pipeline is not a weak gate — it is a *display*, and
nothing consumes it. Either it blocks with a deliberate, recorded escape hatch,
or it should be deleted so it stops implying coverage it does not provide.

## The gate as briefed could not have failed — and neither could my fix, twice

The FILED query as specified carried four independently-measured defects, each
sufficient on its own to make a **blocking** gate silently always-pass:

| Defect | Measured |
|---|---|
| `--search` | returns empty cross-repo under an App/action token |
| default `--limit` | 30 returned vs 271 real |
| `(Ref\|Closes\|Fixes) #N` keyword filter | ~40% of real filings |
| `--label deferred-scope-out` | ~8% of what PRs actually file |

A blocking gate with any of these is **strictly worse** than the advisory one it
replaces, because it also carries the authority of having passed.

Then security review found the same class **twice more, in the fix itself**:

- The hook resolved only its *script path* from `CLAUDE_PROJECT_DIR` and ignored
  payload `.cwd`, while its own header asserted it was cwd-independent. False:
  the delegated script resolves the PR from process cwd, so merging a feature
  worktree from a main checkout would resolve no PR and **fail open silently** —
  precisely the bypass the gate was written to close.
- Fail-open emitted `event_type: transient`, which `rule-metrics-aggregate.sh`
  counts as **nothing** (it counts only `deny|bypass|applied|warn`). The
  script's own header claimed a fail-open was distinguishable from a pass. It
  was not.

**Rule.** Writing the gate does not confer immunity to the defect the gate
targets. Mutation-test every gate — apply the regression you fear (loosen the
threshold, delete the filter, revert the fix) and confirm a specific assertion
reddens. 13 mutations were applied here and 13 killed; every one of them was a
defect that a green test run would otherwise have certified as absent.

**Corollary on telemetry:** an `emit_incident` call is not observability until
you check that the aggregator *counts* that `event_type` and does not treat the
`rule_id` as an orphan. Here the new `rule_id` would have hard-failed the
metrics run (`exit 5`) on the very first real event, paging ops.

## Diagnose the channel before building the mechanism

Issue #6769 asked for a staleness contract on `action-required` — auto-nag, SLA,
or auto-close. The cheapest check first (is the harvester actually running?)
inverted the deliverable entirely.

`operator-digest` **worked**: active cron, 7/8 successful runs, correct query,
the backlog surfaced ≥5 consecutive weeks. It posted to a **private repo with
zero subscribers** — verified live: 7 digest issues, all with 0 assignees, and
`gh variable list` empty. 130 days accumulated because nobody was notified.

Every proposed mechanism would have posted into the same dead channel. The fix
was one flag (`--assignee`), not new apparatus.

**Rule.** When a reporting surface "isn't working", prove the **delivery** leg
before building a louder producer. Producer-works/consumer-never-sees is a
distinct failure mode from producer-broken, and they look identical from the
issue text. Same family as "a component reports success but its downstream
effect is absent".

## Two false-green traps hit in one session

1. **`local a="$1" b="$WORK/x-$a"`** — `local` marks *both* names local (and
   unset) before evaluating `b`'s RHS, so `$a` reads as unset under `set -u`.
   Split the declarations. Symptom was an "unbound variable" pointing at the
   function-definition line.
2. **`nohup bash -c "cmd > log; echo $? > rc"` reports the wrapper's exit,** not
   the command's. The harness notified "completed (exit code 0)" **twice** while
   `test-all.sh` was still running. Only the explicit `rc` **file** plus a
   `pgrep` is trustworthy. Same shape as `cmd | tail` reporting `tail`'s status —
   which also bit here, printing "PUSH OK" for a push that had actually failed
   with a non-fast-forward.

## What is deliberately NOT claimed

The re-measured ratio at session close was **2.08 against a 0.95 target**. The
gate governs future PRs and cannot move a trailing 7-day window, so no
improvement is claimed. The soak criterion (filed-per-PR ≤ 0.95 **and** open
count at merge+14d ≤ count at merge) is what would demonstrate effect; it is not
built. Reporting the mechanism as a result would be the same error as reporting
an advisory display as a gate.
