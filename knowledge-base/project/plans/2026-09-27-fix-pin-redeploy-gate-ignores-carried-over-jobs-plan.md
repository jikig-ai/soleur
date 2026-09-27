---
title: "fix: the pin-redeploy gate skips a carried-over git-data job only when a deploy already followed its apply (#8760)"
type: fix
date: 2026-09-27
slug: fix-pin-redeploy-gate-ignores-carried-over-jobs
branch: feat-one-shot-8760-pin-redeploy-rerun-carryover
issue: 8760
closes: 8760
priority: p3
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: the pin-redeploy source-run gate stops replaying git-data jobs carried over by a partial re-run

## Overview

The source-run gate that decides whether a git-data birth or replace rotated the host-key pin
reads the jobs of the attempt that fired it. After a "re-run failed jobs", a git-data job that
already succeeded in the earlier attempt is listed again in the new attempt as if it had run
there, so the new attempt's follower forces a second production web release for a rotation the
earlier follower already handled. This plan makes the gate recognise such carried-over jobs from
their measured API shape and skip the release **only when a web-platform release created after
that job's apply step finished has a successful `deploy` job** — i.e. only when the release would
provably be redundant. Every unprovable case keeps today's behaviour (redeploy).

Scope: `.github/actions/dispatch-web-redeploy/source-run-gate.sh` (decision), its suite
`tests/scripts/test-dispatch-web-redeploy.sh` (plus two captured fixture files), and three prose
sync points (one sentence in the follower workflow's header comment, one clause in ADR-237, one
sentence in the cutover runbook). No workflow `if:`, job, env or step change.

