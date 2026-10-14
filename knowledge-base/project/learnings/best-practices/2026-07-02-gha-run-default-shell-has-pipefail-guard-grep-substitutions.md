---
title: "GHA `run:` default shell enables `pipefail` — `set +e/set -e` does not disable it; guard `grep | head` substitutions"
date: 2026-07-02
category: build-errors
tags: [github-actions, bash, pipefail, errexit, workflow, grep, drift-cron]
symptoms: [Workflow step aborts silently at a grep-parse line, Anomaly/error-handling branch after a parse becomes unreachable dead code, "$GITHUB_OUTPUT" status write skipped so downstream steps mis-gate]
module: CI
component: github_actions_workflow
problem_type: build_error
resolution_type: code_fix
root_cause: wrong_assumption
severity: medium
issue: 5872
---

# GHA `run:` default shell enables `pipefail`; guard `grep | head` substitutions

## Problem

The `scheduled-domain-model-drift.yml` executor parsed a stale-citation count out
of an analyzer report:

```yaml
run: |
  set +e
  bash scripts/domain-model-drift.sh drift ... > "$RUNNER_TEMP/dm-drift.txt" 2>&1
  rc=$?
  set -e                                         # <-- re-enables errexit, NOT pipefail-off
  stale_line=$(grep -oE '^## Stale register citations \([0-9]+\)' "$RUNNER_TEMP/dm-drift.txt" | head -1)
  ...
  if [[ -z "$stale_line" ]]; then ... fi         # empty-stale anomaly guard
```

On a report **missing** the stale heading, `grep` exits 1. The author assumed
`grep | head` was safe because the pipeline's exit is `head`'s (0). It is not:
GitHub Actions runs a plain `run:` block under **`bash --noprofile --norc -eo
pipefail {0}`** — `pipefail` is ON by default. With `pipefail`, the pipeline
inherits `grep`'s exit 1, and under the re-enabled `set -e` the
command-substitution assignment **aborts the step at the parse line**. The
empty-stale anomaly guard below it became unreachable dead code, and on a
missing `undoc` heading with `stale > 0` the step died before writing
`status=ok`/filing the issue — silently suppressing a real drift issue.

Caught by a code-quality review agent (the author's own self-verification had
*mis-cleared* it, wrongly asserting the default shell omits `pipefail`).

## Solution

Disable `pipefail` explicitly for the parse and guard every substitution — the
`scheduled-realtime-probe.yml` precedent already does this:

```yaml
run: |
  set +e +o pipefail                              # errexit AND pipefail off through the parse
  bash ...drift.sh ... > "$RUNNER_TEMP/dm-drift.txt" 2>&1
  rc=$?
  stale_line=$(grep -oE '...' "$RUNNER_TEMP/dm-drift.txt" | head -1) || stale_line=""
  undoc=$(grep -oE '...' ... | head -1 | grep -oE '[0-9]+' | head -1) || undoc=""
  undoc=${undoc:-0}
```

Verified by running the exact block under `bash -eo pipefail` against a report
with the stale heading absent: execution now reaches the anomaly guard instead
of aborting.

## Key Insight

`set -e` and `set -o pipefail` are **independent**. A `set +e ... set -e`
bracket toggles errexit only — `pipefail` set by the invoking shell survives it.
On GitHub Actions the invoking shell for a plain `run:` is `-eo pipefail`, so any
`cmd | grep | head` substitution whose upstream stage can legitimately exit
non-zero (grep no-match, `head` closing the pipe early) will abort the step. When
a workflow bash block deliberately tolerates a non-zero exit (an analyzer that
exits 1 by design, a no-match grep), disable BOTH (`set +e +o pipefail`) AND
guard each substitution with `|| var=""`. A pipeline ending in `| head` is NOT
self-protecting under `pipefail`.

## Addendum — 2026-07-30 (#7025): a correction to this file, and the ordering trap

This file's rule held; two of its details were wrong, and the class recurred anyway. It cost
a production dispatch on the git-data rung-2 rehearsal route, whose capture step ran **one of
twenty** poll attempts and exited four seconds in, making the birth interlock unreleasable by
any dispatch.

### Correction: the default `run:` shell is `bash -e {0}`, not `-eo pipefail`

