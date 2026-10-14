---
title: "The gate I built to catch a blind spot had the same blind spot, and my numbers were the least-checked thing in the PR"
date: 2026-08-06
category: build-errors
module: CI
issue: 7304
pr: 7305
tags: [errexit, github-actions, guard-building, mutation-testing, measurement-discipline]
---

# Learning: the gate I built to catch a blind spot had the same blind spot

## Problem

`scheduled-prod-version-drift.yml` failed 8 of 8 scheduled runs emitting zero diagnostic
output. GitHub invokes a `run:` step with no `shell:` key as `bash -e {0}`, so errexit is
already on and `set -uo pipefail` — which only ADDS flags — never cleared it. The capture

```bash
out="$(bash scripts/prod-version-drift-check.sh 2>&1)"; rc=$?
```

killed the shell AT that line on any non-zero exit.

The checker's contract made it maximally perverse: exit 0 is the QUIET verdict
(`CLEAN`/`DRIFT_PENDING`), exit 1 and 2 are the two that ALERT. Errexit killed exactly the
alerting verdicts and let the silent one through. The production-staleness alarm was quiet
when it had nothing to say and **dark precisely when production was stale**.

## Solution

`set +e` at 17 sites across 7 files, a repo-wide lint gate (ADR-170 / AP-022) calibrated at
**17 findings on `origin/main` → 0 on the fixed tree**, and a test harness that executes the
SHIPPED step body under `bash -e` on all three verdicts.

## Key insight 1 — a guard-building PR fails IN the guard, and its own fix ships unfixtured

The review panel fed my linter five defect-shaped steps. It caught **one**.

Invisible to it: `echo "rc=$?"` (the anchor required a separator before the identifier and a
double quote is none — and this form is **live at `fix-constraints-stage-a.yml:85` and `:139`**,
files the gate reported as scanned); `rc="$?"`; `rc=${?}`; bare `if [[ $? -ne 0 ]]`;
`set -x; cmd; rc=$?` (any `set`-matching line skipped its own capture — a one-token bypass);
and a false heredoc opener (`echo "usage: send <<EOF"`, `mask=$(( 1 << n ))`) which blanked
every remaining line, unbounded.

**A gate certifying its own blind spot as scanned is the defining failure of this class.**

The deepest one was a modelling error, not a regex gap: the gate judged errexit **at the read**
rather than **at the command**. So the single most likely mis-fix —

```bash
terraform plan -out=tfplan
set +e          # "clear errexit around the capture", exactly what the remediation text says
rc=$?           # dead code: the command already died
```

— reported clean. For a `${PIPESTATUS[n]}` read it is strictly worse than the original bug,
because `set` is a builtin and bash resets PIPESTATUS after it.

Then the second half: I fixed all of that and shipped **no fixtures**. `test-design-reviewer`
mutated the fixes straight back out and the suite stayed byte-identical green. The fix for a
blind spot is exactly as unpinned as the blind spot was, and it feels finished, because the
manual probe you just ran is fresh in your head and reads like coverage.

**Prevention:** for any guard-building PR, ask an agent to *mutate the guard out on a sandbox
copy and re-run*. Every fix to a detector needs a must-FIRE fixture in the same commit — the
manual probe that found the gap is not the regression test for it.

## Key insight 2 — the fix reproduced the bug it was fixing, one file over

Sweeping the class, I added `|| true` to a `gh issue list` capture in
`cla-evidence-timestamp.yml` so an abort could not destroy a tracking issue. That `|| true`
conflates **"lookup failed"** with **"nothing found"** — so a `gh` blip files a DUPLICATE issue
whose `createdAt` is now, silently resetting a 7-day escalation clock on a monthly cron with no
other operator channel.

The workflow being repaired in the same PR carries four handlers whose comment reads, verbatim:
**"A FAILED LOOKUP IS NOT 'NOTHING FOUND'."** I restored those and violated the rule in the
same breath, because the sweep felt mechanical and `|| true` is what you reach for when the
goal in your head is "stop the abort".

**Prevention:** when a fix's remedy is "make this not abort", ask what the non-aborting value
now MEANS to the consumer. `|| true` answers "did it abort"; `|| rc=$?` answers "what
happened", and only the second is a value the next branch can read.

## Key insight 3 — the least-checked thing in a measurement-heavy PR is its measurements

Four load-bearing numbers did not reproduce. The worst sat in the ADR paragraph that explicitly
says *"this wording is load-bearing and was arrived at by measurement, not by taste"*:

| claim | shipped | measured |
|---|---|---|
| assignment-anchored rule reaches | 2 of 17 | **8 of 17** (9 bare) |
| pre-fix suite totals | 136 / 118 / 18 | **151 / 133 / 18** |
| bare `grep -c 'set +e'` | 8 | **15**, and it read 13 in between |
| latent class | 12 sites, 3 inherited | **13 sites, 5 inherited / 8 explicit** |

I applied *"plan-quoted numbers are preconditions to verify"* to the line numbers, the site
counts, the terraform handlers, the run conclusions — and not to the one figure whose whole job
was to make a reader distrust their intuition. It came from the plan, it sounded decisive, and
decisiveness is what stopped me re-deriving it. The arithmetic in its own sentence did not even
close: 2 + 9 = 11, not 17.

Two of the four were *my own corrections of the plan* that went stale within the same branch,
because I recorded a point-in-time reading as a fact and then kept editing the file it measured.

**Prevention:** publish the COMMAND next to any number that survives into a durable artifact,
and re-run it at ship time. A figure that drifts while you edit is a property of the prose, not
a fact — which is precisely why the acceptance criterion for it must be anchored
(`^[[:space:]]*set \+e[[:space:]]*$` → 7, stable) rather than a raw count.

