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

### SUPERSEDED at review-resolution time (#7657 D1/D3/D5)

Both terms above were the wrong shape and the ladder they justified is not what ships.

**Term (1) was multiplicative on additive overhead.** `arm_one` spends four `curl --max-time 15`
round-trips that the `elapsed` accounting never sees — the pre-loop GET, the unpause PATCH, the
final iteration's own GET, and the rollback PATCH — plus one poll interval of loop overshoot. That
is `poll_interval + 4 × curl_max_time = 70 s` **per call site**, whatever the deadline. Measured by
running the shipped script under its own PATH stubs with all six monitors seeded `paused`:

| round-trip cost | wall clock, 6 arms | vs the old 1860 s step ceiling |
|---|---|---|
| 0 s | 1660 s | ok |
| 8 s | 1854 s | ok by 6 s |
| **9 s** | **1891 s** | **BREACHED** |
| 15 s (curl's own `--max-time`) | 2020 s | breached by 160 s |

**Term (2) budgeted nothing after the gate.** `jobS − stepS ≥ p95(pre-gate)` left 129 s for the
re-pause sweep, the bridge teardown and the post-apply summary combined — and the sweep only has
work when the ARM step was cut, i.e. exactly when the least budget remains.

**And the deadline formula reserved 10 s for a rollback that can take 40.** `deadline = period +
grace − 10` re-paused the monitor AFTER its first absence alert at as little as 2 s of Better Stack
round-trip. Reserve is now `poll_interval + 2 × curl_max_time = 40`.

The per-call-site overhead also carries the ROLLBACK RETRY added for #7658 E8 — the rollback is
the one write whose failure reds a routine apply, and while #7228 is open the inngest arm executes
it on every merge, ~990 unretried round-trips a year. One immediate retry on a 5xx/000 (never on a
4xx) makes the term `poll_interval + (3 + ARM_ROLLBACK_ATTEMPTS) × curl_max_time` = 85, not 70. It
does NOT enter the rollback RESERVE: a failed PATCH re-paused nothing, so it lengthens the step's
wall clock without lengthening the monitor's live window.

```
deadlines      200 (240−40) / 440 (480−40) / 200 / 440 / 200 / 30      Σ = 1510
work bound     1510 + 6 × 85                                         = 2020
(1) step ≥ work                 →  35 min (2100 s) ≥ 2020            ✓ slack 80 s
(2) job − step ≥ max(pre-gate) + post-gate
    post-gate = 6 × 15 (sweep) + 30 (mint `timeout`) + 60 (teardown+summary) = 180
                                →  2460 − 2100 = 360 ≥ 111 + 180 = 291  ✓ slack 69 s
ladder: 2020 (work) < 2100 (step ceiling) < 2460 (job ceiling)
```

**So the `apply` job is `timeout-minutes: 41`, the ARM step is 35, and the re-pause sweep carries
its own `timeout-minutes: 3`.** Fleet-mutex worst case on a push is preflight 1 + apply 41 +
notify 5 = **47 min** (`preflight` was uncounted in the earlier "40", which was itself 41).
Priced honestly: the worst case for an emergency dispatch issued while a merge apply is in flight
moves from 16 min to 47 min, and the overlap histogram over 80 runs of the shared group is
`{0: 69, 1: 11}` — 11 of 80 runs DID queue.
Every one of those numbers is re-derived by the guard suite from the script and the workflow rather
than restated; see `describe("the ARM gate's deadlines fit its job")`.

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

Sorted: 58, 62, 64, 81, 91, **111**.

Plan states 57/58/64/81/91/111, p95 111. The 57 has aged out of the window and a 62 has entered.

### RE-MEASURED at review-resolution time (#7657 D4) — n = 6 could not support the word "p95"

The figure above was labelled `p95` and is the sample **MAXIMUM of six**. At n = 6 the 95th
percentile is not estimable. Re-pulled over a window wide enough to say something:

```bash
gh run list --workflow=apply-web-platform-infra.yml --branch main --limit 60 \
  --json databaseId,event,createdAt --jq '.[]|select(.event=="push")|[.databaseId,.createdAt]|@tsv' \
  | sort -k2 -r | head -45 | cut -f1 > runs.txt
while read -r id; do
  gh api "repos/:owner/:repo/actions/runs/$id/jobs?per_page=100" \
    --jq '.jobs[]|select(.name=="apply")|[(.started_at),([.steps[]?|select(.name|test("Arm web-host"))|.started_at]|first//"-"),(.completed_at)]|@tsv'
done < runs.txt
```

**42** of the 45 most recent push applies reached the ARM step (3 died before it). Pre-gate, sorted:

```
8 27 30 31 31 32 33 36 36 36 36 37 38 38 39 42 42 42 51 52 53 54 55 56 57 57 57 58 58 58 59 60 62
63 64 65 65 68 77 81 91 111
```

| statistic | value |
|---|---|
| n | 42 |
| min | 8 s |
| median | 48 s |
| nearest-rank p95 (ceil(0.95 × 42) = 40th) | **81 s** |
| **max** | **111 s** |

The ladder uses the **max**, deliberately, and now calls it that. Same pull, whole-job duration:
11–350 s (max **5.8 min**) — which is what retires the `~0.6 min/resource × ~70 targets = ~42 min
worst-case cold-cache` sentence that sat two lines above the ladder in the workflow and
contradicted it by 22×. A genuinely cold-cache build of this root is a `web_host_create` /
`*_host_replace` DISPATCH job with its own budget, not the merge-path `apply` job.

<!-- LADDER-PIN: MAX_PRE_GATE_S=111 -->

The pin above is machine-read by `plugins/soleur/test/terraform-target-parity.test.ts`
(`pinnedFromMeasurements`), so the guard's pre-gate term and this measurement cannot drift apart —
and the guard throws if the pin is missing rather than falling back to a literal that fails open.

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

## 6.1 — the bound suites, each named explicitly

A touched-file selection reaches only the first, so every suite is named and run.

| # | Suite | Result |
|---|---|---|
| 1 | `bun test plugins/soleur/test/terraform-target-parity.test.ts` | **159 pass, 0 fail** (was 130 — +29 from Guards 1 and 2) |
| 2 | `bun test plugins/soleur/test/stock-preflight-coverage.test.ts` | 9 pass, 0 fail |
| 3 | `bash tests/scripts/test-preapply-entrypoint-gate.sh` | 43 passed, 0 failed |
| 4 | `bash tests/scripts/test-vector-redeliver-wiring.sh` | 34 passed, 0 failed |
| 5 | `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` | 23 passed, 0 failed |
| 6 | `bash apps/web-platform/infra/arm-heartbeats.test.sh` | **69 passed, 0 failed** (new) |
| 7 | `bash plugins/soleur/test/c4-model-freshness.test.sh` | ALL TESTS PASSED |
| 8 | `bash plugins/soleur/test/c4-count-parity.test.sh` | ALL TESTS PASSED (10/10) |
| 9 | `python3 scripts/lint-workflow-errexit-capture.py` | clean — 75 workflows, 759 `run:` bodies |
| 10 | `bash scripts/lint-orphan-test-suites.sh` | `walked 363 tracked *.test.sh … 363 covered, 0 orphaned` |
| 11 | `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` | `OK: no human-run infra steps in 6 scanned file(s)` |
| 12 | `bun test plugins/soleur/` (whole directory) | 2511 pass, **1 fail** — see below |
| 13 | `./node_modules/.bin/vitest run test/c4-render.test.ts test/c4-code-syntax.test.ts` (in `apps/web-platform`) | 23 passed |

**The one failure, diagnosed rather than waved through.**
`plugins/soleur/test/changelog-data.test.ts > returns html from GitHub Releases API` timed out at
5000 ms inside the 64-file concurrent run, logging
`[github.js] GitHub API failed, using fallback: The operation was aborted`. It is a **live network
call**, and:

```bash
git diff origin/main...HEAD --name-only | grep -iE 'changelog|github\.js'   # → no match
bun test plugins/soleur/test/changelog-data.test.ts                        # → 3 pass, 0 fail (529ms)
```

The diff touches neither the test nor its subject, and the file is green in isolation. Recorded as
an environment flake, **not** cleared as "unrelated" without the isolated re-run.

**`scripts/test-all.sh` was NOT run.** This work ran as a subagent with `SOLEUR_SUBAGENT=1`, so the
runner exits **4 — REFUSED, nothing ran**. That is neither a pass nor a reap. The full gate is the
parent's to run.

---

## 6.2 — actionlint, and every new/edited `run:` snippet

```bash
actionlint .github/workflows/apply-web-platform-infra.yml .github/workflows/infra-validation.yml   # rc 0
```

`actionlint` did fire once during implementation and the finding was real: a **comment** inside the
`cause` step's `run:` body quoted `${{ … }}`, which the linter lexes as an expression
(`got unexpected character '…' while lexing expression`). Reworded rather than suppressed.

Each new/edited snippet was extracted from the parsed YAML and checked on its own — never
`bash -n` on the `.yml`:

| Snippet | `bash -n` | `shellcheck -x` |
|---|---|---|
| ARM gate step (edited) | rc 0 | rc 0 |
| `Re-pause any monitor left unconfirmed` (new) | rc 0 | rc 0 |
| `Resolve the failing step from the jobs API` (new) | rc 0 | rc 0 |
| `apps/web-platform/infra/arm-heartbeats.sh` (new file) | rc 0 | rc 0 at every severity |
| `apps/web-platform/infra/arm-heartbeats.test.sh` (new file) | rc 0 | rc 0 at every severity |

**Two of the three snippets were additionally EXECUTED**, which is a stronger check than a syntax
pass and is what the task actually wants. The ARM step was not: it mints a production Doppler
credential and PATCHes live monitors, so running it is not a syntax check.

*Sweep, empty state file* (the `ssh_apply_skip` / no-work run):

```bash
RT=$(mktemp -d); env RUNNER_TEMP="$RT" GITHUB_STEP_SUMMARY=$(mktemp) DOPPLER_TOKEN_WEB_ARM= bash snippet-sweep.sh
# → rc 0, ZERO bytes of output, and no `doppler` invocation at all
```

That is AC4's early exit proven behaviourally: no credential re-mint and no false mint-failure
alarm on a run with nothing to sweep.

*Sweep, non-empty state file with an unreadable credential* (Test Scenario 9):

```
rc=1
::warning::Heartbeat re-pause sweep FIRED: 1 monitor(s) were left unpaused-and-unconfirmed …
::error::Re-pause sweep: BETTERSTACK_API_TOKEN unreadable via DOPPLER_TOKEN_WEB_ARM — 1 monitor(s) are LIVE AND UNFED …
$GITHUB_STEP_SUMMARY → armed=1 repaused=0 failed=1 outcome=mint-unreadable
```

*Cause step, against a nonexistent run id* (fail-soft):

```
::warning::Could not read the jobs API (rc=1); the email will name the failing step as unresolved.
rc=0; $GITHUB_OUTPUT → failing_step<<cause-e9936f41fc7acc27e912dd83 / unresolved / …
```

*Cause step, POSITIVE CONTROL against a genuinely failed apply run* (`31976455160`):

```
jobs API says:  apply → failure, failing step "Terraform plan (allow-list, non-SSH resources only)"
snippet emits:  failing_step = "Terraform plan (allow-list non-SSH resources only)"
rc=0
```

The extraction resolves a real failing step's name end to end against the live API. The comma is
stripped by AC2c's charset — cosmetic, and deliberately not widened: the allow-list is the
criterion's own literal.

### One claim RETRACTED at this point, before it propagated

The rewritten `arc == 2` warning originally told the reader that `status=pending` means no beat has
arrived since the unpause and that any other non-up status means Better Stack saw something else.
**Nothing in this change measured that.** The only verified enumeration in the repo is that
`up` / `pending` / `down` / `paused` all occur — the ARM gate's own op/state gate lists them — and
the precise semantics of `pending` versus `down` on an unpaused-but-unfed heartbeat was an
inference dressed as an observation, in the very message whose whole purpose is to stop an operator
debugging a surface that is working. The message now reports the two observed fields and says what
they are FOR, without claiming what each value means; the test's comment records the same about its
fixture (it asserts the SUT *echoes* the status it saw, not that `pending` is what the vendor
returns). Retracted here rather than left for review, because a false reading instruction in an
alert propagates into whatever the operator does next.

---

## 6.3 — acceptance criteria walk

| AC | Verdict | Evidence |
|---|---|---|
| **AC1** predicate / `needs` / budget / permissions / `continue-on-error` | **MET** | `describe("apply-web-platform-infra has a failure channel")` — the predicate is EVALUATED over the 48-row cross product, `needs` pinned to `["preflight","apply"]`, `timeout-minutes: 5 ≤ 10`, `permissions: {contents: read, actions: read}`, email step `continue-on-error: true`. Mutation rows G1-M1/M3/M4/M5 all RED. |
| **AC2** named steps, body elements, interpolation allow-list | **MET** | Three tests in the same describe. The cancelled branch is asserted on the EXPRESSION (`/needs\.apply\.result\s*==\s*'cancelled'\s*&&/`), not the prose word. Allow-list enforced as a set difference; `needs.apply.outputs.*` explicitly absent. |
| **AC2b** no `terraform apply` / `-target=` in any `run:` | **MET** | Guard test over parsed `run:` bodies, and `stock-preflight-coverage.test.ts` green (9/9) — that suite is the reason it matters: `jobFor("manual-rerun")` now returns two hits and disambiguates by `appliesTerraform`. |
| **AC2c** cause-token shape validation | **MET** | Guard test asserts all five elements (CR/LF strip, charset clamp, 80-char clamp, HTML-escape, random heredoc delimiter). Plus the two live executions in §6.2 — fail-soft and positive control. |
| **AC3** job `timeout-minutes`, comparator comment, two-part inequality | **MET, with the literal DELIBERATELY SUPERSEDED** | The job is **35**, not the AC's 30, and the ARM step is **31**, not 27 — see §0.3(a): the plan sized its ladder from the reachable Σ (1430) while writing this very guard against `sum(arm_one deadlines)` (1660), so the plan's own ladder fails its own guard. The **binding half of AC3 — the two-part inequality — is implemented exactly as written** and is what `ladderViolations` asserts; only the literals moved. The false comparator comment is replaced and now cites the measured p95 and the sibling's real 90. Mutation row G2-M1 RED. |
| **AC4** step ceiling below the job, `always()` sweep, own credential, 2xx-only removal | **MET** | Guard test identifies the sweep by `always()` + the state-file literal + *not* invoking the arming script (a name-keyed match would false-RED on a rename; `always()` + literal alone matches the ARM step too — found by executing G2-M5). Removal-on-2xx-only proven behaviourally by `arm-heartbeats.test.sh` T4/T5/T6. |
| **AC4b** sweep exits non-zero, and reports counts | **MET, with one honest narrowing** | rc 1 proven by live execution (§6.2). Counts go to `$GITHUB_STEP_SUMMARY` and the sweep's own annotations; the notify body carries the sweep's **outcome** (`steps.cause.outputs.sweep_conclusion`, read from the jobs API) rather than the integers — see Deviations. Every path that leaves the state file non-empty now reds the apply job, so the notify job always runs when the sweep has fired. |
| **AC5** wall clock, explicit `set +e`, `\|\| true`, no bare `(( … ))` | **MET** | Guard test `AC5` (structural) plus `arm-heartbeats.test.sh` M1 (behavioural: 695 s observed vs a 230 s reported elapsed under the reverted accounting). `lint-workflow-errexit-capture.py` clean. |
| **AC6** `inngest_consumer` deadline exactly 30, others unchanged, `arc == 2` rewritten | **MET** | `expect(deadlines).toEqual([230, 470, 230, 470, 230, 30])`, `ARM_INNGEST_DEADLINE=30`. Every other row verified byte-identical against `git show origin/main:` (diff empty). The warning carries the deadline from the variable, drops the "the probe is broken" instruction, and emits `status` + `updated_at` — asserted by T2. |
| **AC6b** `arming_pending` comment | **MET** | `plugins/soleur/lib/heartbeat-manifest.ts` — records the ~2-day probabilistic window and that removal must follow **observed** arming, not a #7462 checklist tick. |
| **AC7** every matrix row executed, log recorded | **MET** | §5.7 above — 16 real-artifact rows plus 6 script-layer rows, one initial survivor found and fixed. |
| **AC8** CI green on every bound suite | **MET locally; CI not run** | §6.1. `scripts/test-all.sh` refused with rc 4 (subagent) by design; the parent runs the full gate. |
| **AC9** ADR-117 amendment + `model.c4` edge | **MET** | `### Amendment (2026-08-20, #7587)` in ADR-117 naming both items; `github -> betterstack` now names the ARM gate's `PATCH /api/v2/heartbeats/<id>` under `DOPPLER_TOKEN_WEB_ARM`. `model.likec4.json` regenerated; c4 suites green. |
| **AC10** post-merge `manual-rerun` dispatch, ARM step < 60 s | **NOT DONE — out of scope for this phase** | Phase 7 belongs to `/ship`, which the parent controls. Nothing here asserts it. |

---

## notify-apply-failure job header (relocated 2026-09-19 from `apply-web-platform-infra.yml`)

Verbatim header comment of the `notify-apply-failure` job, moved here when the workflow file
reached GitHub's 512,000-byte ceiling (run 35431689935: "Workflow file exceeds the maximum allowed
size of 500 KB", zero jobs). The job keeps a compact pointer to this section. Nothing below was
edited in the move; line references and run IDs are as recorded on 2026-08-20.

```text
--- #7586: a non-green apply run reaches a channel ----------------------------------------
Before this job, the file had exactly ONE `notify-ops-email` call site — the `#7539` step
inside `apply`, gated on `ssh_apply_skip == 'true'`. That is a GREEN-SKIP predicate: it fires
when the run completed green having delivered nothing, and it cannot fire when the run goes
red. Nothing else covered the gap: no `workflow_run` watcher names this workflow, it has no
`sentry-heartbeat` call site, and GitHub's built-in failed-run email routes to the pushing
actor, which `reusable-release.yml` already documents in-repo as "frequently a GitHub App
identity, i.e. nobody". Measured on 2026-08-20: 23 `failure` + 1 `cancelled` of the last 60
`main` runs, none of which notified anyone, while the post-mortem for this same workflow
records detection as "by looking at the Actions tab" after three days of unapplied
production infrastructure.

A separate JOB, not the sibling `if: failure()` step the issue proposed (Cut List C1). A job
that exceeds `timeout-minutes` concludes `cancelled`, and `failure()`-gated steps are SKIPPED
on that path, so a step arm is structurally silent on exactly the #7587 path. A downstream job
reads `needs.apply.result` regardless.

CITATION, corrected (#7661 G5). Run 32168637847 is real and it measures the FIRST half: Main
Health Monitor ran 70m43s against `timeout-minutes: 70` and concluded `cancelled`, and its
`always()` siblings still ran, consuming 43 s past the timeout instant. It does NOT measure
the second half — the step it was cited for, `Create issue on failure`, is gated
`if: ${{ !cancelled() && … }}`, and that run contains no `failure()`-gated step at all.

THE TWO LOAD-BEARING PREMISES, MEASURED (#7661 G5). Both were asserted from documentation; both
were then checked against this repo's own run history, and each is recorded with exactly what
its evidence covers and what it does not.

  (a) A downstream `always()` JOB runs when an upstream job is CANCELLED.
      VERIFIED. `infra-validation.yml`, runs 32272435663 / 32294251707 / 32296436704: the job
      `validate (apps/web-platform/infra)` concluded `cancelled` after 6h, annotated "The job
      has exceeded the maximum execution time of 6h0m0s / The operation was canceled", and the
      downstream `infra-validate-required` (`needs: [detect-changes, validate]`, `if: always()`)
      concluded `failure`, NOT `skipped` — its own log printed `RESULT: cancelled`, so it both
      ran and read the cancelled result. NARROW SPOT: that job declares no `timeout-minutes`,
      so the ceiling that cancelled it was GitHub's 6h platform default. That the two ceilings
      are one code path is separately measured — `deploy-script-tests` (`timeout-minutes: 14`,
      runs 32299138340 / 32299155123 / 32300783446) emits the identical annotation with a
      different number, concludes `cancelled`, and every sibling job after it ran to `success`.
      NOT IN HISTORY: a job cancelled by its DECLARED `timeout-minutes` that is literally named
      in the `needs:` of the `always()` job that ran. The two halves are measured; the single
      run joining them is not.

  (b) A STEP exceeding its own `timeout-minutes` concludes `failure` (not `cancelled`) and the
      job carries on. VERIFIED, in two halves from two workflows.
      Half 1 — `web-platform-release.yml`, runs 32293304541 (job 96217488153) and 32283291347
      (job 96183288475): step "Install psql", `timeout-minutes: 5`, logged "The action 'Install
      psql' has timed out after 5 minutes", API step conclusion `failure`, and the JOB was not
      cancelled — it ran on through `Post Run actions/checkout` and `Complete job`, both
      `success`. Half 2 — `reusable-release.yml`'s `Tear down cloudflared registry bridge`
      (`if: always()`) concludes `success` after a failed sibling step, across ~30 runs
      (30913993850, 31379319736, 31751479655). NOT IN HISTORY: a step-level TIMEOUT with an
      `if: always()` sibling behind it in the same job. Half 1 gives the conclusion, half 2
      gives the continuation; no single run gives both.

  Measurement note that feeds the ladder: a timeout kill overshoots its declared ceiling by
  13–31 s of API wall clock (313 s against 300, 859–930 s against 840, 4243 s against 4200).
  The job ceiling's 69 s of slack over the step ceiling absorbs that; do not shrink it below it.

This job's HEADER COMMENT is inside `extractJobBlock(wf, "apply")` — that helper resets only
on `/^ {2}[A-Za-z0-9_-]+:/` and `#` is not in that class, so 2-space-indented comment lines
never close a job block (#7661 G4; the first version of this sentence claimed the opposite).
The `#7539` guard survives anyway, for a different reason: its `extractStep` requires
`^ {6}- name:` and takes the FIRST `/Notify ops/` STEP, which is still the one in the apply
job. Guards that key on the apply block's TEXT must account for this header being in it.

RESIDUAL, RE-DERIVED AND LARGER THAN FIRST STATED (#7654 A3). The first version of this
paragraph read "~24/60 to ~1/60", which silently assumed all 23 failures were pushes. Counted
properly over the same window (`gh run list --workflow apply-web-platform-infra.yml --branch
main --limit 60`, 2026-08-20): 27 push/success, 18 push/failure, 9 dispatch/success,
5 dispatch/failure, 1 dispatch/cancelled — 24 non-green.

This job covers the 18 push failures. It does NOT cover:
  - the 5 dispatch failures, because every one of them was a NON-`manual-rerun` target
    (registry_store_restore, registry_pull_path_gate x2, registry_luks_recut,
    registry_host_replace) and the trigger clause below admits only `push` or `manual-rerun`;
  - the 1 dispatch cancellation (run 32293338273, a `vector-redeliver` dispatch), for the
    same reason AND because a RUN-level cancellation cancels queued jobs too, so an `always()`
    job never starts. (A concurrency supersede cannot happen here: the group declares
    `cancel-in-progress: false`.)
Post-PR residual is therefore 6/60, not ~1/60.

Note also that `preflight` carries no `if:` and no `needs:`, so it runs on EVERY dispatch
target while no dispatch job `needs:` it — a red `preflight` reds the run while the target job
goes green, and this job is silent on all 13 non-`manual-rerun` targets. Widening the trigger
clause to every dispatch target means widening `needs:` to jobs that do not run on a push,
which changes the predicate's shape; it is deliberately NOT done here, and the uncovered set
is named above rather than glossed. The covering mechanism for BOTH residuals -- the 5
non-`manual-rerun` dispatch failures and the 1 run-level cancellation -- is a `workflow_run`
watcher, which does not exist for this workflow. It is tracked by #7662 (a default
notification posture for production-affecting workflows), filed at ship time from the #7642
plan's `## Deferrals`. `workflow_run` fires on `completed` INCLUDING `cancelled`, which is why
it reaches the run-level cancellation that no in-run mechanism can: when a run is cancelled,
its queued jobs are cancelled with it, so an `if: always()` job never starts at all.

Asserted by `describe("apply-web-platform-infra has a failure channel")` in
`plugins/soleur/test/terraform-target-parity.test.ts`, which EVALUATES the predicate below
over {success,failure,cancelled,skipped}² × {push,manual-rerun,other} rather than
string-matching it, and pins `needs:` in the same test so shrinking the array cannot shrink
the obligation.
```