The Session Errors entry below says to treat *"GHA `run:` default shell is `-eo pipefail`"* as
a fixed fact. That is the expansion of an **explicit `shell: bash`**. A bare `run:` with no
`shell:` key runs as **`bash -e {0}`** — measured directly in the run log of
`git-data-rung2-rehearsal.yml`, which declares zero `shell:` overrides.

The distinction rarely changes the outcome (a step that sets its own `pipefail` gets it
either way) but it changes the *diagnosis*, and diagnosing from the wrong default is how the
next one gets missed. **What is invariant, and is the actual rule:** `-e` is applied by the
**invocation**, so it is outside the artifact your `set` line can address. Writing
`set -uo pipefail` does not clear it. You can only turn errexit off by *saying so*:
`set +e`.

One exception worth carrying, because this repo hits it: inside a **container** without
bash, the bare-`run:` default is `sh -e {0}`, not `bash -e {0}`. `deploy-docs.yml` says so
in its own `defaults.run.shell` comment (*"container `run:` steps default to /bin/sh (dash
on Jammy)"*) — which is why that job sets `shell: bash` explicitly and therefore gets
`-eo pipefail` rather than plain `-e`.

That also explains why shellcheck/actionlint cannot catch this class: shellcheck lints each
`run:` body as a standalone script and cannot see the invocation the `-e` lives in. Measured
against a synthesized workflow carrying the exact bug — actionlint with shellcheck returns
only `SC2034 … appears unused`. Nothing about errexit, `PIPESTATUS`, or the dead retry. So
this is not a "just turn the linter on" gap; it needs a bespoke rule.

### The ordering trap: `set -e` RESETS `PIPESTATUS`

The obvious fix is a `set +e` bracket. Its obvious phrasing is silently wrong:

```bash
set +e; ( exit 2 ) | cat; rc=${PIPESTATUS[0]}; set -e   # rc=2  <- CORRECT
set +e; ( exit 2 ) | cat; set -e; rc=${PIPESTATUS[0]}   # rc=0  <- SILENT FALSE PASS
```

`set -e` is a **builtin**, therefore a pipeline, and bash resets `PIPESTATUS` after every
pipeline. Run against the real step body, the reordered form yields exit 0, one attempt,
`capture_rc=0`, and a green `PASS` summary — **on a host that never booted.** That is
strictly worse than the bug being fixed, which at least failed loudly. `rc=${PIPESTATUS[0]}`
must be the first command after its pipeline, with nothing between them.

### Two alternatives that look fine and are disqualified

Measured under `bash -e`, pipeline exits 2, `tee` exits 0:

| form | result |
|---|---|
| `pipeline \|\| true` then `rc=${PIPESTATUS[0]}` | **rc=0.** `true` runs as its own pipeline and resets `PIPESTATUS`. Every retryable outcome reads as success. |
| `pipeline \|\| rc=$?` | **rc=1 when `tee` fails and the real command passed.** Under `pipefail`, `$?` is the rightmost failing stage, so a `tee` failure is reported as a failure of the thing being measured. |
| `set +e` … `rc=${PIPESTATUS[0]}` … `set -e` | Preserves `PIPESTATUS[0]` exactly. **Use this.** |

**The discriminator is NOT "does a `PIPESTATUS` read follow".** An earlier draft of this
addendum said it was, and 2 of the 3 bracket sites in the fixing PR contradicted it — both
read a plain `rc=$?`, no `PIPESTATUS` anywhere. The real question is **what you need out of
the failure**:

- *A numeric exit code* (to branch on it, report it, or count consecutive failures) → use
  the `set +e` … `rc=$?` (or `rc=${PIPESTATUS[0]}`) … `set -e` bracket. `cmd || rc=$?`
  leaves `rc` stale on the success path unless you pre-zero it.
- *A default value*, where the failure just means "absent" → `|| true` / `|| var="default"`
  is the house form and a bracket is overkill.

`PIPESTATUS` is one instance of the first case, not the rule. Shipping a rule that its own
PR contradicts is the same failure this file documents, one level up.

### The part worth internalising: five prior statements of this rule did not prevent it

At the time of the recurrence the repo carried **four learnings** on this rule (including
this file) and **13** in-workflow comments stating it. Each figure is published with the
command that derives it, because a bare number in prose is exactly what this file argues is
not a control — and the first draft of this very paragraph said "five comments" and "nine
near-copies", both wrong:

