---
date: 2026-08-01
category: workflow-patterns
module: ci-alerting
issues: [7138, 7142, 7143]
pr: 7139
tags: [mutation-testing, test-vacuity, fixture-design, alerting, review]
---

# My mutation battery was green, and my own tests pinned the bug

## Problem

#7138: both notification steps in `web-platform-release.yml`'s `release-outcome` job gated on
`steps.outcome.outputs.failed != ''` — an *output* of the classify step. A classify step that
dies before its terminal `>> "$GITHUB_OUTPUT"` write leaves that empty, so both conditions
were false, both steps skipped, and a failed release went out silent.

The fix is small. Everything worth recording is about how much of it my own verification
could not see.

I shipped: widened conditions, 21 new assertions, a `pull_request` harness executed on
GitHub's real evaluator (run `30710703476`, 9/9 rows matched), and a **10-mutation battery
that reported 10 RED, zero survivors**. Then eight review agents reproduced **four P1s** by
execution.

## Root cause of the blind spots

### 1. A battery measures the mutations you imagined

All ten of my mutations perturbed bytes an assertion already read — delete a condition,
rename an id, revert a string. Green was guaranteed to be uninformative about anything else.
The axes it never touched were exactly where the defects were:

- deleting an `env:` **declaration** (not a value)
- swapping a **discriminator** between two predicates that my fixtures kept correlated
- sweeping a **value space** (`R_DEPLOY ∈ {success, failure, skipped, cancelled, unset}`)
- deleting an **assertion block** outright

Before crediting a battery, enumerate the *axes* it edits, not the count it reports.
**N mutations of one shape is one mutation.**

### 2. Fixtures sampled only the correlated diagonal of a 2×2

The property was over (`CLASSIFIER` died, `FAILED` non-empty). I instantiated `(failure, "")`
and `(success, "populated")` — the two cells where the two predicates agree. So swapping the
implementation from `CLASSIFIER` to `-z FAILED` in **either** body survived every assertion.

The missing cell was the state my own workflow comment named as the entire justification for
the design ("a classifier that dies AFTER writing its output has BOTH"). The most-argued
decision in the PR had a discriminating population of **zero**. And in that cell the mirror
emitted a *false statement* — "the classifier died before it could record which jobs failed"
about a run where it demonstrably had.

> Whenever a comment argues "we key on X, not Y", the fixture set must contain a row where
> X and Y disagree. If it does not, the comment is unpinned prose.

### 3. The harness fabricated the environment it was verifying

`run_step`/`run_mirror` hardcoded their env lists and **injected** `CLASSIFIER`. So they
tested a variable the workflow might not declare: deleting `CLASSIFIER:` from either step
reverted the entire fix at **48/48 green**. That is #7136's defect class recurring for the
new variable, and neither existing gate could see it — the linter exempts the guarded
`${CLASSIFIER:-}` form, and the arms supplied the very key the workflow had stopped
declaring. Only `R_DEPLOY` had a declaration assertion, and only because a prior incident
forced one.

**Fix the class, not the instance:** both harnesses now derive their env from the step's own
`env:` block, so a dropped declaration becomes an unset variable and the arms go red.

That fix then exposed a fail-open *inside itself*: the key file had no trailing newline, so
`while IFS= read -r k` silently dropped the **last** key — the harness supplying a key the
workflow no longer declared, which is precisely what the derivation exists to prevent.
`grep -qx` tolerates a missing final newline, so a sibling assertion passed while the loop
under-read. Fixed at both ends (`|| [[ -n "$k" ]]`, and a terminating newline on write).

### 4. My tests pinned the bug

`B6` passed `rdep=unset` and asserted the *reassuring* subject. So the suite actively enforced
the inversion it should have caught. A test written from the same wrong model as the code
does not check the code; it ratifies it.

## The P1 the tests were protecting

