---
title: "A ten-run sample said 'structurally unreachable'; the defect was live at 2%"
date: 2026-07-28
category: test-failures
module: tests/scripts/lib, .github/workflows, .claude/hooks
issues: [6997, 7002, 7024, 7005]
pr: 7035
tags: [sigpipe, pipefail, vacuity, mutation-testing, measurement, fail-open, actionlint, terraform-plan-gates]
---

# A ten-run sample said "structurally unreachable"; the defect was live at 2%

Three issues, one shape: **a check that cannot report is indistinguishable from one that
passed.** Nine plan claims were falsified by measurement during implementation, and the two
most consequential defects were found by **mutating** artifacts rather than reading them.

## Problem

- **#6997** — nine tfplan gates authorising destructive production infrastructure could not
  classify a degraded `terraform show -json`.
- **#7002** — `actionlint` deadlocked on one workflow, so the repo's only workflow linter
  reported nothing at all, on every file.
- **#7024** — assertions whose exit status was decided by SIGPIPE rather than by the thing
  they assert.

## The measurement that reversed a scoping decision

The plan (and decision-challenge DC-5) recorded #7024's sentry case as **not** a live
fail-open, on this reasoning: `apply-sentry-infra.yml` strips to ~16.8 KB against a
65,536-byte pipe buffer, so the producer's whole output fits and `grep -v` finishes writing
before `grep -q` can close the pipe. Ten runs returned `0` every time. On that basis the
whole of #7024 was filed as a latent shape, and an acceptance criterion was written
forbidding any demand for `rc=141` from the real input.

**The reasoning is wrong.** The pipe buffer bounds how much a producer can write *before
blocking*; it does not stop the consumer exiting first. `grep -q` exits on its first match
and closes the pipe, and any write the producer has not yet completed then takes EPIPE.
Being under the buffer makes the race **narrow, not impossible**.

Re-measured — 100 runs, binaries pinned under `env -i PATH=/usr/bin:/bin`, positive control
confirmed firing:

```
rc=141 -> 2 ; rc=0 -> 98
```

**~2%.** A 10-run sample had a ~82% chance (`0.98^10 ≈ 0.82`) of observing zero of those, so
the original all-zero result was the *likely* outcome even with the defect fully live.

Severity follows from the assertion's direction: `_has_executable_target` is a **positive**
predicate, so `rc=141` reads as "no `-target=` found" and the test reports **ok**. That is a
live FAIL-OPEN, roughly 1 run in 50, in the #6074 guard on `terraform destroy` reachability.

**This is the second occurrence of a class documented one issue earlier**
([2026-07-27-my-ab-could-not-resolve-the-effect-i-concluded-from-it.md](2026-07-27-my-ab-could-not-resolve-the-effect-i-concluded-from-it.md)):
concluding from a sample whose power was never computed. Awareness did not prevent it.

## Key insight

**Compute the power before believing the null.** For a rare event, "N runs returned zero" is
only evidence if `(1-p)^N` is small for the `p` you would care about. At `p = 2%`, `N = 10`
is not a measurement — it is a coin flip that usually says "clean".

## The producer family decides whether a reproduction works at all

Building a synthetic SIGPIPE reproduction, the obvious `cat big | grep -q PAT` **never**
fires. Measured on a 202,014-byte input with the match on line 1:

| producer | rc=141 |
|---|---|
| `grep -v … \| grep -q MATCH` | **50/50** |
| `cat … \| grep -q MATCH` | **0/50** |

A `cat`-based probe reports a clean 0 forever and proves nothing — the instrument removing
the phenomenon it is meant to observe. **Use the production producer family in the
reproduction.**

## Vacuity found by mutation, not by reading

### The guard the PR built would have linted nothing

The plan prescribed `timeout 120 actionlint .github/workflows/`. **actionlint takes FILES**;
given a directory it exits **3** (`is a directory`) and only auto-discovers when given no
path at all. Since 3 is neither 124 nor 0/1, the prescribed guard would have printed
`rc=3 … acceptable` and exited 0 **having linted nothing** — the exact
cannot-report-so-it-passed shape all three issues are about, reproduced inside the remedy
for them. Found by *running* the guard, not reading it.

Fix: a `*.yml` glob, a catch-all `*)` arm that fails on any unrecognised status, and a ≥40
workflow-file floor.

### Nothing asserted the assertions RAN

Every anti-vacuity mechanism the PR added lives inside a helper — the `cmp -s` mutation
floors, the layered contract's unmutated control, the preamble-distinctive anchors. All are
defeated by the same move: not calling them. Deleting five arms from a suite took it from 13
assertions to 8 and it **still exited 0**, because the only merge gate is `fails -eq 0` and
CI reads a bare exit code.

**The first fix was itself defective**, and that is the more useful half: the floor called a
`gate_assert_ran` helper from the shared harness, but the harness `source` lives *inside the
arm block being deleted*. Deleting the arms also undefined the floor — it exited 127 under
`set -uo pipefail`, recorded nothing, and the suite passed.

> **A floor that depends on the thing it guards is not a floor.**

Shipped version is self-contained: bash builtins and each suite's own counters. A **floor,
not equality** — the count is developer-incremented, so `-eq` reddens on every legitimately
added assertion and trains people to bump the number unread.

### The published derivation command policed presence, not invocation

ADR-149 and the preamble header both published:

```bash
grep -l 'local plan_json' tests/scripts/lib/*gate*.sh | xargs grep -L plan_gate_assert_readable
```