```bash
# in-workflow comments stating the rule (13 at the fixing PR's base commit)
grep -rn -iE '#.*(inherited|invocation).*(-e|errexit)|#.*set \+e so' .github/workflows/*.yml | wc -l

# files carrying the "intentionally omitted" comment (3: apply-github-infra,
# apply-sentry-infra, apply-web-platform-infra)
grep -rl "intentionally omitted so we can capture" .github/workflows/ | wc -l
```

Three files carry a comment reading *"`-e` is intentionally omitted so we can capture
terraform plan's exit code in `$rc`"* directly above code where `rc=$?` and its `::error::`
branch are both unreachable. **Prose is not a control for this class.** A guard has to
execute the body; the fix shipped one that extracts the real step body from the live YAML,
runs it under `bash -e` with stubs, and carries mutation arms that must go RED.

The remaining audit is #7098. Its scope, with the command:

```bash
# 56 bodies of 637 total, comment-stripped: a `set … pipefail` line that omits -e,
# with no `set +e` anywhere in the body.
```

Note the backlog was **59 at that PR's branch base** and 56 after it fixed three — the three
it fixed had arrived in the interim from a sibling PR, so a count taken before the branch was
cut would have undercounted the class rather than the remainder.

## Addendum — 2026-08-06 (#7304): occurrence six, and the gate that should have shipped in July

The section above ends by observing that prose is not a control for this class. It then shipped
no repo-wide control. **Six days later the class recurred**, on the production-staleness alarm.

### What it cost

`scheduled-prod-version-drift.yml` calls a checker whose exit code is its verdict: 0 for the two
QUIET verdicts (`CLEAN`, `DRIFT_PENDING`), 1 for `DRIFT_SUSTAINED`, 2 for `CHECK_ERROR`. Inherited
errexit killed the step at the capture on **exactly the two verdicts that alert** and let the
silent ones through. The alarm was quiet when it had nothing to say and dark precisely when
production was stale — 8 of 8 scheduled runs failed emitting zero diagnostic output.

The asymmetry is the part to internalise, because it is what makes this class survive review:

| checker exit | verdict | intent | under inherited `-e` |
|---|---|---|---|
| 0 | `CLEAN` / `DRIFT_PENDING` | no alert | works, unchanged |
| 1 | `DRIFT_SUSTAINED` | **ALERT** | step dies silently |
| 2 | `CHECK_ERROR` | **ALERT** | step dies silently |

Measured directly: running the shipped step body under `bash -e` against the pre-fix workflow
gives 118 pass / 18 fail, with every exit-1 and exit-2 assertion red and **every exit-0
assertion green**. A fix — or a test — verified only on the clean path is indistinguishable from
no fix at all, because the clean path already worked throughout the outage.

### The tell you can grep for

A trailing `set -e` re-arm with **no matching `set +e` above it**. The author wrote the second
half of a bracket whose first half was never there — they believed `-e` was off, which is
precisely the false premise this file exists to correct.

### The rule an automated detector must use, and the one that looks right and is not

Anchor on the **`$?` / `${PIPESTATUS[n]}` READ**, then inspect the preceding logical command.

The intuitive rule — "a command-substitution assignment is a finding" — was prototyped against
the real tree and found **2 of 17 sites**. Nine of the seventeen are *bare commands* followed by
`rc=$?`, so an assignment-anchored rule is structurally blind to every terraform site while
reporting as full coverage. `${PIPESTATUS[n]}` must be included too: two sites, including one of
the six occurrences, never touch `$?`.

One false-positive class, worth knowing because it is an ordering bug rather than a rule bug:
test the `|| rc=$?` exemption **before** stripping the trailing separator. Stripping first turns
`cmd ||` into `cmd |`, which then fails the `||`-in-command test — 13 false positives, all in the
two workflows independently verified as correctly protected.

### The intervention that had not been tried

Four learnings + six in-workflow comments + two hand sweeps → a sixth occurrence. #7304 shipped
`scripts/lint-workflow-errexit-capture.py` + its unit suite, registered in `scripts/test-all.sh`
(ADR-170, principle AP-022), calibrated in both directions: **17 findings against origin/main,
0 against the fixed tree**. No `.highwater`.

Calibrate any such gate against the PRE-FIX tree, and keep that tree available
(`git worktree add <scratch> origin/main`) until the calibration is recorded. A gate authored
after the fixes have erased the evidence can only be validated against fixtures its own author
wrote — which is exactly how the 2-of-17 rule would have shipped reading as complete.

