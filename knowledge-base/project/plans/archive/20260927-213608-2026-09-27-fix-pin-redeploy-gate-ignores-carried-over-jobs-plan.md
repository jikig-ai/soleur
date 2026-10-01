---
title: "fix: the pin-redeploy follower leaves a carried-over git-data job to the attempt that ran it, and only rotating followers take the redeploy lock (#8760, #9085)"
type: fix
date: 2026-09-27
slug: fix-pin-redeploy-gate-ignores-carried-over-jobs
branch: feat-one-shot-8760-pin-redeploy-rerun-carryover
issue: 8760
closes: 8760, 9085
priority: p3
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: the pin-redeploy follower stops replaying git-data jobs carried over by a partial re-run

## Enhancement Summary

**Deepened on:** 2026-09-27 (plan v3).
**Review seats:** plan-review (DHH, Kieran, code-simplicity, CTO) produced v2; deepen-plan (security-sentinel,
test-design-reviewer, architecture-strategist) produced v3.

### Key Improvements

1. **Deleted the deploy-evidence conjunct (v2's DEPLOYED_AFTER).** Deepen found three ways it could
   certify a pin load that never happened: a `deploy` job that ends `success` after the
   "superseded" ordering guard skips the actual deploy steps (`web-platform-release.yml`
   "Refuse a version regression"); a branch-dispatched release whose `deploy` job is a no-op; and a
   skip that let the newly entering follower cancel ANOTHER rotation's pending follower. All three
   cases were attempts to protect against #9085. Once the concurrency defect itself is fixed, the
   evidence check has nothing left to protect, so it goes.
2. **Folded #9085 in: the follower is split into a `gate` job (no lock) and a `redeploy` job
   (`needs: gate`, `if: proceed == 'true'`, holding the job-level lock).** A follower that does not
   redeploy never enters the group, so it can never cancel anyone. A pending redeploy is only ever
   replaced by a NEWER redeploy, which dispatches a release after every earlier pin was
   published, so the replacement is benign. That makes the brief's timestamp discriminator safe on its own.
3. Test-harness corrections from test-design review: a violation marker instead of a return-code
   change in `_gexec`, and no env leaks between rows. The harness also gets its own RED row.

### New Considerations Discovered

- `web-platform-release.yml`'s `deploy` job can conclude `success` without running `ci-deploy.sh`
  (superseded arm), and a release can be dispatched from any ref. `track.sh` accepts both shapes
  today. It is not changed here: F1's own dispatched release still deploys, so the issue is
  pre-existing. It is filed as #9086.
- Runbook lookups `.jobs[0].steps[]` assume a one-job follower; the split moves the tracker into
  the `redeploy` job, so both lookups (runbook lines with `startswith("Dispatch web-platform-release")`)
  and PT5's lookup test are updated.

## Overview

The source-run gate that decides whether a git-data birth or replace rotated the host-key pin
reads the jobs of the attempt that fired it. After a "re-run failed jobs", a git-data job that
already succeeded in the earlier attempt is listed again in the new attempt as if it had run
there, so the new attempt's follower forces a second production web release for a rotation the
earlier follower already graded. This plan (1) makes the gate recognise a carried-over job from
its measured API shape — its `startedAt` is earlier than the attempt's run `startedAt` — and grade
it `carried_over` (no redeploy); and (2) splits the follower workflow so only a follower that
actually redeploys takes the concurrency lock, which is what makes the skip safe (and fixes #9085).

Scope: `.github/actions/dispatch-web-redeploy/source-run-gate.sh`, `.github/workflows/git-data-pin-redeploy.yml`
(two jobs), `tests/scripts/test-dispatch-web-redeploy.sh` (+ one captured fixture),
`plugins/soleur/test/terraform-target-parity.test.ts` (follower-structure tests), ADR-237 (one
clause), the cutover runbook (verdict sentence + two lookups).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured 2026-09-27) | Plan response |
|---|---|---|
| #8760: `gh run view --json jobs` "lists the latest attempt of each job" | The gate already passes `--attempt "$SOURCE_RUN_ATTEMPT"` (#8755); `gh run view 36325677861 --attempt 2 --json jobs` lists all 14 jobs, 11 carried over | Keep the attempt read; add the discriminator. |
| #8760 candidate: ignore jobs whose `run_attempt` is lower | Carried jobs appear in attempt 2 with `run_attempt: 2` and a NEW id (`detect-changes` 108637873581 -> 108641168446); gh does not expose `run_attempt` | Rejected. Discriminator: job `startedAt` < attempt run `startedAt`. |
| Brief: carried jobs keep attempt-1 timestamps | Confirmed: `detect-changes` 14:26:30Z/14:26:47Z in both attempts; attempt-2 run `startedAt` 14:41:55Z; re-executed jobs start 14:44:03Z, 14:48:32Z, 14:48:35Z; carried steps intact | Fixture captured from this run (AC3). |
| Brief: "`run_started_at`" | `gh run view <id> --attempt 2 --json startedAt` = `2026-09-27T14:41:55Z` = REST `run_started_at`; `createdAt` differs by scope (14:41:56Z vs 14:22:30Z) | One call `--json jobs,startedAt`; never the source run's `createdAt`. |
| #8760: impact is "an extra redeploy, never a missed one" | True only because F2's redeploy accidentally covers an F1 cancelled while pending (#9085: every dispatched apply run's follower enters the job-level group; a newer pending member cancels an older one) | Fix #9085 structurally in the same PR (split), so the skip needs no cover. |
| v2: deploy-evidence proves the pin loaded | False in two measured shapes: superseded `deploy` = `success` with the deploy steps skipped (`web-platform-release.yml` ordering guard); branch-dispatched release (no `environment:` on `deploy`) | Mechanism deleted (see Enhancement Summary). |

## Research Insights

**Premise Validation.** #8760 OPEN; #8710 CLOSED by PR #8755 (merged 2026-09-24T22:06:07Z); its
plan is archived at `knowledge-base/project/plans/archive/20260925-115424-2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md`.
#9085 OPEN (filed by this plan's research). All edited files exist at branch base `ab4a07e5e0`.

**Measurements (read-only, 2026-09-27, `GH_REPO=jikig-ai/soleur`, gh 2.101.0):**

- `gh api repos/jikig-ai/soleur/actions/runs/36325677861` -> `run_attempt 2`, `run_started_at 14:41:55Z`;
  `.../attempts/{1,2}` -> `run_started_at` 14:22:30Z / 14:41:55Z; `.../attempts/2/jobs` equals
  `?filter=latest` (14 jobs, all `run_attempt: 2`); `?filter=all` = 28 distinct ids.
- `gh run view 36325677861 --attempt 2 --json jobs,startedAt`: top-level keys `jobs`, `startedAt`;
  job keys `completedAt conclusion databaseId name startedAt status steps url`; step keys
  `completedAt conclusion name number startedAt status`; timestamps `YYYY-MM-DDTHH:MM:SSZ`;
  `select(.startedAt < $run)` selects exactly the 11 carried jobs.
- Real git-data runs: 35979304442 (replace: `preflight` + `git_data_host_replace`), 34822248580 (birth:
  `preflight` + disclosure job + `git_data_host_create`). `git_data_host_replace` has no `needs:`,
  so the realistic #8760 shape is `preflight` failing while the replace succeeds.
- jq (CI `ubuntu-24.04`: 1.7.1; local 1.8.2): `fromdateiso8601` -> `1790520115` for the run start;
  Go zero time -> `-62135596800`; `""`, `null`, fractional seconds -> error.
- `gh api repos/jikig-ai/soleur/rulesets`: branch rulesets only (no tag ruleset) — relevant to #9086.

**Relevant files.** `source-run-gate.sh` (`_q`, `grade()`, combination loop, header table);
`git-data-pin-redeploy.yml` (one `redeploy` job today: gate step, pointer step, `track.sh` step,
pin_published email + retry-fail step, failure email; job-level `concurrency`; `actions: write`);
`tests/scripts/test-dispatch-web-redeploy.sh` (gh stub, `_gexec`, `_gjob`/`_gdoc`/`_rep`/`_birth`, G1–G26, GH list,
GM mutations, `FLOOR=102`, registered in `scripts/test-all.sh`);
`plugins/soleur/test/terraform-target-parity.test.ts` `describe("git-data-pin-redeploy.yml")`
(tests at "runs for dispatched apply runs from ANY branch, in its own JOB-level lock",
"least privilege: …", "sparse credential-less checkout, the source-run gate, the tracker gated on
it, a failure email", PT3 `pinPublishedEmailParity` reading `doc.jobs.redeploy`, PT5
`verdictParity` and the runbook lookup test reading `jobs.redeploy`); ADR-237 bullet
`A CI-to-CI dispatch edge.`; runbook `git-data-luks-cutover-5274.md` (`If only the redeploy failed:`,
the `.jobs[0].steps[]` lookups, check G2).

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`:
  `carried_over` is the fail-open direction, so it requires positive proof; anything unparseable
  grades as today.
- `knowledge-base/project/learnings/2026-04-19-mu1-ac2-fixture-repo-gate-design.md`: `"" < "2026-…"`
  is TRUE in jq — parse, require `> 0`, never string-compare.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`:
  harness RED rows in the suite, and must-PASS non-canonical rows.

**Related.** #8710/PR #8755, #7226, #5914, ADR-237, #8776 (not edited), #8211, #9085 (closed by this
plan), #9086 (filed: `track.sh` accepts superseded and branch-dispatched deploys).

