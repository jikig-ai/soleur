---
issue: 7307
type: bug
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: main-health-monitor is dark — timeout reads as `cancelled`, `tee` masks a red suite, and infra was never covered

**Issue:** #7307 · **Branch:** `feat-one-shot-7307-main-health-monitor-silent-timeout` · **PR:** #7371 · **Date:** 2026-08-09
**Labels:** `priority/p1-high`, `type/bug`, `domain/engineering` (all verified present via `gh label list`)
**Lane:** no `spec.md` for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

---

## Overview

`.github/workflows/main-health-monitor.yml` is the repo's only main-branch health backstop. Its contract is: run the full suite against `main` every 6 hours; file a P1 `ci/main-broken` issue when it goes red; close it when it goes green. **Every arm of that contract is currently broken**, and the most consequential break is not the one in the issue title.

**A — a timeout reads as `cancelled`, and the filer is gated on `failure`.** Job-level `timeout-minutes: 15` is exceeded; GitHub records a job timeout as `cancelled`, never `failure`, so `if: steps.tests.outcome == 'failure'` never fires. Measured 2026-08-09: **18 of the last 30 runs** ended `cancelled`.

**B — `| tee` masks a red suite, so a genuine failure reports success.** *(Not in the issue.)* The step is `run: bash scripts/test-all.sh 2>&1 | tee /tmp/test-output.txt` with no `shell:` key. GitHub's default is `bash -e {0}` — `-e` but **no `pipefail`** (verified against the workflow-syntax docs; `shell: bash` would give `-eo pipefail`, but it is not set). A pipeline's status is its last stage, and `tee` always exits 0. Reproduced:

```
$ bash -e -c 'bash /tmp/failing.sh 2>&1 | tee /tmp/o.txt; echo "exit=$?"'
exit=0
```