**Plan v2** (after a four-seat plan review: DHH, Kieran, code-simplicity, CTO). Changes from v1
are listed in `## Plan Review Revisions`; taste and user-challenge findings not applied are in
`knowledge-base/project/specs/feat-one-shot-8760-pin-redeploy-rerun-carryover/decision-challenges.md`.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #8760 / brief) | Reality (measured 2026-09-27) | Plan response |
|---|---|---|
| Issue: `gh run view <id> --json jobs` "lists the latest attempt of each job" | The gate already passes `--attempt "$SOURCE_RUN_ATTEMPT"` (#8755). `gh run view 36325677861 --attempt 2 --json jobs` lists all 14 jobs, 11 of them carried over from attempt 1 | The defect is that an attempt's listing includes carried-over jobs. Keep the attempt read; add the discriminator. |
| Issue candidate fix: ignore jobs whose `run_attempt` is lower | Carried-over jobs appear in attempt 2 with `run_attempt: 2` and a NEW job id (`detect-changes` 108637873581 in attempt 1, 108641168446 in attempt 2). `gh run view --json jobs` does not expose `run_attempt` at all | Rejected: cannot work. Discriminator: job `startedAt` earlier than the attempt's run `startedAt`. |
| Brief: carried-over jobs keep attempt-1 `started_at`/`completed_at` | Confirmed: `detect-changes` 14:26:30Z/14:26:47Z in both attempts; attempt-2 run `startedAt` 14:41:55Z; the 3 re-executed jobs start 14:44:03Z, 14:48:32Z, 14:48:35Z. A carried job's steps keep attempt-1 timestamps and stay intact (6 steps) | Fixture captured from this run (AC3). |
| Brief: "`run_started_at`" | `gh run view <id> --attempt 2 --json startedAt` prints `2026-09-27T14:41:55Z` = REST `run_started_at` of attempt 2 (same value without `--attempt`). `createdAt` differs by scope: 14:41:56Z with `--attempt 2`, 14:22:30Z without | One call, `--json jobs,startedAt`. Never `createdAt` of the source run. |
| Issue: impact is "an extra same-pin redeploy, never a missed one" | True only by accident: the attempt-N follower's redundant release also covers an attempt-(N-1) follower that never ran (cancelled while pending in the job-level concurrency group, #9085). A discriminator-only fix removes that cover | The skip also requires deploy evidence. Without it, grade as today. |
| (plan v1) Evidence = a `completed` release run | `web-platform-release.yml`'s `live-verify` and `release-outcome` jobs `needs: deploy`, and `track.sh` returns as soon as `deploy` succeeds, so F1's release is usually still `in_progress` when F2's gate runs (Kieran P1) | Adopt `track.sh`'s rule verbatim: skip only `queued` runs; the `deploy` job's own conclusion is the evidence. |

## Research Insights

**Premise Validation (Phase 0.6).** #8760 is OPEN (p3, type/bug, meta/machinery). Predecessor
#8710 is CLOSED by PR #8755 (merged 2026-09-24T22:06:07Z); its plan is archived at
`knowledge-base/project/plans/archive/20260925-115424-2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md`
(the brief's un-archived path no longer exists). `source-run-gate.sh`, `track.sh`,
`git-data-pin-redeploy.yml` and `tests/scripts/test-dispatch-web-redeploy.sh` exist on the branch
base (`ab4a07e5e0`). The issue's blocker ("no re-run exists to measure") is discharged by run
36325677861 attempt 2; its candidate mechanism is refuted by measurement. No ADR rejects a
timestamp discriminator or a deploy-evidence check.

**Measurements (read-only, 2026-09-27, `GH_REPO=jikig-ai/soleur`, gh 2.101.0):**

- `gh api repos/jikig-ai/soleur/actions/runs/36325677861` -> `run_attempt: 2`,
  `run_started_at: 2026-09-27T14:41:55Z`. `.../attempts/1` -> `run_started_at 14:22:30Z`, failure;
  `.../attempts/2` -> `run_started_at 14:41:55Z`, success. `.../attempts/2/jobs` equals
  `.../jobs?filter=latest` (14 jobs, all `run_attempt: 2`); `?filter=all` returns 28 distinct ids.
- `gh run view 36325677861 --attempt 2 --json jobs,startedAt`: top-level keys `["jobs","startedAt"]`;
  job keys `completedAt conclusion databaseId name startedAt status steps url`; step keys
  `completedAt conclusion name number startedAt status`; every timestamp `YYYY-MM-DDTHH:MM:SSZ`.
  `jq '.startedAt as $r | .jobs[] | select(.startedAt < $r)'` selects exactly the 11 carried jobs.
- Release evidence: `gh run view <id> --json databaseId,status,conclusion,event,createdAt` for
  36324585966 (`workflow_run`, created 14:04:07Z, `deploy` success started 14:15:19Z),
  36338915404 (`workflow_run`, created 17:58:39Z, `deploy` success started 18:01:25Z, 9 steps),
  36339814543 (`workflow_run`, created 18:12:56Z, `deploy` skipped, 0 steps). `gh run list
  --workflow web-platform-release.yml --limit 50` spans ~34 h (08:30:51Z on 09-26 to 18:19:07Z on
  09-27), 31 of 50 non-`push`.
- Real git-data runs: 35979304442 (replace) runs `preflight` + `git_data_host_replace`;
  34822248580 (birth) runs `preflight` + the birth disclosure job + `git_data_host_create`.
  `git_data_host_replace` has no `needs:`, so the realistic #8760 shape is `preflight` failing
  (`timeout-minutes: 1`) while the replace succeeds; "re-run failed jobs" re-runs `preflight` only.
- jq (CI `ubuntu-24.04` ships 1.7.1; local 1.8.2): `"2026-09-27T14:41:55Z" | fromdateiso8601` ->
  `1790520115`; `"0001-01-01T00:00:00Z"` (Go zero time) -> `-62135596800`; `""`, `null` and
  fractional seconds raise an error.

**Relevant files.**

- `.github/actions/dispatch-web-redeploy/source-run-gate.sh` — the one source read; `_q` (checked
  per-job read, jq failure -> `_unreadable` exit 1); `grade()`; the combination loop; header table.
- `.github/actions/dispatch-web-redeploy/track.sh` — `EVENT_ARM='["workflow_dispatch","workflow_run"]'`,
  `DEPLOY_JOB="deploy"`, `queued` runs not viewed, exactly-one-`deploy`-with-`success` rule. The
  gate's evidence check adopts these; a parity row pins the two literals (Guard row H3).
- `.github/workflows/git-data-pin-redeploy.yml` — `SOURCE_RUN_ATTEMPT: ${{ github.event.workflow_run.run_attempt }}`
  (empty on manual dispatch); gate step `timeout-minutes: 5`; job-level concurrency; `actions: write`
  (covers reading release runs, as `track.sh` does).
- `tests/scripts/test-dispatch-web-redeploy.sh` — gh PATH stub (exact argv, `UNEXPECTED` + exit 64
  otherwise); `_gjob`/`_gdoc`; rows G1–G26; GH stubbed-gate list; GM mutations; `FLOOR=102`.
  Registered in `scripts/test-all.sh` (`run_suite "tests/scripts/dispatch-web-redeploy"`).
- `plugins/soleur/test/terraform-target-parity.test.ts` — PT1–PT4 pin the follower's structure;
  **PT5** (`verdictParity`) requires every `verdict=<token>` cited on a runbook/ADR/workflow line
  matching `/pin-redeploy|source-run-gate|pin_published|plan_only/` to be emitted by a gate line
  starting with `echo` or `_summary`. Not edited; the new token must satisfy it (AC9).
- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md` (bullet
  `A CI-to-CI dispatch edge.`); `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
  (paragraph `If only the redeploy failed:`).

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`:
  the new verdict is this gate's fail-OPEN direction (no redeploy), so it needs positive evidence
  on both axes; anything unprovable grades as today.
- `knowledge-base/project/learnings/2026-04-19-mu1-ac2-fixture-repo-gate-design.md`: `"" < "2026-…"`
  is TRUE in jq — parse with `fromdateiso8601` and require `> 0`, never string-compare.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`:
  must-PASS non-canonical rows and a precondition-holds-but-must-redeploy row (GC5).

**Related issues/PRs.** #8710 / PR #8755, #7226, #5914, ADR-237, #8776 (not edited), #8211 (the
intended replacement redeploy path, which may retire this gate), **#9085** (filed by this plan:
a pending rotation follower can be cancelled by a later dispatched apply run's follower).

**Property List (Phase 0.6b).**

- P1. A follower fired by attempt N >= 2 does not force a release for a git-data job that ran in an
  earlier attempt when a release created after that job's apply finished has already deployed.
- P2. A real rotation in a re-run still reaches the app (a git-data job re-executed in attempt N is
  graded as today).
- P3. The manual path (`workflow_dispatch -f source_run_id=<id>`, no attempt) and attempt 1 are
  unchanged, including their call log (no evidence reads).
- P4. Alerts are never suppressed: red carried jobs keep 5a/5b; every fail-closed arm keeps precedence.
- P5. Whenever either half of the skip condition cannot be proven, the gate redeploys as today.

**Cut List (Phase 0.6b + plan review).**

- `run_attempt` filter (issue candidate) -> refuted by measurement.
- Attempt-(N-1) twin read; attempt-(N-1) follower lookup; pin comparison against Doppler -> the
  deploy-evidence conjunct answers "was the pin loaded?" from state; the follower lookup has no API
  link (a `workflow_run` run names no upstream run id) and the follower holds no Doppler access.
- `createdAt >= T_apply - 3600` window and a per-deploy `startedAt >= T_apply` check (v1) -> replaced
  by `createdAt >= T_apply` alone: a run created after the apply cannot deploy before it; stricter,
  so it only errs toward redeploying (DHH P1).
- `status == completed` filter (v1) -> wrong: defeats the main case (Kieran P1); replaced by
  `track.sh`'s `queued`-skip.
- Per-job `.carried=` token, step-summary line, list caching across jobs, the attempt-1 fixture, the
  premise row GP, the run-list fixture, GC14 -> no listed property (simplicity review).
- Workflow-level `run_attempt == 1` gate -> violates P2. Follower split into gate + redeploy jobs ->
  #9085's scope.

**Value-proposition (Phase 0.6c).** One avoided production release per partial re-run of a
rotating apply run; measured frequency at filing: zero re-runs in the repo's last 500 runs.

**Scoped advisor consult (Phase 4.5).** Returned (1) require proof beyond one timestamp comparison
and (2) keep the accidental cover for a cancelled attempt-(N-1) follower. Both adopted through one
mechanism, the deploy-evidence conjunct.

## Problem Statement

`git-data-pin-redeploy.yml` fires on every completed dispatched apply run and passes
`SOURCE_RUN_ATTEMPT`. Attempt 1 of a git-data replace whose `preflight` failed still completes, so
follower F1 grades the replace `rotated` and dispatches release R1. "Re-run failed jobs" re-runs
`preflight`; the replace is carried over; attempt 2 completes; follower F2 (queued behind F1 in the
job-level group) reads a listing where the replace appears with job + apply `success`, grades it
`rotated`, and dispatches a second, unplanned production release.

## Proposed Solution

### Decision rule (delta to the #8710 table)

Source read: `gh run view "$rid" "${att[@]}" --json jobs,startedAt` (one document, one call).

Two predicates, defined once under the header table (the table gains one line for row 2c):

**CARRIED(job)** — all of: (1) `SOURCE_RUN_ATTEMPT` matched `^[1-9][0-9]*$` and is `>= 2`; (2) the
job's `startedAt` parses (`try (fromdateiso8601) catch 0`) to `> 0`; (3) the document's run-level
`startedAt` parses the same way to `> 0`; (4) job epoch `<` run epoch (strict). The comparison runs
inside ONE jq expression over the document that prints a single word (`yes`/`no`), read through a
checked assignment that is NOT routed to `_unreadable`: a jq failure here means `no`.

**DEPLOYED_AFTER(job)** — evaluated only when CARRIED is `yes`. `T_apply` = the job's single apply
step's `completedAt`, parsed the same way (`> 0` or the predicate is false). Then:

1. `gh run list --workflow web-platform-release.yml --limit 50 --json databaseId,status,event,createdAt`
   succeeds and is one JSON array;
2. candidates, newest first: `event` in `EVENT_ARM`, `status != "queued"` (as `track.sh`),
   `createdAt` parsing to `>= T_apply`, `databaseId` matching `^[0-9]+$`;
3. for each candidate, `gh run view <id> --json jobs` (the exact argv `track.sh` sends) succeeds and
   has EXACTLY ONE job named `deploy`, whose conclusion is `success`. The first such run is the
   evidence `EV`.

Any read failure, non-array document, unparseable value, or no qualifying run -> false (never exit
1, never an error annotation). No caching: each carried job does its own list read.

| row | job | apply step | CARRIED and DEPLOYED_AFTER | result | token |
|---|---|---|---|---|---|
| 2c | success | A == success, N == 1 | both hold | quiet notice, no redeploy | `verdict=carried_over` |

Row 2c sits inside the `1:success` arm, before row 2; everything else is unchanged. Row 4 keeps
precedence (CARRIED is only consulted on that arm); a carried green job with apply `skipped` stays
`no_apply`; a carried red job keeps 5a/5b (P4).

**Combination.** Any row 4 -> exit 1. Else any `rotated` -> proceed (birth wins a tie, but a birth
demoted to `carried_over` is not `rotated`, so a fresh replace proceeds with
`source_job=git_data_host_replace`). Else any 5a/5b -> warning. Else any `carried_over` -> quiet
notice. Else `no_apply`, else `not_run`.

**Output.** `tokens` is unchanged. The first job in `JOBS` order whose verdict is `carried_over`
is named, with its evidence (`EV` validated `^[0-9]+$`, else not printed as evidence):

`echo "::notice::source-run-gate: no redeploy — in run ${rid} attempt ${SOURCE_RUN_ATTEMPT} ${tokens}: ${cj} and its apply step succeeded in an EARLIER attempt of this run, and web-platform-release run ${EV} (created after that apply finished) deployed successfully, so it read Doppler prd at least as new as the rotation. deploy_after_apply=${EV} verdict=carried_over. To redeploy anyway: ${REDEPLOY_CMD}."`

— one source line starting with `echo` (PT5). When CARRIED holds but DEPLOYED_AFTER does not, the
existing `verdict=rotated` notice gains the literal `deploy_after_apply=none` so an operator can see
why a re-run follower redeployed. `${SOURCE_RUN_ATTEMPT}` is the validated integer.

### Files to Edit

- `.github/actions/dispatch-web-redeploy/source-run-gate.sh` — source argv `--json jobs,startedAt`;
  a run-level epoch read (a separate checked read; `_q` only reaches `.jobs[]`); CARRIED and
  DEPLOYED_AFTER as above (constants `RELEASE_WORKFLOW`, `EVENT_ARM`, `DEPLOY_JOB` spelled as in
  `track.sh`); row 2c in `grade()`; the `carried` flag and notice arm in the combination loop;
  header: predicates block, row 2c, replace the paragraph `The jobs are read for SOURCE_RUN_ATTEMPT…`
  with the carried-over rule and its evidence (run 36325677861 attempt 2), and the `Env:` line.
- `tests/scripts/test-dispatch-web-redeploy.sh`:
  - gh stub: the gate's source arms become `run view <id> --json jobs,startedAt` and
    `run view <id> --attempt N --json jobs,startedAt`; the old `--attempt N --json jobs` arm is
    deleted (only the old gate sent it); `run view <id> --json jobs` stays (track + evidence) and
    gains a per-id `$d/view.<id>.rc`; new arm `run list --workflow web-platform-release.yml --limit 50 --json databaseId,status,event,createdAt`
    served from `$d/relruns.json` (default `[]`), `$d/relruns.rc` for failure;
  - `_gexec`: after every run, asserts zero `UNEXPECTED` lines, and — unless the row sets
    `EVIDENCE=1` — zero release-list calls (`grep -cxF '<exact argv>' calls.log`, compared to 0;
    never a negated regex grep). This single helper replaces per-row edits of G1–G26;
  - `_gjob`: jobs and steps carry `startedAt`/`completedAt` (defaults = the captured re-executed
    job's values); `_rep`/`_birth` take an optional timestamp profile so the apply step's
    `completedAt` is named explicitly (the carried profile sets the apply step's `completedAt` to
    the captured carried job's `completedAt`, 14:26:47Z — never an index-mapped step); `_gdoc`
    emits the captured run-level `startedAt`, overridable/removable;
  - fixture-provenance comment: add run 36325677861 attempt 2, releases 36324585966, 36338915404,
    36339814543, the capture commands and date;
  - G23 expects `run view 555 --attempt 2 --json jobs,startedAt` / `run view 555 --json jobs,startedAt`;
  - new rows GC1–GC13, H3, their GH entries and GM mutations (Guard Contract);
  - `FLOOR`: re-measured from a green CI run (`pass + fail`) and commented with date and #8760
    (convention per the brief; the floor itself is the enforcing check).
- `.github/workflows/git-data-pin-redeploy.yml` — comment only: one sentence in the `THE GATE`
  paragraph (a git-data job carried over from an earlier attempt is not redeployed again once a
  release created after its apply has deployed; a manual dispatch grades it as a rotation).
- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md` — in
  `A CI-to-CI dispatch edge.`, after "so a `plan_only` rehearsal never redeploys": "and a job carried
  over from an earlier attempt by a partial re-run is not redeployed again once a release created
  after its apply has deployed (#8760)". No status change.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` — in `If only the
  redeploy failed:`, on one line that also names `source-run-gate` (so PT5 reads it): "`verdict=carried_over`
  from source-run-gate means a later attempt's follower saw a carried-over git-data job and a release
  that already deployed after its apply (named by `deploy_after_apply=`); no action is needed, and
  `gh workflow run git-data-pin-redeploy.yml --ref main` redeploys anyway."

### Files to Create

Captured read-only with `GH_REPO=jikig-ai/soleur`, trimmed by `jq` to the records the suite uses,
every field of each kept record preserved. The commands are reproducible for as long as GitHub
retains the runs (per-id reads, not a moving list):

- `tests/scripts/fixtures/gh-run-view-36325677861-attempt2-jobs-startedAt.json` —
  `gh run view 36325677861 --attempt 2 --json jobs,startedAt | jq -c '{startedAt, jobs: [.jobs[] | select(.name == "detect-changes" or .name == "deploy-script-tests (1/4)")]}'`
  (one carried job, one re-executed).
- `tests/scripts/fixtures/gh-web-platform-release-evidence.json` —
  `for id in 36324585966 36338915404 36339814543; do gh run view $id --json databaseId,status,event,createdAt,jobs | jq -c '{databaseId, status, event, createdAt, jobs: [.jobs[] | select(.name == "deploy")]}'; done | jq -s -c .`

The suite builds `relruns.json` and `jobs.<id>.json` from the second file with `jq`. Both files
are GitHub run metadata of this public repository — no secrets, emails or tokens.

## Technical Considerations

- **Manual arm and attempt 1 excluded (P3).** The runbook's recovery `-f source_run_id=<apply-run-id>`
  reads the latest attempt; the operator's explicit dispatch keeps today's semantics. Attempt 1
  cannot carry anything over, and excluding it keeps its call log byte-identical.
- **Why `createdAt >= T_apply` is sufficient evidence.** The apply step is the only CI writer of the
  pin (parity PT4), so the new pin is in Doppler prd before `T_apply`. A release run created after
  `T_apply` starts its `deploy` job later still, and `ci-deploy.sh` re-downloads prd in that job —
  the same reasoning `track.sh` step 3 relies on ("a merge-triggered release that deploys after the
  pin was published loads it just as well"). A re-run release keeps its original `createdAt` and
  may be excluded; that only errs toward redeploying.
- **The main case works.** F2 runs after F1 (job-level group); F1's `track.sh` returned once R1's
  `deploy` succeeded, so R1 is `in_progress` or `completed` with `deploy` `success`, created after
  `T_apply` (F1 fires only after attempt 1 completes).
- **#9085.** If F1 was cancelled while pending, no release followed the apply unless an unrelated
  one did; DEPLOYED_AFTER is then false and F2 redeploys — the accidental cover becomes deliberate.
  Once #9085 lands, the deploy-evidence conjunct may be simplifiable (comment posted on #9085).
- **Security.** Printed values: constants, allowlisted conclusions, the validated source run id,
  the validated attempt integer, a `^[0-9]+$`-validated release id. The token already reads release
  runs in `track.sh`. Not an authorization gate (#8710's plan).
- **Cost.** One `run list` plus one `run view` per candidate (few: created after `T_apply`), only on
  attempt >= 2 followers with a carried rotated job.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `run_attempt < SOURCE_RUN_ATTEMPT` filter (issue's candidate) | Measured: carried jobs carry `run_attempt == N`; gh does not expose it. |
| Timestamp discriminator alone | Removes the accidental cover for a cancelled attempt-(N-1) follower (#9085); any timestamp oddity becomes a missed redeploy. |
| DEPLOYED_AFTER alone, dropping CARRIED conjuncts 2-4 (DHH, simplicity) | Taste/user-challenge: the brief names the `startedAt` discriminator; dropping it widens the skip to re-executed jobs. Recorded in decision-challenges.md. |
| Annotate only, keep redeploying; or close #8760 as won't-fix (CTO, DHH, simplicity) | User-challenge: the brief asks for a fix with `Closes #8760`. Recorded in decision-challenges.md. |
| Attempt-(N-1) twin read / follower lookup / Doppler pin compare | See Cut List. |
| Workflow-level `run_attempt > 1` skip | Breaks P2. |
| Apply the skip to red jobs (suppress duplicate pin_published email) | Suppresses an alert (P4). |
| Source run `createdAt` as the attempt boundary | Measured inconsistent across `--attempt` scopes. |
| Shared sourced lib for `EVENT_ARM`/`DEPLOY_JOB` with `track.sh` | Touches `track.sh` and its sparse-checkout path; a parity row (H3) pins the two literals with less diff. |

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) an unplanned production web release
  after an operator re-runs a failed apply run (a brief web-app restart; today's behaviour), or
  (b) — the worse direction — a MISSED redeploy after a real git-data rotation, so the app keeps
  the old host-key pin and account erasures fail with `host_key_mismatch` until an operator
  redeploys. Every unprovable case routes to (a).
- **If this leaks, the user's data is exposed via:** no new exposure vector. The gate reads GitHub
  run metadata only, holds no Terraform or Doppler credential, and prints only constants,
  allowlisted conclusions and validated integers.
- **Brand-survival threshold:** `aggregate pattern` — a missed or spurious redeploy degrades
  erasures or availability for everyone in a window; no single user's data is exposed.

## Observability

```yaml
liveness_signal:
  what: "the pin-redeploy run's gate step log line prefixed `source-run-gate:` carrying `in run <source id>` and one `verdict=` token (rotated, carried_over, no_apply, not_run, pin_published, pin_maybe_published, unidentified; carried arms also print `deploy_after_apply=<release run id>|none`), plus the `Dispatch web-platform-release and wait for its deploy` step conclusion"
  cadence: "per completed dispatched apply-web-platform-infra run attempt (workflow_run)"
  alert_target: "operator email via notify-ops-email on any failure of the redeploy job and on verdict=pin_published/pin_maybe_published (unchanged); GitHub run annotations"
  configured_in: ".github/workflows/git-data-pin-redeploy.yml (step gate; the two notify-ops-email steps)"

error_reporting:
  destination: "layer 6 — workflow run log and ::error::/::warning::/::notice:: annotations on the pin-redeploy run; Resend email to ops on job failure and on pin_published"
  fail_loud: "unchanged fail-closed arms (`(fail closed)` and `verdict=unidentified`, exit 1). The new arm never fails loud by design: every unprovable carried case falls back to `verdict=rotated deploy_after_apply=none` and a redeploy, whose own failure emails ops"

failure_modes:
  - mode: "gh stops printing the run-level startedAt, or the release reads fail"
    detection: "layer 6: a re-run follower prints verdict=rotated and redeploys (status quo); CI: G23's exact source argv, and the stub's UNEXPECTED check in _gexec on every row"
    alert_route: "none needed — the fallback is the pre-fix behaviour (one extra release)"
  - mode: "a carried rotation skipped although the app did not load the pin"
    detection: "requires a release created after the apply whose successful deploy job did not re-read Doppler prd, which ci-deploy.sh excludes; CI rows GC5, GC10, GC11, GC13 pin every evidence-negative shape to a redeploy"
    alert_route: "PR check failure; at runtime erasures surface host_key_mismatch through the existing ADR-237 Sentry op"
  - mode: "real rotation in a re-run attempt misread as carried over"
    detection: "CI rows GC2, GC8, GC9 and mutations 2-4"
    alert_route: "PR check failure"

logs:
  where: "GitHub Actions run logs of git-data-pin-redeploy.yml (gh run view <id> --log)"
  retention: "GitHub Actions log retention for the repository (90 days default)"

discoverability_test:
  command: "grep -m1 -o 'verdict=carried_over' .github/actions/dispatch-web-redeploy/source-run-gate.sh"
  expected_output: "verdict=carried_over"
```

The token is a literal in the gate source. The probe proves presence, not reachability — GC1 proves
that. It fails on `main` today (0 occurrences).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-237 Consequences bullet `A CI-to-CI dispatch edge.` with the one clause in Files to Edit.
No new ADR: a refinement of the gate's input rule on an existing edge. No status change.

### C4 views

No C4 impact. Checked against `knowledge-base/engineering/architecture/diagrams/model.c4`,
`views.c4` and `spec.c4` in the work phase: no new external actor (the operator who re-runs a
failed apply run is the existing operator actor); no new external system (GitHub Actions, Doppler
and the web-platform release path are modeled or explicitly out of C4 scope — ADR-237: "C4 does not
model CI-to-CI edges"); no container or store touched; no access relationship changed (the
follower's token already reads release runs in `track.sh`). Backed by a green
`bash plugins/soleur/test/c4-count-parity.test.sh` (AC10).

### Sequencing

Lands with the code change in the same PR.

## Guard Contract

### Guard 1 — the gate skips a git-data rotation only when it ran in an earlier attempt AND a later release already deployed

**Property.** For a follower fired by attempt N, `source-run-gate.sh` emits `proceed=false` with
`verdict=carried_over` for a green git-data job whose apply step succeeded if and only if N >= 2,
the job's `startedAt` is strictly earlier than attempt N's run `startedAt`, and some non-`push`,
non-`queued` web-platform-release run created at or after that apply step's `completedAt` has
exactly one `deploy` job, concluded `success`; every other green-job-with-apply-success shape,
including every shape where one of those facts cannot be read, emits `proceed=true`,
`verdict=rotated`, as before.

**Assembly.** Three input chokepoints: (1) the source read `gh run view "$rid" "${att[@]}" --json jobs,startedAt`
(per-job `.startedAt`, the apply step's `.completedAt`, run-level `.startedAt`); (2) the evidence
list `gh run list --workflow web-platform-release.yml --limit 50 --json databaseId,status,event,createdAt`;
(3) the per-candidate `gh run view <id> --json jobs`. The property quantifies over both members of
`JOBS` and over every candidate release run. Decision chokepoints: `grade()`'s `1:success` arm
(the only consumer of CARRIED/DEPLOYED_AFTER) and the combination loop's `src` selection (the only
producer of `proceed=true`). Attempt authority: `SOURCE_RUN_ATTEMPT` as validated by the existing
`^[1-9][0-9]*$` test. Evidence-rule authority: `track.sh`'s `EVENT_ARM` and `DEPLOY_JOB`, pinned
equal by H3.

**Mutation matrix** (FROM/TO literals recorded in the GM block; each FROM unique in the gate):

| # | Mutation | Row that must go RED |
|---|---|---|
| 1 | Delete the demotion (the #8760 defect restored) | GC1 |
| 2 | `<` -> `<=` in the attempt-boundary comparison | GC8 (same-second job reads evidence: `_gexec` counts a release-list call) |
| 3 | Consult CARRIED without an attempt (manual arm) | GC4 |
| 4 | Consult CARRIED at attempt 1 (`>= 2` -> `>= 1`) | GC9 |
| 5 | Consult CARRIED on the red-job branch | GC7 |
| 6 | Drop the `> 0` check on the job epoch (Go zero time parses to a negative number) | GC6 |
| 7 | Drop DEPLOYED_AFTER (skip on CARRIED alone) | GC5 |
| 8 | Drop the `createdAt >= T_apply` filter | GC10 (36324585966, created 14:04:07Z, before the 14:26:47Z apply) |
| 9 | Accept any `deploy` conclusion as evidence | GC11 |
| 10 | Examine only the newest candidate | GC12 |
| 11 | `src` picks the first job with apply success ignoring its verdict | GC3 |
| 12 | A failed candidate `run view` counts as evidence | GC13b |
| 13 | Drop the exactly-one rule (first `deploy` match) | GC13c |

The gate stubbed to `exit 0` (own dispatch) is covered by adding every non-proceed GC row to the
existing GH list.

**Harness rows.**

- H1 (suite edit that must go RED, recorded once in the PR body): the pre-fix gate
  (`git show origin/main:.github/actions/dispatch-web-redeploy/source-run-gate.sh`) with ONLY its
  source argv patched to `--json jobs,startedAt` fails GC1 (prints `verdict=rotated`).
- H2: `_gexec`'s UNEXPECTED and zero-release-list checks each red a row when deliberately violated
  (a stub argv typo; `EVIDENCE` unset on GC1) — recorded once in the PR body.
- H3 (in suite): the anchored assignments `EVENT_ARM=…` and `DEPLOY_JOB=…` carry identical values in
  `track.sh` and `source-run-gate.sh`; a mutant of either literal reds H3.
- Must-PASS non-canonical inputs: GC2 (re-executed rotation in a re-run), GC8 (same-second
  boundary), GC4 (carried shape via the manual arm), GC12 (the qualifying release is not the newest),
  GC1c (the evidence run is `in_progress` with `deploy` success).

**Anchor.** The fixtures and the gate can change in one diff. Outside the commit: the live API (the
work phase re-runs both per-id capture commands and diffs against the committed files, result in
the PR body) and the `@deruelle` CODEOWNERS row on `/.github/actions/dispatch-web-redeploy/`
(`.github/CODEOWNERS` line 214; the new fixtures fall under the catch-all `*` row).

## Acceptance Criteria

- [ ] AC1. `source-run-gate.sh` reads the source run with one `gh run view "$rid" "${att[@]}" --json jobs,startedAt` call and implements CARRIED, DEPLOYED_AFTER and row 2c as specified; `bash -n` passes; `shellcheck` clean at the repo's configured level.
- [ ] AC2. GC1: `SOURCE_RUN_ATTEMPT=2`, replace success + apply success with captured carried timestamps, captured run start, release evidence {36338915404} -> exit 0, `proceed=false`, `pin_published=false`, a `::notice::` line containing `deploy_after_apply=36338915404` and `verdict=carried_over`, no `::warning::`. H1 shows the pre-fix gate yields `proceed=true` on the same fixture.
- [ ] AC3. Both fixture files exist, equal the output of their recorded capture commands (re-capture + `diff` in the PR body), and every GC timestamp or id comes from them except rows labelled synthetic (GC6 zero-time/absent, GC8 equality built from the captured run start, GC9 attempt-1 skew, GC13c duplicated `deploy`).
- [ ] AC4. G1–G26 pass with timestamped fixtures; G23 asserts the new exact argv for both shapes; `_gexec` enforces zero UNEXPECTED lines and zero release-list calls on every row without `EVIDENCE=1`.
- [ ] AC5. GC1–GC13 (with sub-rows) and H3 pass; every mutation 1–13 reds its named row; every non-proceed GC row is in the GH list and catches the stub.
- [ ] AC6. The `track.sh` rows (1a–D, H, M) pass unchanged.
- [ ] AC7. `FLOOR` equals the measured `pass + fail` of the final green run, commented with date and #8760.
- [ ] AC8. The workflow diff is comment-only: `git diff origin/main...HEAD -- .github/workflows/git-data-pin-redeploy.yml | grep -E '^[+-][^+-]' | grep -vE '^[+-]\s*(#|$)'` prints nothing.
- [ ] AC9. `plugins/soleur/test/terraform-target-parity.test.ts` passes (PT5 reads the runbook's `verdict=carried_over` line and finds it emitted by the gate's `echo` line).
- [ ] AC10. `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC11. New gate output contains only constants, allowlisted conclusions, `${rid}`, the validated attempt integer and a `^[0-9]+$`-validated release id; G19 still passes.
- [ ] AC12. Required CI checks pass by name on the exact PR head SHA before merge (the suite runs in CI via `scripts/test-all.sh`; the local battery is not the gate on this contended machine). The PR body says `Closes #8760`.

## Test Scenarios

`_gexec` harness, `SOURCE_RUN_ID=555`, `ATT` env, `EVIDENCE=1` on rows expected to read releases.
"Carried" = `detect-changes`' job `startedAt`/`completedAt` from the attempt-2 fixture, with the
apply step's `completedAt` = the job's `completedAt` (14:26:47Z); "fresh" = `deploy-script-tests (1/4)`'s;
"run start" = the fixture's `startedAt`; release records from the evidence fixture.

- **GC1 (#8760).** ATT=2, EVIDENCE=1; replace success + apply success, carried; releases {36338915404} -> `carried_over` as AC2.
  - **GC1b** both jobs carried with evidence -> `carried_over`, names `git_data_host_create` (first in `JOBS`).
  - **GC1c** (must-PASS) 36338915404 with `status: in_progress` -> `carried_over`.
- **GC2 (must-PASS).** ATT=2; replace fresh -> `rotated`, no release-list call.
- **GC3.** ATT=2, EVIDENCE=1; birth carried + evidence, replace fresh -> `proceed=true`, `source_job=git_data_host_replace`.
- **GC4 (must-PASS).** ATT unset; GC1's documents -> `rotated`, argv `run view 555 --json jobs,startedAt`, no release-list call.
- **GC5.** ATT=2, EVIDENCE=1; carried; releases `[]` -> `rotated`, `deploy_after_apply=none`.
- **GC6.** ATT=2; replace job `startedAt` removed; sub-rows `"0001-01-01T00:00:00Z"`, run-level `startedAt` removed, apply `completedAt` removed (release evidence present, never read) -> `rotated` each, no release-list call.
- **GC7.** ATT=2; replace failure + apply success + poll failure, carried, evidence -> `pin_published`, `pin_published=true`, warning.
- **GC8 (must-PASS).** ATT=2; replace `startedAt` == run start -> `rotated`, no release-list call.
- **GC9.** ATT=1; replace `startedAt` one second before run start (synthetic), evidence available -> `rotated`, no release-list call.
- **GC10.** ATT=2, EVIDENCE=1; carried; releases {36324585966} -> `rotated` (filtered by `createdAt`, never viewed).
- **GC11.** ATT=2, EVIDENCE=1; carried; releases {36339814543, deploy skipped} -> `rotated`.
- **GC12 (must-PASS).** ATT=2, EVIDENCE=1; releases [36339814543 newest, 36338915404] -> `carried_over` naming 36338915404.
- **GC13.** ATT=2, EVIDENCE=1; carried; (a) `relruns.rc=1`; (b) `view.36338915404.rc=1`; (c) 36338915404 with its `deploy` job duplicated (one `failure`, one `success`); (d) a `push`-event run with `deploy` success, never viewed -> `rotated`, exit 0, no `::error::` each.
- **H3.** `EVENT_ARM` / `DEPLOY_JOB` literal parity between `track.sh` and the gate.
- **Regression.** G1–G26 unchanged in expectation; G23 argv updated; `track.sh` rows unchanged.

## Success Metrics

- On the next partial re-run of a rotating apply run, the attempt-N follower prints
  `verdict=carried_over` and dispatches nothing when a release already deployed after the apply,
  or `verdict=rotated deploy_after_apply=none` and redeploys otherwise.

## Dependencies & Risks

- **#9085 (pre-existing, tracked).** Neither fixed nor widened; a comment on #9085 notes that its fix
  may let the deploy-evidence conjunct be simplified. #8211 may retire this redeploy path entirely.
- **gh output drift.** Missing timestamps or failed release reads fall back to `verdict=rotated`.
- **Evidence staleness.** 50 release runs span ~34 h; a follower firing later than that after the
  apply finds no evidence and redeploys — the safe direction.
- **PR touches `.github/`** -> UNTRUSTED-CI class: auto-merge only (the brief's admin-merge path does
  not apply).
- **Merges from `main`:** resolve any `PROMOTED_FILES` conflict by union; re-derive `FLOOR` after any
  merge that touches the suite. Do not edit the #8634 audit.

## Plan Review Revisions (v2)

| Finding (seat) | Class | Applied change |
|---|---|---|
| `status completed` filter misses F1's in-progress release (Kieran P1) | Mechanical | `track.sh`'s `queued`-skip; GC1c |
| `createdAt >= T_apply - 3600` + per-deploy `startedAt` check (DHH P1, simplicity P1, Kieran P2) | Mechanical | `createdAt >= T_apply` only; `conclusion` dropped from the list argv |
| AC3 re-capture of a moving list is not reproducible (Kieran P1, CTO P1) | Mechanical | per-id capture commands; attempt-1 and run-list fixtures cut |
| GC1 expected `deploy_after_apply=` the template did not print; `${job}` undefined for two carried jobs (Kieran P1) | Mechanical | literal token in the notice; first carried job in `JOBS` order; GC1b |
| `.carried=` token breaks G24 contiguity and buys no property (Kieran P1, simplicity P1) | Mechanical | token cut |
| `_q` routes jq errors to exit 1; run-level field unreachable via `_q` (Kieran P1) | Mechanical | CARRIED is one jq expression with its own checked read, failure = `no`; mutation 6 reworded |
| GC8 could not catch mutation 2 (Kieran P1) | Mechanical | `_gexec` zero-release-list check |
| GC13 / mutation 12 inexpressible with a global `view.rc` (Kieran P1) | Mechanical | per-id `view.<id>.rc` |
| T_apply index-mapped from `detect-changes`' steps (Kieran P1) | Mechanical | apply `completedAt` = captured job `completedAt`, named |
| Missing rows: run start absent, apply `completedAt` absent, duplicate `deploy`, push-arm run (Kieran P2) | Mechanical | GC6 sub-rows, GC13c, GC13d |
| PT5 consumer unnamed (Kieran P2) | Mechanical | AC9; runbook line wording |
| Stub's old `--attempt N --json jobs` arm (Kieran P2) | Mechanical | deleted |
| Stub UNEXPECTED blind on swallowed evidence reads (DHH P2) | Mechanical | checked in `_gexec` on every row |
| 26 per-row edits for "no release-list call" (CTO, DHH, simplicity, Kieran) | Mechanical | one `_gexec` check with `EVIDENCE=1` opt-in |
| Duplicated `track.sh` rules will drift (DHH, CTO, simplicity) | Mechanical | H3 parity row |
| Notice overclaims "already loaded"; use `REDEPLOY_CMD` (CTO P1) | Mechanical | reworded; `REDEPLOY_CMD` in notice and runbook |
| Step-summary line; list caching; GC14; GP (simplicity) | Mechanical | cut |
| Row table readability (CTO P2) | Mechanical | predicates block + one-line row 2c |
| Drop CARRIED 2-4 / annotate-only / won't-fix (DHH, simplicity, CTO) | Taste / User-Challenge | not applied; decision-challenges.md |
| Cut ADR clause, workflow comment, AC10 (DHH, simplicity) | Taste | not applied (PT5 reads ADR-237 and the workflow; one sentence each) |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a CI gate's decision input,
its tests, three prose sync points). No user-facing surface, copy, pricing, legal or
data-processing change.

## Open Code-Review Overlap

None. Open `code-review` issues (limit 200) were searched for `source-run-gate.sh`,
`test-dispatch-web-redeploy.sh`, `git-data-pin-redeploy.yml`, `ADR-237`,
`git-data-luks-cutover-5274.md` and `tests/scripts/fixtures`: zero matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- `"" < "2026-09-27T14:41:55Z"` is TRUE in jq; parse timestamps, never string-compare.
- `gh run view --attempt N --json createdAt` is the attempt's creation; without `--attempt` it is
  the run's. Never use the source run's `createdAt`.
- Change the gate's source argv and the stub in one commit, or every G row reds on call shape.
- A `workflow_run` release often concludes `success` with `deploy` `skipped` (36339814543); a push
  release never deploys (ADR-217). Evidence is the `deploy` JOB's conclusion.
- "No release-list call" checks use `grep -cxF` compared to 0, never `! grep -q <regex>`.
- The `verdict=carried_over` notice must stay one source line starting with `echo`, and the
  runbook sentence citing it must sit on a line naming `source-run-gate`, or PT5 misreads them.

## References & Research

- Run 36325677861 (Infra Validation), attempts 1-2; releases 36324585966, 36338915404,
  36339814543; git-data runs 35979304442, 34822248580 — all read 2026-09-27.
- Predecessor plan (archived): `knowledge-base/project/plans/archive/20260925-115424-2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md`.
- ADR-237; runbook `git-data-luks-cutover-5274.md`; issues #8760, #8710, #7226, #5914, #8211, #8776, #9085.
