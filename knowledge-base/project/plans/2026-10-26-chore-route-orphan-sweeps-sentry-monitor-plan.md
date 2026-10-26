---
title: "infra: route the scheduled-orphan-sweeps Sentry monitor (due 2026-10-27)"
type: chore
date: 2026-10-26
slug: route-orphan-sweeps-sentry-monitor
branch: feat-one-shot-10972-route-orphan-sweeps-monitor
issue: 10972
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# infra: route the scheduled-orphan-sweeps Sentry monitor (due 2026-10-27)

## Enhancement Summary

**Deepened on:** 2026-10-26
**Agents used:** CTO (two rulings rounds), learnings-researcher, functional-discovery, DHH, Kieran, code-simplicity, security-sentinel, observability-coverage-reviewer, spec-flow-analyzer, git-history-analyzer, framework-docs-researcher.

### Key improvements
1. The detector-id fallback (apply forensics artifact) was found not to exist for a successful apply; the `plan_pr` artifact is the only tokenless source, otherwise `Blocked`.
2. The probe was cut to a pinned 14-day window with an `ok`-count floor, exit 3 for every read failure, `NOT_BEFORE` hard-coded so the editable issue-body date is not the control, and no response body in any output.
3. The merge gate now authenticates each slot run, carries a state record and wake arming, a pre-ready sync check against `origin/main`, and a merge-SHA-based apply read-back that tolerates cancelled-successor runs.

### New considerations
- Draft-PR CI is light; the first full battery runs after the last gate on the due date (operator-class challenge recorded in decision-challenges.md).
- Three stale comment sites in `scheduled-terraform-drift.yml` (not two) go in the deferral issue.
- Sentry API specifics (`per_page` max, `missed` rows listed, `timeout` counting) are unverified from public docs; the design cannot produce a false 0 from them and the scratch-tracker dry run reads them on real data.

## Overview

The Sentry cron monitor `scheduled-orphan-sweeps` (Terraform label `scheduled_orphan_sweeps`, crontab `0 6,18 * * *`, margin 60 min) was created unrouted under the two-PR rule when #10952 shipped (PR #10967). Until it is bound to `sentry_alert.cron_monitor_failure`, a missed or failed check-in opens a Sentry issue that emails nobody. The aggregator job `orphan-sweeps-checkin` and the two sweeps' own failure emails are the only cover, and they share one mail key (`RESEND_API_KEY`), so they are not independent of each other. This PR is the second PR of the two-PR rule for this monitor: move the label from `local.cron_monitor_alert_unrouted` into `monitor_ids`, regenerate `alert-reference.json`, and tie off the follow-up the issue demands (the 2026-11-09 re-look).

Three things make this more than a three-line diff, and the plan is organised around them:

1. **The merge is time-gated.** The PR is built, tested and reviewed now (2026-10-26 about 09:45Z) but is not marked ready and not merged until the 2026-10-26T18:00Z drift slot, and the 2026-10-27T06:00Z slot, read as ok. A not-ok read ends the run with `Blocked: <reason>`.
2. **The new detector id cannot be derived offline** and reading a Sentry token value is out of bounds. The id arrives through the documented CI artifact path (`sentry-alert-reference-expected-<run-id>`), which needs no credential.
3. **The re-look on 2026-11-09 is automated, not remembered.** #10972 itself is enrolled in the follow-through sweeper with a small probe over a pinned 14-day window, so the closure is mechanical (CTO rulings below).

Ref #10972, Ref #9927, Ref #10112. No closing keyword on any of them (owner's rule for #9927 and #10112; #10972 closes through the sweeper after the re-look, or by the owner).

## Research Insights

### Premise Validation (Phase 0.6)

Checked against GitHub and `origin/main` on 2026-10-26:

