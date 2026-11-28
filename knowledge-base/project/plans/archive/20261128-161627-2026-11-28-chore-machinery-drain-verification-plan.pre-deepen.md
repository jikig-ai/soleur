---
title: "follow-through: enroll weekly machinery-drain actor-gate verification for #13095"
type: chore
date: 2026-11-28
slug: chore-machinery-drain-verification
branch: feat-one-shot-13122-machinery-drain-verification
issue: 13122
closes: 13122
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Overview

Enroll a time-gated, automated follow-through probe that verifies the weekly scheduled machinery-drain actor-gate fix after the first qualifying bot-triggered run, without firing any production-mutating manual trigger.

## Research Insights

### Premise Validation (Phase 0.6)

- **#13122** is OPEN, unclosed, and has zero closing PR references. Collision precheck exit 10 names only PR **#13124**, this pipeline's own auto-created draft on this branch; foreign process check was clean. Prechecks for cited #13095/#13096/#9508 were clean.
- **#13095** is CLOSED by one PR; **PR #13096** is MERGED at `2026-11-28T12:57:15Z` (`46b114ca50f7c21a1742a069e6ab4ee46570f1b2`); **#9508** is OPEN with labels `keep-open` and `meta/machinery`. The verification premise is live, not stale.
- Verified on `origin/main`: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, `scripts/followthroughs/`, `.github/workflows/scheduled-followthrough-sweeper.yml`, and `.github/workflows/scheduled-machinery-drain.yml` all exist. `scripts/machinery-drain.sh` is absent because the drain uses `anthropics/claude-code-action` directly in the workflow.
- `.github/workflows/scheduled-machinery-drain.yml:84-107` names the exact step `Drain the machinery ledger`, sets `continue-on-error: true`, and pins `allowed_bots: "soleur-ai[bot]"`; lines 168-248 update the standing measurement issue. Lines 3-7 explain that scheduling is external via `cron-machinery-drain.ts` and the YAML itself has no `schedule:` block.
- Live pre-fix evidence: run `45143702615` (2026-11-23) was triggered by `soleur-ai[bot]`; its Drain step log contains the emitted line `##[error]Action failed with error: Workflow initiated by non-human actor: soleur-ai (type: Bot)...`, while the jobs API reports the Drain step conclusion as `success` because of `continue-on-error`. This proves why run/step conclusions are insufficient.
- CLI/API verification performed 2026-11-28: `gh run list --help` exposes no `actor` JSON field but does expose `--user`; the REST workflow-runs endpoint exposes `actor` and `triggering_actor`. A live read of `repos/jikig-ai/soleur/actions/workflows/scheduled-machinery-drain.yml/runs?per_page=10&actor=soleur-ai%5Bbot%5D&status=completed&created=%3E%3D2026-11-20T00%3A00%3A00Z` returned exactly run 45143702615; the post-cutoff query currently returns `total_count=0`, as expected before the first post-merge weekly dispatch.
- The documented step-log endpoint `GET /repos/{owner}/{repo}/actions/jobs/{job_id}/steps/{step_number}/logs` was verified live: `gh api --allow-escape-sequences repos/jikig-ai/soleur/actions/jobs/137587683013/steps/5/logs` returned 264 lines containing the refusal at line 217. `gh api --help` confirms `--allow-escape-sequences` (needed because GitHub log bytes may contain terminal escapes). An unauthenticated `curl` to the same step-log endpoint returned HTTP 403, so the probe's `GH_TOKEN` requirement is real.
- The issue-comments endpoint was verified live with `repos/jikig-ai/soleur/issues/9508/comments?since=2026-11-23T09%3A03%3A54Z&per_page=100`; it returned the corresponding bot-authored comment containing `Machinery drain outcome:` and `closed=0` at `2026-11-23T09:04:32Z`.
- `.github/workflows/scheduled-followthrough-sweeper.yml` already grants `actions: read` and `issues: write`, and binds `GH_TOKEN` in the sweeper environment. Therefore `secrets=GH_TOKEN` needs **no workflow edit**.
- Mechanism-vs-ADR corpus: follow-through enrollment instantiates the existing sweeper/directive substrate; ADR-216 explains the machinery ledger, and ADR-033/030 explain the existing Inngest dispatch substrate. No proposed mechanism sits in a rejected-alternatives table. No new scheduler, workflow, persistent store, secret, or infrastructure is needed.

