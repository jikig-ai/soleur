# Acceptance evidence — #7304

All commands run from the worktree
`.worktrees/feat-one-shot-7304-drift-alerter-errexit` unless stated.

`CALIB` below is a pristine worktree pinned to `origin/main` at `546294c1f`, created before any
edit and kept until AC13 was recorded:

```
git worktree add --detach <scratch>/errexit-calib origin/main
```

## Pre-fix control reading (Phase 0.2)

```console
$ gh run list --workflow=scheduled-prod-version-drift.yml --limit 8 --json conclusion,databaseId
```

**8 of 8 `failure`** — `31054501973`, `31049906696`, `31042537116`, `31032771691`,
`31023342082`, `31012806189`, `31002109688`, `30992678866`.

## The both-direction result (the load-bearing measurement)

The suite executes the SHIPPED `check` step body under `bash -e` — GitHub's actual invocation —
with the checker stubbed to exit 0, 1 and 2.

| tree | result |
|---|---|
| **pre-fix** (`DRIFT_TEST_WORKFLOW=$CALIB/...`) | `Total: 136  Pass: 118  Fail: 18` |
| **fixed** | `Total: 149  Pass: 149  Fail: 0` |

The 18 pre-fix failures are **every exit-1 and exit-2 assertion, plus B15/B16/B17**. **Every
exit-0 assertion passed against the broken body.** That is the trap #7304 names: the CLEAN path
worked throughout the outage, so a fix — or a test — verified only there proves nothing.

## Linter calibration (AC11 / AC13 / AC15)

```console
$ python3 scripts/lint-workflow-errexit-capture.py --root $CALIB
lint-workflow-errexit-capture: scanned 71 workflow(s), 7 composite action(s), 697 run: body/bodies
...
17 finding(s). See ADR-170.                                   # rc=1

$ python3 scripts/lint-workflow-errexit-capture.py
lint-workflow-errexit-capture: scanned 71 workflow(s), 7 composite action(s), 697 run: body/bodies
lint-workflow-errexit-capture: clean                          # rc=0
```

The 17 pre-fix findings land on exactly the 7 expected files at exactly the expected lines
(106, 212, 350, 476, 516 / 80 / 220 / 1280 / 245 / 282, 592 / 1183, 1331, 1516, 1740, 2456, 3065)
— a third independent method agreeing site-for-site with the two planning sweeps.

## Per-criterion

| AC | Result | Evidence |
|---|---|---|
| AC1 exit 1 → `exit_code=1`, `verdict=DRIFT_SUSTAINED`, one `::error::` stale build | PASS | B14 (exit 1) arm |
| AC2 exit 2 → `exit_code=2`, `verdict=CHECK_ERROR`, one `::error::` cannot-evaluate | PASS | B14 (exit 2) arm |
| AC3 exit 0 → `exit_code=0`, `verdict=CLEAN`, **zero** `::error::` | PASS | B14 (exit 0) arm |
| AC4 control: axis11 deletes `set +e`, child RED naming B14 | PASS | `C-axis11-drop-errexit-clear caught by B14, the assertion it targets` |
| AC5 `grep -cE '^[[:space:]]*set \+e[[:space:]]*$' <drift wf>` = 7 | PASS | returns `7` |
| AC6 diff shape (errexit / comments / `steps.check.outcome` only) | PASS | see below |
| AC6b B17 = 0 and axis12 RED naming B17 | PASS | `C-axis12-drop-outcome-conjunct caught by B17` |
| AC7 per-sibling diff shape; every `set +e` has a `set -e` re-arm; no `set -u` added | PASS | see below |
| AC8 checker unmodified | PASS | `git diff --quiet origin/main -- scripts/prod-version-drift-check.sh` → rc 0 |
| AC9 suite exits 0, Parts A/B/C all run | PASS | `C0 unmutated control is GREEN` present; `Total: 149` |
| AC10 `MIN_B` 49→79, `MIN_C` 11→13, `MIN_ASSERTIONS` 117→149, none decreased | PASS | raised by exactly the added counts |
| AC11 linter exits 0 with non-zero scanned count | PASS | 71 workflows / 7 actions / 697 bodies |
| AC12 fixture suite exits 0, incl. `shell: bash` and same-line `; rc=$?` as must-FIRE | PASS | F4 and F2; `Total: 27 Pass: 27` |
| AC13 reverting the fix makes the linter report the drift workflow | PASS | H3 (+ H3b control on the unmutated copy) |
| AC14 both suites registered and executing in the `scripts` shard | PASS | `[ok] scripts/lint-workflow-errexit-capture (10190ms)`, `[ok] ...-live (2031ms)` |
| AC15 all 17 confirmed sites fixed; linter finds none | PASS | 17 → 0 |
| AC16 the two false-premise comments gone (excluding the corrective quote) | PASS | returns `0` |
| AC17 one tracking issue for the latent class | see §Deferral |
| AC18 `actionlint` on every edited workflow | PASS (qualified) | see below |
| AC19 ADR-170 accepted, `Enforced by:` names linter + test + `test-all.sh`, alternatives incl. `defaults.run.shell` | PASS | ADR body |
| AC20 the 2026-07-02 learning appended to; no new file | PASS | `## Addendum — 2026-08-06 (#7304)` |
| AC21 PR body uses `Closes #7304` | PASS | PR body |
| AC22 `bash scripts/test-all.sh scripts` green | see §Shard |
| AC23 ADR ordinal agrees across filename, body, plan, tasks, AC19/AC23 | PASS | 170; max on `origin/main` is 169, **167 is a gap and was not reused** |

