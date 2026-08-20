# Measurements — feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline

Every number the plan quotes is a precondition to re-derive, not a fact. This file records what was
actually measured at `/work` time, the exact command that produced it, and whether it CONFIRMED or
CONTRADICTED the plan's literal. Where a number was NOT measured it says so rather than restating
the plan.

All measurements taken 2026-08-20 from the worktree
`.worktrees/feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline` at base
`5cf9761a4`.

---

## 0.2 — issue states unchanged

```bash
for n in 7586 7587 7228 7462; do gh issue view $n --json state,title --jq "{n:$n,s:.state,t:.title}"; done
```

| Issue | State | Note |
|---|---|---|
| #7586 | **OPEN** | work target |
| #7587 | **OPEN** | work target |
| #7228 | **OPEN** | context only — **not** a work target, not closed by this PR |
| #7462 | **OPEN** | blocks #7228 per ADR-100's addendum |

**CONFIRMED** — matches the plan's Premise Validation.

---

## Run-conclusion distribution (the Problem Statement's headline figure)

```bash
gh run list --workflow=apply-web-platform-infra.yml --branch main --limit 60 \
  --json conclusion --jq '[.[]|.conclusion]|group_by(.)|map({(.[0]):length})'
# → [{"cancelled":1},{"failure":23},{"success":36}]
```

Plan states `[{"cancelled":1},{"failure":24},{"success":35}]`.
**CONTRADICTED, immaterially** — the window has advanced by one green run since the plan was
written. 24 non-green of the last 60 rather than 25. The workflow comment and the commit message
use the re-derived **23 failure + 1 cancelled**, not the plan's 24.

---

## 0.3(a) — the reachable deadline sum

Derived from the `arm_one` call sites themselves, not from the plan's table:

```bash
grep -nE "^arm_one .*'" apps/web-platform/infra/arm-heartbeats.sh
```

| Arm | Deadline (pre-change) | Deadline (post-change) | In merge-path tfstate? |
|---|---|---|---|
| `web_zot_consumer["web-1"]` | 230 | 230 | yes |
| `web_nic_guard["web-1"]` | 470 | 470 | yes |
| `web_zot_consumer["web-2"]` | 230 | 230 | yes |
| `web_nic_guard["web-2"]` | 470 | 470 | yes |
| `git_data_prd` | 230 | 230 | **no** — see 0.6(a) |
| `inngest_consumer` | 230 | **30** | yes |
| **Nominal Σ (all call sites)** | **1860** | **1660** | |
| **Reachable Σ (merge path today)** | **1630** | **1430** | |

**CONFIRMED** — all four sums match the plan exactly (1860 / 1630 pre, 1430 reachable post).

### …and the one place this CONTRADICTS the plan, materially

The plan sizes the ladder from the **reachable** sum (1430) but writes the guard against
`sum(arm_one deadlines)` — AC3, unqualified, i.e. every call site. Those are different numbers, and
the plan's own ladder does not satisfy its own guard:

```
plan:  arm_step_timeout ≥ Σ × 1.1  →  1620 (27 min) ≥ 1430 × 1.1 = 1573   ✓ against the reachable Σ
                                      1620          ≥ 1660 × 1.1 = 1826   ✗ against the guard's Σ
```

A call site that is absent from tfstate **today** is still a call site, and the wall-clock ceiling
has to hold on the day it is not absent. Resolved by sizing the ladder from the nominal Σ instead
of relaxing the guard:

```
(1) arm_step_timeout ≥ 1660 × 1.1 = 1826  →  31 min (1860 s)   ✓
(2) job_timeout − arm_step_timeout ≥ 111  →  2100 − 1860 = 240 ✓  (slack 129 s)
ladder: 1660 (work) < 1860 (step ceiling) < 2100 (job ceiling)
```

**So the `apply` job is `timeout-minutes: 35`, not the plan's 30, and the ARM step is 31, not 27.**
This is a deliberate deviation from AC3's literal `30`; see 0.7 for the constraint that made it
safe, and the Deviations section of the work report.

---

## 0.3(b) — p95 pre-gate duration (job start → ARM step start)