The classifier-death headline was gated `CLASSIFIER == 'failure' && R_DEPLOY != 'failure'`.
But `deploy` has five upstream `needs:`, so `needs.deploy.result` is **`skipped`** — not
`failure` — whenever an upstream job fails. `"skipped" != "failure"` is true, so a release
that demonstrably never rolled out was paged as *"we could not tell whether this release
reached production — nothing here says it failed."*

That is the #7095 outage with a reassuring subject line, produced by the PR that exists to
prevent it. One sub-case was a **strict regression against `main`**. `needs.deploy.result` was
in the step's own `env:` and is unaffected by the classifier dying — the truth was available
on every path and a negative gate discarded it.

> A negative gate (`!= 'failure'`) over a closed enum with 4+ members is a single-literal gate
> wearing a disguise. Enumerate the enum and gate positively on the value you actually mean.

## Two false mutation results — the failure mode of mutation testing itself

Both produced a *result-shaped* output that was not a result:

- **Red baseline.** A sandbox copy of the test file placed outside the repo broke its
  `SCRIPT_DIR` resolution, so extraction never ran and the trace showed an empty environment.
  That voids the measurement; it is not a finding.
- **A mutation that did not mutate.** An `||` fallback meant the *first* anchor matched, so
  the mutation inserted a comment and never removed the declaration — and reported
  `SURVIVED`. Re-run with a verified anchor, it went RED.

Assert the mutation landed against a **pristine copy** (`diff -q`), not against `HEAD` — the
tree is legitimately dirty during a review pass, so `git diff` proves nothing. And run the
**unmutated control first**: a red baseline makes every subsequent row noise.

## A correction that was itself wrong

Correcting `model.c4`'s stale `NoOne` count, I ran:

```bash
awk '/^resource "sentry_issue_alert"/ { name=$3 } /NoOne/ { print name }' issue-alerts.tf
```

and reported **2**. The second hit is the token `NoOne` inside an explanatory **comment**.
Parsing `^\s*fallthrough_type\s*=\s*"…"` gives **28 `ActiveMembers` / 1 `NoOne`**.

This is `cq-assert-anchor-not-bare-token` — a documented rule — broken in the one sentence of
the architecture model that says *who gets paged*, by the commit whose stated purpose was
fixing stale counts there. Two agents caught it by parsing instead of grepping.

> The moment a task requires both "count X" and "document X", a bare-token scan will match the
> documentation. Anchor on the assignment syntax.

## What review caught that no local gate could

Eight agents, four P1s, all reproduced by execution rather than argued. Also:

- A **run-link hint** branched on the headline while the list it pointed at branched on
  `FAILED_HTML` → "the red entry named above" with no entry above.
- The deploy-succeeded branch still closing with *"nothing reaches production"* two paragraphs
  after saying the code is live — a phrase this file's own #7095 comment already lists as
  false there. My change was the edit that would have fixed it and instead preserved it.
- **A residual I called unclosable was closable.** I attributed the classify-hang gap to
  `!cancelled()`; the proximate cause is that the only `timeout-minutes` was *job*-level, so a
  hang burned the budget and neither alert step was ever scheduled. A step-level timeout turns
  a hang into the failure this PR now catches.
- **An argument that was a non-sequitur.** DC-1 led with "release-outcome is the only channel
  that fires regardless of which job failed" — true of the **job**, and both the email and the
  mirror are steps *inside* it, so it argues equally for the mirror-only fix.

## Sequencing defect: the CONCUR gate ran after filing