### Mechanism Minimality Gate (Phase 0.6b)

**Property List** — the discrete properties the ask buys:

- P1: the first completed post-`2026-11-28T12:57:15Z` `scheduled-machinery-drain.yml` run triggered by `soleur-ai[bot]` is selected deterministically.
- P2: the verdict is based on the Drain step runtime log, never on the vacuous run conclusion or the parent step conclusion.
- P3: the verdict comment on #9508 is positively correlated to that run and `closed=N` is parsed.
- P4: echoed workflow or shell source text is never counted as runtime evidence.
- P5: the tracker closes only on the exact exit-0 evidence bar; not-yet, persistent-refusal, and unmeasurable states remain distinguishable.
- P6: enrollment happens without firing `cron/machinery-drain.manual-trigger` or any other production-mutating trigger.

**Cut List** — mechanisms considered and cut before design:

- *Edit `.github/workflows/scheduled-followthrough-sweeper.yml` to wire GH_TOKEN* → P6 — cut: `GH_TOKEN` is already bound in that workflow's `env:` block.
- *Use #13122 itself as the follow-through tracker* → P5 — cut: #13122 is the implementation issue the PR should close; a tracker closed at merge would stop being a visible open verification obligation. Follow the #10585 precedent: file a separate post-merge tracker and close the implementation issue after enrollment.
- *Poll the Inngest cron or dispatch a manual drain* → P1/P6 — cut: the required evidence is the weekly GitHub Actions run; manual dispatch is explicitly production-mutating and unnecessary.
- *Use `gh run list --user` alone* → P1 — cut as insufficiently auditable: it filters server-side but its JSON output cannot re-verify `triggering_actor`; use the REST workflow-runs response, which carries both `actor` and `triggering_actor`.
- *Parse the whole job log* → P2/P4 — cut: the documented per-step log endpoint reads exactly the Drain step and avoids cross-step contamination.

Surviving mechanism: one closing follow-through probe plus one post-merge tracker on the existing sweeper substrate.

### Relevant File Paths