```bash
gh run list --workflow=apply-web-platform-infra.yml --branch main --limit 12 \
  --json databaseId,conclusion,event,createdAt --jq '.[]|[.databaseId,.conclusion,.event,.createdAt]|@tsv'
for id in 32360734255 32356859661 32318240780 32293304282 32288987090 32283291074; do
  gh api "repos/:owner/:repo/actions/runs/$id/jobs" \
    --jq '.jobs[]|select(.name=="apply")|{start:.started_at,completed:.completed_at,
          arm:([.steps[]?|select(.name|test("Arm web-host"))|{s:.started_at,c:.completed_at}]|first)}'
done
```

The six most recent **push** (merge) applies:

| Run | Job start | ARM step start | Pre-gate (s) | ARM step (s) | Apply job (s) |
|---|---|---|---|---|---|
| 32360734255 | 10:49:26 | 10:50:28 | **62** | 237 | 302 |
| 32356859661 | 10:05:01 | 10:05:59 | **58** | 240 | 302 |
| 32318240780 | 00:42:36 | 00:43:40 | **64** | 239 | 307 |
| 32293304282 | 19:29:56 | 19:31:47 | **111** | 237 | 350 |
| 32288987090 | 18:45:47 | 18:47:08 | **81** | 239 | 324 |
| 32283291074 | 18:02:01 | 18:03:32 | **91** | 240 | 335 |

Sorted: 58, 62, 64, 81, 91, **111**. **p95 = 111 s.**

Plan states 57/58/64/81/91/111, p95 111. **CONFIRMED** — the 57 has aged out of the window and a 62
has entered; **p95 is unchanged at 111 s**, so term (2) of the inequality carries no stale number.

Two figures fall out of the same pull and both **CONFIRM** the plan: the ARM step is 237–240 s on
every one of the six (the plan cites 240), and the apply job is 302–350 s (the plan cites 302).

---

## 0.4 — the errexit premise, verified directly

```bash
awk 'NR>=1054 && NR<=1070' .github/workflows/apply-web-platform-infra.yml | grep -nE 'shell:'   # → no match
gh run view 32360734255 --log | grep -F 'Arm web-host probe heartbeats' | grep -F 'shell:'
# → apply  Arm web-host probe heartbeats (…)  2026-08-20T10:50:28.0569331Z shell: /usr/bin/bash -e {0}
```

The step declares **no `shell:` key** and the runner logs the invocation as `/usr/bin/bash -e {0}`.
**Errexit is ON in that step today.** **CONFIRMED** — this is the correction the plan's panel made
against its own first draft, and it holds. Both the reworked script and the new sweep step declare
`set +e` explicitly rather than relying on omitting `-e`.

---

## 0.5 — the bound suites, GREEN before the first edit

Run at base `5cf9761a4` with no working-tree changes, so a later red is attributable.

| Suite | Result |
|---|---|
| `bun test plugins/soleur/test/terraform-target-parity.test.ts` | 130 pass, 0 fail (rc 0) |
| `bun test plugins/soleur/test/stock-preflight-coverage.test.ts` | 9 pass, 0 fail (rc 0) |
| `bash tests/scripts/test-preapply-entrypoint-gate.sh` | 43 passed, 0 failed (rc 0) |
| `bash tests/scripts/test-vector-redeliver-wiring.sh` | 34 passed, 0 failed (rc 0) |
| `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` | 23 passed, 0 failed (rc 0) |

---

## 0.6(a) — `git_data_prd` is absent from the merge-path tfstate

Read from a run's ARM-step log, not from a committed file, exactly as the task requires:

```bash
gh run view 32360734255 --log | grep -F 'Arm web-host probe heartbeats' | grep -iE 'git-data|not present'
# → 2026-08-20T10:50:30.6681631Z ##[notice]git-data-prd: not present in tfstate
#    (address betteruptime_heartbeat.git_data_prd) — skipping (this apply path did not create it).
```