So on a red suite `outcome == 'success'`: nothing is filed, **and the closer runs and auto-closes any open `ci/main-broken` tracker.** That is worse than silence — an active green light that will close a human-filed tracker. Corroboration: all three `ci/main-broken` issues ever (#1357, #5372, #5393) were authored by the human `deruelle`. The bot has filed zero across two known red-main episodes since the workflow was born in PR #1358 (2026-04-01) — the commit that introduced the `| tee`.

**C — infra suites were never covered on the main path.** `test-all.sh` gates its nested infra runner on `_infra_in_diff` from `origin/main...HEAD`, which on a clean checkout **of** `main` resolves and is empty. The range *resolving* matters: `_infra_detect_ok=1`, so the script's existing fail-SAFE arm does not fire.

**B2/B3/B4 — three more ways the filer dies before it files.** The filing step also has no `shell:` key. `SUMMARY=$(tail -30 /tmp/test-output.txt)` under `bash -e`: if the file is absent, `tail` exits 1, the assignment inherits it, and errexit kills the step **before `gh issue create`**. `--milestone "Post-MVP / Later"` hard-fails the same way if the milestone is renamed or closed. And `tail -30` of a run killed mid-suite renders in-progress noise under a "Failure summary" heading, sending the operator after a phantom.

**D — `cancel-in-progress: true` manufactures cancellations.** Measured: three runs on 2026-08-06 cancelled at 1m20s / 2m31s / 6m29s — far under the ceiling. Once `cancelled` becomes a signal, fixing A without D converts a silent monitor into one that files spurious P1s.

**E — nothing watches the watcher.** No `sentry_cron_monitor` exists for this workflow, unlike its same-cadence Inngest-dispatched sibling `scheduled-terraform-drift`. Scheduling moved to Inngest and the workflow now carries only `workflow_dispatch:`, so **a dropped dispatch, a disabled workflow, or an unavailable runner is currently 100 % invisible** — and no in-workflow mechanism can ever cover those.

### Why it survived

Two learnings already documented defect B — `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md` (this exact `test-all.sh`-into-a-filter pairing) and `best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md` (a 2026-07-30 correction stating bare `run:` is `bash -e {0}`, pipefail off; a 2026-08-06 addendum recording six occurrences). The second shipped `scripts/lint-workflow-errexit-capture.py`, registered in `test-all.sh`, which scans 698 `run:` bodies and reports clean — because its rules key on `$?`/`PIPESTATUS` *reads*, and here the **workflow engine** reads the exit code. That is deliberate, per its docstring: *"it fires only where the code ITSELF proves the author expected to handle a failure."* Not a linter bug; a different class. Post-fix the class has zero known instances, so no new gate is built — the durable record is the Phase 8 learning.

This mirrors the sibling learning that produced this issue (`2026-08-06-a-wrong-measurement-propagated…`): *a declared mechanism is not an applied one.* Accordingly every fix here is verified by observing behaviour, not by grepping the diff for the text of the fix.

---

## Research Reconciliation — Spec vs. Codebase

Only rows where reality diverged from the issue, or where a plan-time claim was corrected.

| Claim | Reality (verified 2026-08-09) | Response |
|---|---|---|
| "raise `timeout-minutes` past the observed 14m49s–15m19s band" | **The band is right-censored.** Every run over 15m was killed at 15m, so it measures the ceiling, not the suite. True duration unknown, ≥15m. | Phase 1 measures; Phase 3 derives. No number copied. |
| "pass an explicit `TEST_GROUP`" | Right route, wrong shape: `TEST_GROUP=infra` bypasses the diff gate but makes `want_scripts/bun/webplat` all false — it runs *only* infra. A second step, not a substituted argument. | Adopted as a second step (Phase 4). |
| "or set the fail-safe" | Rejected: the empty range *resolves*, so this reclassifies "no branch delta" as "run infra", changing behaviour for `package.json` `test` (`bash scripts/test-all.sh`, i.e. every local run on a main checkout). | Alternatives. |
| *plan v1 claimed* the suite grows ~80 %/week | **Withdrawn as unsound** — see H2. | Growth left unresolved, deliberately; see H2. |
| *plan v1 claimed* "87 infra suites" | `run-registered-suites.sh --list` returns **92**. The 87 came from a stale comment in `test-all.sh`. | Cite `--list`, never a literal — the plan's own thesis applied to itself. |
| *plan v1 coupled* `max_runtime_minutes` to the job ceiling | `cron-monitors.tf` header: for single end-of-job heartbeats the field is **"decorative — only missed-run detection is in play."** | Coupling deleted; value set to the sibling convention. |
| *plan v1 claimed* the Sentry monitor is "the ONLY signal" surviving a job cancel | False. A separate `needs:` + `if: always()` job does run when its upstream job is cancelled (`infra-validation.yml`'s `notify-main-failure`). | Justification narrowed to the genuinely-uncoverable set (gap E). |
| *plan v1's* errexit fallback | Tested the **absent-file** case, which does not occur in production: `tee` creates and truncates the file at pipeline start, so on a timeout it is present and possibly empty. | Fixed with `[[ -s ]]`; see Phase 2.3. |

---

## Hypotheses

The Phase 1.4 gate fired on the substring `timeout`. **The L3→L7 network checklist is not applicable and is dismissed with reason:** the symptom is a GitHub-hosted runner exceeding a wall-clock budget on a job that completes its own work — no host, SSH, DNS or TLS path is implicated, and any resolution/connectivity failure would have failed `actions/checkout`, which succeeds in every observed run. Firewall, DNS/routing and TLS layers are therefore N/A; the finding is entirely L7 service-layer.

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | Job exceeds `timeout-minutes: 15`, recorded `cancelled`, missed by the `== 'failure'` gate | **CONFIRMED** | 18/30 runs `cancelled` at 15m16s–15m26s (`gh run view --json jobs`). |
| H2 | The suite's runtime is growing | **UNRESOLVED — and deliberately left so** | The 8m20s→14m58s series is successes-only, i.e. right-censored: as true duration rises past 15m, slow runs leave the sample and the surviving max is dragged toward the ceiling, manufacturing a growth curve indistinguishable from a real one. *Plan v1 asserted ~80 %/week from this series; withdrawn.* It no longer needs resolving: after this fix, re-saturating the ceiling is **loud** (the filer fires, the monitor pages), so the failure is self-reporting rather than something to forecast. |
| H3 | `\| tee` under the default shell discards the suite's exit code | **CONFIRMED** | Docs + local reproduction + zero bot-authored trackers in 4 months. |
| H4 | A step exceeding its own `timeout-minutes` yields `outcome == 'failure'`, not `cancelled` | **CONFIRMED at runner source** | `actions/runner` `StepsRunner.cs` sets `TaskResult.Failed` on step timeout, guarded by `!jobCancellationToken.IsCancellationRequested`; `ExecutionContext.ApplyContinueOnError` then moves it to `Outcome`. **GitHub's public docs do not state this** — cite the source, and re-verify empirically in Phase 1. |
| H5 | Cancellations come from `concurrency`, not the ceiling | **PARTIALLY CONFIRMED — both** | 15m16s–15m26s cluster = ceiling; the three short 2026-08-06 runs = concurrency. |
| H6 | The infra runner is skipped because the diff range is empty on main | **CONFIRMED** | The run log's `SKIPPED (diff does not touch …)` is the `not_in_diff` arm, reachable only when `_infra_detect_ok=1` and `_infra_in_diff=0`. |
| H7 | Raising the ceiling alone fixes the monitor | **REFUTED** | H3 is independent; a longer budget just yields a green run that closes real trackers. |
| H8 | The suite is green on a clean `main` checkout *in this job's environment* | **UNKNOWN — top delivery risk** | We know only that `ci.yml`'s **sharded** run is green. The monitor runs `TEST_GROUP=all` serially where `origin/main...HEAD` is empty — different ordering and diff-range surface. Phase 1 reads the real epilogue before the filer is armed (R1). |
| H9 | Adding the infra runner yields meaningful coverage | **CONDITIONAL — only with a toolchain assertion** | `run-registered-suites.sh` header: suites "self-skip with exit 0 when [their] tool is absent … this runner prints **PASS** for a skip", so a bare runner produces a green that is not evidence. CI does not rely on the skip; `infra-validation.yml` has a `docker info` assertion that must stay **ordered before** the docker-dependent suites. Phase 4.2 mirrors that. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — which is the hazard. The monitor is an internal backstop, so a broken fix reproduces today's state: `main` goes red, no issue appears, and the founder's next deploy carries the regression to their live product. The outcome unique to *this* change is a **partial** fix: raising the ceiling without fixing the `tee` masking gives the monitor a longer green window in which it **actively closes** human-filed red-main trackers.

**If this leaks, the user's data/workflow/money is exposed via:** no new exposure vector. No new data path; the one new outbound call carries a monitor slug and an ok/error status. The failure excerpt already goes into a repo issue, unchanged in kind.

**Brand-survival threshold:** `aggregate pattern`. The monitor is a *second* line of defence — PRs are gated by `ci.yml`'s required checks plus `strict_required_status_checks_policy`. A dark monitor removes a safety net rather than putting a defect in front of a user; the harm is cumulative across undetected episodes, which is the aggregate tier. No CPO sign-off; `user-impact-reviewer` not required.

---

## Open Code-Review Overlap

**None.** 64 open `code-review` issues checked against every planned path via `jq --arg path … contains($path)`. Zero matches.

---

## Files to Edit

| File | Change |
|---|---|
| `.github/workflows/main-health-monitor.yml` | Defects A, B, B2–B4, C, D + gap E's check-in. |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | One `sentry_cron_monitor` for `main-health-monitor`. |

No change to `scripts/test-all.sh`: `TEST_GROUP=infra` already bypasses the diff gate, so a new env lever would be duplicate surface for zero capability.

## Files to Create

None (plan + `tasks.md` excepted).

---

## Implementation Phases

### Phase 0 — Preconditions

0.1 **Confirm the workflow exists on the default branch:** `gh workflow list --all | grep -i "Main Health Monitor"`. This is the key precondition — because the workflow is *not new*, `gh workflow run main-health-monitor.yml --ref <branch>` dispatches the **modified** file from the branch. The "a new workflow cannot be dispatched pre-merge" sharp edge does not apply, which is what makes every acceptance criterion verifiable pre-merge.

0.2 **Confirm no open tracker** before any dispatch: `gh issue list --label ci/main-broken --state open` (currently empty). A green measurement run would otherwise close it.

0.3 **Read the committed toolchain table** in `apps/web-platform/infra/run-registered-suites.sh` (anchor: the per-tool counts `docker 2`, `terraform 5`, `python3 5`, `cloud-init 1`, `jq 3`) and the paragraph above it on silent PASS. Derive Phase 4.1's install list from that table plus `infra-validation.yml`'s installs — do not hardcode from this plan.

### Phase 1 — Measure (before choosing any ceiling, and before arming the filer)

1.1 On the branch, apply *only* the Phase 2 pipefail guard, the Phase 4 infra step + toolchain, and a deliberately absurd provisional ceiling (steps 90/40, job 140). Push; `gh workflow run main-health-monitor.yml --ref feat-one-shot-7307-main-health-monitor-silent-timeout`. Record **job-level** durations (`gh run view <id> --json jobs`) — not run-level, which includes queue + teardown and overstates by ~20–30 s. Repeat once.

The measurement must include the infra suites: sizing a post-fix ceiling from a pre-fix run that excluded the workload Phase 4 adds would be the same class of error as defect B.

1.2 **Record the per-step maxima separately** — `tests` and `infra` — because Phase 3's rule sizes them independently.

1.3 **Read the epilogue before arming the filer (R1).** Answer H8: is the suite actually green here? Confirm `=== N/N suites passed ===` with zero failures, and that the toolchain assertion passed. If suites fail for environmental reasons, fix or scope them **before** Phase 2.4 makes the filer loud — otherwise the first live run files a false P1 and re-comments every 6 hours.

### Phase 2 — Make failures reportable (defects B, B2–B4) — do first

2.1 **Reset the capture file once**, so the two steps' `tee -a` cannot depend on declaration order:

```yaml
- name: Reset test output capture
  run: ': > /tmp/test-output.txt'
```

2.2 **The test step**, using the house `set +e` / `${PIPESTATUS[0]}` / `set -e` idiom (precedents: `web-platform-release.yml` live-verify; `git-data-rung2-rehearsal.yml`):

```yaml
- name: Run test suite
  id: tests
  continue-on-error: true
  timeout-minutes: <tests_step, Phase 3>
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    set +e
    bash scripts/test-all.sh 2>&1 | tee -a /tmp/test-output.txt
    rc=${PIPESTATUS[0]}
    set -e
    exit "$rc"
```

Load-bearing, do not "simplify":
- `${PIPESTATUS[0]}`, not `$?` — `$?` is `tee`'s.
- **Nothing may sit between the pipeline and the read.** `set -e` is a builtin, i.e. a pipeline, so bash **resets `PIPESTATUS` after it**; re-arming before the read makes `rc` always 0 — a silent false pass, worse than the original bug. Documented verbatim in `git-data-rung2-rehearsal.yml`. No new mutation test is needed: `lint-workflow-errexit-capture.test.sh` cases **F14** (`set -o errexit` re-arms) and **F15b** (same for a `${PIPESTATUS[n]}` read — "set also RESETS PIPESTATUS") already fire on exactly this mutation, and that linter is registered in `test-all.sh` and kept green by AC12.
- `|| true` / `|| rc=$?` are disqualified: `true` is its own pipeline and resets `PIPESTATUS`; under pipefail `$?` is the rightmost failing stage, mis-blaming a `tee` failure on the suite.
- `exit "$rc"` is what makes the engine see the verdict; without it the step's status is `set -e`'s (0) and the whole fix is a no-op.
- Not `shell: bash`: it fixes pipefail but the house idiom is the `PIPESTATUS` capture, which is more precise (pipefail reports the rightmost failing stage; `PIPESTATUS[0]` reports `test-all.sh`).

2.3 **Harden the filer's own errexit (B2).** Guard on *emptiness*, not existence — `tee` creates and truncates the file at pipeline start, so in the timeout case the file is **present** and may be empty; `tail` then exits 0, a `|| echo` fallback never runs, and the issue carries an empty code fence:

```bash
if [[ -s /tmp/test-output.txt ]]; then
  SUMMARY=$(tail -30 /tmp/test-output.txt)
else
  SUMMARY="(no test output captured — the run was killed before the suite wrote its log)"
fi
```

`[[ ]]` as an `if` condition is exempt from errexit, so no extra guard is needed.

2.4 **Fix the conditionals (A).** Filer `== 'failure'` → `!= 'success'`; closer stays strict at `== 'success'`. The two arms are then exhaustive and disjoint over `success | failure | cancelled | skipped`.

2.5 **Guard the milestone (B3).** Drop `--milestone` from `gh issue create`; set it afterwards with `gh issue edit … || echo "::warning::milestone not set"` — a warning annotation rather than a silent `|| true`, so the fallback is visible in the run.

2.6 **Branch the body on failure shape (B4).** If the captured output contains a `[FAIL]` marker, render "Failure summary" as today; otherwise "The run did not complete — killed at the N-minute ceiling; the suite did not report." Include the `outcome` value verbatim either way.

2.7 **Record the outcomes where they can be read.** `steps.<id>.outcome` exists only inside `${{ }}`; `gh run view --json jobs` exposes `steps[].conclusion`, which `continue-on-error: true` forces to `success`. Without this step the outcome is unobservable after the fact and AC2/AC3 cannot be checked:

```yaml
- name: Record step outcomes
  if: always()
  run: |
    {
      echo "tests=${{ steps.tests.outcome }}"
      echo "infra=${{ steps.infra.outcome }}"
    } >> "$GITHUB_STEP_SUMMARY"
```

### Phase 3 — Size the ceilings from the measurement

3.1 The rule, stated so a reader can reproduce the number:

```
roundup5(x)  = 5 * ceil(x / 5)                 # exact multiples unchanged: roundup5(30) = 30
measured_max = max over the run IDs in the comment, job-level, kept fractional to 2dp
               (18m42s -> 18.70), never truncated to whole minutes
tests_step   = max(30, roundup5(measured_tests_max * 1.5))
infra_step   = max(10, roundup5(measured_infra_max * 1.5))
setup        = 5    # checkout + 2x bun install + setup-terraform + apt-get cloud-init
job_ceiling  = tests_step + infra_step + setup + 10
```

**`job_ceiling` must dominate the SUM of the step ceilings, not the max.** With two timed steps, `job = max_step + 10` lets the job token trip mid-way through the second step — a job cancel that skips every remaining step regardless of `if:`, recreating defect A with the fix in place.

The `× 1.5` and the floors are **arbitrary slack, not a variance estimate** — two samples cannot size a variance multiplier, and the growth justification was withdrawn (H2). They are affordable because the repo is **public**, so Actions minutes are free. Say that plainly rather than inviting a future reader to recompute a derivation that was never there.

3.2 The **step** ceilings are primary. A step timeout fails the step and leaves the job alive (H4), so `continue-on-error` + the inline conditionals still fire. A **job** timeout cancels the job and skips every remaining step. The job ceiling is a pure outer bound.

3.3 Keep them well separated: H4's `Failed` branch is guarded by `!jobCancellationToken.IsCancellationRequested`, so if the job token trips concurrently the runner takes the `Canceled` branch and defect A returns. The `+10` above is that margin.

3.4 Cadence bound: `job_ceiling <= 120`. Concrete and checkable, with real slack against the 6h cadence — overlapping runs would both mutate the same tracker.

3.5 Record it in-file, with the working, so AC5 is checkable from the comment alone:

```yaml
# TIMEOUT BUDGET — measured, not guessed. Re-derive; do not copy.
#   Measured <YYYY-MM-DD>, job-level, full suite INCLUDING the infra runner:
#     <run-id> tests=<Xm Ys> infra=<Xm Ys>
#     <run-id> tests=<Xm Ys> infra=<Xm Ys>
#   The "14m49s-15m26s band" in #7307 is CENSORED DATA: every run over 15m was killed
#   at 15m, so it measures the old ceiling, not the suite. Do not reuse it.
#   Rule: roundup5(x) = 5*ceil(x/5); minutes kept fractional (18m42s -> 18.70)
#         tests_step = max(30, roundup5(tests_max * 1.5))
#         infra_step = max(10, roundup5(infra_max * 1.5))
#         job        = tests_step + infra_step + 5 (setup) + 10 (cancel-token margin)
#         job must stay <= 120 (6h cadence) or runs overlap.
#   Worked: tests 18m42s = 18.70 -> x1.5 = 28.05 -> roundup5 30 -> floor 30 -> 30
#           infra  6m10s =  6.17 -> x1.5 =  9.25 -> roundup5 10 -> floor 10 -> 10
#           job = 30 + 10 + 5 + 10 = 55
#   1.5x and the floors are arbitrary slack (Actions minutes are free — public repo),
#   NOT a variance estimate. Re-derive with:
#     gh run list --workflow=main-health-monitor.yml --limit 30 \
#       --json databaseId,conclusion,createdAt
#     gh run view <id> --json jobs   # job-level, NOT run-level
```

### Phase 4 — Cover the infra suites (defect C)

**Decided, not deferred.** Plan v1 left this an open question; the data resolves it. `deploy-script-tests` (the job that runs these suites in CI) measured 6m23s / 7m15s / 6m58s / 7m04s / 7m31s / 8m05s across the six most recent `infra-validation` runs. Docker is preinstalled on GitHub-hosted runners (no workflow installs it). Toolchain install is one pinned action plus two apt packages, ~1–2 min. So the post-fix monitor lands around 15 + ~9 ≈ **24 min** — comfortably inside the budget, and the coverage is worth it.

Do **not** subset to "only the time-rotting suites". `run-registered-suites.sh` derives its list from `infra-validation.yml` precisely so the two cannot drift; a hand-curated subset in the monitor would be a new drift surface.

4.1 Install the toolchain per the Phase 0.3 table, mirroring `infra-validation.yml`: `hashicorp/setup-terraform` (pinned to the same SHA as the sibling), `sudo apt-get install -y -qq cloud-init`, plus anything else the committed table names. `python3` and `jq` are preinstalled; docker is preinstalled.

4.2 **Assert the toolchain before the suites run.** This is not optional hygiene — per H9, a suite whose tool is absent self-skips with exit 0 and the runner prints **PASS**, so without this the monitor goes green over silently-absent coverage: exactly the "looks like coverage" shape this plan exists to eliminate. Mirror `infra-validation.yml`'s `docker info` assertion and keep it **ordered before** the infra step:

```yaml
- name: Assert infra toolchain present
  run: |
    command -v terraform && command -v cloud-init && command -v python3 && command -v jq
    docker info >/dev/null
```

4.3 The infra step, with its own ceiling and outcome:

```yaml
- name: Run infra suites
  id: infra
  continue-on-error: true
  timeout-minutes: <infra_step, Phase 3>
  env:
    TEST_GROUP: infra
  run: |
    set +e
    bash scripts/test-all.sh 2>&1 | tee -a /tmp/test-output.txt
    rc=${PIPESTATUS[0]}
    set -e
    exit "$rc"
```

4.4 Widen the filer to `steps.tests.outcome != 'success' || steps.infra.outcome != 'success'`; tighten the closer to `steps.tests.outcome == 'success' && steps.infra.outcome == 'success'`.

> **P0 — `steps.infra` must appear at exactly three sites or zero.** If this phase is ever split out, remove the `steps.infra` clause from **all three** in the same commit: filer `if:`, closer `if:`, and the Phase 5.2 heartbeat `status:`. `steps.infra` with no `id: infra` step is a null dereference — GitHub casts null to `0`, so `== 'success'` is always false and `!= 'success'` always true. The filer would fire on every green run, the closer would never fire, and the heartbeat would report `error` forever: a P1 filed once and re-commented every 6 hours on a healthy main. Enforced by AC9.

4.5 Cosmetic, do not "fix": the first step's epilogue still prints its accurate `NOT covered above (diff does not touch it)` notice; the infra step's log carries `IS covered above`. `_infra_ran` may be set at exactly one site.

### Phase 5 — Make the monitor observable from outside itself (gap E)

Justification, stated precisely: it is **not** that nothing else can see a job cancel — a separate `needs:` + `if: always()` job does run when its upstream job is cancelled (`infra-validation.yml`'s `notify-main-failure` is exactly that). It is that scheduling moved to Inngest and this workflow carries only `workflow_dispatch:`, so **a dropped dispatch, a disabled workflow, or an unavailable runner produces no run at all** — invisible to any in-workflow or in-repo mechanism. Only an external missed-check-in alarm covers that.

5.1 Add to `apps/web-platform/infra/sentry/cron-monitors.tf`, mirroring `scheduled_terraform_drift`:

```hcl
resource "sentry_cron_monitor" "main_health_monitor" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "main-health-monitor"
  schedule                = { crontab = "0 */6 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

`crontab` must match the Inngest cron — read it from `cron-main-health-monitor.ts`, do not trust memory. `checkin_margin_minutes = 60` follows the Inngest-dispatch cohort convention documented in that file's header; do not tighten it (the header records a false-page from a tighter margin). `max_runtime_minutes = 15` is the sibling convention and is **decorative here** — the file's own header states it "only matters for two-step (in_progress -> ok/error) check-ins", and 5.2 sends a single terminal heartbeat. Detection of a job-level cancel is therefore by margin, which is adequate at a 6h cadence. Do not add a coupling comment tying it to the job ceiling; that relation is unread.

5.2 Terminal check-in as the **last** step, mirroring `scheduled-terraform-drift.yml`'s `Sentry check-in (final)`:

```yaml
- name: Sentry check-in (final)
  if: always()
  continue-on-error: true
  uses: ./.github/actions/sentry-heartbeat
  with:
    monitor-slug: main-health-monitor
    status: ${{ (steps.tests.outcome == 'success' && steps.infra.outcome == 'success') && 'ok' || 'error' }}
    sentry-ingest-domain: ${{ secrets.SENTRY_INGEST_DOMAIN }}
    sentry-project-id: ${{ secrets.SENTRY_PROJECT_ID }}
    sentry-public-key: ${{ secrets.SENTRY_PUBLIC_KEY }}
```

The `A && 'ok' || 'error'` ternary is safe because both branches are non-empty truthy strings. `continue-on-error: true` so a Sentry outage cannot red a healthy run.

5.3 **The workflow step and the `.tf` resource must land in one commit.** `scripts/prod-version-drift-check.test.sh` case `B10g` asserts every heartbeat slug has a matching `sentry_cron_monitor`, and `apps/web-platform/scripts/sentry-monitors-audit.sh` sweeps the reverse. Its comment states why: a mismatched slug "leaves the Sentry monitor permanently green over a dead alarm: the worst shape available, since it looks like coverage."

### Phase 6 — Concurrency (hazard D)

`cancel-in-progress: true` → `false`. At a 6h cadence with a ~25-minute run, queuing costs nothing and stops the workflow manufacturing `cancelled` conclusions indistinguishable from timeouts. Residual, recorded not fixed: GitHub still cancels older *pending* runs in a group, so this reduces rather than eliminates hazard D — the Sentry monitor makes a missed run legible either way.

### Phase 7 — Documentation and closure

7.1 Capture the learning under `knowledge-base/project/learnings/` (directory + topic only; author picks the date). Topic: the engine-reads-the-exit-code class, why the existing errexit linter correctly does not cover it, and censored-series reasoning.
7.2 PR body: `Closes #7307` — a code fix effective at merge, not an ops-remediation.

---

## Acceptance Criteria

### Pre-merge (PR)

Every criterion is verifiable pre-merge by dispatching the modified file from the branch (Phase 0.1). None is deferred.

1. **AC1 — a red suite is reported red (the defect-B proof).** Dispatch with a deliberately-failing shim (temporary, reverted). The job summary records `tests=failure`, a `ci/main-broken` issue **is** filed, nothing is closed. *Asserts behaviour, not that the YAML contains `!= 'success'`.*
2. **AC2 — a green suite is reported green.** Clean dispatch: summary records `tests=success` (and `infra=success`), nothing filed, any open tracker closed.
3. **AC3 — the filer survives both no-output shapes.** (a) `/tmp/test-output.txt` absent, (b) present and zero-length — the shape a timeout actually produces. Both reach `gh issue create`; both bodies carry the fallback string.
4. **AC4 — the filer survives a bad milestone**, and emits a `::warning::` annotation when it cannot set one.
5. **AC5 — measured durations recorded with worked arithmetic.** The comment names ≥2 run IDs with per-step job-level durations, and shows product → rounded → floor for **every** `timeout-minutes` in the file. Reproducible from the comment alone.
6. **AC6 — the censored band is labelled.** The comment does not present 14m49s–15m26s as the suite's duration.
7. **AC7 — `job_ceiling` dominates the sum**, i.e. `job >= tests_step + infra_step + 15`, and `job <= 120`.
8. **AC8 — infra suites actually ran, with a real toolchain.** The toolchain assertion step passed, and the log shows `IS covered above` with no `SKIPPED (diff does not touch`. *Observed via `_infra_ran`, not predicted.*
9. **AC9 — no orphaned `steps.infra` reference.** `grep -c 'steps\.infra' .github/workflows/main-health-monitor.yml` is `3` if the file contains an `id: infra` step, `0` if it does not. Any other count is a reject.
10. **AC10 — timeout and red-suite bodies differ.** The timeout body does not say "Failure summary"; both carry the literal `outcome` value.
11. **AC11 — terraform validates and slug parity holds in one commit.** `terraform validate` passes in `apps/web-platform/infra/sentry/`; `bash scripts/prod-version-drift-check.test.sh` passes (case `B10g`); the workflow step and the `.tf` resource are in the same commit.
12. **AC12 — the errexit linter is still clean.** `python3 scripts/lint-workflow-errexit-capture.py` → `clean`, rc 0. (This is also what guards the `set -e`-above-the-read mutation, via F14/F15b.)
13. **AC13 — the monitor's crontab matches the real dispatcher**, read from `cron-main-health-monitor.ts`.
14. **AC14 — actionlint introduces no new finding** relative to `origin/main`.
15. **AC15 — full suite green.** `bash scripts/test-all.sh > /tmp/out.log 2>&1; echo $?` = 0. *Redirect + `$?`, never a pipe — this plan may not reproduce the defect it is fixing.*
16. **AC16 — every temporary shim is reverted.** `git diff origin/main` contains no fixture used only for AC1/AC3/AC4.

### Post-merge (operator)

**None.** `apply-sentry-infra.yml` auto-applies the monitor on push to `main` (its `paths:` filter covers the whole `infra/sentry/**` tree). No operator step, no dashboard action, no SSH.

---

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "main-health-monitor" — terminal check-in from the job's last step
  cadence: every 6h (crontab 0 */6 * * *, matching Inngest cron-main-health-monitor)
  alert_target: Sentry issue via failure_issue_threshold = 1 (org jikigai-eu, project web-platform)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
                 (sentry_cron_monitor.main_health_monitor)
                 + .github/workflows/main-health-monitor.yml (uses ./.github/actions/sentry-heartbeat)

error_reporting:
  destination: (1) GitHub issue labelled ci/main-broken, filed on outcome != success;
               (2) Sentry cron-monitor issue on a missed or error check-in
  fail_loud: yes — the check-in is if: always(); a run that never happens emits nothing and
             Sentry pages on the miss. The filer's condition is exhaustive over the outcome
             domain, and its own errexit traps (B2/B3) are guarded so it cannot die before writing.

failure_modes:
  - mode: test suite genuinely red on main
    detection: steps.tests.outcome == failure (correct now — PIPESTATUS[0] carries the real code);
               mirrored to the job summary so it is readable after the fact
    alert_route: ci/main-broken P1 issue + check-in status=error
  - mode: a step exceeds its own ceiling
    detection: step fails, job survives (H4), outcome == failure
    alert_route: same, with a timeout-shaped body distinguishable from a red suite
  - mode: infra suites red, or their toolchain absent
    detection: steps.infra.outcome != success; the toolchain assertion reds the job before the
               suites can pass vacuously
    alert_route: same filer
  - mode: job exceeds the outer ceiling (runner wedged)
    detection: no terminal check-in
    alert_route: Sentry missed-check-in issue (by margin, within 60 min)
  - mode: Inngest dispatch never fires / workflow disabled / runner unavailable
    detection: no check-in within checkin_margin_minutes = 60 — no in-repo mechanism can see this
    alert_route: Sentry missed-check-in issue

logs:
  where: GitHub Actions run logs + job summary (step outcomes) + the tail-30 excerpt in the issue
  retention: 90 days (Actions), indefinite (issue body excerpt)

discoverability_test:
  command: gh run list --workflow=main-health-monitor.yml --limit 5 --json databaseId,conclusion
           && gh issue list --label ci/main-broken --state open
  expected_output: recent runs conclude success or failure (NOT cancelled); an open ci/main-broken
                   issue exists if and only if the most recent run was not success
```

No `ssh` in the discoverability path.

**Soak follow-through:** not required. No criterion is time-gated; every claim is verified by a pre-merge dispatch and closure happens at merge. The first natural post-merge fire is covered by the Sentry monitor, which is itself the watchdog.

---

## Infrastructure (IaC)

**Terraform changes.** One additive `sentry_cron_monitor` in `apps/web-platform/infra/sentry/cron-monitors.tf`. No new provider, version pin, variable, or secret — the three check-in secrets already exist and are already consumed by `scheduled-terraform-drift.yml`.

**Apply path.** Auto-applied on merge by `apply-sentry-infra.yml` (`paths:` covers `infra/sentry/**`, plan full-root). No operator step. Additive only, so the `sentry-destroy-required` / `[ack-destroy]` gate is not engaged. No downtime.

**Distinctness / drift safeguards.** Slug parity is mechanically enforced in both directions (`prod-version-drift-check.test.sh` B10g; `sentry-monitors-audit.sh`), and AC11 requires both edits in one commit. `checkin_margin_minutes` follows the documented cohort convention. `max_runtime_minutes` is decorative under the single-heartbeat pattern and is set to the sibling value for schema consistency — deliberately *not* coupled to the job ceiling.

**Vendor-tier reality check.** None applicable — eight sibling `sentry_cron_monitor` resources already apply cleanly on this org/plan.

---

## Encryption Posture

No persistent store is introduced, so `at_rest` is n/a — the Sentry cron monitor is a vendor-side config object and the workflow writes only ephemeral runner-local files. `in_transit`: the one new connection is the runner's HTTPS check-in to the Sentry ingest domain (`de.sentry.io`, DE residency) via the shared `sentry-heartbeat` composite, which uses curl defaults, so **cert verification is on**; it does not authenticate Sentry to us beyond public CA trust, and a swallowed check-in degrades to the missed-check-in alarm — failing toward paging, not silence. Disclosed under the existing Art. 30 PA8 §(e) Sentry ingest entry, unchanged: the payload is a monitor slug and an ok/error status. No exception block needed — no plaintext store, no disabled verification.

---

## Architecture Decision (ADR/C4)

**No ADR, no C4 change.** A bug fix on an existing surface plus one observability hookup on an established pattern: no ownership or tenancy boundary moves, no new substrate or integration pattern, no trust-boundary change, no ADR reversed or extended.

C4 completeness, checked against all three of `model.c4`, `views.c4`, `spec.c4` (read in full, not keyword-grepped): the change adds **no external human actor**, **no external system** (GitHub and Sentry are both already modelled — and the `sentry` element's description already covers this resource class: *"the cron monitors (cron-monitors.tf — one per scheduled workflow, `failure_issue_threshold` opens an issue on a missed check-in)"*, so a ninth monitor instantiates the modelled pattern rather than changing it), **no container or data store**, and **no actor↔surface access relationship**. Both systems are already `include`d in the `context` view, so there is no new `include` line and no render change; `spec.c4` defines only element kinds and is untouched. No element description is falsified.

---

## Domain Review

**Domains relevant:** Engineering.

**Engineering (CTO) — reviewed.** Confirmed H4 at `actions/runner` source, settling the plan's largest semantic unknown. Five findings changed the plan: the v1 growth estimate was withdrawn as censored-data reasoning; the proposed `SOLEUR_FORCE_INFRA` lever was cut as duplicate of `TEST_GROUP=infra`; the infra step's real cost was identified as the **toolchain**, not runtime; three unlisted defects in the filing step were folded in (B2–B4); and the linter rule was ruled a poor fit for its host gate. Also corrected a cost premise — the repo is **public**, so Actions minutes are free.

**Product/UX Gate:** not applicable. The mechanical UI-surface override was run against `## Files to Edit` and `## Files to Create`: one workflow file and one `.tf` file, matching no UI-surface term or glob. No wireframe required; `ux-design-lead` is not applicable — no UI surface. **Brainstorm-recommended specialists:** none (one-shot pipeline, no brainstorm).

**Other domains:** Legal, Finance, Marketing, Sales, Support, Operations — not relevant. The Operations cost angle was checked and dismissed on evidence (public repo, free minutes; no recurring vendor expense, so `wg-record-recurring-vendor-expense-before-ready` does not fire).

**GDPR gate:** not invoked. The canonical regulated-data regex does not match, and each of the four expansion triggers was checked individually and none fires — no LLM processing of operator data, threshold is not `single-user incident`, no new cron reads `learnings/` or `specs/`, no new distribution surface.

---

## Alternatives Considered

| Alternative | Why not |
|---|---|
| `shell: bash` instead of the `PIPESTATUS` capture | Fixes pipefail, but the house idiom (7+ call sites) is the capture, and it is more precise: pipefail reports the rightmost failing stage, `PIPESTATUS[0]` reports `test-all.sh`. |
| Drop `\| tee`, redirect only | What the 2026-05-18 learning recommends, but it loses live log streaming in the Actions UI — the main way a human diagnoses a slow run. The guard keeps both. |
| Job-level ceiling only, with `if: always()` on the filer | Rejected on measured evidence: `always()` also fires on concurrency cancellation, and three such runs occurred on 2026-08-06. Step-level ceilings remove the ambiguity at source. |
| A separate `needs:`+`if: always()` notify job | Cut as redundant once the Sentry monitor was added — the monitor covers strictly more (dropped dispatch, disabled workflow, unavailable runner) with less workflow surface. Recorded because it *is* the house pattern and a reviewer will ask. |
| New `SOLEUR_FORCE_INFRA=1` lever in `test-all.sh` *(v1's choice)* | Cut. `TEST_GROUP=infra` already bypasses the diff gate; a second way to say the same thing is new surface, new docs, and a new test axis for zero capability. |
| Change the empty-range fail-safe default in `test-all.sh` | Rejected on blast radius: the range *resolves* on main, so this reclassifies "no branch delta" as "run infra", making every local `bun test` on a main checkout pay 92 infra suites. |
| Subset the infra step to the time-rotting suites only | Rejected: `run-registered-suites.sh` derives its list from `infra-validation.yml` so the two cannot drift; a hand-curated subset is a new drift surface, for ~9 minutes. |
| Shard the monitor like `ci.yml` | Rejected, not deferred: sharding multiplies the `outcome` values the filer must aggregate (`ci.yml` needed a synthetic aggregator job) and buys wall-clock nothing waits on. |
| A new linter rule for the engine-reads-the-exit-code class | Cut entirely, including the deferral. It contradicts the host gate's documented scope and direction-of-error, and after this PR the population is **zero**. The durable record is the Phase 7.1 learning. |
| Add an opening `in_progress` check-in to make `max_runtime_minutes` load-bearing | Would catch a job cancel at the ceiling rather than within the 60-min margin, but breaks the single-heartbeat convention every sibling monitor follows. Margin detection is adequate at a 6h cadence. |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **R1 (HIGH) — the first loud run files a false P1, then re-comments every 6h.** The bot has never filed in 4 months, so there is no evidence the suite is green on a clean main checkout *in this job's environment* (H8) — only that the sharded CI run is green. | Phase 1.3 reads the real epilogue from the measurement dispatch **before** Phase 2.4 arms the filer. |
| **R2 (HIGH) — the filer dies before it files** (B2/B3), including on the empty-file shape a timeout actually produces. | Phase 2.3/2.5; AC3 tests both no-output shapes, AC4 the milestone. |
| **R3 (HIGH) — a split or partial Phase 4 leaves an orphaned `steps.infra`**, filing a P1 on every green run and paging Sentry forever. | The three-sites-or-zero rule in Phase 4.4; AC9 makes it a grep-checkable count. |
| **R4 (HIGH) — the infra step goes green over absent tools.** Suites self-skip exit 0 and the runner prints PASS. | Phase 4.2's assertion step, ordered before the suites; AC8 requires it to have passed. |
| **R5 (MEDIUM) — `job_ceiling` under-sized against two timed steps**, recreating defect A. | Phase 3.1 sums the step ceilings; AC7 asserts it. |
| **R6 (MEDIUM) — the `PIPESTATUS` idiom regresses** if a later edit moves `set -e` above the read: a false pass, worse than the original bug. | Already guarded by `lint-workflow-errexit-capture.test.sh` F14/F15b, registered in `test-all.sh`; AC12 keeps it green. No new test needed. |
| **R7 — the step-timeout semantic could land as `cancelled`** if the job token trips concurrently (H4's guard clause). | Ceilings well separated (Phase 3.3); `!= 'success'` covers it regardless; Phase 1 exercises it empirically. |
| **R8 — `cancel-in-progress: false` does not fully remove hazard D** (pending runs are still cancelled). | Accepted and recorded (Phase 6); the monitor makes a missed run legible. |
| **R9 — a green measurement run closes a real open tracker.** | Phase 0.2 checks the label is empty before dispatching. |
| **R10 — leftover test shims.** | AC16; shims are temporary files, never edits to real suites. |

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder will fail `deepen-plan` Phase 4.6.
- **Never verify this plan's own work through a pipe.** AC15 uses `bash scripts/test-all.sh > /tmp/out.log 2>&1; echo $?`. Piping the verification of a pipe-masking bug into another unguarded pipe is the shape of the 2026-08-06 learning where the fix reproduced the defect it was fixing.
- **A right-censored series cannot measure growth.** Successes-only durations under a hard ceiling drift toward that ceiling as true duration rises, manufacturing a growth curve. v1 of this plan made this error. `max(observed)` where every over-limit sample was truncated tells you the limit, not the distribution.
- **Verify the fallback against the shape that actually occurs.** v1 "proved" its `|| echo` guard by testing an *absent* file; `tee` creates the file at pipeline start, so the production timeout shape is *present and empty*, where `tail` exits 0 and the guard never runs. Reproducing the wrong scenario is a green that means nothing.
- **`steps.<id>.outcome` is only readable inside `${{ }}`.** `gh run view --json jobs` exposes `steps[].conclusion`, which `continue-on-error: true` pins to `success`. Mirror outcomes to `$GITHUB_STEP_SUMMARY` or they are unobservable after the fact — and any AC asserting on them is unverifiable.
- **A `steps.<id>` reference with no such step is a null dereference, not a no-op.** GitHub casts null to `0`, so `== 'success'` is always false and `!= 'success'` always true.
- **With two timed steps, the job ceiling must exceed their sum**, not their max, or the job token trips mid-second-step and cancels everything.
- `${PIPESTATUS[0]}` is destroyed by any intervening command — including `set -e`, `|| true`, and `echo`. Read it on the line immediately after the pipeline.
- **`TEST_GROUP=infra` is not "add infra" — it is "run *only* infra".** Reading it as additive is what makes the issue's first suggestion look like a one-word change.
- **A registered infra suite whose tool is absent PASSES.** `run-registered-suites.sh` prints PASS for a self-skip; only an explicit toolchain assertion, ordered before the suites, turns that into a red.
- Cite `run-registered-suites.sh --list` for the suite count, never a literal. `test-all.sh`'s comment says 87; the derived list returns 92.
- `gh run view <id> --json jobs` gives job-level timings; `gh run list` gives run-level, which includes queue and teardown and overstates by ~20–30 s.
- A heartbeat slug and its `sentry_cron_monitor` must land in the same commit, or `prod-version-drift-check.test.sh` B10g reds — and in production it leaves "a Sentry monitor permanently green over a dead alarm."
- `max_runtime_minutes` is **decorative** for single-terminal-heartbeat monitors (per `cron-monitors.tf`'s header); do not write a comment coupling it to a job ceiling, because nothing reads that relation.