- `.github/workflows/scheduled-machinery-drain.yml:84-107` — Drain step, actor allowlist, prompt, model pin; `:115-157` floor verdict emits `before=<n> after=<n> closed=<n> floor=<n>`; `:168-248` standing-issue update.
- `.github/workflows/scheduled-followthrough-sweeper.yml:568-582` — permissions (`contents: read`, `issues: write`, `actions: read`); `:642-646` — `GH_TOKEN` already bound.
- `scripts/sweep-followthroughs.sh` — directive parser and launcher; per-probe timeout default 300s; exit meanings 0/1/2/3/5/78.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md:17-100` — probe contract, emitted-line rule, credential posture, retirement header, column-0 unfenced directive; `:159-169` — pre-existing issue enrollment cautions.
- `scripts/followthroughs/claude-cli-fable-bump-12514.sh` — close precedent: first post-merge runs, exact-step evidence, bounded reads, exit vocabulary.
- `scripts/followthroughs/bearer-curl-s4-first-runs-9905.sh` and `.test.sh` — emitted-line anchoring, xtrace refusal, cost budget, synthesized `gh` fixture harness.
- `scripts/lint-followthrough-varq-ban.sh` — probe lint: no `${VAR:?}` exits, retired Sentry credential ban, repo-path existence, comment-verdict rules, exec/probe census.
- `scripts/test-all.sh` — explicit `run_suite` registration required for follow-through tests.
- `scripts/regenerate-shard-manifest.py --incremental --write` — canonical regeneration path for `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` after registration.
- `knowledge-base/project/plans/archive/20261029-212547-2026-10-29-verify-web-host-replace-first-deploy-plan.md` — closest plan precedent: separate post-merge tracker, sweeper dry-run, no workflow edit when secrets already bound.

### Institutional Learnings Applied

- `2026-10-10-a-log-scraping-probe-matched-the-script-it-echoed-and-the-inline-copies-dropped-the-trim-the-library-had.md` — anchor only timestamped emitted lines; include echoed-source fixtures.
- `2026-10-05-the-drain-was-born-broken-and-the-waiver-hid-it.md` — this exact drain was green-masked before; verify live shapes, including API-specific identity spellings, rather than remembered behavior.
- `2026-09-25-a-fixture-suite-cannot-see-that-the-probe-can-no-longer-take-its-reading.md` — dry-run the real sweeper on the branch before shipping probe changes.
- `2026-07-07-followthrough-and-shape-gate-silent-falseness.md` — never use `${VAR:?}` in a probe; missing credentials must not exit 1.
- `2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md` — population claims must come from the enforcing mechanism's call sites; here the enforcing surfaces are the workflow's exact step names and the sweeper's directive parser.

### Community / External Research

- Community discovery found generic GitHub Actions investigation skills (`steeef/claude-skill-github-actions`, workflow-probe examples), but none implement this repo's follow-through directive contract, exit vocabulary, emitted-line discipline, or #9508 correlation. No install; the local substrate is the correct mechanism.
- External documentation used: GitHub REST workflow-runs docs (`https://docs.github.com/en/rest/actions/workflow-runs`) and workflow-jobs docs (`https://docs.github.com/en/rest/actions/workflow-jobs`). The docs confirm `actor`, `triggering_actor`, `status`, `created`, job step metadata, and the per-step logs endpoint. No additional external research needed; this is internal ops machinery on already-used GitHub APIs.

### Research Reconciliation — Spec vs. Codebase

No branch `spec.md` exists. Reconciliation is therefore against the issue text: the issue says inspect the Drain step log; live evidence shows `gh run view --log` may associate action output with `UNKNOWN STEP`, so the plan uses the per-step logs API instead of relying on `gh run view` step prefixes. The issue says use `secrets=GH_TOKEN`; the sweeper already binds it, so no workflow edit appears in scope.

### Agent-Fanout Note

The authoring harness exposes no Task/subagent tool. An attempted Claude CLI availability probe failed with `Not logged in`; repo research, learnings research, functional overlap, and technical assessment were therefore performed inline using the repository and live read-only GitHub evidence above. This is recorded transparently rather than claimed as independent agent coverage.

## Problem Statement / Motivation

PR #13096 fixed the actor allowlist, but the proof is inherently time-gated: the first weekly bot dispatch after the merge. Without an enrolled probe, the verification depends on a future session remembering to inspect a workflow whose run conclusion is deliberately vacuous (`continue-on-error: true`). The failure mode is not merely a missing checkbox: the pre-fix runs already showed the Drain step reporting `success` in the jobs API while its runtime log contained the actor refusal.

## Proposed Solution

Create one closing follow-through probe and enroll one separate post-merge tracker on the existing sweeper. The probe never dispatches the drain and never writes to #9508; it reads GitHub Actions and issue-comment state only.

### Probe algorithm — `scripts/followthroughs/machinery-drain-actor-gate-13122.sh`

Credential posture: requires `GH_TOKEN` with the sweeper's existing `actions: read` + `issues: write` token. Refuse xtrace with exit 78 when a live credential is present. Missing/empty `GH_TOKEN` exits 3 through an explicit `[[ -z ]]` check.