### A second, adjacent defect that `set +e` does NOT fix

Actions `==` is **loose**: operands of differing types are cast to Number, an unset step output is
`''`, and `''` casts to 0 — so **`'' == '0'` is TRUE**. A step that dies before writing
`$GITHUB_OUTPUT` therefore satisfies every `== '0'` gate downstream.

Verified on run `31054501973`: the step gated `exit_code != '0' && != '1'` was **skipped** while
its exact logical complement, gated `== '0' || == '1'`, **ran**. The workflow would have
auto-closed the issue reporting its own breakage, posting an empty verdict.

This bit twice in one PR. In `infra-validation.yml` the plan step carries
`continue-on-error: true` and the job-failing guard is `if: steps.plan.outputs.exit_code != '0'`
— which is **false** on the abort path, so a failing production `terraform plan` could report
green. The plan for #7304 had reasoned the opposite ("caught today by accident") and was wrong in
the unsafe direction; the run above settled it.

Remedy: lead every consumer of a step's outputs with `steps.<id>.outcome == 'success'`. That
conjunct is what discriminates "the step ran and measured 0" from "the step never ran".

### Mutating a fix whose rationale comment quotes the fix

Every correction in this class ships a comment containing the literal `set +e` (it has to — it
explains why the statement is required). A mutation-testing arm that does
`s.replace("set +e", "", 1)` therefore rewrites the **comment**: the file differs, `diff -q`
reports the mutation landed, the child suite stays green, and the axis reports SURVIVED against a
perfectly correct artifact. Mutators must be line-based and skip lines whose first non-space
character is `#`.

The same edit broke two *existing* mutation axes in the drift suite, both for related reasons —
one was anchored on an exact `if:` expression string that the new conjunct split, the other
replaced the first occurrence of a token that was unique before the fix and no longer is. **A
mutator keyed on an exact expression shape is coupled to every future edit of that expression.**
Assert that the mutation matched (`assert n == 1`), or an axis silently stops testing anything.

## Session Errors

1. **`pipefail` parse-abort (P2, pr-introduced).** Authored the parse under a
   `set +e/set -e` bracket believing GHA's default `run:` shell omits `pipefail`.
   Recovery: `set +e +o pipefail` + `|| var=""` guards. **Prevention:** this
   learning + the guard idiom; treat "GHA `run:` default shell is `-eo pipefail`"
   as a fixed fact when authoring workflow bash.
   **CORRECTED 2026-07-30 — see the addendum above:** `-eo pipefail` is what an
   explicit `shell: bash` expands to; a bare `run:` is `bash -e {0}`. The
   invariant to carry is that `-e` comes from the INVOCATION and only `set +e`
   clears it.
2. **7 new SC2086 warnings.** Switched `/tmp/*.md` literals to `$RUNNER_TEMP/*.md`
   unquoted. Caught by re-running `actionlint`. Recovery: quoted them.
   **Prevention:** run `actionlint` (with shellcheck) after any workflow bash
   edit, not just after authoring.
3. **Margin doc drift (P3).** Plan/tasks said `checkin_margin_minutes = 120`
   while the shipped monitor is `60` (a plan internal inconsistency; code took
   the correct CTO-refined 60). Recovery: fixed the stale prose.
   **Prevention:** when a plan's IaC prose and its Deepen/CTO section disagree on
   a literal, the later CTO refinement wins — reconcile at work-start.
4. **Header comment mis-attribution (P3).** Dispatcher header said a token-mint
   failure routes to `reportSilentFallback`, but the mint is outside the
   try/catch (routes to the Inngest sentry-correlation middleware). Recovery:
   reworded. **Prevention:** verify observability-layer citations against the
   actual try/catch boundary.
5. **Wrong test path (one-off).** Ran `test/server/inngest/list-routines.test.ts`;
   actual is `test/server/routines/list-routines.test.ts`. Self-corrected via
   `find`. **Prevention:** `find`/glob a test path before asserting it's missing.
6. **tsc 2-min timeout (one-off).** First `tsc --noEmit` hit the default 2-min
   Bash timeout; re-ran with a longer timeout. **Prevention:** budget ≥7 min for
   `tsc --noEmit` on `apps/web-platform`.

## Tags
category: build-errors
module: CI
