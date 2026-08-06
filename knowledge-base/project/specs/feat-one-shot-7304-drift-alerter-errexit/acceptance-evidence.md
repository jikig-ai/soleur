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

**8 of 8 `failure`** at the time of measurement (the streak has since grown; a review pass
re-ran it at 10/10 and then 12/12) — `31054501973`, `31049906696`, `31042537116`, `31032771691`,
`31023342082`, `31012806189`, `31002109688`, `30992678866`.

## The both-direction result (the load-bearing measurement)

The suite executes the SHIPPED `check` step body under `bash -e` — GitHub's actual invocation —
with the checker stubbed to exit 0, 1 and 2.

| tree | result |
|---|---|
| **pre-fix** (`DRIFT_TEST_WORKFLOW=$CALIB/...`) | `Total: 151  Pass: 133  Fail: 18` |
| **fixed** | `Total: 151  Pass: 151  Fail: 0` |

The 18 pre-fix failures are **every exit-1 and exit-2 assertion, plus B15/B16/B16b/B17**.
**Every exit-0 assertion passed against the broken body** (`grep -c 'FAIL: B14 (exit 0)'` → 0).
That is the trap #7304 names: the CLEAN path worked throughout the outage, so a fix — or a
test — verified only there proves nothing.

*(An earlier revision of this row read `Total: 136 Pass: 118`. Those were a Parts-A+B-only run
captured before 15 further assertions were added and never refreshed — the `Fail: 18` was right
and the totals were stale. Re-derived on the full A+B+C run.)*

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
| AC9 suite exits 0, Parts A/B/C all run | PASS | `C0 unmutated control is GREEN` present; `Total: 151` |
| AC10 `MIN_B` 49→81, `MIN_C` 11→13, `MIN_ASSERTIONS` 117→151, none decreased | PASS | raised by exactly the added counts; `MIN_ASSERTIONS == MIN_A+MIN_B+MIN_C` is asserted |
| AC11 linter exits 0 with non-zero scanned count | PASS | 71 workflows / 7 actions / 697 bodies |
| AC12 fixture suite exits 0, incl. `shell: bash` and same-line `; rc=$?` as must-FIRE | PASS | F4 and F2; `Total: 38 Pass: 38` (F9–F15 added at review) |
| AC13 reverting the fix makes the linter report the drift workflow | PASS | H3 (+ H3b control on the unmutated copy) |
| AC14 both suites registered and executing in the `scripts` shard | PASS | `[ok] scripts/lint-workflow-errexit-capture (10190ms)`, `[ok] ...-live (2031ms)` |
| AC15 all 17 confirmed sites fixed; linter finds none | PASS | 17 → 0, preserved across the review hardening |
| AC16 the two false-premise comments gone (excluding the corrective quote) | PASS | returns `0` |
| AC17 one tracking issue for the latent class | PASS | #7311 — see §Deferral |
| AC18 `actionlint` on every edited workflow | PASS (qualified) | see below |
| AC19 ADR-170 accepted, `Enforced by:` names linter + test + `test-all.sh`, alternatives incl. `defaults.run.shell` | PASS | ADR body |
| AC20 the 2026-07-02 learning appended to; no new file | PASS | `## Addendum — 2026-08-06 (#7304)` |
| AC21 PR body uses `Closes #7304` | PASS | PR body |
| AC22 `bash scripts/test-all.sh scripts` green | see §Shard result | both new suites `[ok]` |
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

The plan predicted a bare `grep -c 'set +e'` would return **14** against 7 statements. It
returns **15** on the shipped tree — the rationale comments repeat the literal more often than
either the plan or my first correction assumed, and the figure moved twice during the branch as
comments were added. That is exactly why the AC is anchored rather than pinned to a count: the
bare-token number is a property of the prose and drifts, while
`grep -cE '^[[:space:]]*set \+e[[:space:]]*$'` returns **7** and tracks the statements. Both my
own earlier "8" and the plan's "14" were point-in-time readings stated as facts.

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

Counted as **SITES** (`pr-auto-close-scanner.yml:84,85,86` is three, not one — the counting
convention is what made three different totals all look defensible):

| errexit origin | sites |
|---|---|
| INHERITED (no `set` line, or one without `-e`) | **5** |
| EXPLICIT `set -euo pipefail` | **8** |
| **total deferred** | **13** |