1. Query `repos/jikig-ai/soleur/actions/workflows/scheduled-machinery-drain.yml/runs` with `per_page=100`, `actor=soleur-ai%5Bbot%5D`, `status=completed`, `event=workflow_dispatch`, and `created=>=2026-11-28T12:57:15Z`. Validate shape; re-filter rows locally on `triggering_actor.login == "soleur-ai[bot]"`, `event`, `status`, `head_branch == "main"`, and `created_at >= cutoff`. Sort ascending by `created_at`.
2. If no row exists, print `NOT YET` and exit 2. Skip rows whose conclusion is `cancelled` or `skipped` because they cannot measure the drain; record that they were skipped. Select the first remaining completed run. This is a bounded technical ruling: a cancelled/skipped run is not evidence about the actor gate and must not permanently wedge verification behind a non-measurement.
3. Read `repos/.../actions/runs/<run-id>/jobs`; require exactly the job `measure-and-drain` with numbered steps `Drain the machinery ledger` and `Update the standing measurement issue`. Missing API data, missing steps, or a non-cancelled run whose drain step did not execute exits 3.
4. Download `repos/.../actions/jobs/<job-id>/steps/<drain-step-number>/logs` via `gh api --allow-escape-sequences`. Empty or unreadable logs exit 3.
5. Detect the actor refusal only as an emitted runtime line anchored after the timestamp: `##[error]Action failed with error: Workflow initiated by non-human actor: soleur-ai (type: Bot).` Do not strip ANSI before matching and never match the bare sentence. Fixture rows cover colourised or indented echoed `run:` source. If this line is present, print the run URL and exit 1 immediately.
6. Establish drain outcome evidence independently of step conclusion. A substantive non-actor diagnosis is an emitted `##[error]` line inside the Drain step log that is neither the actor refusal nor the generic `Process completed with exit code` line. `drain.run` success needs no diagnosis. `drain.run` failure with only the generic process line is not "clearly diagnosed" and exits 3.
7. Download the Update step log and require the emitted end-anchored line `updated standing issue #9508` (echoed `echo "updated standing issue..."` source must not count). Then read `repos/.../issues/9508/comments?since=<run-created-at>&per_page=100`; accept only a `github-actions[bot]` comment created within `[run.created_at, run.updated_at + 900s]`, containing `Machinery drain outcome:` and a parseable `before=<n> after=<n> closed=<N> floor=<n>` line. Missing, stale, wrong-author, or unparseable evidence exits 3.
8. Exit 0 only when the actor refusal is absent AND the correlated comment evidence exists AND one of these holds: `closed>0`; or `closed=0` with a substantive non-actor Drain-step diagnosis printed by the probe; or `closed=0` with an explicit `WAIVED-EMPTY`/`WAIVED-SUPPLY` verdict (a diagnosed non-actor outcome, not a drain failure). Otherwise exit 3 with the missing evidence named. Exit 2 is reserved for no qualifying completed measurement yet.

Cost is bounded at roughly five authenticated reads for the normal path (run list, jobs, two step logs, comments) and below 30s healthy time, far under the sweeper's 300s per-probe cap. Every `gh` invocation gets a bounded timeout; malformed JSON is an exit-3 input failure.

### Enrollment

Post-merge, create a new tracker issue titled `follow-through: weekly machinery-drain actor-gate verification` with label `follow-through`, close criteria in prose, and this unfenced column-0 directive:

```html
<!-- soleur:followthrough
script=scripts/followthroughs/machinery-drain-actor-gate-13122.sh
earliest=2026-11-30T18:00:00Z
secrets=GH_TOKEN
-->
```

`2026-11-30T18:00:00Z` is the first scheduled sweeper slot after the first expected Monday 09:00 UTC drain. This is a technical ruling, not operator scope: it avoids nine daily NOT-YET comments before evidence can exist while leaving the script's own exit-2 gate as the real availability test. After creating the tracker, close #13122 with a comment naming the tracker and the branch dry-run evidence. The PR body must use `Ref #13122`, not `Closes #13122`, because the issue closes only after enrollment.