### AC6 / AC7 — diff shape

```console
$ git diff -U0 origin/main -- .github/workflows/scheduled-prod-version-drift.yml \
    | grep '^[+-]' | grep -vE '^(\+\+\+|---)' \
    | grep -vE 'set \+e|set -e|^[+-][[:space:]]*#|steps\.check\.outcome'
(empty)
```

Every added `set +e` in a sibling file is bracketed by a `set -e` re-arm. No Terraform resource,
`-target=` set, guard filter or job/step condition was altered, and `set -u` was **not**
introduced into `infra-validation.yml`.

### AC18 — actionlint, stated honestly

5 of 7 edited workflows are clean. `scheduled-cron-artifact-age.yml` (1 finding) and
`scheduled-inngest-health.yml` (32 findings) report SC2016 **info**-level shellcheck notes — in
steps this PR does not touch. Counts are **identical on `origin/main`** (1 and 32), so this
branch adds none. `ci.yml` treats actionlint `rc=1` as expected (census tracked in #7042) and
only fails on a hang or an unrecognised status, so these are not gating.

### AC5 — a plan figure corrected

The plan predicted a bare `grep -c 'set +e'` would return **14** against 7 statements. As
written it returns **8**; the wording of the rationale comments repeats the literal fewer times
than the plan's draft did. The plan's *point* — that a bare token grep is not the statement count,
so AC5 must be line-anchored — holds, and the anchored form returns exactly 7.

## Corrections to the plan found during implementation

1. **`infra-validation.yml` was mis-analysed in the UNSAFE direction.** The plan stated the abort
   is "caught today by accident" because the downstream guard `exit_code != '0'` sees an empty
   output and evaluates true. It evaluates **false** — `''` casts to 0, so `'' != '0'` is false.
   Combined with that step's `continue-on-error: true`, a failing production `terraform plan`
   aborted at the capture, the job-failing guard was skipped, and the job reported **green**.
   Evidence: run `31054501973`, where a step gated `!= '0' && != '1'` was skipped on an empty
   output while its exact complement `== '0' || == '1'` ran. The fix is unchanged; the
   justification is now the measured one.
2. **Two existing Part C mutation axes were broken by the Phase 1b edit and had to be repaired.**
   `axis5` was anchored on the exact string `!cancelled() && ...exit_code == '1'`, which the new
   `steps.check.outcome == 'success' &&` conjunct splits — its mutation silently stopped landing.
   `axis8` replaced the first occurrence of that conjunct anywhere in the file, which was safe
   only while the heartbeat was its sole occurrence; the new rationale comment now precedes it,
   so it would have mutated **prose** and reported SURVIVED against a correct artifact. Both now
   `assert n == 1`.
3. **L460 (`verdict == 'CLEAN'`) was already safe.** It is a string-to-string comparison, so no
   numeric coercion applies and `'' == 'CLEAN'` is false. The `outcome` conjunct was added there
   for uniformity, not as a fix — recorded so a future reader does not infer a defect that was
   not there.

## Deferral (AC17) — and the site the CONCUR gate rescued from it

The `code-simplicity-reviewer` CONCUR gate ran **before** filing, as required. It returned
**DISSENT on the blanket 13**: CONCUR on 12, with one site required to be fixed inline.

**`cla-evidence-timestamp.yml:325-332` — fixed inline, not deferred.** The deferral's whole
justification is that an abort at these sites is *fail-loud*, so the operator still learns
something. That premise is **false** here, and the check was worth running rather than assuming:
the step is gated `if: failure()`, so **the job is already red before the line executes**. An
abort therefore adds zero incremental signal while destroying the only durable one — the tracking
issue, plus the 7-day `action-required` escalation that reads `createdAt` out of `$N`. It is the
**last** step of a **monthly** (`0 6 1 * *`) workflow with no other notification path, so this is
silent *in effect*, and silent in the **same** direction as #7304. Both abort paths correlate
with the failure it reports: a `gh` blip (it runs only when the network path is already degraded)
and SIGPIPE-141 from `head -1` under `pipefail`. Fix: `|| true` on the assignment; the existing
`-z "$N"` guard already treats empty correctly by filing a fresh issue. One line, so the
cost-of-filing gate says inline, not deferred.

**The remaining 12 → #7311**, with the inventory and re-evaluation criteria.

**A correction to the deferral's framing, measured.** The criterion "widen the gate's rule once
the confirmed class holds at 0" does not reach most of the set. Classifying each site by the
nearest preceding `set` line in its own body:

| errexit origin | count |
|---|---|
| INHERITED (no `set` line, or one without `-e`) | **3** |
| EXPLICIT `set -euo pipefail` | **9** |

Only 3 of 12 are inherited-errexit sites; for the other 9 errexit is deliberate authorship, so a
gate anchored on inheritance would never match them and a second, separately justified rule would
be needed. The review pass put the inherited count at 2; re-measuring found
`apply-web-platform-infra.yml:1009` also opens `set -uo pipefail`. #7311 carries the measured
number and says plainly that one widening does not close all 12.

Net issue flow: **closing 1 (#7304), filing 1 (#7311) → net 0.**

## Post-merge (automated, no operator step)

AC24–AC28 are executed by the shipping agent after merge and appended here.