- #10972 is OPEN, milestone Post-MVP / Later, labels `priority/p2-medium`, `type/chore`, `domain/engineering`. Its "blocked on #10854" second line is stale: #10854 closed 2026-10-24T19:02Z.
- PR #10967 (the monitor's creating PR) merged 2026-10-26T00:14Z (5e46901abe). The monitor resource exists on main (`cron-monitors.tf`, resource `scheduled_orphan_sweeps`) and sits in the unrouted map (`cron-monitor-alerts.tf`). The aggregator job `orphan-sweeps-checkin` exists in `scheduled-terraform-drift.yml` and posts to slug `scheduled-orphan-sweeps`.
- Run 40277293413 (the 2026-10-26T06:00Z slot, main at 81192540bf): both sweep jobs and `orphan-sweeps-checkin` concluded `success`; the check-in step succeeded and the email step was skipped. Re-read today from the job step list (metadata only).
- Draft PR #11154 exists for this branch, state OPEN, draft, base main. Draft PR #10905 (an unrelated Inngest/Supabase feature) also edits `cron-monitor-alerts.tf` and `cron-monitors.tf`: a possible textual conflict only. Not touched.
- No live scheduler: the recent `scheduled-terraform-drift.yml` runs listed are all event `workflow_dispatch` (latest 2026-10-26T06:00:04Z). The next slot's run therefore exists only if the dispatcher fires it; its absence is itself a gate failure (Phase 6).
- ADR corpus: ADR-031 (Sentry as IaC, #8630 amendment) owns the two-PR rule and the one-alert-binds-all-monitors decision; routing one more monitor follows it and decides nothing new. ADR-241's 2026-10-24 entry states "routing is #10972"; that dated pointer stays true history and the ADR is not edited (CTO R5).
- The apply for the #10967 merge (run 40248419931, event push, head 5e46901abe) concluded `success` with `Terraform apply` and `sentry_alert live fidelity` both `success`: the monitor exists in Sentry. That run has 0 artifacts: the forensics upload is `if: failure()`.
- Apply path: `apply-sentry-infra.yml` triggers on `apps/web-platform/infra/sentry/**`. Its `plan_pr` job holds the committed `alert-reference.json` equal to the plan projection (`scripts/sentry-alert-reference-gate.sh`) and uploads the expected document as artifact `sentry-alert-reference-expected-<run-id>` on a mismatch. Its apply job runs `sentry_alert live fidelity` as a late step, which compares live `detectorIds` of `cron-monitor-failure` against the projection of the plan just applied.

### Property List and Cut List (Phase 0.6b)

Properties the ask is made of:

- **P1** A missed, errored or timed-out check-in of `scheduled-orphan-sweeps` emails the org through Sentry.
- **P2** The committed `alert-reference.json` equals the projection of the plan this PR applies (the routing-parity test and the reference gate are green).
- **P3** Nothing merges until the later scheduled slots have read ok.
- **P4** The apply's convergence is evidenced without reading a credential value.
- **P5** The 2026-11-09 re-look (all slots since 2026-10-26, plus the monitor's issue state) is tracked and cannot rot.

Mechanisms the brief names, each with the property it buys and what already covers it:

| Mechanism | Buys | Already on main? |
|---|---|---|
| Move label into `monitor_ids`, drop it from the unrouted map | P1 | The map and `monitor_ids` are the repo's own mechanism (guarded by `sentry-cron-monitor-routing-parity.test.ts`, 24/24 green at baseline). Used as is. |
| Regenerate `alert-reference.json` | P2 | Reference gate + CI artifact (authority read: `scripts/sentry-alert-reference-gate.sh` and the README two-PR section). Used as is. |
| Hold ready/merge until the 18:00Z slot reads ok | P3 | Nothing automates it; it is a plan gate with read-only commands (Phase 6). |
| Read the live monitor by name after the apply | P4 | `apply-sentry-infra.yml` step `sentry_alert live fidelity` compares live `detectorIds` inside CI. CTO ruling (Fork 3): sufficient, no token read. |
| Dated tracked follow-up for 2026-11-09 | P5 | The follow-through sweeper (`scheduled-followthrough-sweeper.yml`, `SENTRY_ACTIONS_RO_TOKEN` already wired) and the sibling probe `community-monitor-checkin-soak-5728.sh`. A new probe, not a new substrate. |

Cut List (mechanisms considered and removed before research):

- A separate post-merge Sentry token read of the monitor -> P4 -> covered by the apply's own fidelity step (CTO Fork 3).
- Editing the three stale comment sites in `scheduled-terraform-drift.yml` (two say "unrouted until #10972", lines near 3000 and 3280; the "THE EMAIL STEP IS PERMANENT" block near 3309 says "while it is unrouted its issues email nobody") -> P1 does not need them; a comment-only edit would pull the heavy token-drift gate into a routing PR (CTO Fork 2). Tracked as a deferral instead.
- Reading Sentry issue state in the new probe -> an endpoint nobody has verified in this repo; with `failure_issue_threshold = 1` every `missed`, `timeout` or `error` check-in opens an issue and an `ok` after it resolves it (`recovery_threshold = 1`), so the check-in statuses determine whether an issue was opened. The residual (resolved vs open at the time of the look) is stated as not measured.
- Per-slot bucket coverage in the probe -> a missing check-in already shows up as a server-generated `missed` row; replaced by the simple window plus an `ok`-count floor (CTO R1).
- The ADR-241 dated amendment -> the ADR's pointer is history, the runbook is what triage reads (CTO R5).
- The apply-forensics artifact as a detector-id fallback -> it is uploaded only on a failed apply, so it does not exist for the successful #10967 apply.
- Any edit to PR #10905 or to monitors other than this one -> out of scope.

### Learnings applied (institutional)

- `2026-10-11-two-pr-rule-monitor-routing-recipe.md`: the routing recipe is four greppable moves (delete map entry, insert `sentry_cron_monitor.<label>.id` at the `LC_ALL=C` sorted position, add the live detector id to the string-sorted `detectorIds` tail, verify with the parity test, `terraform fmt -check`, `jq -S` canonicality and sortedness). The artifact download is the contingency there because the id could be read; here it cannot be read without a token, so the artifact path is the primary path and the `plan_pr` gate is the proof.
- `2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md`: a late dispatched run reads as missed-then-regressed; the monitor's 60-minute margin is already sized for it, so the gate reads the actual check-in, not the clock.
- `2026-10-05-a-green-dispatch-checkin-is-not-an-executed-probe-and-plan-pilot-numbers-expire.md`: say what the check-in covers. This one is `ok` = both sweep jobs concluded success (job success, not delivery; ADR-241 residual), and the PR body says so.
- `2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md`: a soak must not read an armed state the wiring never set. The probe reads check-in rows, not a monitor-status field.
- `2026-10-23-timeout-record-satisfies-verdicts-in-both-directions.md`: a `timeout` row can satisfy negative arms vacuously; the probe's fixtures include a timeout row in each bucket position.
- Sibling `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`: the org is `jikigai-eu` on host `de.sentry.io`; the probe pins both literals (as the sibling does) rather than reading them from the environment.

### Sentry API facts (deepen-plan research, 2026-10-26, Sentry public docs)

Confirmed: the path `GET /api/0/organizations/{org}/monitors/{monitor}/checkins/` exists (https://docs.sentry.io/api/crons/retrieve-checkins-for-a-monitor); failure thresholds count missed and error check-ins and consecutive ok check-ins resolve the open issue (https://sentry.io/changelog/2023-12-20-margins-and-thresholds-for-cron-monitors). Unverified from public docs: the `per_page` maximum and Link-header pagination, whether server-generated `missed` rows are listed, whether `timeout` counts toward the failure threshold, and `sentry_alert.monitor_ids` accepting cron-monitor ids explicitly (the provider docs type it as a set of strings; this repo already binds 63 cron monitors that way and the apply's fidelity step passes). The probe is designed so none of the unverified items can produce a false 0: it does not rely on `missed` rows existing (the `ok`-count floor catches a silent monitor independently), it treats a full page that does not reach the window start as exit 3, and the sibling probe already reads the `dateAdded` and `status` fields live (verified in #5728 Phase 0). The scratch-tracker dry-run is where the rest is read on real data.

### Functional overlap

Registry search (3 of 3 reachable) found only partial overlaps (`sentry-cli`, `sentry`, `use-sentry`, `error-tracking`); none covers Terraform alert routing or a sweeper probe, and none is installed. Built in-repo.

## Technical rulings

First round (CTO agent, 2026-10-26, before drafting):

- **Fork 1 - follow-up mechanism:** Ruled by CTO agent, 2026-10-26: enroll #10972 itself in the follow-through sweeper (option A). Plan rule 2.9.1 and ship Phase 5.5 require a time-gated close criterion to be enrolled; the other options leave closure to memory. New probe plus sibling suite, directive `earliest=2026-11-09T00:00:00Z`, `secrets=SENTRY_ACTIONS_RO_TOKEN`, label `follow-through`, no new secret.
- **Fork 2 - stale prose:** Ruled by CTO agent, 2026-10-26: edit the `.tf` comment above the monitor, the unrouted-map entry (removed with it) and the runbook; leave the `scheduled-terraform-drift.yml` comments (the CTO counted two stale sites; the attribution check found a third, the block near line 3309 whose sentence "while it is unrouted its issues email nobody" also becomes false, so all three are named in the deferral issue). Amended by R5 below (ADR-241 edit dropped).
- **Fork 3 - apply read-back:** Ruled by CTO agent, 2026-10-26: the post-apply `sentry_alert live fidelity` step plus the committed `alert-reference.json` is sufficient evidence of convergence; no separate token read. Prove it from `gh run view` on the apply run for the merge SHA: fidelity step `success` (not `skipped`) and Terraform apply step `success`. (Checked at plan time: `scripts/sentry-alert-live-fidelity.sh` compares `detectorIds` per rule by name and reports `MONITOR UNBIND` on a difference; the same two step names read `success` on the last apply, run 40248419931.)

Second round (after the four-agent plan review; Ruled by CTO agent, 2026-10-26):

- **R1 - probe verdict shape:** the sibling's simple window, not per-slot buckets. Window is [2026-10-26T06:00Z, 2026-11-09T06:00Z) with START and END pinned as literals and the probe refusing to judge before the window closes (security review: not clipped to now), so the verdict is immutable and a later row cannot re-fail a closed tracker. `missed`, `timeout` and `error` rows each exit 1 (reverses the first-round "error does not fail": the probe never reads Sentry issue state, and with `failure_issue_threshold = 1` an `error` row is the case that opens an issue, so a closing probe fails closed). Zero rows, truncation, or fewer `ok` rows than closed 12-hour slots in the window exit 3.
- **R2 - suite:** 12 rows, now 14 after the security review added rows 13 and 14 (listed in the Guard Contract); crontab-parity row and harness row (a) dropped (moot with the end pinned).
- **R3 - exit codes:** exit 3 (CANNOT ESTABLISH) for every read or integrity failure (zero rows, truncation, non-array, unpinned destination, unusable token, HTTP or auth failure, failed floor); exit 2 (NOT YET) only for nothing-to-judge (no closed slot yet); 78 for xtrace. Authority: `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` (lines 11, 55, 71) and `scripts/sweep-followthroughs.sh` (renders 2 and 3 separately, both non-closing). The sibling's blanket exit 2 is legacy.
- **R4 - detector id source:** the CTO kept the `plan_pr` artifact primary and the apply forensics artifact as contingency. **Plan-author correction of fact, recorded in decision-challenges.md:** the forensics upload step is `if: failure()` and run 40248419931 (the apply for the #10967 merge, `success`) lists 0 artifacts, so the contingency does not exist. The only credential-free source is the `plan_pr` artifact; if it is absent the step ends `Blocked`.
- **R5 - prose scope:** drop the ADR-241 amendment (its "routing is #10972" is a dated pointer and stays true history). Keep the `.tf` comment edits, the runbook edit and the deferral issue for the two stale workflow comments (`wg-when-deferring-a-capability-create-a`; #10972 cannot carry it because the sweeper closes #10972).
- **R6 - slot B and closure:** the 2026-10-27T06:00Z slot is a hard gate: missing, late or not `ok` is `Blocked: <reason>`, never downgraded to best effort (relaxing a gate or schedule is the owner's call). The sweeper closes #10972 on exit 0 without a Sentry issue-state read; this is accepted and stated under "Not measured" in the PR body; the probe is not notify-only.

All rulings are persisted as rows in `knowledge-base/project/specs/feat-one-shot-10972-route-orphan-sweeps-monitor/decision-challenges.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly on the product. The failure is that a dead or failed orphan sweep still emails nobody through Sentry, so a stranded rehearsal server, volume or scratch Doppler config (which holds a live volume key and an ingest token) can sit unreported for longer than one slot; or that the apply fails and the Sentry-managed alerts show drift issues until it is repaired.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The change adds one monitor id to an existing email alert and a read-only probe; the PR and the probe carry no token value, no user identifier and no personal data (the probe reads check-in status rows only and prints counts and timestamps).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** routing a monitor to the org email is an operations-visibility change, so there is no one-user exposure path; the cost of getting it wrong accrues across many missed slots, not in one incident, hence `aggregate pattern` rather than `single-user incident`.

## Implementation Phases

### Phase 0 - Read-only measurements (done once now, repeated at the gate)

All commands are metadata only (`gh run list`, `gh run view --json jobs`, `gh run view --job <id> --log` filtered to one anchored line). Nothing reads a Doppler value or a Sentry token.

Already measured 2026-10-26 about 09:40Z (and recorded on #10972 by the owner): run 40277293413 clean, identity HTTP 200 for both sweeps, check-in `ok`, `sentry-heartbeat: http_code=202`. Not measured: Sentry's own view of the monitor, and any slot after 06:00Z today.

### Phase 1 - Route the monitor

Edit `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`:

1. Delete the `scheduled_orphan_sweeps = "..."` entry and its comment block from `local.cron_monitor_alert_unrouted` (three entries remain: `scheduled_bot_pr_reaper`, `workspaces_luks_verify_web2`, `scheduled_betterstack_incident_mirror`).
2. Insert `sentry_cron_monitor.scheduled_orphan_sweeps.id,` into `monitor_ids` at its `LC_ALL=C` sorted position: after `scheduled_oauth_probe` and before `scheduled_plausible_goals` (`or` sorts before `pl`). The list goes from 63 to 64 elements.
3. Edit the comment above `resource "sentry_cron_monitor" "scheduled_orphan_sweeps"` in `cron-monitors.tf` ("Created UNROUTED under the two-PR rule ...; routing is #10972") to say it is routed by #10972 (2026-10-26).

Verify locally (read-only):

- `cd apps/web-platform && npx vitest run test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` stays 24/24 (the guard is XOR: routed XOR unrouted, no duplicate, sorted derivation matches `DERIVATION_CMD`).
- `terraform fmt -check -recursive apps/web-platform/infra/sentry` (terraform 1.17.0 is on PATH).
- `bash plugins/soleur/test/c4-count-parity.test.sh` stays green (baseline measured green 2026-10-26; counts do not move because monitor and workflow counts are unchanged).

### Phase 2 - Regenerate `alert-reference.json` through the CI artifact

The id is the monitor's live detector id, which is not derivable offline and not readable without a token.

1. Commit Phase 1 as its own commit and push. The `plan_pr` job of `apply-sentry-infra.yml` runs on the draft PR; its reference gate is expected to go red once (committed reference lacks the new id) and uploads `sentry-alert-reference-expected-<run-id>`. The step summary states the credential-free remedy: `gh run download <run-id> -n sentry-alert-reference-expected-<run-id>`.
2. Download into the scratch directory (never into the repo tree), then compare structurally: the expected document must differ from the committed one in exactly one place, one new element in `cron-monitor-failure.detectorIds`. Print only booleans and counts (`jq` length, sortedness, the count of keys that differ), never the document.
2a. Download into a fresh empty directory in the scratchpad and check `jq -e 'type=="object"'` on it before any copy; word the PR-body claim about it as "the projection's allowlist plus a shape denylist" (the workflow's secret sweep is a prefix denylist and covers only that one file), not "swept clean".
2b. Before trusting the artifact: `gh run view <run-id> --json headSha` must equal the Phase 1 commit (a superseded or cancelled run gives a stale document). If the gate went red for another reason and no artifact exists, read the failing step: a 410 brownout in the plan step clears on `gh run rerun <run-id> --failed` (rerun once); a binding-gate or destroy-gate red is a real defect to fix. Record the run id in the state record (Phase 6 step 0).
3. Copy it over `apps/web-platform/infra/sentry/alert-reference.json`, commit separately, push, and wait for the reference gate to turn green.
4. Invariants (mechanical, run locally), stated relative to `origin/main` so a sibling merge (PR #10905 also edits these files) cannot falsify them: `jq -S . alert-reference.json | diff -q - alert-reference.json` (canonical), `detectorIds | . == sort`, count = main's count + 1 (63 to 64 at plan time), and the id set equals main's plus exactly one id.

If the `plan_pr` artifact is absent (the gate went red for another reason, or the artifact expired): stop with `Blocked: detector id needs a Sentry token read` and name this step. There is no tokenless fallback: the apply forensics artifact is uploaded only on a failed apply (`if: failure()`), and the apply for the #10967 merge (run 40248419931) succeeded and has none.

### Phase 3 - Follow-through enrollment for the 2026-11-09 re-look

Files: `scripts/followthroughs/orphan-sweeps-relook-10972.sh` (probe) and `scripts/followthroughs/orphan-sweeps-relook-10972.test.sh` (fixture suite). The probe is a small delta on `community-monitor-checkin-soak-5728.sh` (refuse under xtrace, token-shape guard, pinned org `jikigai-eu` and host `de.sentry.io`, bearer on curl's stdin config channel, response shape check before trusting a zero), with these changes (CTO R1 to R3):

- Slug `scheduled-orphan-sweeps`; `per_page=100`; `--max-time 30 --proto '=https'`; window start the literal 2026-10-26T06:00:00Z and window end the literal 2026-11-09T06:00:00Z. The probe also hard-codes `NOT_BEFORE=2026-11-09T06:00:00Z` (the window end) and exits 2 before it, so the verdict always covers the FULL window with the 28-slot floor: the `earliest=` in the editable issue body is a convenience, not the control, and editing it cannot make a partial window close the tracker (security review: the sweeper does not track edits to the directive).
- Exit 1 on any `missed`, `timeout` or `error` row in the window. `in_progress` rows are ignored (not a verdict). Exit 0 only when no such row exists AND the count of `ok` rows is at least the number of slots in the full window (28).
- Output never echoes the response body (a public Actions log and a public issue comment carry it): on a non-200 or non-array response print only the HTTP status and a fixed reason string.
- Exit 3 for zero rows, a non-array response, a full page whose oldest row is newer than the window start (truncation), an unpinned destination, an unusable token, an HTTP or auth failure, or a failed floor. Exit 2 only before `NOT_BEFORE`. Exit 78 under xtrace.
- Output: counts per status and the first few offending timestamps; a closing line that the Sentry issue state was not read. No ids, no values.
- Header states the credential posture (read-only `SENTRY_ACTIONS_RO_TOKEN`, no GitHub token), the consequence of exit 1 (a bad slot makes the verdict permanent; closing then needs the owner), and a `RETIREMENT:` line (convention requirement) listing every site to delete with the probe: the suite, the `run_suite` line in `scripts/test-all.sh`, the four generated manifest files (and `scripts/ci-pr-affected-audit.baseline.tsv` if a row was added), and the `follow-through` label on #10972.

Pre-merge lints that gate a new probe and suite (run them locally, all read-only): `scripts/lint-followthrough-varq-ban.sh` (no `${VAR:?}` gating), `scripts/lint-shell-trace-credential-refusal.py` (xtrace refusal in the prologue), `scripts/lint-orphan-test-suites.sh`, and `shellcheck`.

Registration (follow the nearest sibling `ci-draft-light-soak-9728`): a `run_suite "scripts/followthroughs/orphan-sweeps-relook-10972" bash scripts/followthroughs/orphan-sweeps-relook-10972.test.sh` line in `scripts/test-all.sh`, then the manifest rows through the generator, never by hand: `python3 scripts/regenerate-shard-manifest.py --incremental --write`. This is mechanical regeneration, not design. Check `scripts/ci-pr-affected-audit.baseline.tsv` against the affected gate and regenerate with its own tool only if the gate demands a row.

Dry-run on real data (the one check a fixture cannot make; run it only AFTER the lints, the suite and the review fixes pass, because it executes the branch's probe with the live read-only token on a public Actions log, so first confirm the probe prints only counts and timestamps; close the scratch tracker and remove any untracked copy immediately): the sweeper skips a tracker whose `earliest=` is in the future, so a dry-run on the real #10972 would never run the probe. Record the scratch issue number (and any untracked copy path in the main checkout) in the state record BEFORE creating it, and clean both up on resume if the session died; the real scheduled sweeper from main would otherwise keep seeing a stray tracker. Use a throwaway scratch issue labelled `follow-through` whose directive has the same `script=` and `secrets=` but `earliest=<now>`, then `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-10972-route-orphan-sweeps-monitor -f dry_run=true`, read the scratch tracker's `exit=` line and output tail (dry-run posts nothing), and close the scratch issue. It answers whether `per_page=100` is honoured on the EU host and how many rows 14 days return. The directive gate resolves `script=` under the main checkout; use the convention's untracked copy there if it reports "does not exist", and remove the copy afterward.

Enrollment on #10972: label `follow-through` and the directive pasted UNFENCED at column 0:

```text
<!-- soleur:followthrough
  script=scripts/followthroughs/orphan-sweeps-relook-10972.sh
  earliest=2026-11-09T00:00:00Z
  secrets=SENTRY_ACTIONS_RO_TOKEN
-->
```

Timing (decided): the sweeper runs from main and checks that the script exists before it checks `earliest=`, so enrolling before the merge produces a "missing in repo HEAD" failure line on each sweep until the merge, while enrolling only after the merge depends on a session surviving the queue (a lost enrollment is silent and means #10972 is never closed mechanically). Enroll at Phase 6 step 6, right before arming the merge, after both slots read ok: the noise window is then only the merge-queue minutes, and the enrollment no longer depends on a post-merge session. Ship Phase 5.5's fail-closed soak gate is satisfied at the same point.

Deferral tracking (filed at work time, milestone Post-MVP / Later): one issue "chore: refresh the two stale 'unrouted until #10972' comments in scheduled-terraform-drift.yml at its next edit", naming the three sites by content anchor ("its Sentry monitor is unrouted until" twice, and "while it is unrouted its issues email nobody" in the aggregator's rule block), the trigger (next real edit to that workflow) and the reason (CTO Fork 2). #10972 cannot carry it because the sweeper closes #10972.

### Phase 4 - Prose that the routing makes false

- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: the orphan-sweeps paragraph says the monitor "was created unrouted (its Sentry issues email nobody until the routing follow-up #10972 lands ...)" and a triage row says "(once routed)". Update both to the routed state with the 2026-10-26 date; keep the residual that the emails share one mail key and that the routed monitor is the only path not using it.
- ADR-241 is NOT edited (CTO R5): its "routing is #10972" is a dated pointer and stays true history.
- The unrouted-map entry's own comment goes with the entry.

### Phase 5 - Local affected gate, review, PR body

- Run the affected gate before marking ready, not after (`plugins/soleur/scripts/affected-tests.sh`, contract in `plugins/soleur/skills/ship/references/affected-gate-contract.md`). Rc 6 (AFFECTED_GATE_BUDGET_DEFERRED) is not a pass: rerun with budget until rc 0, or report the blocked step.
- Run `soleur:review` on the branch (it is a 3-file infra diff plus a probe and its tests; the probe is where the review attention goes).
- PR body: `Ref #10972`, `Ref #9927`, `Ref #10112` only. It states what was measured and what was not, with dates (see Acceptance Criteria 12). Note the infra validation check is red on main for an unrelated reason (cloud-init pin vs tag mismatch), not required and not from this PR.
- Do not sync a BEHIND merge-queue PR by hand; read the verdict with `plugins/soleur/scripts/ci-head-verdict.sh verdict 11154`.

### Phase 6 - Time-gated merge gate (hold ready and merge until this passes)

Earliest 2026-10-26T18:00Z. Slot runs are dispatched from main; each run finishes about 45 seconds after it starts.

Step 0, before this run ends (it ends well before 18:00Z, and a comment wakes nothing):

- Post ONE state record on draft PR #11154: branch, the Phase 1 and Phase 2 commit SHAs, the `plan_pr` run ids and their `headSha`, the scratch issue number and any untracked-copy path (Phase 3), the evidence read so far, and the line "merge gate waiting on slot A 2026-10-26T18:00Z and slot B 2026-10-27T06:00Z; not ready".
- Arm a one-time wake for about 18:05Z and 06:05Z through the harness's scheduling facility when one is available; otherwise the end-of-work resume prompt (naming both times, the PR, the plan path and the state-record comment) is the only wake, and the pipeline's next phase owns it.
- A `Blocked` result is posted on #11154 and #10972; if the 2026-10-27 due date will slip, file ONE `action-required` issue.
- Post-merge checklist (Phase 7, the #10972 comment) goes into the PR body so the merge itself carries what remains.

Before marking ready (after slot B reads ok), run a pre-ready sync check: `git fetch origin main`, then diff `origin/main` against the last pushed base for `apps/web-platform/infra/sentry/**` and `tests/scripts/lib/sentry-alert-projection.jq`. Nothing changed: proceed. Changed (including PR #10905 landing first, which edits the same two `.tf` files): merge `origin/main` into the branch, re-derive the sorted position and re-run the Phase 1 and Phase 2 checks, push, wait for `plan_pr` to go green, then proceed. This pre-ready sync is allowed; the "do not sync by hand" rule applies only to a PR that is already in the merge queue. The slot reads do not need to be redone after such a sync (they concern runtime, not code). Reason: `plan_pr` runs on `pull_request` default types, so `ready_for_review` does not re-run it and `merge_group` skips the heavy plan, which makes the last green `plan_pr` as old as the last push.

CI note recorded as an operator-class challenge in decision-challenges.md: pushes to a draft PR run only the light CI checks; the first full battery runs on `ready_for_review`, after the last gate, on the due date. Mitigations inside the brief: the local affected gate to rc 0 before ready; a stated budget (a red full battery after ready is fixed and re-queued, and a slip past 2026-10-27 is reported, not hidden).

0b. Authenticate the run before trusting it (a hand dispatch of the workflow on any ref would otherwise produce a green aggregator): `gh api repos/jikig-ai/soleur/actions/runs/<id> --jq '[.head_branch,.path,.triggering_actor.login,.run_started_at,.head_sha]'` must show `main`, `.github/workflows/scheduled-terraform-drift.yml`, the same dispatcher login the 06:00Z run 40277293413 shows (read it the same way once and record it), a start within about 15 minutes of the slot, and a `head_sha` that `git merge-base --is-ancestor <sha> origin/main` accepts. A run that fails this is excluded and named, never counted; at least one authentic run must exist.
1. Slot A, 2026-10-26T18:00Z:
   `gh run list --workflow scheduled-terraform-drift.yml --created ">=2026-10-26T17:30:00Z" --limit 10 --json databaseId,createdAt,event,status,conclusion,headSha`
   Every run created in that window must pass the reads below (a retry or second dispatch is read too; a failed first run followed by a green retry is NOT an ok slot: report it). No run by 19:30Z is a gate failure: `Blocked: no 18:00Z drift run was dispatched (the dispatcher did not fire)`.
2. For that run, gate on the aggregator itself rather than a hard-coded job count (the sole-copy job is planned to join `needs` later, #10430): `gh run view <id> --json jobs --jq '.jobs[] | select(.name=="orphan-sweeps-checkin") | .steps[] | [.name,.conclusion] | @tsv'` must show `Sentry check-in (orphan sweeps)` = `success` and the email step (name starting `Email notification (orphan sweeps`) = `skipped`; and every `*-orphan-sweep` job must read `success` (`select(.name|endswith("-orphan-sweep"))`).
3. Ingest answer: the job's step conclusions from step 2 are the primary evidence. The only emitted program line is `sentry-heartbeat: http_code=<n>` (GitHub's echo of the step's `env:` block also prints `STATUS: <value>` and `MONITOR_SLUG: <slug>`, which show what the step was GIVEN, not what Sentry received):
   `gh run view <id> --job <checkin-job-id> --log | grep -aE '(sentry-heartbeat: http_code=[0-9]+|STATUS: (ok|error)|MONITOR_SLUG: [a-z-]+)$' | sed -E 's/^.*(sentry-heartbeat: http_code=|STATUS: |MONITOR_SLUG: )/\1/' | head -n 6` must show `MONITOR_SLUG: scheduled-orphan-sweeps`, `STATUS: ok` and `sentry-heartbeat: http_code=202` (the source echo `-w '\nsentry-heartbeat: http_code=%{http_code}\n'` does not end in digits, so it cannot match). Rehearse read-only on run 40277293413 before relying on it.
4. Slot B, 2026-10-27T06:00Z: same reads. It is a hard gate (CTO R6). It finishes about 06:01Z, leaving the rest of 2026-10-27 UTC for the merge queue; a missing, late or non-ok slot B is `Blocked: <reason>` and the due date is then the owner's call.
5. Any `error` status, any non-2xx, any sweep job not `success`, or a missing run: stop, do not mark the PR ready, report `Blocked: <slot, run id, which check failed>`.
6. Post each slot's run id and its read lines as a comment on #11154 at the time of reading (a resumed session must not re-derive them). Only then: run the pre-ready sync check, enroll #10972 (Phase 3), mark ready, then `gh pr merge 11154 --squash --auto` per the repo's merge flow (merge queue; no hand sync of a queued PR).

What this gate does not prove: Sentry's own view of the monitor (a 202 shows acceptance only) and the Sentry issue state. Both stay named as not measured in the PR body.

### Phase 7 - Post-merge read-back (Done-when item 2)

Take the merge SHA from `gh pr view 11154 --json mergeCommit`. The apply workflow's concurrency group keeps one pending run, so a later Sentry-tree merge can cancel the run for your SHA while its successor applies your change too. Therefore: select the earliest push-event apply run on main whose head contains the merge SHA as an ancestor (`git merge-base --is-ancestor`); a `cancelled` run means read its successor. If the run is queued or in progress, wait with a bounded `Monitor` until-loop (not a sleep). Read the step list, matching the fidelity step by prefix (`startswith("sentry_alert live fidelity")`) so an AC-tag rename cannot flip a pass into `Blocked`. Required: `Terraform apply (cron + uptime monitors)` = `success` and the fidelity step = `success` (not `skipped`); judge by these step conclusions, not by the run conclusion (the later BYOK and AC17 steps can fail a run whose apply and fidelity converged, and that is reported separately). If no apply run exists for the SHA, check the squashed commit message for a `[skip-sentry-apply]` line and report that as the reason. If the apply or fidelity step is `skipped` or failed: `Blocked: apply did not converge (run <id>, step <name>)`; do not hand-apply. This proves convergence of live state against the plan just applied, not that the committed JSON equals live; the daily `scheduled-sentry-alert-drift.yml` owns the latter. The next scheduled drift run after the apply then posts to a monitor that exists and is routed.

Then post one comment on #10972 with the measured facts and dates, and leave the issue open for the sweeper (enrolled for 2026-11-09).

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` (unrouted entry removed, `monitor_ids` +1)
- `apps/web-platform/infra/sentry/alert-reference.json` (one id appended to `cron-monitor-failure.detectorIds`, from the CI artifact)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (comment above `scheduled_orphan_sweeps` only)
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (two sentences)
- `scripts/test-all.sh` (one `run_suite` line)
- `scripts/suite-shard-legs.tsv`, `scripts/suite-shard-legs.tsv.n`, `scripts/suite-durations.tsv`, `scripts/suite-durations.tsv.n` (generated by `regenerate-shard-manifest.py --incremental --write`, never hand-edited)

Deliberately NOT edited: `.github/workflows/scheduled-terraform-drift.yml` (CTO Fork 2), ADR-241 (CTO R5), `scripts/followthroughs/community-monitor-checkin-soak-5728.sh` (the model), anything in PR #10905.

## Files to Create

- `scripts/followthroughs/orphan-sweeps-relook-10972.sh`
- `scripts/followthroughs/orphan-sweeps-relook-10972.test.sh`
- `knowledge-base/project/specs/feat-one-shot-10972-route-orphan-sweeps-monitor/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10972-route-orphan-sweeps-monitor/decision-challenges.md`

Path verification (`hr-when-a-plan-specifies-relative-paths-e-g`): every Edit path above was confirmed to exist with `ls`/`grep` in the worktree on 2026-10-26; the two probe paths follow the `scripts/followthroughs/<short-name>-<issue>.sh` convention and the directive's required prefix.

## Open Code-Review Overlap

Query of open `code-review` issues against every planned path:

- `scripts/followthroughs` (directory prefix): #10464, #10463, #10462 (the zot fill-rate probe), #8800 (census sandbox fixture), #8435 (a GSC indexing probe). **Acknowledge:** different probes, none touches the files this PR creates; they stay open.
- `scripts/test-all.sh`: #7942 (two mutation batteries run in no gate). **Acknowledge:** a different concern; this PR adds one registered suite line and does not touch those.
- The `.tf`, `alert-reference.json`, runbook and ADR paths: none.

## Guard Contract

### Guard 1 - orphan-sweeps re-look probe (`orphan-sweeps-relook-10972.sh`)

**Property.** The probe exits 0 only when, in the full pinned window [2026-10-26T06:00:00Z, 2026-11-09T06:00:00Z), evaluated only once the window has closed, no check-in has status `missed`, `timeout` or `error` and at least 28 `ok` check-ins exist (one per 12-hour slot); it never exits 0 on an empty, truncated, malformed, unpinned or unauthenticated reading.

**Assembly.** One chokepoint: the single `jq` evaluation over the one checkins response that yields per-status counts and the oldest row's timestamp; every path that can end in 0 or 1 flows through the final verdict arm. The inputs proven before that arm: xtrace refusal, token shape, destination pin (org and host literals), HTTP 200, response type (array), row timestamps parse, window coverage (oldest returned row at or before the window start, or the page is not full), and the slot floor computed from the window length. Window start and end are literals in the probe; the floor is arithmetic over them, so there is no second schedule to keep in sync. Members drift (new rows arrive daily) but the pinned end makes the evaluated set immutable once the window closes.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Clean fixture: 28 `ok` rows across the window | exit 0 |
| 2 | Empty array (zero rows) | exit 3, never 0 (vacuity) |
| 3 | One `missed` row among 28 `ok` rows | exit 1 |
| 4 | One `timeout` row, and a second bad row (`error`) after a compliant first bad one, with `ok` rows after both | exit 1 and both reported (a check that stops at the first member is the defect) |
| 5 | One `error` row among otherwise `ok` rows | exit 1 |
| 6 | A bad row dated after the pinned end | ignored, exit 0 |
| 7 | Full page of rows whose oldest row is newer than the window start (truncation) | exit 3 |
| 8 | Response is an object, not an array | exit 3 |
| 9 | `ok` count below the 28-slot floor (27 `ok` rows) | exit 3 |
| 10 | `SENTRY_ORG` or `SENTRY_API_HOST` differs from the pinned literal | exit 3, no request sent |
| 11 | Token unset, or containing a newline | exit 3, no request sent |
| 12 | Script run under `bash -x` with a token set | exit 78, no token in output |
| 13 | Run before 2026-11-09T06:00Z (the issue-body `earliest=` edited earlier) | exit 2, no request sent |
| 14 | A 401 or non-array fixture whose body carries a token-shaped string | exit 3 and nothing from the body appears in stdout or stderr |

**Harness rows.** The suite asserts a nonzero executed-row count (a ledger of `0 passed, 0 failed` is a failure), so a suite that dispatches nothing cannot score green. Must-PASS inputs that are not the canonical clean fixture: rows 6 and an `in_progress` row inside the window (ignored, still 0), and an `ok` row arriving at the end of its slot. Boundary rows: exactly 100 rows with the oldest before the window start passes the truncation guard; 100 rows with the oldest after it exits 3.

**Anchor.** The window literals and `NOT_BEFORE` live in the probe, so weakening the verdict or the date needs a reviewed diff; the issue-body `earliest=` is outside the commit but is NOT relied on (the sweeper does not track edits to a directive, so an early `earliest=` would otherwise let a partial window close the tracker; row 13 pins this). The probe proves "no failed check-in and the full count of ok check-ins in the window", not the integrity of Sentry's data: a spoofed `ok` from the public write-only ingest key (already true of every monitor, stated in the workflow comment) is out of scope and named as not defended.

Order and lifetime properties: none. The probe reads once and keeps no state, so no reorder row applies; stated so the omission is deliberate.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor scheduled-orphan-sweeps (check-in per 06:00 and 18:00 UTC slot from the orphan-sweeps-checkin job)
  cadence: twice daily; missed-check-in margin 60 minutes
  verified_by_this_plan: the binding (apply fidelity step) and check-in acceptance (HTTP 202); NOT verified here: email delivery
  alert_target: sentry_alert.cron_monitor_failure emails issue owners, falling through to all active org members, at most once per 1441 minutes per monitor environment
  configured_in: apps/web-platform/infra/sentry/cron-monitor-alerts.tf (monitor_ids) and apps/web-platform/infra/sentry/cron-monitors.tf (resource scheduled_orphan_sweeps)

error_reporting:
  destination: Sentry web-platform project via the cron check-in ingest key (public write-only key held as repo secrets in the aggregator job)
  fail_loud: a non-success sweep posts status error, the aggregator also sends its own per-slot email, and the Sentry issue now emails the org

failure_modes:
  - mode: a sweep job fails, is cancelled or times out
    detection: Sentry monitor scheduled-orphan-sweeps receives an error check-in from orphan-sweeps-checkin; workflow run log of job orphan-sweeps-checkin and of the failed sweep job (named error slug)
    alert_route: Sentry issue to org email (this PR) plus the aggregator's own email (shared mail key)
  - mode: no run is dispatched for a slot
    detection: Sentry monitor missed check-in (server-generated after the 60 minute margin)
    alert_route: Sentry issue to org email (this PR); the aggregator email cannot fire because no job ran
  - mode: the check-in POST is rejected (non-2xx, for example a rotated ingest key)
    detection: workflow run log of job orphan-sweeps-checkin, line sentry-heartbeat http_code (the step is continue-on-error, so the run stays green); then Sentry monitor missed check-in about 60 minutes later
    alert_route: Sentry issue to org email once the miss registers; the run log shows the cause immediately
  - mode: the apply leaves the alert unbound to the new detector
    detection: workflow run log of apply-sentry-infra.yml, step sentry_alert live fidelity (::error:: MONITOR UNBIND); daily scheduled-sentry-alert-drift.yml compares live against the committed alert-reference.json
    alert_route: the apply-failure tracking issue (ci/apply-sentry-infra) and the daily drift issue (ci/sentry-alert-drift)
  - mode: the monitor is deleted or recreated out of band (a new detector id)
    detection: daily scheduled-sentry-alert-drift.yml (ci/sentry-alert-drift issue) and the next apply's plan
    alert_route: the drift issue
  - mode: the alert is bound but the email is suppressed or undelivered (the 1441-minute throttle, an empty recipient fall-through, a muted member)
    detection: not measured in this PR. A Sentry monitor issue that is open with no email received is the symptom; the Sentry issue state is read on 2026-11-09 only as far as check-in statuses (probe), not delivery. Named residual; the aggregator's own per-slot email is the independent-of-Sentry path but shares the mail key
    alert_route: none beyond the residual note in the PR body and the runbook triage row
  - mode: the 2026-11-09 re-look finds a missed, timeout or error check-in
    detection: sweeper run log and comment on #10972, probe exit 1 (exit 3 when it cannot read, for example an expired SENTRY_ACTIONS_RO_TOKEN, which comments on #10972 each sweep and leaves it open)
    alert_route: sweeper comment on #10972; on a persistent exit 3 the owner refreshes the token through the runbook sentry-actions-ro-token-rotation.md (no host access involved)

logs:
  where: GitHub Actions run logs for scheduled-terraform-drift.yml (job orphan-sweeps-checkin) and apply-sentry-infra.yml; Sentry check-in history for the monitor
  retention: GitHub Actions log retention for the repository; Sentry monitor check-in retention per the org plan

discoverability_test:
  command: grep -cE '^    sentry_cron_monitor\.scheduled_orphan_sweeps\.id,$' apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: "1"
```

The command is a static binding check only (anchored so it cannot match a longer name or a comment) and says so: the live state is verified by the apply run's fidelity step (Phase 7), because a live read needs a credential the run does not hold. No `ssh` anywhere; every read above is `gh` or `curl` against a vendor API from CI.

## Encryption Posture

This plan adds no persistent store (the probe keeps no state; the alert reference is a committed repo file holding configuration ids only). The `.tf` edit changes the membership of an existing alert and creates no store. It does add one new cross-component connection: the follow-through probe's read of the Sentry API from the sweeper's runner.

```yaml
at_rest:
  - store: none introduced (the probe writes nothing; apps/web-platform/infra/sentry/alert-reference.json is committed configuration, not user data)
    mechanism: not a store - the committed reference lives in the git repository, whose own posture is unchanged by this PR
    evidence: apps/web-platform/infra/sentry/alert-reference.json holds rule names, frequencies, trigger and action shapes and numeric detector ids only (checked 2026-10-26: its top-level keys per rule are actionFilters, detectorIds, enabled, frequency, name, triggerConditions, triggerLogicType, and the file contains no '@' character)
    defends_against: nothing is claimed for this file beyond repository access control
    does_not_defend: anyone with read access to the repository can read the file; it is not a secret and is treated as public configuration
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no store to verify
in_transit:
  - connection: follow-through sweeper runner -> de.sentry.io Sentry organisation API (GET checkins, bearer SENTRY_ACTIONS_RO_TOKEN)
    enforced_at: scripts/followthroughs/orphan-sweeps-relook-10972.sh (curl with --proto '=https', destination pinned by literal equality to jikigai-eu / de.sentry.io, bearer on curl's stdin config channel), modelled on scripts/followthroughs/community-monitor-checkin-soak-5728.sh
    tls: https, curl defaults (TLS 1.2 or newer negotiated with the vendor)
    cert_verification: on
    does_not_defend: a compromised runner or a leaked read-only token (the token is org-level read-only, ADR-031); a vendor-side breach; traffic metadata
    disclosed_as: not-publicly-claimed
```

No `exception` block: nothing is plaintext and certificate verification stays on.

### Network-Outage Deep-Dive (trigger match was the word "timeout" as a Sentry check-in status, not a connectivity symptom)

The plan has no SSH, firewall or provisioner dependency. The only network paths are HTTPS 443 from GitHub-hosted runners to `api.github.com` (gate reads), to `de.sentry.io` (probe read) and to the Sentry ingest host (existing check-in). L3 firewall allow-list: not applicable, no allow-list sits on these paths (GitHub-hosted runners, public vendor endpoints). L3 DNS/routing: not applicable beyond the probe's resolver-confinement prologue copied from the sibling. L7 TLS: certificate verification on (above). L7 application: the HTTP status of the checkins read is mapped to exit 3 with the status code in the output (no body is echoed beyond 500 bytes, as in the sibling).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add scheduled_orphan_sweeps to monitor_ids of sentry_alert.cron_monitor_failure, remove it from local.cron_monitor_alert_unrouted" [brief, issue #10972] | Phase 1, Files to Edit entry `cron-monitor-alerts.tf` | mapped |
| 2 | "regenerate alert-reference.json so the routing-parity test is green" [brief, issue #10972] | Phase 2, Files to Edit entry `alert-reference.json` | mapped |
| 3 | "check read-only (gh run list / run log step lists, metadata only) that the scheduled drift runs after the 06:00Z run on 2026-10-26 posted an ok check-in on scheduled-orphan-sweeps" [brief] | Phase 0 and Phase 6 steps 1 to 4 | mapped |
| 4 | "Build, test and review everything now. Do not mark the PR ready or merge until the 18:00Z slot (and the next one if it exists before the due date) is read as ok." [brief] | Phases 1 to 5 now; Phase 6 gate | mapped |
| 5 | "If it is not ok, stop and report \"Blocked: <reason>\"." [brief] | Phase 6 step 5, Phase 7 | mapped |
| 6 | "The merge's Sentry apply (apply-sentry-infra.yml) must converge; read the live monitor by name, metadata only, to confirm (Done-when item 2)." [brief] | Phase 7 (CTO Fork 3: the apply's own fidelity step, no token read) | mapped |
| 7 | "Record the re-look due 2026-11-09 ... as a dated, tracked follow-up on #10972 or a filed issue, per the deferral rules." [brief] | Phase 3 (enroll #10972, CTO Fork 1) plus the filed deferral for the stale comments | mapped |
| 8 | "Ref #9927 and Ref #10112 only, never a closing keyword on those" [brief] | Phase 5 PR body | mapped |
| 9 | "The PR body states what was measured and what was not, with dates." [brief] | Phase 5, Acceptance Criteria 12 | mapped |
| 10 | "Run the local affected gate before marking ready, not after. Rc 6 (AFFECTED_GATE_BUDGET_DEFERRED) is not a pass." [brief] | Phase 5 | mapped |
| 11 | "open draft PR #10905 ... Do not touch that PR." [brief] | Files to Edit "Deliberately NOT edited" | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cron-monitor-alerts.tf` edit | "add scheduled_orphan_sweeps to monitor_ids ... remove it from local.cron_monitor_alert_unrouted" | asked |
| `alert-reference.json` edit | "regenerate alert-reference.json so the routing-parity test is green" | asked |
| Phase 6 merge gate | "Do not mark the PR ready or merge until the 18:00Z slot ... is read as ok" | asked |
| Phase 7 read-back | "read the live monitor by name, metadata only, to confirm" | asked |
| Probe `orphan-sweeps-relook-10972.sh` and its suite | "Record the re-look due 2026-11-09 ... as a dated, tracked follow-up" | asked (mechanism chosen by CTO Fork 1; the repo's soak rule 2.9.1 requires automated enrollment) |
| `scripts/test-all.sh` and manifest rows | "Record the re-look due 2026-11-09 ... as a dated, tracked follow-up" | inferred - justification: a new `.test.sh` that no gate runs is an orphan suite; the repo registers suites through `run_suite` and the manifest generator |
| `cron-monitors.tf` comment edit | "remove it from local.cron_monitor_alert_unrouted" | inferred - justification: the comment above the monitor says it is created unrouted and that routing is #10972, which this PR makes false (same file the two-PR rule keeps in sync) |
| Runbook prose | "Done when ... the Sentry apply for that PR converged" | inferred - justification: it names the monitor as unrouted "until #10972 lands", which routing makes false and triage reads it (CTO Fork 2 and R5) |
| Filed deferral for the two stale workflow comments | "per the deferral rules" | asked (the deferral rule requires a tracking issue for anything left undone) |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform/infra/sentry`, `scripts` (probe, suite, registry), `knowledge-base` (runbook, ADR, spec artifacts)
- Planned files: 12 | Estimated changed lines: about 330 (the probe about 100, its suite about 180, the rest under 40)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The probe is the only part that could be split out, but the issue's Done-when includes the 2026-11-09 re-look, and enrolling it in the same PR is what lets the sweeper close #10972 mechanically.

## Acceptance Criteria

Pre-merge (PR author, mechanical):

1. `local.cron_monitor_alert_unrouted` no longer contains `scheduled_orphan_sweeps` (one fewer entry than on `origin/main`; 3 remain at plan time) and `monitor_ids` contains `sentry_cron_monitor.scheduled_orphan_sweeps.id,` exactly once, between `scheduled_oauth_probe` and `scheduled_plausible_goals` (`grep -c` returns 1; `terraform fmt -check` passes).
2. `sentry-cron-monitor-routing-parity.test.ts` passes (24 of 24 at baseline; same count after).
3. `alert-reference.json` is canonical (`jq -S . f | diff -q - f`), `cron-monitor-failure.detectorIds` is sorted with 64 elements, and it differs from `origin/main`'s copy by exactly one added id and has one more element than main's (64 at plan time, 63 on main). The `plan_pr` reference gate is green on the PR's head commit. (Implementation location: Phase 2, artifact `sentry-alert-reference-expected-<run-id>` of `apply-sentry-infra.yml`.)
4. `plugins/soleur/test/c4-count-parity.test.sh` passes.
5. `orphan-sweeps-relook-10972.test.sh` passes with all 14 matrix rows and the harness and boundary rows driven, prints a nonzero assertion count; `shellcheck`, `scripts/lint-followthrough-varq-ban.sh`, `scripts/lint-shell-trace-credential-refusal.py` and `scripts/lint-orphan-test-suites.sh` are clean for the new files. The probe header carries the credential posture and a `RETIREMENT:` line listing every site (suite, `run_suite` line, four manifest files, the `follow-through` label on #10972).
6. The sweeper dry-run against a throwaway scratch tracker (same `script=` and `secrets=`, `earliest=<now>`) shows the probe's `exit=` line and output tail on real data with a real verdict or a stated exit 3 reason; the scratch issue is closed afterward. A silent or unexplained result is a defect fixed before ready.
7. After the merge (or at ship if Phase 5.5 requires earlier): #10972 carries the `follow-through` label and the unfenced directive (`script=scripts/followthroughs/orphan-sweeps-relook-10972.sh`, `earliest=2026-11-09T00:00:00Z`, `secrets=SENTRY_ACTIONS_RO_TOKEN`); the sweeper's directive gate accepts it.
8. A deferral issue exists for the two stale comment sites in `scheduled-terraform-drift.yml` (Post-MVP / Later, with the re-evaluation trigger).
9. The local affected gate returned rc 0 (not 6) before the PR was marked ready.
10. The runbook reflects the routed state with the 2026-10-26 date; no sentence in it says the monitor is currently unrouted. ADR-241 is unchanged.
11. `scheduled-terraform-drift.yml`, ADR-241 and PR #10905's files are unchanged in this diff (`git diff origin/main --stat` lists none of them).
12. The PR body: `Ref #10972`, `Ref #9927`, `Ref #10112`, no closing keyword; a "Measured" list (2026-10-26 06:00Z run 40277293413 clean, identity HTTP 200, `http_code=202`; the 18:00Z and 2026-10-27 06:00Z slots with run ids and the `ok` reads; the apply's fidelity step result) and a "Not measured" list (Sentry's own view of the monitor; Sentry issue state, with the note that the sweeper may close #10972 on exit 0 without reading it; slots after the last read), each dated.

Merge gate (time-gated):

13. The 2026-10-26T18:00Z slot and the 2026-10-27T06:00Z slot each read `ok` per Phase 6, before the PR is marked ready. Otherwise the run ends with `Blocked: <reason>`, posted on #11154 and #10972.

Post-merge (read-only):

14. The apply run for the merge SHA has `Terraform apply` = `success` and the `sentry_alert live fidelity` step = `success` (not `skipped`); a comment on #10972 records it with the date.
15. #10972 stays open; the sweeper (enrolled) closes it on 2026-11-09 or later when the probe exits 0, or the owner closes it (the owner decides after an exit 1, which is permanent for the pinned window).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled the three technical forks on 2026-10-26 (see Technical rulings). No other domain (product, legal, marketing, finance, sales, support) is touched: no user-facing surface, no personal data processed, no spend, no external copy. Operations is the consumer of the alert (org email) and its cover story is unchanged beyond the routing.

No Product/UX gate: the mechanical UI-surface override does not fire (no `components/**`, `app/**` page or layout in Files to Edit/Create).

## Test Scenarios

- Routing parity: before and after, `sentry-cron-monitor-routing-parity.test.ts` 24 of 24. A fixture edit that lists the label in both the map and `monitor_ids` must red (existing row; observed by temporarily double-listing it locally and reverting).
- Reference gate: committed reference without the new id reds `plan_pr` and uploads the expected artifact (the Phase 2 first push); with it, green.
- Probe suite: the fourteen matrix rows plus the harness and boundary rows; the "0 passed, 0 failed" ledger case reds.
- Gate rehearsal (read-only, now): run the Phase 6 commands against run 40277293413 and confirm they print three `success` jobs, `skipped` email step, `http_code=202`, `STATUS` `ok`. That proves the commands on a known-good slot before the unknown one.
- Apply read-back rehearsal: run the Phase 7 `gh run view` against the most recent successful `apply-sentry-infra.yml` push run and confirm both step names are present with a conclusion.

## Sharp Edges

- **Never print the expected-reference document, the apply plan, or any diff.** Compare with `jq` and print counts and booleans. The detector id is a numeric configuration id, not a secret, but the artifact is a whole projection.
- **A 202 from the ingest endpoint shows acceptance only.** The gate's "ok" is job success and an accepted check-in, not Sentry's own monitor status. The PR body must not claim more.
- **`per_page=100` on the EU checkins endpoint is unverified** (the sibling uses 30 and a 7-day window). The probe's truncation guard (full page that does not reach the window start is exit 3) makes a cap show up as a non-closing result with a reason, never a pass; the scratch-tracker dry-run is where the real row count is read. If the endpoint caps lower than 14 days of slots, switch the probe to follow the `Link` cursor, within the same script.
- **The directive must be pasted unfenced at column 0** in the #10972 body; a fenced or indented one enrolls nothing (the sweeper's fence predicate in `scripts/sweep-followthroughs.sh`).
- **The directive gate resolves `script=` under the main checkout, not the worktree**; use the convention's untracked copy if it reports "does not exist", and remove the copy afterward.
- **A sweeper dry-run on the real #10972 never runs the probe** (the `earliest=` gate precedes it); only a scratch tracker with `earliest=<now>` does.
- **Retiring the probe leaves the label behind**: removing the script while the `follow-through` label stays on closed #10972 logs a "missing in repo HEAD" error daily for the sweeper's lookback window. The `RETIREMENT:` header line says to remove the label too.
- **The apply forensics artifact does not exist for a successful apply** (`if: failure()`); never plan around it.
- **The sweeper closes #10972 on exit 0.** Anything that must outlive that (the stale-comment deferral) lives in its own issue, which is why Phase 3 files one.
- **Do not hand-sync or rebase a BEHIND merge-queue PR.** Wait for the queue and read `ci-head-verdict.sh verdict 11154`.
- **A not-ok slot is a result, not an obstacle.** Report `Blocked: <reason>`; never route around the gate, and never hand-dispatch the drift workflow or the apply to manufacture a green slot.
- **A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan Phase 4.6.** It is filled above (`aggregate pattern`).
- **Terraform sort order is `LC_ALL=C`**: `scheduled_oauth_probe` < `scheduled_orphan_sweeps` < `scheduled_plausible_goals`; the parity test derives the list with that locale.
- **Re-check after any merge of `origin/main`**: PR #10905 edits the same two `.tf` files, so a sibling landing first can move the sorted neighbours; resolve by re-deriving the position, not by trusting line numbers (cite content anchors).

## Risks

- The 18:00Z or 06:00Z run does not occur or posts `error`: handled as `Blocked`; the due date 2026-10-27 may then slip, which is the owner's call, not this run's.
- The artifact path yields no id: contingency in Phase 2, else `Blocked` on the exact step.
- The probe's real-data dry run shows the endpoint behaves differently than the sibling's: the fixture suite cannot see it, which is why the scratch-tracker dry run precedes enrollment.
- Exit 1 on the probe is permanent for the pinned window; the sweeper then comments daily and only the owner closes #10972. Accepted (CTO R1, R6).
- The 2026-10-24 ruling C5 (#10952 plan) cut a follow-through script for the routing issue; the present ruling reverses that in effect because the re-look is now enrolled under rule 2.9.1. The simplicity reviewer's alternative (no suite, a sibling copy) was ruled against by the CTO for the 14-row suite because a wrong exit 0 closes the tracker silently.