**Property List.**

- P1. A follower fired by attempt N >= 2 does not force a release for a git-data job that ran in an
  earlier attempt.
- P2. A real rotation in a re-run (a git-data job re-executed in attempt N) still redeploys.
- P3. The manual path (no attempt) and attempt 1 are graded exactly as today.
- P4. Alerts are never suppressed: red carried jobs keep 5a/5b; fail-closed arms keep precedence.
- P5. An unprovable carry-over grades as today (`rotated`).
- P6. No rotation's redeploy is lost to concurrency: a follower that does not redeploy never
  enters the lock, and a pending redeploy is replaced only by a newer redeploy.

**Cut List.**

- `run_attempt` filter -> refuted by measurement.
- Deploy-evidence conjunct (v2) -> existed only to cover #9085; unsound in two measured shapes;
  replaced by fixing #9085 (P6).
- Attempt-(N-1) twin read, follower-run lookup, Doppler pin compare -> no API link / no access; not
  needed once P6 holds.
- Workflow-level `run_attempt == 1` skip -> violates P2.
- Per-job `.carried=` token, step-summary line, attempt-1 fixture, premise row -> no listed property.

**Value-proposition.** One avoided production release per partial re-run of a rotating apply run
(zero re-runs in the last 500 runs at filing), plus the #9085 missed-redeploy window closed.