**CONFIRMED** on the most recent merge apply. The same log also confirms the plan's cost case
verbatim: the five healthy arms run 10:50:30.024 → 10:50:30.661 (**0.64 s for five arms**) and the
`inngest_consumer` arm runs 10:50:30.87 → 10:54:25.98 (**235.1 s** against a 230 s nominal deadline,
i.e. **+2.2 %** overhead from the uncounted round-trips, consistent with the plan's +3 %).

---

## 0.6(b) — `$RUNNER_TEMP` persists across steps within a job

**Load-bearing for the whole sweep design**, and the plan flags it as unverifiable from the repo.
Confirmed EMPIRICALLY from a real run rather than from GitHub's documentation.

There is no dispatchable probe for this, so the measurement is a live run of a workflow that
already depends on the property. `scheduled-terraform-drift.yml` writes
`${RUNNER_TEMP}/plan-output.txt` in one step and reads it in another, two steps later:

```bash
python3 - <<'PY'   # enumerate cross-step $RUNNER_TEMP paths repo-wide
import re,glob,collections
for f in sorted(glob.glob('.github/workflows/*.yml')):
    lines=open(f).read().split('\n'); step=-1; names={}; per=collections.defaultdict(set)
    for i,l in enumerate(lines):
        if re.match(r'^\s{6,8}- (name|uses|id):',l): step+=1; names[step]=l.strip()[:60]
        for m in re.finditer(r'RUNNER_TEMP\}?/([A-Za-z0-9._/-]+)',l): per[m.group(1)].add(step)
    for p,s in per.items():
        if len(s)>1: print(f,p,sorted(s),[names.get(x,'?') for x in sorted(s)])
PY
# → scheduled-terraform-drift.yml plan-output.txt [6,17,18]
#      ['- name: Terraform plan (drift detection)', '- name: Create or update drift issue',
#       '- name: Prepare email content']

gh api repos/:owner/:repo/actions/runs/32337769628/jobs \
  --jq '.jobs[]|.steps[]|[.number,.conclusion,.name]|@tsv' | grep -iE 'plan \(drift|drift issue|email content'
# → 8  success  Terraform plan (drift detection)
#    19 success  Create or update drift issue
#    20 success  Prepare email content

gh run view 32337769628 --job 96330532329 --log | grep -nF 'plan-output.txt'
# → :279 (write, 06:00:28.5378184Z)  :637 :657 (read, 06:01:25.886…Z)  :706 :707 (read)

gh api repos/jikig-ai/soleur/issues/comments/5352021203 --jq '.body' | head -30
```

The write happens at **06:00:28.53** in step 8; the reads happen at **06:01:25.89** in step 19 —
~57 s later, two steps apart, in the same job, under `shell: /usr/bin/bash -e {0}` (so a failed
`cat` would have killed the step). The resulting comment on issue #7316 carries the terraform plan
output **verbatim**.

**CONFIRMED. `$RUNNER_TEMP` survives step boundaries within a job, so the design is unchanged** —
`$RUNNER_TEMP/armed-unconfirmed` stays a plain file written by the ARM step and read by the
`if: always()` sweep step. No step output and no artifact round-trip is required.

(The alternatives, had it failed, and why they would have been worse: a job `outputs:` is
explicitly not the design and is unreliable on the cancelled path the sweep exists for, and an
`upload-artifact`/`download-artifact` round-trip is unreliable on that same path for the same
reason. Recording this because it also settles the sweep-count question in Phase 2 — see the
Deviations section.)

---

## 0.7 — observed queue depth / wait on `terraform-apply-web-platform-host`

**The plan explicitly did NOT measure this** ("the binding constraint is per-merge queue wait,
which this plan has **not** measured"). It is the constraint the budget raise rests on, so it is
measured here.

The group is shared by **two** workflows (`apply-web-platform-infra.yml` and
`apply-deploy-pipeline-fix.yml`), so both are pulled:

```bash
python3 - <<'PY'
import json,subprocess,datetime
def runs(wf,n):
    o=subprocess.run(["gh","run","list",f"--workflow={wf}","--limit",str(n),"--json",
                      "databaseId,event,conclusion,createdAt,updatedAt,status"],capture_output=True,text=True)
    return [dict(x,wf=wf) for x in json.loads(o.stdout)]
def t(s): return datetime.datetime.fromisoformat(s.replace("Z","+00:00"))
all_=[r for r in runs("apply-web-platform-infra.yml",40)+runs("apply-deploy-pipeline-fix.yml",40)
      if r["status"]=="completed"]
all_.sort(key=lambda r:t(r["createdAt"]))
depths=[sum(1 for o in all_ if o is not r and t(o["createdAt"])<=t(r["createdAt"])<t(o["updatedAt"]))
        for r in all_]
import collections; print("depth histogram:",dict(collections.Counter(depths)))
print("durations:",sorted(round((t(r["updatedAt"])-t(r["createdAt"])).total_seconds()) for r in all_))
PY
```

Window **2026-07-16T14:03:19Z → 2026-08-20T10:54:29Z (35.0 days), 80 completed runs**:

| Quantity | Measured |
|---|---|
| Overlap-depth histogram | `{0: 69, 1: 11}` — **depth never exceeded 1** |
| Longest run in the group | **1422 s = 23.7 min** |
| p95 run duration | ~620 s = 10.3 min |
| Median run duration | ~103 s |

And the wait actually experienced, from run creation to the first job starting, over the 16 most
recent `apply-web-platform-infra.yml` runs (same script, `pf_q` column):

```
3, 3, 5, 14, 14, 21, 22, 30, 62, 65, 185, 319, 333, 359, 434, 492   (seconds)
```

Max **492 s = 8.2 min**; median ~46 s.

**Verdict: does NOT contradict the raise, and it is what makes the deviation to 35 defensible.**
Three things follow. (a) Depth never exceeded 1 across 35 days, so at most one run has ever been
waiting — the raise widens a tail bound, it does not create a queue. (b) `timeout-minutes` is a
CEILING, not a duration: the modal apply is 302 s today and drops below 120 s after the
`inngest_consumer` resize, so the *typical* mutex hold **falls** by ~79 % while the worst case
rises. (c) The group demonstrably tolerates far more already — `apply-deploy-pipeline-fix.yml`'s
own apply job is `timeout-minutes: 90`, and the longest run actually observed in this group is
23.7 min.

The honest cost, stated at its true size: the group is **workflow-level**, so the run-level worst
case is the **sum across jobs in the run** — now `apply 35 + notify-apply-failure 5 = 40 min`, not
the plan's 35. The `registry_luks_recut` mutex-accounting comment is updated with this number in the
same PR (task 4.4).

---

## 5.7 — every row of both mutation matrices, executed against the REAL artifacts

A guard that cannot be driven RED is vacuous. Two independent batteries were run.

### (a) `arm-heartbeats.test.sh`'s own battery — Guard 2 rows 6-9 at the script layer

Six rows, each mutating a pristine COPY of `apps/web-platform/infra/arm-heartbeats.sh` and
asserting the edit landed before running it. Run with `bash apps/web-platform/infra/arm-heartbeats.test.sh`:

```
PASS: M-wallclock mutation landed against a pristine copy
PASS: M1 RED: the sleep-tally blows T3's 450s observed-clock bound (measured 695s)
PASS: M1 and it does so while REPORTING a compliant elapsed (230s) — which is why T3 asserts the clock
PASS: M-unpause-rollback mutation landed against a pristine copy
PASS: M2 RED: the terminal PATCH is no longer paused:true
PASS: M-no-state-add mutation landed against a pristine copy
PASS: M3 RED: a failed rollback no longer leaves the id on the sweep's books (T5 would be vacuous)
PASS: M-soft-failed-rollback mutation landed against a pristine copy
PASS: M4 RED: the apply job goes GREEN while a monitor is live-and-unfed
PASS: M-deadline-230 mutation landed against a pristine copy
PASS: M5 RED: the inngest arm advertises its old 230s budget again
PASS: M5 and burns it: the observed clock passes 230s
PASS: M6 control: the UNMUTATED copy still soft-lands at rc=0
PASS: M6 control: and still advertises the 30s deadline
```

Suite total: **69 passed, 0 failed (69 assertions)**, rc 0.

**The M1 row is the one worth reading.** Under the pre-#7587 sleep tally the SUT still *reports* a
compliant `230s` elapsed while the observed clock reaches **695 s**. An assertion on the reported
number alone passes over the defect — which is exactly what a regex-over-YAML guard would have
been able to check. That is the measured case for the extraction.

### (b) The real-artifact battery — Guard 1 and Guard 2 rows 1-5, 7-9 and the harness rows

Each row mutates the SHIPPED `.github/workflows/apply-web-platform-infra.yml` /
`arm-heartbeats.sh` in place, runs `bun test plugins/soleur/test/terraform-target-parity.test.ts`,
restores from a pristine backup and asserts byte-identity. A row whose edit does not land is
reported as a failure rather than counted as a pass, and an unmutated control runs both before and
after so a red baseline cannot masquerade as a caught mutation.

```
CONTROL (unmutated): rc=0  GREEN
  OK G1-M1  predicate -> needs.apply.result == 'failure'
        want=RED got=RED
  OK G1-M2  delete the notify-apply-failure job
        want=RED got=RED
  OK G1-M3  drop the needs.preflight.result clause
        want=RED got=RED
  OK G1-M4  narrow the trigger clause to push only
        want=RED got=RED
  OK G1-M5  drop preflight from needs: AND from the predicate
        want=RED got=RED
  OK G1-H2  reorder the operands (semantics identical)
        want=PASS got=PASS
  OK G2-M1  lower the apply job back to timeout-minutes: 15
        want=RED got=RED
  OK G2-M2  delete every arm_one call site
        want=RED got=RED
  OK G2-M3  add a 2nd arm_one whose deadline pushes the sum over
        want=RED got=RED
  OK G2-M4  remove the ARM step's step-level timeout-minutes
        want=RED got=RED
  OK G2-M5  remove the if: always() re-pause sweep step
        want=RED got=RED
  OK G2-M7  flip the sweep's PATCH body to {"paused":false}
        want=RED got=RED
  OK G2-M8  delete || true from the sweep's re-pause PATCH
        want=RED got=RED
  OK G2-M9  delete the sweep's ::add-mask:: on the re-minted token
        want=RED got=RED
  OK G2-H3  apply job with NO timeout-minutes at all
        want=RED got=RED
  OK G2-H4  step ceiling written 32 instead of 31 (still < job)
        want=PASS got=PASS
POST-RESTORE control: rc=0  GREEN

=== mutation rows: 16 executed, 0 unexpected ===
```

**One row initially SURVIVED, and the finding is in the guard rather than the code.** `G2-M8`
(delete `|| true` from the sweep's re-pause `PATCH`) was reported PASS on the first execution: the
assertion was a bare `/\|\|\s*true\s*\)/` over the step body, and the step's OWN Doppler line
(`doppler secrets get … 2>/dev/null || true)`) satisfies it. The guard was re-anchored on the
construct it protects — `--data-raw '{"paused":true}' … || true)` — and the row then goes RED.
This is `cq-assert-anchor-not-bare-token`, found by executing the matrix rather than by reading it.

**Rows not in this battery, and why.** Guard 2 row 6 (the wall-clock accounting) is in battery (a)
because it is only checkable behaviourally; the parity suite carries the cheap structural
companion, and its comment says so rather than claiming it is the proof. Guard 1's H1 is
row-identical to G1-M2 (a subject-less fixture) and is additionally asserted synthetically inside
the suite, which is where it runs in CI forever.

### Axes this battery did NOT edit, stated plainly

- **Assertion dispatch** — the batteries do not neuter `expect`/`pass`/`fail` themselves. The
  `.sh` suite carries a minimum-cardinality floor (55) that catches an emptied case loop, but not a
  gutted `assert` helper.
- **Fixture direction for the workflow-side guards** — `channelTruthTableViolations` quantifies
  over the full 4 x 4 x 3 cross product, so the direction axis is covered there by construction;
  the ladder guard is one-sided (it has no "too generous a ceiling" arm, because there is no upper
  bound to violate).
- **Population growth on the sweep** — no row ADDS a second `if: always()` state-file step. The
  guard asserts `sweeps.length === 1`, so a second one reds, but that assertion is not
  mutation-proven.

---

## 6.3 — acceptance criteria walk

See the section appended below.