`grep -L <symbol>` is a **presence** check. Every retrofitted gate contains that literal
inside its `if ! declare -F plan_gate_assert_readable` re-source guard — so a gate that
*sources* the preamble and never *calls* it satisfies the command and reports clean. The
vacuity the retrofit had to be proved against was sitting inside the command meant to police
it. Anchor on the call form (`-E '^\s*plan_gate_assert_readable'`); and `xargs -r` matters
because without it an empty first stage leaves `grep -L` reading **stdin**.

## A diagnostic message is not a validated set

The per-gate `plan_gate_assert_numeric` calls were generated from each gate's
`counter parse failed (…)` message. That message lists `arm='${arm}'` for operator context —
but `arm` is a **string** discriminant (`"recut"`/`"resume"`/`"preserve-store"`) that the
original `for v in …` loop never validated. Asserting it numeric reddened 27 arms.

Gate: diff the generated argument list against the **original loop's variable list**, per
gate. 9/9 exact match after the fix.

## Solution

- Retrofitted the shared fail-closed preamble onto 9 gates (derivation 11 → 2).
- Added `all(.change.actions[]; type == "string")` + an element-type guard to the helper.
- Extracted `cutover-inngest.yml`'s 118,722-byte `run:` body verbatim (sha256-verified) to
  `scripts/cutover-inngest.sh`; actionlint went `rc=124` → `rc=0`.
- Converted 16 piped `grep -q` sites to herestrings; extended the drift guard.
- Added per-suite assertion-count floors across 11 suites.

**The headline defect, reproduced before/after:** a plan that births `web-2` while carrying
`hcloud_server.web["web-1"]` with `"actions": []` — a destroy of the singleton behind
`app.soleur.ai` — scores `rc=0 PASS` on `origin/main` and `rc=1 ABORT` (naming the offender)
after this change.

## Prevention

1. **State the power before accepting a null result.** `N` runs of zero is evidence only if
   `(1-p)^N` is small for the `p` that would matter.
2. **Run the guard you are prescribing.** A plan-quoted invocation is a claim; `rc=3` is
   indistinguishable from `rc=0` to a guard that only special-cases one failure code.
3. **Every rc-classifying guard needs a catch-all arm.** Treat any unrecognised status as
   failure, never as "acceptable".
4. **Mutate to test a test.** Delete the assertions, not just perturb the code — and assert
   the mutation LANDED (`diff -q` against a pristine backup) with a GREEN baseline control
   first, or the result is void in both directions.
5. **Derive from the validated set, never the diagnostic message.**
6. **Prefer a self-contained floor.** Any check that shares a lifetime with the thing it
   guards can be removed by the same edit.

## Session Errors

1. **Backticks in `git commit -m "…"` were command-substituted.** Three spans (`` `before` ``,
   `` `declare -F …` ``, `` `grep -L` ``) were silently eaten from the committed message.
   *Recovery:* `git commit --amend --file=<path>`. *Prevention:* always pass commit messages
   containing backticks via `--file` / heredoc, never `-m "…"`.
2. **`sed` replacement `&` expanded as the whole match**, mangling two lines into nested
   garbage. *Recovery:* repaired with an exact-string `Edit`. *Prevention:* escape `\&` or
   prefer a Python exact-string replace with an assertion that the anchor occurred once.
3. **A regex arm-deletion silently did not land**, and the unchanged pass-count read exactly
   like "the guard caught nothing". *Recovery:* re-did it with a `diff -q` landing assertion.
   *Prevention:* the documented rule — a mutation that does not mutate is UN-RUN, never
   evidence.
4. **The first anti-vacuity floor was harness-dependent** and exited 127 silently.
   *Recovery:* rewrote self-contained. *Prevention:* see Key insight above.
5. **A verification regex `[a-z_]+_gate` excluded digits**, producing a false MISMATCH on
   `web2_retire_gate`. *Recovery:* widened to `[a-z_0-9]+`. *Prevention:* when a checker
   reports a mismatch on exactly one oddly-named member, suspect the checker.
6. **Generated a numeric-assert list from the abort message** rather than the validated loop
   (27 red arms). *Recovery + prevention:* see above.
7. **A QA scenario compared the preamble instead of the gate**, briefly producing the wrong
   before/after conclusion. *Recovery:* re-ran against the gate. *Prevention:* the artifact
   under test is the one the AC names.
8. **Plan-quoted baseline runtime (~417 s) was wrong**, and 553 `[ok]` lines were briefly
   misread as the suite count (225). *Prevention:* re-derive plan-quoted numbers; read the
   runner's own summary line, not a grep of per-assertion output.
9. **Push rejected non-fast-forward** after the work-start rebase. *Recovery:*
   `--force-with-lease`.
10. **CI `lint-bot-statuses` red on first push** — new `mktemp` sites without an owning trap.
    *Recovery:* owning `trap` in the new script, `# lint-trap-ownership: ok` on the three
    inline-`rm -f` test sites. *Prevention:* run
    `python3 scripts/lint-trap-tempfile-ownership.py` before pushing any diff that adds
    `mktemp`.
11. **`actionlint <dir>` rc=3 was initially recorded as "odd"** before being diagnosed.
    *Prevention:* an unexplained exit code is a finding, not noise.
12. **Killing the stale background suite surfaced exit 144.** Expected; noted so a future
    reader does not treat it as a failure.

**Forwarded from `session-state.md` (plan phase):** five invocation-brief premises were
falsified by measurement and recorded in the plan's `## Verified Facts` rather than silently
edited — including "D1/D2/D3 are fail-open" (all nine gates already aborted) and "nine gate
call sites" (there are 21).