Before PR-ready, run the read-only branch dry run prescribed by the convention: `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-13122-machinery-drain-verification -f dry_run=true`, then read the run log for this probe's parse/exit line. This is not the forbidden machinery-drain manual trigger and posts nothing.

## Technical Considerations

- The per-step logs endpoint is load-bearing. `gh run view --log` can label composite-action output as `UNKNOWN STEP`; the jobs API plus `/steps/<n>/logs` reads exactly the Drain step.
- The probe must not treat `Drain` step conclusion `success` as evidence: the pre-fix run already had that shape because `continue-on-error` converts the parent step outcome.
- The probe reads public issue comments but authenticated Actions logs; unauthenticated `curl` to the step-log endpoint returned HTTP 403 in validation.
- No workflow YAML, Inngest function, new scheduler, secret, persistent store, vendor, Terraform resource, UI surface, or production mutation is introduced. IaC, GDPR, Encryption Posture, Task-Design, Product/UX, and ADR/C4 gates are therefore skipped; this instantiates the existing follow-through architecture rather than changing it.
- NFR impact: reliability/operability only. No user-data model, latency-sensitive request path, or cost-bearing LLM fan-out is added. API cost is bounded as stated above.

## Files to Create

- `scripts/followthroughs/machinery-drain-actor-gate-13122.sh` — executable probe implementing the algorithm above, with credential posture, cost bound, exit contract, and `RETIREMENT:` header.
- `scripts/followthroughs/machinery-drain-actor-gate-13122.test.sh` — synthesized fixture suite with a strict stub `gh`, no live network, and mutation coverage below.

## Files to Edit

- `scripts/test-all.sh` — register `run_suite "scripts/machinery-drain-actor-gate-13122" bash scripts/followthroughs/machinery-drain-actor-gate-13122.test.sh`.
- `scripts/suite-shard-legs.tsv` — regenerate with `python3 scripts/regenerate-shard-manifest.py --incremental --write`.
- `scripts/suite-durations.tsv` — regenerated by the same command.

## Open Code-Review Overlap

- #7942 mentions `scripts/test-all.sh` but concerns discovery of `plugins/soleur/test/*.mutation.sh` batteries. **Acknowledge, do not fold in:** this plan adds one explicit `run_suite` line and does not alter suite-glob discovery semantics; the overlap is a shared file, not the same concern.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the actor-gate verification remains unmeasured and the machinery backlog signal stays ambiguous; the blast radius is an ops-telemetry gap.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — the probe reads GitHub Actions metadata/logs and public issue comments through the existing sweeper credential; it writes nothing except the sweeper's normal tracker comment.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal machinery verification only; no user data, user-facing surface, production mutation, or destructive capability is added.

## Observability

```yaml
liveness_signal:
  what: "Daily sweeper verdict on the follow-through tracker (PASS closes; NOT YET, FAIL, CANNOT ESTABLISH comment)"
  cadence: "daily 18:00 UTC after earliest=2026-11-30T18:00:00Z"
  alert_target: "GitHub tracker issue comment; sweeper workflow run log"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml (existing schedule/env; no edit)"
error_reporting:
  destination: "sweeper captures the probe's last 4KB stdout/stderr into the tracker comment"
  fail_loud: "exit 1 posts FAIL when the actor refusal persists; exit 3 posts CANNOT ESTABLISH naming the unreadable input; missing GH_TOKEN is exit 3"
failure_modes:
  - mode: "actor refusal persists"
    detection: "anchored emitted refusal line in Drain step log"
    alert_route: "exit 1 -> FAIL tracker comment with run URL"
  - mode: "weekly run has not completed"
    detection: "workflow-runs query returns no qualifying completed measurement"
    alert_route: "exit 2 -> NOT YET tracker comment"
  - mode: "GitHub API/log/comment evidence unavailable or malformed"
    detection: "bounded gh call failure, JSON shape validation, missing step/comment"
    alert_route: "exit 3 -> CANNOT ESTABLISH tracker comment"
  - mode: "echoed source mistaken for runtime output"
    detection: "fixture suite rows containing colourised/indented echoed source must not match"
    alert_route: "suite red before merge"
logs:
  where: "scheduled-followthrough-sweeper run logs and the tracker issue comment history"
  retention: "GitHub Actions retention for run logs; issue comments permanent"
discoverability_test:
  command: "bash scripts/followthroughs/machinery-drain-actor-gate-13122.sh"
  expected_output: "CANNOT ESTABLISH"
  credentials_required: "GH_TOKEN actions:read — unauthenticated workflow-list reads are public, but step-log download returned HTTP 403 in validation, so no unauthenticated probe verifies the same property"
```