Both `deferred-scope-out` issues were filed during the work phase (the plan's Phase 7); the
second-reviewer gate only ran at review. That **inverts the gate's purpose** — it becomes
ratification rather than admission control, because closing an already-filed issue costs more
social friction than declining to file one.

It caught a real DISSENT anyway (#7143 was split, two false-GREEN heartbeats pulled inline),
but it had to argue against a published artefact to do it. The plan prescribed Phase 7
filings without prescribing the gate that governs them.

## A worse variant found downstream

The sweep for sibling instances of #7138 found two `sentry-heartbeat` calls resolving an empty
producer output into an affirmative check-in:

```yaml
status: ${{ steps.probe.outputs.failure_mode == '' && 'ok' || 'error' }}
```

`if: always()`, dead producer, no output written, `'' == ''` → checks in **`ok`**. #7138 lost
an alert but something still went red; this produces a **green monitor with nothing red
anywhere**. These were fixed inline rather than deferred, because they live at `with.status`
and the `if:`-scoped linter rule they had been filed against could never have covered them.

> Before deferring instances to a future linter, confirm the linter's scope actually reaches
> them. A deferral to a rule that structurally cannot see the defect parks it forever.

## Session Errors

1. **Plan draft blocked twice by its own gates** — a section certifying the absence of a
   forbidden pattern reproduced that pattern's trigger vocabulary. **Prevention:** describe
   the scan, never quote its needles (already a plan Sharp Edge).
2. **Planner fabricated a quotation** attributed to the workflow header (R25). **Prevention:**
   every quoted string must be greppable in the cited file before it ships.
3. **Plan's central premise was unverified** against the live Sentry API and turned out FALSE.
   **Prevention:** R34-style "verify before writing the dependent phase" gates must execute,
   not be recorded as intent.
4. **Plan named a non-existent root `CHANGELOG.md`.** **Prevention:** plan paths are claims;
   `ls` before editing.
5. **Plan's C4 gate cited vitest suites that never read `model.c4`.** **Prevention:** an AC
   whose command cannot fail is not an AC.
6. **`awk` bare-token match counted a comment as config** (see above). **Prevention:** anchor
   on assignment syntax.
7. **First mutation battery was green and insufficient.** **Prevention:** enumerate the axes
   the battery edits; ask an independent reviewer to find the vacuity it missed, not to re-run
   its mutations.
8. **Fixtures sampled one diagonal of a 2×2.** **Prevention:** where a comment argues "X not
   Y", require a fixture where X and Y disagree.
9. **Harness fabricated the env it verified.** **Prevention:** derive test environments from
   the artifact under test.
10. **Trailing-newline drop in that derivation.** **Prevention:** `read` loops need
    `|| [[ -n "$k" ]]`; a silent under-read in a verification loop fails open.
11. **Sandbox mutation trace ran on a red baseline** (broken `SCRIPT_DIR`). **Prevention:** run
    the unmutated control first and require it green.
12. **A mutation that did not land reported SURVIVED.** **Prevention:** `diff -q` against a
    pristine copy before reading any mutation result.
13. **`printf '%s'` does not expand `\t` in arguments** — would have written literal
    backslash-t. **Prevention:** `%b`, and verify with `cat -A`. Caught pre-ship.
14. **A quoted heredoc terminator cannot be indented** inside a nested `run:` block.
    **Prevention:** `printf` for small tables. Caught pre-ship.
15. **`grep -E '^FAIL'` matched `FAIL: 0` summary lines**, reporting 5 phantom failures.
    **Prevention:** anchor on the emitter's real failure prefix.
16. **Foreground `test-all.sh` hit the 10-minute tool timeout.** **Prevention:** background it
    and read the terminal `=== N/M suites passed ===` marker, not the notification exit code.
17. **CONCUR gate ran after filing** (see above). **Prevention:** the gate belongs at the
    filing site, in whichever phase files.

## Key Insight

Every gate I built was green, and each was narrower than the claim it carried. The battery
proved things about the mutations I thought of; the fixtures proved things about the cells I
sampled; the harness proved things about an environment it supplied itself. Green means "the
checks I wrote did not fire" — it never means "the property holds."

The cheapest counter is not more assertions. It is asking, per check: **name an implementation
a reasonable engineer might write next that satisfies this while violating the property.** If
you can name one, the check is decoration.