Only 5 of 13 are inherited-errexit sites; for the other 8 errexit is deliberate authorship, so a
gate anchored on inheritance would never match them and a second, separately justified rule would
be needed. Three different numbers were asserted for this set before it was counted by site (the
plan's 13-including-cla, a review pass's 2-inherited, my own 3-inherited/12-total). #7311 now
carries the by-site figures and the convention.

Net issue flow: **closing 1 (#7304), filing 1 (#7311) → net 0.**

## Post-merge (automated, no operator step)

AC24–AC28 are executed by the shipping agent after merge and appended here.

## Review findings (11-agent panel, report-only)

Panel run report-only and every fix applied from a known SHA, per the concurrent-agent
contamination rule. Agents: security-sentinel, observability-coverage-reviewer,
architecture-strategist, code-quality-analyst, pattern-recognition-specialist,
test-design-reviewer, user-impact-reviewer, code-simplicity-reviewer, git-history-analyzer.
Deterministic gates run inline: semgrep (**153 rules, 100% parsed, 0 findings** — non-vacuity
confirmed, since `--quiet` prints nothing on a clean run and a bad `--config` exits 7 while
still reporting 0), shellcheck (clean), actionlint (no new findings).

**The gate was blind to four capture shapes, two of them live in the scanned tree.** Of five
defect-shaped steps, it caught one. `echo "rc=$?"` — live at `fix-constraints-stage-a.yml:85`
and `:139` — evaded because the anchor required a separator before the identifier and a double
quote is none. Also `rc="$?"`, `rc=${?}`, bare `if [[ $? ]]` / `case $?`, `set -x; cmd; rc=$?`
(any `set`-matching line skipped its own capture), and a false heredoc opener that blanked the
rest of the body unbounded. Root cause of the deepest one: the gate judged errexit **at the
read** rather than **at the command**, so `cmd` / `set +e` / `rc=$?` — the mis-fix the
remediation text invites — reported clean. `scan_body` is now two passes. All ten evasion
shapes fire; calibration held at 17 → 0 throughout; F9–F15 pin each shape.

**Three behavioural defects outside the gate:**

1. `infra-validation.yml`'s job-failing guard still read `''` as 0. Fixed with
   `always() && (outcome != 'success' || exit_code != '0')`.
2. My own `|| true` on the CLA lookup conflated "lookup failed" with "nothing found" — a `gh`
   blip would file a duplicate and reset the 7-day escalation clock. Replaced with the
   sibling's `list_rc` capture. This was the PR's own lesson, violated by its own fix.
3. The drift check body now re-arms errexit before the `$GITHUB_OUTPUT` write.

**Four test guards were vacuous** and are fixed: B15 asserted presence not position; B17's
selector excluded the `verdict` consumer and its substring test could not see a neutered
conjunct; axis11's label matched `B14b`; axis5 could still mutate prose.

### Numbers that did not reproduce

Every load-bearing figure was independently re-derived. Four were wrong, all inherited or
stale, none changing a conclusion:

| claim | stated | measured |
|---|---|---|
| assignment-anchored rule reaches | 2 of 17 | **8 of 17** (9 bare) |
| pre-fix suite totals | 136 / 118 / 18 | **151 / 133 / 18** (`Fail: 18` was right) |
| bare `grep -c 'set +e'` | 8 | **15** (drifts with prose — this is why AC5 is anchored) |
| latent class | 12 sites, 3 inherited | **13 sites, 5 inherited / 8 explicit** |

The first is the one worth naming: it sat in the ADR paragraph asking the reader to trust a
measurement over intuition, it came from the plan, and I never re-derived it — the exact rule I
applied to every other plan-quoted figure in this session. One review claim was itself wrong and
was not adopted: "six days" between occurrence 5 and 6 is correct (`447211a1a` → `1af49f532` is
6 days 2 hours), not the 7 days a pass reported.

### Declined

`code-simplicity-reviewer` built a 35-line checker giving byte-identical verdicts on both trees
and recommended replacing the linter and splitting the PR three ways. The split is declined —
the plan that scoped this passed a 6-agent panel and CPO sign-off, and its Phase 2.10 gate makes
the ADR and gate deliverables of *this* plan. Its concrete simplifications were taken: the
zero-contribution `||`/`&&` arm is gone, the dead branch is gone, and the false justification for
continuation-walking is corrected (it is needed to report the command, not to detect the class —
the 35-line rule found the site my docstring claimed a physical-line matcher would miss).