## Guard Contract

### Guard 1 — machinery-drain actor-gate verification probe

**Property.** The tracker closes only when the first qualifying bot-triggered post-cutoff measurement run has no emitted actor refusal in its Drain step runtime log and has correlated #9508 verdict evidence; echoed source, run conclusion, wrong actors, stale comments, and malformed evidence must never close it.

**Assembly.** Every verdict flows through one probe decision path: workflow-runs API selection -> jobs API exact step resolution -> per-step Drain log scan -> Update-step emitted-comment confirmation -> #9508 comments API correlation -> exit-code decision. The fixture suite exercises that path through a strict `gh` stub; no alternative input path may decide the exit.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Match the bare actor-refusal sentence instead of the timestamped `##[error]Action failed` emitted shape | RED on a fixture whose only match is echoed source |
| 2 | Treat run conclusion or Drain step conclusion as evidence and skip the step-log read | RED on the pre-fix-shaped fixture (green conclusion + refusal in log) |
| 3 | Select the newest rather than the first/oldest post-cutoff run | RED with two qualifying runs whose verdicts differ |
| 4 | Accept a #9508 comment that predates the run, is outside the correlation window, or is not `github-actions[bot]`-authored | RED |
| 5 | Parse any `closed=N` anywhere rather than the bot comment's machinery-outcome evidence line | RED on a decoy comment/body |
| 6 | Return exit 2 or 0 when the Drain step, step log, update confirmation, or comment evidence is missing | RED; expected exit is 3 (guard's own dispatch/anti-vacuity) |
| 7 | Drop the second-run/cancelled-run handling so only the first row is ever examined | RED with a cancelled first row and a valid second measurement row |
| 8 | Mutate the harness so the strict `gh` stub answers an unexpected request shape instead of exiting 64 | RED; fixture harness must fail closed |
| 9 | Must-pass non-canonical input: fractional timestamp precision, CRLF log endings, and a WAIVED-SUPPLY `closed=0` verdict | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "add a committed probe under `scripts/followthroughs/`" | Files-to-Create probe | mapped |
| 2 | "file/enroll the time-gated tracker with label `follow-through`" | Enrollment phase | mapped |
| 3 | "use a column-0 directive with `secrets=GH_TOKEN`" | Enrollment directive | mapped |
| 4 | "select the first post-`2026-11-28T12:57:15Z` completed `scheduled-machinery-drain.yml` run triggered by `soleur-ai[bot]`" | Probe algorithm step 1-2 | mapped |
| 5 | "exit 2 (NOT YET) if no such completed run exists" | Probe algorithm step 2 | mapped |
| 6 | "inspect the drain-step log for the actor refusal" | Probe algorithm steps 3-5 | mapped |
| 7 | "inspect #9508 for the corresponding verdict comment and parse `closed=N`" | Probe algorithm step 7 | mapped |
| 8 | "exit 0 only when the actor refusal is absent and the verdict evidence is present, with `closed>0` or a clearly diagnosed non-actor failure" | Probe algorithm steps 6-8 | mapped |
| 9 | "exit 1 when the actor refusal persists" | Probe algorithm step 5 | mapped |
| 10 | "exit 3 when evidence cannot be established" | Probe algorithm steps 3-8 | mapped |
| 11 | "The probe needs a test fixture because GitHub logs echo workflow source text" | Files-to-Create test + Guard Contract | mapped |
| 12 | "Do **not** fire `cron/machinery-drain.manual-trigger` without explicit operator authorization" | Proposed Solution non-goal + enrollment | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Probe file | "add a committed probe under `scripts/followthroughs/`" | asked |
| Fixture suite | "The probe needs a test fixture" | asked |
| Tracker enrollment | "file/enroll the time-gated tracker with label `follow-through`" | asked |
| `test-all.sh` registration | — | inferred — justification: the fixture suite must run in CI or the required regression protection rots |
| shard/duration rows | — | inferred — justification: registration regeneration is the test runner's enforcement contract |
| branch sweeper dry-run | — | inferred — justification: the follow-through convention requires real-sweeper validation before shipping a probe |

### Split Assessment

- Subsystems touched: 1 — `scripts`
- Planned files: 5 | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `scripts/followthroughs/machinery-drain-actor-gate-13122.sh` exists, is executable, follows the follow-through header/exit/credential/retirement conventions, and never fires `cron/machinery-drain.manual-trigger` or any workflow dispatch.
- [ ] The probe selects the first qualifying completed post-cutoff `scheduled-machinery-drain.yml` workflow_dispatch run on main whose `triggering_actor.login` is `soleur-ai[bot]`, with cancelled/skipped non-measurements explicitly skipped and reported.
- [ ] The probe reads the exact `Drain the machinery ledger` step through the per-step logs API; run conclusion and parent step conclusion are never used as actor-gate evidence.
- [ ] The actor-refusal detector matches only timestamped emitted `##[error]Action failed...` runtime lines and fixture rows prove echoed workflow/shell source does not count.
- [ ] The probe requires emitted `updated standing issue #9508` evidence in the Update step log and a correlated `github-actions[bot]` #9508 comment inside the run window containing `Machinery drain outcome:` plus parseable `closed=N`.
- [ ] Exit semantics are exactly: 2 when no qualifying completed measurement exists; 1 when the refusal persists; 3 when evidence cannot be established; 0 only under the evidence bar in the algorithm.
- [ ] `scripts/followthroughs/machinery-drain-actor-gate-13122.test.sh` uses synthesized fixtures, includes all mutation-matrix rows, and passes locally; probe/lint suites pass (`lint-followthrough-varq-ban.sh`, followthrough exec-bit/predicate parity as applicable).
- [ ] `scripts/test-all.sh` registers the suite and `suite-shard-legs.tsv`/`suite-durations.tsv` are regenerated with the documented incremental command.
- [ ] A read-only sweeper dry-run on the branch completes and the run log shows the probe parse/exit line with no missing-secret error.
- [ ] Post-merge, a new issue is created with label `follow-through`, the exact column-0 unfenced directive, `earliest=2026-11-30T18:00:00Z`, and `secrets=GH_TOKEN`; #13122 is then closed with a comment naming that tracker.
- [ ] `.github/workflows/scheduled-followthrough-sweeper.yml` is not edited because `GH_TOKEN` is already bound.

## Test Scenarios

- **Unit:** Given no completed post-cutoff runs, when the probe runs, then it prints NOT YET and exits 2.
- **Unit:** Given a completed run whose Drain log contains the emitted actor refusal, when scanned, then it exits 1 even if jobs/run conclusions are success.
- **Unit:** Given only colourised/indented echoed source containing the refusal sentence, when scanned with otherwise clean evidence, then it does not exit 1 and may pass.
- **Unit:** Given clean Drain evidence and a correlated comment with `closed=3`, when all reads succeed, then it exits 0.
- **Unit:** Given clean actor evidence, `closed=0`, and a substantive non-actor `##[error]` diagnosis, when correlated comment evidence exists, then it exits 0 and prints the diagnosis.
- **Unit:** Given `closed=0` with only the generic process-exit line or an unexplained BREACH, when evaluated, then it exits 3.
- **Unit:** Given a WAIVED-SUPPLY or WAIVED-EMPTY verdict with `closed=0`, when actor evidence is clean, then it exits 0.
- **Unit:** Given missing GH_TOKEN, malformed run/jobs JSON, missing Drain/Update steps, unreadable logs, missing update emission, stale/wrong-author/unparseable comment evidence, or a gh failure, when encountered, then the probe exits 3.
- **Unit:** Given a cancelled first row and a valid later measurement row, when selecting, then it reports the skip and verifies the valid row.
- **Unit:** Given xtrace with GH_TOKEN set, when invoked, then it exits 78.
- **Integration:** Given the strict stub `gh`, when the probe requests any unanticipated shape, then the stub exits 64 and the suite row goes red.
- **Integration:** Given the branch dry run, when the real sweeper parses the directive, then the log shows the probe executed without REQUIRED-SECRET-MISSING.

## Implementation Phases

### Phase 1 — Probe and fixture harness

1. Create the probe and executable bit. Use small helper functions for API reads, validation, emitted-line scans, and verdict classification so fixture mutations can target behavior rather than copy-pasted inline conditions.
2. Create the synthesized fixture suite first for the exit semantics and log-echo traps; confirm selected rows fail before implementation where practical, then implement to green.
3. Register the suite in `scripts/test-all.sh` and regenerate shard/duration rows.

### Phase 2 — Static gates and branch sweeper dry run

1. Run the fixture suite standalone; run `scripts/lint-followthrough-varq-ban.sh`; run followthrough exec/predicate parity suites that cover this directory.
2. Run targeted `test-all.sh` selection or the affected shard as required by work/QA.
3. Run the read-only sweeper dry run on this branch and inspect the log.

### Phase 3 — Post-merge enrollment

1. Create the new tracker issue with label `follow-through` and the directive exactly as specified.
2. Verify `gh issue view <tracker> --json labels,body` shows label + unfenced column-0 directive.
3. Close #13122 with a comment naming the tracker and dry-run evidence. Do not close the new tracker; the probe closes it only on PASS.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal engineering/ops verification machinery (`meta/machinery`); the mechanical UI-surface override does not fire because no UI-surface files are in the Files lists.

## Success Metrics

- The first post-cutoff weekly run produces a deterministic tracker verdict at the 2026-11-30 18:00 UTC sweep without any manual trigger.
- If the actor refusal persists, the tracker remains open with a FAIL comment naming the run and emitted log evidence.
- If the fix is verified, the tracker closes automatically only after runtime-log and #9508-comment evidence agree.

## Dependencies & Risks

- **GitHub log API availability/shape drift** — mitigated by malformed-shape exit 3, fixture-pinned endpoint shapes, and bounded retries through the daily sweeper.
- **First week `closed=0` ambiguity** — deliberately not an automatic failure; the exit-0 bar requires either positive drain count or explicit non-actor diagnosis/waiver.
- **Comment correlation false-positive** — mitigated by the Update-step emitted line plus author/time/body conjuncts.
- **Tracker lifecycle inversion** — mitigated by using a separate post-merge tracker and `Ref` rather than `Closes` in the implementation PR.
- **Sweeper dry-run is a workflow dispatch** — it is read-only by design (`dry_run=true`) and is the convention-required validation; it is distinct from the forbidden machinery-drain production trigger.

## References & Research

- Issue: #13122; source issue #13095; fix PR #13096; measurement issue #9508.
- Docs: GitHub REST workflow-runs and workflow-jobs endpoints (URLs in Research Insights).
- Precedents: `scripts/followthroughs/claude-cli-fable-bump-12514.sh`, `scripts/followthroughs/bearer-curl-s4-first-runs-9905.sh`, and the #10585 first-deploy verification plan.
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