## Key insight 4 — one edit silently disarmed two existing mutation axes

Adding `steps.check.outcome == 'success' &&` to six `if:` gates broke two Part C axes that had
nothing to do with the change:

- **axis5** was anchored on the exact string `!cancelled() && …exit_code == '1'`, which the new
  conjunct splits. Its mutation stopped landing; the axis reported nothing wrong.
- **axis8** replaced the FIRST occurrence of `steps.check.outcome == 'success'` anywhere in the
  file — safe only while the heartbeat was its sole occurrence. My new rationale *comment* now
  precedes it, so it would have mutated PROSE, `diff -q` would report the mutation landed, and
  the axis would score SURVIVED against a correct artifact.

**A mutator keyed on an exact expression shape is coupled to every future edit of that
expression.** Both now `assert n == 1` and skip comment lines.

**Prevention:** when a diff changes an expression, grep the mutation battery for that
expression's literal — an axis that stops matching is silent by construction.

## Key insight 5 — a background suite measures the tree you keep editing

I launched `test-all.sh scripts` in the background and then applied the review fixes to
`scripts/` and `.github/` while it ran. The shard came back 258/259 with
`cf-tunnel-liveness-gate-mutations` FAILED — and the failing assertion was that suite's own
anti-contamination guard: *"the working tree CHANGED under scripts/ or .github/ while this
battery ran — a mutation escaped."*

Not a finding. A snapshot of my own mid-edit state, and it cost a baseline run plus an isolated
re-run to prove it. The suite reads `apply-web-platform-infra.yml`, which my diff genuinely
touches, so "my diff doesn't touch its inputs" — my first instinct — was also wrong.

**Prevention:** `git status --porcelain` must be empty before launching a long suite, and if an
edit cannot wait, kill the run rather than reinterpreting its output.

## Session Errors

1. **Inherited the plan's "2 of 17" into ADR-170 without re-deriving it.** The one paragraph
   asking readers to trust a measurement. **Prevention:** re-derive every plan-quoted number
   that survives into a durable artifact, and publish the command beside it.
2. **Recorded "bare grep returns 8" as a correction of the plan's 14.** It read 13, then 15, as
   I added comments. **Prevention:** a count over prose is not a fact; anchor the AC instead.
3. **Recorded pre-fix suite totals from a Parts-A+B run as the full result.** **Prevention:**
   label which invocation produced a number, or re-run it before committing.
4. **`LINT_RC=$?` set inside `out="$(run_lint …)"` was discarded by the subshell**, so every
   must-FIRE assertion compared a stale rc and failed while the linter was correct — 14 false
   failures. This trap is documented in AGENTS.rules.md and I hit it anyway. **Prevention:** a
   function that must report a status sets globals; only pure-stdout functions are `$( )`-safe.
5. **Hand-counted 12 fixture line numbers wrong.** **Prevention:** let the tool report the line
   and assert against its output. (one-off)
6. **`cp -r "$SRC/.github" "$dst/.github"` where the destination already existed** produced
   `.github/.github`. **Prevention:** `rm -rf` the destination first. (one-off)
7. **An apostrophe in a PYEXTRACT comment ("consumer's") terminated the single-quoted bash
   string**, breaking the harness with a syntax error 3 lines later — the exact trap that
   block's own docstring warns about. **Prevention:** grep the block for `'` after editing it.
8. **`local name="$1" root="$TMP/fx-$name"`** — SC2318; the first assignment has not taken
   effect. Caught by shellcheck. **Prevention:** run shellcheck on every edited `.sh`. (one-off)
9. **Shipped a false justification for the continuation-walking machinery** (claimed a
   physical-line matcher "misses a confirmed site"; a reviewer's 35-line rule found that site
   without it — the walk is needed to REPORT the command, not to detect the class).
   **Prevention:** a justification citing a measurement needs the measurement re-run against the
   alternative, not just against the status quo.
10. **Shipped `is_protected` arms self-documented as contributing ZERO findings.**
    **Prevention:** do not ship code you have measured as contributing nothing.
11. **Shipped a dead branch in `clears_errexit`** (`flags in ("o","e") … and flags == "o"`).
    **Prevention:** mutation-test each branch, or reduce the condition by hand. (one-off)
12. **My `|| true` reproduced the "A FAILED LOOKUP IS NOT 'NOTHING FOUND'" bug this PR
    restores.** **Prevention:** see Key insight 2.
13. **The Phase 1b edit silently disarmed axis5 and axis8.** **Prevention:** see Key insight 4.
14. **Edited `scripts/` and `.github/` while a background shard ran**, producing a false RED.
    **Prevention:** see Key insight 5.
15. **Shipped the linter hardening with no fixtures** — every fix was mutation-revertible at
    full green until `test-design-reviewer` found it. **Prevention:** see Key insight 1.
16. **AC6's literal command was unsatisfiable** — its carve-out covered only the `+` side of the
    `if:` rewrite. Amended explicitly (and strengthened) rather than quietly widened.
    **Prevention:** run every AC's literal command once before claiming it passes.
17. **`semgrep --quiet` printed nothing and I nearly read it as a clean result.** A bad
    `--config` exits 7 while still reporting 0 findings. **Prevention:** always confirm
    `Ran N rules on M files` with non-zero N before trusting a clean SAST run.
18. **Forwarded from the plan phase:** the IaC-routing hook blocked the plan write by
    pattern-matching trigger phrases quoted inside the gate section itself; three ACs were
    unsatisfiable as first written. Both self-corrected at deepen time.

## Tags

category: build-errors
module: CI