## Problem Statement

`git-data-pin-redeploy.yml` fires on every completed dispatched apply run and passes
`SOURCE_RUN_ATTEMPT`. Attempt 1 of a git-data replace whose `preflight` failed still completes, so
follower F1 grades the replace `rotated` and redeploys. "Re-run failed jobs" re-runs `preflight`;
the replace is carried over; F2 reads a listing where it appears with job + apply `success`, grades
it `rotated` and dispatches a second, unplanned production release. Separately (#9085), every
dispatched apply run's follower enters the job-level group before its gate runs, so a rotation's
follower pending behind a running redeploy is cancelled by any later dispatched apply run's
follower — no redeploy and no email.

## Proposed Solution

### Part A — gate: CARRIED (the brief's discriminator)

Source read: `gh run view "$rid" "${att[@]}" --json jobs,startedAt` (one document, one call).

**CARRIED(job)** — all of: (1) `SOURCE_RUN_ATTEMPT` matched `^[1-9][0-9]*$` and is `>= 2`; (2) the
job's `startedAt` parses (`try fromdateiso8601 catch 0`) to `> 0`; (3) the document's run-level
`startedAt` parses the same way to `> 0`; (4) job epoch `<` run epoch (strict). One jq expression
over the document prints `yes` or `no`; it is read through its own assignment whose failure means
`no` — it is NOT routed through `_q`/`_unreadable` (which exit 1) and never exits.

Row **2c** (one line in the header table; CARRIED defined in a block under it), inside the
`1:success` arm before row 2: job success, apply `success`, N == 1, CARRIED -> quiet notice, no
redeploy, `verdict=carried_over`. Row 4 keeps precedence; carried + apply `skipped` stays
`no_apply`; a carried RED job keeps 5a/5b (P4).

**Combination.** Any row 4 -> exit 1. Else any `rotated` -> proceed (a demoted birth is not
`rotated`, so a fresh replace proceeds with `source_job=git_data_host_replace`). Else any 5a/5b ->
warning. Else any `carried_over` -> quiet notice. Else `no_apply`, else `not_run`.

**Output** (one source line starting with `echo`, for PT5; `${cj}` = first carried job in `JOBS`
order; `${SOURCE_RUN_ATTEMPT}` printed only inside this arm, where it is validated):
`echo "::notice::source-run-gate: no redeploy — in run ${rid} attempt ${SOURCE_RUN_ATTEMPT} ${tokens}: ${cj} and its apply step succeeded in an EARLIER attempt of this run (the job started before this attempt did), so that attempt's follower graded it. verdict=carried_over. To redeploy anyway: ${REDEPLOY_CMD}."`

### Part B — follower: only a redeploying follower takes the lock (#9085)

`git-data-pin-redeploy.yml` becomes two jobs:

- **`gate`** — same `if:` as today; NO `concurrency`; `permissions: {actions: read, contents: read}`;
  `timeout-minutes: 10`; `outputs: {proceed, source_job, pin_published}` from `steps.gate.outputs`;
  steps: sparse credential-less checkout; the gate step (unchanged body, `id: gate`); the
  pin_published email (`id: pin_email`, unchanged `if:`); the unsent-email fail step; a
  `failure()` email (the gate-arm body: unidentified / pin_published recovery text).
- **`redeploy`** — `needs: gate`; `if: needs.gate.outputs.proceed == 'true'`; the job-level
  `concurrency: {group: git-data-pin-redeploy, cancel-in-progress: false}`;
  `permissions: {actions: write, contents: read}`; `timeout-minutes: 80`; steps: sparse checkout;
  the pointer step (reads `needs.gate.outputs.source_job`); `track.sh`; a `failure()` email (the
  tracker-arm body).

Why this closes #9085: a job skipped by its `if:` never enters its job-level group (the property
today's workflow already relies on: "a skipped follower run never enters the group"), so a
non-rotating or `carried_over` follower cannot cancel anyone. Within the group, GitHub keeps one
running and one pending member, and a newer pending member cancels the older pending one; with
only redeploying members, the newer one dispatches its release after the older one's pin was
published (its gate ran after that apply's run completed), so the cancelled rotation is covered.
Semantics, verified 2026-09-27 against
<https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs>:
"By default, any existing `pending` job or workflow in the same concurrency group will be canceled
and the new queued job or workflow will take its place" (the replacement half). The docs are
**silent** on whether a job skipped by `if:` takes part in its group; today's workflow already
relies on it not doing so (its header: "a skipped follower run never enters the group"). The work
phase looks for a measured instance in `git-data-pin-redeploy.yml` history (a skipped run created
while another run's job was pending, with that pending job not cancelled) and records it or its
absence in the PR body (AC12).

`RESEND_API_KEY` is bound by three email steps (was two). No new secret. `actions: write` moves to
the only job that dispatches.

### Files to Edit

- `.github/actions/dispatch-web-redeploy/source-run-gate.sh` — source argv `--json jobs,startedAt`;
  CARRIED; row 2c in `grade()`; `carried` flag + notice arm; header: CARRIED block, row 2c, replace
  the `The jobs are read for SOURCE_RUN_ATTEMPT…` paragraph with the carried-over rule and its
  evidence (run 36325677861 attempt 2).
- `.github/workflows/git-data-pin-redeploy.yml` — Part B; header comment: `WHY A SEPARATE WORKFLOW`
  and `THE GATE` paragraphs updated (lock held only by the `redeploy` job; carried-over jobs).
- `tests/scripts/test-dispatch-web-redeploy.sh`:
  - gh stub: source arms `run view <id> --json jobs,startedAt` and
    `run view <id> --attempt N --json jobs,startedAt` (the `view.rc` failure path covers both);
    delete the `--attempt N --json jobs` arm (only the old gate sent it); `run view <id> --json jobs`
    stays for `track.sh`;
  - `_gexec`: on any `UNEXPECTED` line in `calls.log`, write `$S/harness.violation` — its return code
    is unchanged (so `! _gexec` fail-closed rows cannot flip); the G/GH/GM loops require
    `check_$row && [[ ! -e $S/harness.violation ]]`; per-row `_no_unexpected` calls stay;
    `_scenario` unsets `ATT`;
  - `_gjob`: jobs carry `startedAt`/`completedAt` (defaults = the captured re-executed job's values;
    a `carried` profile uses the captured carried job's); `_gdoc` emits the captured run-level
    `startedAt`, overridable/removable;
  - fixture-provenance comment: run 36325677861 attempt 2, the capture command and date;
  - G23 expects `run view 555 --attempt 2 --json jobs,startedAt` and `run view 555 --json jobs,startedAt`;
  - new rows GC1–GC9, HX (harness RED); GH entries; GM mutations 1–7 (Guard 1);
  - `FLOOR`: re-measured from a green CI run, commented with date and #8760.
- `plugins/soleur/test/terraform-target-parity.test.ts` (`describe("git-data-pin-redeploy.yml")`):
  - the lock test: `d.concurrency` undefined; `jobs.gate.concurrency` undefined;
    `jobs.redeploy.concurrency` = `{group: "git-data-pin-redeploy", "cancel-in-progress": false}`;
    `jobs.redeploy.needs` = `gate`; `jobs.redeploy.if` = `needs.gate.outputs.proceed == 'true'`;
    `jobs.gate.if` keeps today's assertions;
  - least privilege: gate `{actions: read, contents: read}`, redeploy `{actions: write, contents: read}`,
    no `environment` on either, three `secrets.RESEND_API_KEY` bindings, redeploy `timeout-minutes: 80`;
  - step layout: gate job = checkout, gate (`id: gate`), emails; redeploy job = checkout, pointer,
    tracker (the only `track.sh` step in the workflow), failure email last; `jobs.gate.outputs`
    maps the three gate outputs;
  - PT3 reads the pin_published email from `jobs.gate`, and requires a `failure()` email in EACH job;
  - PT5 runbook-lookup test reads `jobs.redeploy`;
  - RED cases (in-test mutated YAML, as PT1–PT3 do): lock moved to `gate`; `if:` dropped from
    `redeploy`; `needs:` dropped; `track.sh` moved into `gate`.
- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md` — bullet
  `A CI-to-CI dispatch edge.`: after "so a `plan_only` rehearsal never redeploys", add "; a job carried
  over from an earlier attempt by a partial re-run is left to that attempt's follower (#8760); and
  only the follower's `redeploy` job holds the redeploy lock, so a follower that does not redeploy
  cannot cancel a pending one (#9085)". No status change.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` — in `If only the
  redeploy failed:`, on a line naming `source-run-gate` (PT5 reads it): "`verdict=carried_over` from
  source-run-gate means this follower saw a git-data job carried over from an earlier attempt; that
  attempt's follower owned the redeploy; `gh workflow run git-data-pin-redeploy.yml --ref main`
  redeploys anyway." Both `.jobs[0].steps[] | select(.name | startswith("Dispatch web-platform-release"))`
  lookups become `.jobs[] | select(.name == "redeploy") | .conclusion` with expected output
  `skipped` (G2) or `success`; the prose around them says the redeploy job is skipped when the gate
  does not proceed.

### Files to Create

- `tests/scripts/fixtures/gh-run-view-36325677861-attempt2-jobs-startedAt.json` —
  `GH_REPO=jikig-ai/soleur gh run view 36325677861 --attempt 2 --json jobs,startedAt | jq -c '{startedAt, jobs: [.jobs[] | select(.name == "detect-changes" or .name == "deploy-script-tests (1/4)")]}'`
  (one carried job, one re-executed; every field of each kept job preserved; reproducible while
  GitHub retains the run). GitHub run metadata of a public repository — no secrets or emails.

## Technical Considerations

- **Manual arm and attempt 1 (P3)** are untouched: no attempt means no CARRIED.
- **When is `carried_over` safe?** The earlier attempt's follower always runs its gate (the gate job
  holds no lock and is never cancelled by the group). Its redeploy either succeeded, failed (the
  failure email fires), or was replaced while pending by a newer redeploy that covers it (P6). An
  operator cancelling a run by hand is their own decision.
- **Follower re-runs.** `gh run rerun <follower-id> --failed` replays the original payload; a failed
  `redeploy` job re-runs alone, keeping `needs.gate.outputs`.
- **Security.** Printed values: constants, allowlisted conclusions, validated `rid`, validated
  attempt. Branch-dispatched apply runs can only fake a rotation, never hide one: GitHub sets the job
  and step timestamps. Least privilege improves (gate: `actions: read`).
- **Cost.** No new API calls: the same single source read with one more JSON field.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `run_attempt` filter (issue candidate) | Measured: cannot work. |
| Timestamp discriminator without fixing #9085 | A skip would remove F2's accidental cover for a cancelled F1, and a skipping F2 entering the group would itself cancel another rotation's pending follower (architecture review). |
| Deploy-evidence conjunct (plan v2) | Superseded `deploy` = `success` without a deploy; branch-dispatched releases can forge it; does not stop a skipping follower cancelling another's pending one. |
| Annotate only / won't-fix (plan-review DC-2) | Brief asks for a fix; the split makes the fix safe. Recorded in decision-challenges.md. |
| Shared library for `track.sh` rules | Moot: v3 reads no release evidence. |
| Fix `track.sh`'s acceptance of superseded / branch-dispatched deploys here | Pre-existing, different blast radius (F1's own dispatched release still deploys); #9086. |

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) an unplanned production web release
  after an operator re-runs a failed apply run (a brief web-app restart; today's behaviour), or
  (b) — the worse direction — a MISSED redeploy after a real git-data rotation, so the app keeps the
  old host-key pin and account erasures fail with `host_key_mismatch` until an operator redeploys.
  (b) is today's #9085 exposure, which this plan closes.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The follower reads
  GitHub run metadata only, holds no Terraform or Doppler credential, and prints only constants,
  allowlisted conclusions and validated integers.
- **Brand-survival threshold:** `aggregate pattern` — a missed or spurious redeploy degrades
  erasures or availability for everyone in a window; no single user's data is exposed.

## Observability

```yaml
liveness_signal:
  what: "the pin-redeploy run's gate job log line prefixed `source-run-gate:` carrying `in run <source id>` and one `verdict=` token (rotated, carried_over, no_apply, not_run, pin_published, pin_maybe_published, unidentified), plus the `redeploy` job's conclusion (success = redeployed, skipped = gate did not proceed)"
  cadence: "per completed dispatched apply-web-platform-infra run attempt (workflow_run)"
  alert_target: "operator email via notify-ops-email: a failure() email in each job (gate: unidentified / unreadable; redeploy: tracker timeout or failure) and the pin_published email; GitHub run annotations"
  configured_in: ".github/workflows/git-data-pin-redeploy.yml (jobs gate and redeploy; their notify-ops-email steps)"

error_reporting:
  destination: "layer 6 — workflow run log and ::error::/::warning::/::notice:: annotations on the pin-redeploy run; Resend email to ops on either job's failure and on pin_published"
  fail_loud: "unchanged fail-closed arms (`(fail closed)` and `verdict=unidentified`, exit 1, gate-job failure email). The new arm never fails loud by design: an unprovable carry-over grades `verdict=rotated` and redeploys"

failure_modes:
  - mode: "gh stops printing the run-level or job startedAt"
    detection: "layer 6: re-run followers grade verdict=rotated and redeploy (status quo); CI: G23's exact source argv and the stub's harness.violation marker"
    alert_route: "none needed — fallback is the pre-fix behaviour (one extra release)"
  - mode: "a rotation's pending redeploy replaced by a newer redeploy"
    detection: "by design benign (the newer redeploy loads every earlier pin); CI: parity RED cases pin the lock to the redeploy job only"
    alert_route: "PR check failure if the structure regresses"
  - mode: "real rotation in a re-run misread as carried over"
    detection: "CI rows GC2, GC6, GC8 and mutations 2-4, 6"
    alert_route: "PR check failure"

logs:
  where: "GitHub Actions run logs of git-data-pin-redeploy.yml (gh run view <id> --log)"
  retention: "GitHub Actions log retention for the repository (90 days default)"

discoverability_test:
  command: "grep -m1 -o 'verdict=carried_over' .github/actions/dispatch-web-redeploy/source-run-gate.sh"
  expected_output: "verdict=carried_over"
```

The token is a literal in the gate source; the probe proves presence (GC1 proves reachability). It
fails on `main` today (0 occurrences).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-237 Consequences bullet `A CI-to-CI dispatch edge.` (clause in Files to Edit). No new ADR:
a refinement of an existing edge's gate and lock placement; no status change.

### C4 views

No C4 impact. Checked against `knowledge-base/engineering/architecture/diagrams/model.c4`,
`views.c4`, `spec.c4` in the work phase: no new external actor (the operator who re-runs a failed
apply run is the existing operator actor); no new external system (GitHub Actions, Doppler and the
release path are modeled or explicitly out of C4 scope — ADR-237: "C4 does not model CI-to-CI
edges"); no container or store touched; no access relationship changed. Backed by a green
`bash plugins/soleur/test/c4-count-parity.test.sh` (AC10).

### Sequencing

Lands with the code change in the same PR.

## Guard Contract

### Guard 1 — the gate grades a git-data rotation `carried_over` only when its job started before the attempt that fired the follower

**Property.** For a follower fired by attempt N, `source-run-gate.sh` emits `proceed=false`,
`verdict=carried_over` for a green git-data job whose apply step succeeded if and only if N >= 2 and
both the job's and the run's `startedAt` parse to positive epochs with the job's strictly earlier;
every other green-job-with-apply-success shape emits `proceed=true`, `verdict=rotated`, as before.

**Assembly.** One input chokepoint: `gh run view "$rid" "${att[@]}" --json jobs,startedAt`
(per-job `.startedAt`, run-level `.startedAt`). The property quantifies over both members of
`JOBS`. Decision chokepoints: `grade()`'s `1:success` arm (the only consumer of CARRIED) and the
combination loop's `src` selection (the only producer of `proceed=true`). Attempt authority:
`SOURCE_RUN_ATTEMPT` via the existing `^[1-9][0-9]*$` test.

**Mutation matrix:**

| # | Mutation | Row that must go RED |
|---|---|---|
| 1 | Delete the demotion (the #8760 defect restored) | GC1 |
| 2 | `<` -> `<=` | GC8 |
| 3 | Consult CARRIED without an attempt | GC4 |
| 4 | `>= 2` -> `>= 1` | GC9 |
| 5 | Consult CARRIED on the red-job branch | GC7 |
| 6 | Drop the job-epoch `> 0` check (Go zero time parses negative) | GC6a |
| 7 | `src` picks the first job with apply success ignoring its verdict | GC3 |

Dropping the run-epoch `> 0` check is equivalent (not a gap): with a job epoch `> 0`, a run epoch
`<= 0` can never exceed it, so CARRIED is `no` either way — recorded in the suite comment.

**Harness rows.** HX (in suite): a stub argv typo on a fail-closed row (G5) writes
`harness.violation` and reds the loop assertion. H1 (PR body): the pre-fix gate with only its argv
patched fails GC1. Must-PASS non-canonical: GC2 (re-executed rotation), GC8 (same-second boundary),
GC4 (carried shape via the manual arm). Every non-proceed GC row joins the GH stubbed-gate list.

**Anchor.** Fixture and gate can change in one diff; outside the commit: the live API (re-capture +
`diff` in the PR body) and the `@deruelle` CODEOWNERS row on `/.github/actions/dispatch-web-redeploy/`
(line 214) and `/.github/workflows/git-data-pin-redeploy.yml` (line 213).

### Guard 2 — only a follower that redeploys holds the redeploy lock

**Property.** In `git-data-pin-redeploy.yml`, the job-level group `git-data-pin-redeploy` is
declared on exactly one job, that job runs `track.sh`, and it runs only when the gate job's
`proceed` output is `true`; no workflow-level `concurrency` exists.

**Assembly.** The parsed workflow's `concurrency` key (workflow level) and every `jobs.<id>.concurrency`;
the job containing the single `track.sh` step; that job's `needs` and `if`. Checked by the parity
test over the real file and in-test mutated copies.

**Mutation matrix:**

| # | Mutation (in-test YAML) | Expected |
|---|---|---|
| 1 | Move the group from `redeploy` to `gate` | RED |
| 2 | Drop `redeploy.if` (a non-rotating follower would enter the lock) | RED |
| 3 | Add the group to `gate` as a SECOND member after a compliant `redeploy` | RED |
| 4 | Move the `track.sh` step into `gate` | RED |
| 5 | Add a workflow-level `concurrency` | RED |

## Acceptance Criteria

- [ ] AC1. `source-run-gate.sh` reads the source run with one `--json jobs,startedAt` call and implements CARRIED and row 2c as specified; `bash -n` passes; `shellcheck` clean at the repo's configured level.
- [ ] AC2. GC1: `SOURCE_RUN_ATTEMPT=2`, replace success + apply success with the captured carried job's timestamps and the captured run start -> exit 0, `proceed=false`, `pin_published=false`, one `::notice::` line containing `verdict=carried_over`, no `::warning::`. H1 shows the pre-fix gate yields `proceed=true`.
- [ ] AC3. The fixture equals its recorded capture command's output (re-capture + `diff` in the PR body); GC timestamps come from it except rows labelled synthetic (GC6 zero-time/absent, GC8 equality built from the captured run start, GC9 attempt-1 skew).
- [ ] AC4. G1–G26 pass with timestamped fixtures; G23 asserts both new exact argvs; the harness marker is checked in the G, GH and GM loops; HX passes.
- [ ] AC5. GC1–GC9 pass; Guard 1 mutations 1–7 each red their named row; every non-proceed GC row catches the stubbed gate.
- [ ] AC6. `track.sh` rows (1a–D, H, M) pass unchanged.
- [ ] AC7. `FLOOR` equals the measured `pass + fail` of the final green run, commented with date and #8760.
- [ ] AC8. `plugins/soleur/test/terraform-target-parity.test.ts` passes, including Guard 2's five RED cases, PT3 per job, and PT5 (runbook `verdict=carried_over` line; runbook lookup reads `jobs.redeploy`).
- [ ] AC9. `git grep -n "jobs\[0\]\.steps" -- knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` prints nothing.
- [ ] AC10. `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC11. New gate output contains only constants, allowlisted conclusions, `${rid}` and the validated attempt integer; G19 still passes.
- [ ] AC12. The PR body quotes the concurrency docs' pending-replacement sentence with the URL, and records either a measured instance from `git-data-pin-redeploy.yml` run history showing a job skipped by `if:` did not cancel a pending job, or that no such instance exists (the property then rests on the same undocumented behaviour today's workflow already relies on).
- [ ] AC13. Required CI checks pass by name on the exact PR head SHA before merge (suites run in CI; the local battery is not the gate on this contended machine). The PR body says `Closes #8760` and `Closes #9085`.

## Test Scenarios

`_gexec` harness, `SOURCE_RUN_ID=555`, `ATT` env (unset by `_scenario`). "Carried" = the captured
`detect-changes` job's `startedAt`/`completedAt`; "fresh" = `deploy-script-tests (1/4)`'s; "run
start" = the fixture's `startedAt`.

- **GC1 (#8760).** ATT=2; birth skipped; replace success + apply success, carried -> `carried_over` (AC2).
  - GC1b: birth AND replace both carried -> `carried_over`, notice names `git_data_host_create`.
- **GC2 (must-PASS).** ATT=2; replace fresh -> `rotated`, `proceed=true`.
- **GC3.** ATT=2; birth carried, replace fresh -> `proceed=true`, `source_job=git_data_host_replace`.
- **GC4 (must-PASS).** ATT unset; GC1's document -> `rotated`; argv `run view 555 --json jobs,startedAt`.
- **GC5.** ATT=2; carried replace with apply `skipped` -> `no_apply` (CARRIED not consulted off `1:success`).
- **GC6.** ATT=2; (a) replace `startedAt` = `"0001-01-01T00:00:00Z"`; (b) replace `startedAt` removed;
  (c) run-level `startedAt` removed; (d) run-level `startedAt` `"2026-09-27T14:41:55.5Z"` -> `rotated`
  each, exit 0, no `::error::`.
- **GC7.** ATT=2; replace failure + apply success + poll failure, carried -> `pin_published`,
  `pin_published=true`, warning.
- **GC8 (must-PASS).** ATT=2; replace `startedAt` == run start -> `rotated`.
- **GC9.** ATT=1; replace `startedAt` one second before run start (synthetic) -> `rotated`.
- **HX.** Harness RED row (Guard 1).
- **Regression.** G1–G26 unchanged in expectation; G23 argv updated; `track.sh` rows unchanged.

## Success Metrics

- On the next partial re-run of a rotating apply run, the attempt-N follower prints
  `verdict=carried_over` and its `redeploy` job is `skipped`.
- No dispatched apply run's follower whose gate did not proceed shows a `redeploy` job in any state
  other than `skipped`.

## Dependencies & Risks

- **GitHub concurrency semantics** are load-bearing for P6. Pending replacement is documented
  (quoted above). "A job skipped by `if:` does not enter its group" is undocumented; today's workflow
  already depends on it for every non-dispatch apply run, so this plan adds no new dependency on it.
  If it were false, the split would still be no worse than today (Part B only moves the lock
  later), and #8760's skip would reopen the #9085 exposure. AC12 records the evidence.
- **gh output drift** -> `rotated` fallback (status quo).
- **#9086** (`track.sh` accepts superseded / branch-dispatched deploys) stays open; not widened here.
- **PR touches `.github/`** -> UNTRUSTED-CI class: auto-merge only (the brief's admin-merge path does
  not apply).
- **Merges from `main`:** resolve `PROMOTED_FILES` conflicts by union; re-derive `FLOOR` after any merge
  touching the suite. Do not edit the #8634 audit.

## Plan Review Revisions (v2)

Applied from plan-review (DHH, Kieran, code-simplicity, CTO): `track.sh`'s `queued`-skip, a
`createdAt >= T_apply` filter, per-id captures, the notice template carrying its tokens, dropping
the `.carried=` token, the summary line, caching, the premise row and GC14, one `_gexec` check
instead of 26 row edits, `REDEPLOY_CMD` in the notice, and a predicates block in the header. Taste
and user-challenge items are in `decision-challenges.md` (DC-1..DC-4).

## Deepen Revisions (v3)

| Finding (seat) | Class | Change |
|---|---|---|
| Superseded `deploy` = `success` without running `ci-deploy.sh` (architecture P0) | Mechanical | deploy-evidence conjunct deleted |
| Branch-dispatched release forges evidence (security P1) | Mechanical | deleted with it; `track.sh` exposure -> #9086 |
| A skipping follower entering the group cancels another rotation's pending follower (architecture P1) | Mechanical | Part B: the lock sits on the `redeploy` job only |
| Evidence reads vs the 5-min gate timeout (security P2) | Mechanical | moot (no evidence reads) |
| `_gexec` return-code change flips `! _gexec` rows (test-design P0) | Mechanical | violation marker, loops check it |
| Env leak between rows; harness RED only in the PR body (test-design P1) | Mechanical | `_scenario` unsets `ATT`; HX in the suite |
| `view.rc` must cover the new argv arms (test-design P2) | Mechanical | stated in Files to Edit |
| Runbook `.jobs[0]` lookups break with two jobs (found while designing Part B) | Mechanical | lookups rewritten; AC9 |
| Folding #9085 into this PR | User-challenge (scope added) | applied as the technical prerequisite of the brief's discriminator; DC-5 |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a CI gate, its follower
workflow's job layout, tests, prose sync points). No user-facing surface, copy, pricing, legal or
data-processing change.

## Open Code-Review Overlap

None. Open `code-review` issues (limit 200) were searched for `source-run-gate.sh`,
`test-dispatch-web-redeploy.sh`, `git-data-pin-redeploy.yml`, `ADR-237`,
`git-data-luks-cutover-5274.md`, `terraform-target-parity.test.ts` and `tests/scripts/fixtures`: zero
matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- `"" < "2026-09-27T14:41:55Z"` is TRUE in jq; parse timestamps, never string-compare.
- `gh run view --attempt N --json createdAt` is the attempt's creation, without `--attempt` the
  run's; never use the source run's `createdAt`.
- Change the gate's source argv and the stub in one commit, or every G row reds on call shape.
- The `verdict=carried_over` notice stays one source line starting with `echo`; the runbook
  sentence citing it sits on a line naming `source-run-gate` (PT5).
- `jobs.gate.outputs` must map `steps.gate.outputs.*`; a missing mapping makes `redeploy` always
  skip — Guard 2 does not catch that, the parity step-layout test does (AC8).

## References & Research

- Run 36325677861 attempts 1-2; releases 36324585966, 36338915404, 36339814543; git-data runs
  35979304442, 34822248580 — read 2026-09-27.
- Predecessor plan (archived): `knowledge-base/project/plans/archive/20260925-115424-2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md`.
- ADR-237; runbook `git-data-luks-cutover-5274.md`; issues #8760, #8710, #7226, #5914, #8211, #8776,
  #9085, #9086.
