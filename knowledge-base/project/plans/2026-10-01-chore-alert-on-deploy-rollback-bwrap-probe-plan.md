---
title: "observability: alert on DEPLOY_ROLLBACK bwrap probe rollback lines (Better Stack)"
date: 2026-10-01
slug: alert-on-deploy-rollback-bwrap-probe
branch: feat-one-shot-9342-bwrap-rollback-alert
issue: 9342
closes: 9342
type: chore
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# observability: alert on DEPLOY_ROLLBACK bwrap probe rollback lines (Better Stack)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch (one-shot path, no brainstorm).

## Enhancement Summary

**Deepened on:** 2026-10-01
**Sections enhanced:** gate verification (User-Brand Impact, Observability, Guard Contract, PAT-shape, encryption posture), citation re-verification.
**Method:** proportionate deepening for a copy-of-precedent chore — mechanical halts and live citation checks run in-session; the 40-agent discovery fan-out was not run (no UI, no new substrate, no novel pattern; plan-review's four-agent panel already ran and its findings are folded in).

### Key Improvements
1. `lint-guard-contract.py` run on this plan: 1 Guard Contract, 1 entry, exit 0.
2. Citations re-verified live: #9336 MERGED, #9045/#8097/#8016 CLOSED, #8706/#8735/#7942 OPEN, #5566 is a MERGED PR; labels `priority/p3-low`, `type/chore`, `domain/engineering`, `observability` exist; rule IDs `hr-all-infrastructure-provisioning-servers`, `cq-write-failing-tests-before`, `cq-cite-content-anchor-not-line-number`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-observability-as-plan-quality-gate` exist in AGENTS.md.
3. PAT-shape sweep: no hits. User-Brand Impact: present, threshold `none` with the sensitive-path scope-out bullet (`apps/web-platform/infra/` matches the canonical regex). Observability: all five fields present; `command` starts with allowlisted `bash`, `expected_output` is a literal, `credentials_required` declared (SKIP-DECLARED waiver; baseline bump planned).
4. Reconciler cadence claim verified: the `logs_alert` arm runs inside the twice-daily `scheduled-terraform-drift` scan (`reconcile-live-heartbeats.ts` invoked from that workflow).

### New Considerations Discovered
- `terraform-target-parity.test.ts` covers `terraform_data` only, so the new guard's `-target` row is the sole enforcement for logtail resources (recorded in Reconciliation and the Guard Contract).
- Burst/dedup behaviour of one rollback per CI retry is unverified against Better Stack semantics; the plan states it as "verify at the first real fire" rather than asserting it.

## Overview

The canary stage of `apps/web-platform/infra/ci-deploy.sh` runs a **blocking** `bwrap` probe. When it fails, the deploy rolls back with `reason=canary_sandbox_failed` and the script writes exactly one journald line under `logger -t ci-deploy`, beginning `DEPLOY_ROLLBACK: bwrap sandbox non-functional in <image>:<tag> …`. Nothing in `apps/web-platform/infra/betterstack-logs-alerts.tf` matches that line. After PR #9336 (merged 2026-10-01T10:05:55Z, dropped `--die-with-parent` from the probe, removing the docker-exec PDEATHSIG race behind the 16-rollbacks-in-7-days flake) and the retirement of the #8016 follow-through sweeper, a recurrence is detectable only through the release-failure email (which has failed once: RESEND_API_KEY unset, 2026-09-27), the workflow `::error::` annotation, or a hand-run query. The runbook says so in as many words: "detection is pull-only until #9342 lands".

This plan adds one native Better Stack Logs alert, `soleur-bwrap-probe-rollback-prd`, as a `logtail_exploration` + `logtail_exploration_alert` pair copied from the `workspaces_luks_deadman_fired` precedent (ADR-218 paging semantics), plus the three companion edits every Logs alert in this repo carries: the apply workflow's `-target=` lines, a drift guard registered in `infra-validation.yml`, and the runbook entries. The apply is the existing push-triggered `apply-web-platform-infra.yml` run, so there is no new apply path.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified on this worktree) | Plan response |
| --- | --- | --- |
| Emitter is at "`ci-deploy.sh` (~line 3556)" | `BWRAP_LINE="DEPLOY_ROLLBACK: bwrap sandbox non-functional in $IMAGE:$TAG …"` is at ~line 4038; the file has grown. Only emitter of the phrase in the repo (`grep` over `*.sh,*.yml,*.ts,*.tf,*.toml`); `ci-deploy.test.sh` pins the same literal. | Cite by content anchor (`BWRAP_LINE="DEPLOY_ROLLBACK: bwrap sandbox non-functional in`), never line number (`cq-cite-content-anchor-not-line-number`). |
| "Name the alert in the rc=137 row of canary-probe-set.md (line ~121)" | The `rc` row of the *Fields* table is at ~line 143; line 121 is the pre-table log-format block. The row already says "After the fix any `rc=137` is unexplained". The runbook also says "detection is pull-only until #9342 lands" (~line 172). | Edit the `rc` row **and** rewrite the "pull-only until #9342" sentence — leaving it would make the runbook lie the day this merges. |
| SQL filters `SYSLOG_IDENTIFIER='ci-deploy'` + `startsWith(message, …)`; no host scope stated | Live probe (below): `ci-deploy` rows come from **three** `host_name` values — `soleur-web-platform` (web-1), `soleur-web-2`, and `soleur-inngest-prd` (web-1's *pre-2026-09-19* name; 2 real rollback rows carry it). The luks sibling's `host_name = 'soleur-web-platform'` conjunct would **silently exclude web-2** and any renamed host. | **No `host_name` conjunct** (deliberate divergence from the luks precedent). The property is "any deploy host rolled back on the bwrap probe"; the sibling's `startsWith` + tag pair already stops quoting rows. |
| "copy the pair for the luks deadman, ~lines 820-889" | The pair is at ~lines 835-889; its `locals` (SQL + runbook URL) at ~lines 820-833, comment block above from ~line 785. Pattern confirmed: single-line `replace(trimspace(…), "/\\s+/", " ")`, `values = [local.vector_prd_source_id]`, free/paid escalation ternary. | Copy shape; adapt names, SQL and `incident_cause`. |
| "Needs a Terraform apply through the existing infra workflow" | `apply-web-platform-infra.yml` triggers on push to main for `apps/web-platform/infra/**` and is `-target`-scoped: an alert not named in its MAIN plan allowlist is **never applied** (#5566). The file header lists a five-step "TO ADD ANOTHER LOGS ALERT" recipe the issue does not mention (two `-target=` lines, runbook row in `betterstack-log-query.md`). `apply-web-platform-infra.yml` is 483,707 B vs the 490,000 B gate (`workflow-file-size.test.ts`): two lines fit. | Add both `-target=` lines; add the guard. |
| (unstated) adding a 9th exploration | `betterstack-send-failed-alert-mutation.test.sh` row M17 asserts the **fmt-aligned** literal `    values        = [local.vector_prd_source_id]` occurs **exactly 8** times (`assert s.count(old) == 8`) and its comment says "EIGHT explorations". A 9th exploration reds that battery (and a mis-aligned line would leave the count at 8). | Bump to 9 / "NINE", append `#9342's bwrap_probe_rollback` to the comment list; write the new `values` line with exactly 8 spaces before `=`. |
| `.tf` header: "the #5566 guard in `terraform-target-parity.test.ts` reds until the `-target=` lines exist" | **Stale for logtail resources.** `plugins/soleur/test/terraform-target-parity.test.ts` guards only SSH-provisioned `terraform_data.*` (`grep logtail` over it returns nothing). For a Logs alert the sibling drift guard's `-target` check is the **only** enforcement. | Keep the `-target` row (R6) in the new guard; do not drop it as redundant. Add one clause to the new comment block so the header does not mislead. |
| (unstated) this plan's own `credentials_required` declaration | `plugins/soleur/test/preflight-discoverability-test.test.ts` G1 counts every plan under `knowledge-base/project/plans/` (archive included) declaring `credentials_required`: `BASELINE_DECLARED_PROBES = 40` → 41 with this plan. Check 10 reports SKIP-DECLARED (a waiver; the command never runs in preflight). | Add that file to Files to Edit with a dated justification comment (placement / truth / no substitute), exactly as the #8016 plan did. |

## Research Insights

**Premise Validation.** Issue #9342 is OPEN with no closing PR. PR #9336 (cited as context) is MERGED, so the cause-removal premise holds; the draft PR for this branch is #9376 (OPEN, draft). Cited paths all exist on this branch (`betterstack-logs-alerts.tf`, `ci-deploy.sh`, `canary-probe-set.md`); two line numbers drifted (see Reconciliation). `LOG_TAG` is `readonly LOG_TAG="ci-deploy"`; `"ci-deploy"` is on the Vector `host_scripts_journald` allowlist (`vector.toml`) and rows demonstrably ship. No ADR rejects the mechanism: ADR-218 *adopts* native Terraform-managed Logs alerts for "pure stateless per-bucket counts with an email-acceptable surface", which this is.

**Property List.**

1. P1 — A blocking bwrap-probe rollback on **any** deploy host sends an alert email (the free-tier channel; escalation only on the paid tier) within about a minute, without relying on the CI release-failure email.
2. P2 — A rollback row that merely *quotes* the marker (inngest ships GitHub-webhook logs quoting issue/PR bodies to the same source) cannot page.
3. P3 — The alert stays coupled to the emitter: rewording the marker in `ci-deploy.sh` reds CI instead of silencing the alert.
4. P4 — The alert actually exists in Better Stack after merge (an un-targeted resource is never applied).
5. P5 — An operator reading the alert email lands on the decode runbook without SSH.

**Cut List** (mechanism → property → what already covers it):

- `host_name` conjunct (luks precedent) → would buy "web-1 only" → **cut**: P1 says any host; web-2 runs the same script (1,026 `ci-deploy` rows on `soleur-web-2` in the 14-day window).
- Synthetic probe + `*_probe_rev` + `terraform_data` + follow-through script (monitor_send_failed precedent, SSH provisioner) → "prove the alert pages through the real path" → **cut**: that mechanism exists because send-failed's *detector is the thing under suspicion* and needed an SSH-applied probe; this alert's failure detection is already covered by the reconciler `logs_alert` arm (reads live `paused`/absence twice daily) and a synthetic fire would cost a real page. No `provisioner` → no network-outage gate.
- New runbook file → P5 → **cut**: `canary-probe-set.md` §"Blocking bwrap sandbox probe" is already the decode runbook; the alert links to its anchor.
- New ADR / C4 edit → **cut**: follows ADR-218 unchanged; no new actor/system/relationship (`betterstack -> founder` edge and the Logs-alert class are already in `model.c4`'s betterstack description, which carries no per-alert counts; `plugins/soleur/test/c4-count-parity.test.sh` is green at plan time).
- Widening to the sibling `DEPLOY_ROLLBACK: canary failed for …` line → **not requested** by #9342; different false-positive profile (health flaps). Not proposed here; `bwrap` rows only.
- Pausing the alert at ship ("shipped paused") → **cut**: post-fix expected volume is zero and a recurrence is exactly the page we want; there is no "correct value that would page continuously" (contrast `inngest_luks_wrong_volume`).

**Live probe (plan time, 2026-10-01, via `scripts/betterstack-query.sh` raw-SQL mode, hot `remote()` UNION `s3Cluster` archive, read credentials from Doppler `prd_terraform`, no values printed).** The alert's exact predicate (tag + `startsWith`, no host conjunct) over the last 14 days matched **19 real rows across 8 UTC days** (2026-09-19 x2 [host `soleur-inngest-prd`, web-1's pre-rename name], 09-23 x1, 09-25 x5, 09-26 x2, 09-27 x2, 09-28 x1, 09-29 x4, 09-30 x2 [host `soleur-web-platform`]). Every row carried `rc=137 cstate=running err_chars=0 bwrap_err="<empty>"` with `ms` 73-104 — the PDEATHSIG signature. This is the positive control (the predicate shape matches live rows; a `startsWith` miss would have returned zero). After #9336 deployed the expected steady state is 0; any match is "unexplained" per the runbook. The `webhook.service`-attributed rows (`_SYSTEMD_UNIT=webhook.service`) are the same line re-logged under `SYSLOG_IDENTIFIER=ci-deploy` (the unit differs, the tag does not), so the tag filter is the right selector, not `_SYSTEMD_UNIT`.

**Learnings applied** (`knowledge-base/project/learnings/`):

- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — `raw` is double-encoded JSON; isolate on the decoded `SYSLOG_IDENTIFIER`, never a line substring. (`JSONExtractString(raw, …)` in the SQL does this.)
- ADR-218 / `betterstack-logs-alerts.tf` header — `treat_as_zero`, `higher_than 0`, free/paid `escalation_target` ternary, single-line SQL at the resource site (perpetual-diff), the five-step add-an-alert recipe.
- `bwrap-deploy-gate-undiagnosable-rollback-postmortem.md` — why the line carries rc/ms/cstate/err_chars/bwrap_err (so the alert text can point at them).

**Gates skipped.** Network-outage check (no SSH wording, no `provisioner`); encryption-posture (the `.tf` matches the detection regex but the plan adds no persistent store and no new connection, and `logtail_exploration[_alert]` are already classified non-store types in `scripts/encryption-posture-ledger.json`); GDPR (no regulated-data surface; `bwrap_err` is redacted at emit); community/functional-overlap discovery (a copy of an in-repo pattern); ADR/C4 (follows ADR-218; no new actor/system/relationship).

## Open Code-Review Overlap

Open `code-review` issues touching files this plan edits: #8735 (`infra-validation.yml`: `notify-main-failure` misses cancelled jobs) and #7942 (`infra-validation.yml`: two `*.mutation.sh` batteries run in no gate). **Acknowledge** both: neither concerns the Logs-alert guards; this plan adds one `run:` step beside an existing sibling and does not touch job-level notification or the `*.mutation.sh` naming. They remain open. No overlap on `betterstack-logs-alerts.tf`, `apply-web-platform-infra.yml`, `ci-deploy.sh`, the two runbooks or the send-failed mutation battery.

## Implementation Phases

Order is RED-first (`cq-write-failing-tests-before`): the guard lands before the resource it guards.

### Phase 1 — Guard (RED)

Create `apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh`, a lean sibling of `workspaces-luks-deadman-fired-alert.test.sh` (same `ok()`/`no()` instrument self-test, `assert_fixture_dir`, here-string greps, copy-and-mutate battery, exact-count floor). It must be RED against the current tree (no resource yet). Contents per the Guard Contract below (trimmed at plan review to the rows that pin P2/P3/P4 and the guard's own dispatch). Register it in `.github/workflows/infra-validation.yml` next to the `#9045` step (an unrun guard is a claim; `scripts/lint-orphan-test-suites.sh` already reds an unregistered `*.test.sh`, so the guard itself does not grep the workflow for its own registration).

### Phase 2 — Resource (GREEN)

In `apps/web-platform/infra/betterstack-logs-alerts.tf`, after the `workspaces_luks_deadman_fired` pair, add (names are the contract the guard reads):

```hcl
locals {
  bwrap_probe_rollback_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy'
      AND startsWith(JSONExtractString(raw, 'message'), 'DEPLOY_ROLLBACK: bwrap sandbox non-functional')
    GROUP BY time
  SQL

  bwrap_probe_rollback_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/canary-probe-set.md#blocking-bwrap-sandbox-probe--reading-its-self-report-8016-pr-8026"
}
```

- `resource "logtail_exploration" "bwrap_probe_rollback"` — `name = "soleur-bwrap-probe-rollback-prd"`, `team_name = "Your team"`, `chart { chart_type = "line_chart" }`, `query { query_type = "sql_expression", source_variable = "source", sql_query = replace(trimspace(local.bwrap_probe_rollback_sql), "/\\s+/", " ") }`, `variable { name = "source", variable_type = "source", values = [local.vector_prd_source_id] }` (in the real file keep terraform-fmt alignment: `    values        = [local.vector_prd_source_id]`, 8 spaces before `=`, or M17's exact-literal count misses it).
- `resource "logtail_exploration_alert" "bwrap_probe_rollback"` — `exploration_id = logtail_exploration.bwrap_probe_rollback.id`, same `name`, `alert_type = "threshold"`, `operator = "higher_than"`, `value = 0`, `check_period = 60`, `query_period = 300`, `confirmation_period = 0`, `recovery_period = 600`, `on_missing_data = "treat_as_zero"`, `paused = false`, `email = true` (push/call/sms/critical_alert false), the sibling's `escalation_target` ternary, `metadata = { runbook = local.bwrap_probe_rollback_runbook_url }`, and an `incident_cause` that **leads with severity** ("No user-facing outage: a release was blocked and rolled back; production still runs the previous version."), then states the blocking bwrap probe failed in the canary; the email carries no row body, so it gives the exact decode command (`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep 'DEPLOY_ROLLBACK: bwrap sandbox non-functional'`, then read `rc`/`ms`/`cstate`/`err_chars`/`bwrap_err` from the row; a recurrence of `rc=137` is unexplained post-#9336); remediation is GitHub "Re-run failed jobs" on the release run, never `apply-deploy-pipeline-fix.yml` and never a host command; runbook URL. Closing prose: "auto-resolves after 10 quiet minutes; resolution does not mean the cause was found; a failed re-run after resolve opens a new incident".
- Comment block above the locals (house style): why this alert, why **no `host_name`** (web-2 and web-1's pre-rename name carry the same rows; this diverges from the luks precedent on purpose), `LIVE-PROBED 2026-10-01` with the 19-row/8-day positive control and the result for the pristine predicate, that a row merely quoting the marker cannot page (tag AND `startsWith`), and that the file header's "#5566 guard reds until `-target=` lines exist" does not cover logtail resources (this alert's drift guard does).

In `.github/workflows/apply-web-platform-infra.yml`, add the two `-target=` lines after the `workspaces_luks_deadman_fired` pair (MAIN plan allowlist, ~line 695):

```text
-target=logtail_exploration.bwrap_probe_rollback \
-target=logtail_exploration_alert.bwrap_probe_rollback \
```

In `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`, update the M17 anchor count `8` → `9` and the "EIGHT explorations carry this line" comment (append `#9342's bwrap_probe_rollback`). Re-grep the count on rebase (a concurrent PR adding an exploration makes it 10). Re-run that battery.

In `plugins/soleur/test/preflight-discoverability-test.test.ts`, raise `BASELINE_DECLARED_PROBES` `40` → `41` and append the dated `#9342` justification comment (placement: correctly-indented child of `discoverability_test:`, one-line quoted scalar; truth: the probe reads `SANDBOX_PROBE_OK` through `betterstack-query.sh` under `doppler run -c prd_terraform`; no substitute: those lines exist only in production logs). Re-count after the plan is final.

### Phase 3 — Runbooks

- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`: in the *Fields* table `rc` row, name `soleur-bwrap-probe-rollback-prd` ("any `rc=137` is unexplained — and now pages; this row is the page's decode"); in "Closing #8016", replace "detection is pull-only until #9342 lands: the release-failure email, the workflow `::error::` annotation and the query above" with the alert as the primary detection, keeping the email/annotation/query as the secondary routes and the "Re-run failed jobs" remediation sentence verbatim.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` §"Standing alarms over this source": add a `logtail_exploration_alert.bwrap_probe_rollback` bullet in the existing format (name, trigger, no-`host_name` rationale, definition file, drift-guard path, runbook link).

### Phase 4 — Live probe before merge

With the resource written, re-run the live probe against the **final SQL text as it appears in the heredoc** (extract it from the `.tf`, substitute `{{source}}`/`{{start_time}}`/`{{end_time}}` for the `$BS_TABLE` union and a 14-day window, run through `scripts/betterstack-query.sh` raw mode). Record in the PR body, counts only (never row bodies): (1) positive control — rows > 0 over 14 days (the pre-#9336 flake; plan-time result: 19); (2) negative control — the same predicate with the needle changed to `DEPLOY_ROLLBACK: bwrap sandbox non-functionalX` returns 0, proving the needle is the discriminator and the predicate is not vacuously true.

### Phase 5 — Ship and post-merge

PR body carries `Closes #9342` (not the title; `wg-use-closes-n-in-pr-body-not-title-to`) and the four labels from the issue (`priority/p3-low`, `type/chore`, `domain/engineering`, `observability`). Post-merge (`soleur:postmerge`): confirm the `apply-web-platform-infra.yml` run for the merge commit concluded success and that the apply plan named `logtail_exploration[_alert].bwrap_probe_rollback`; read the alert back (`paused=false`) via the next `heartbeat-live-reconcile` run's `logs_alert` arm (`SOLEUR_HEARTBEAT_RECONCILE_MISMATCH … logs-alert-absent|logs-alert-paused` is the failure shape; silence means armed).

## Files to Edit

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — locals + exploration + alert + comment block.
- `.github/workflows/apply-web-platform-infra.yml` — two `-target=` lines in the MAIN plan allowlist.
- `.github/workflows/infra-validation.yml` — one `run:` step registering the new guard.
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` — M17 count 8 → 9 + comment.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES` 40 → 41 + dated justification comment.
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` — `rc` row + "Closing #8016" detection sentence (one edit pass).
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarm bullet (step 5 of the `.tf` header's add-an-alert recipe).

## Files to Create

- `apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh` — drift guard + mutation rows.

Path verification: every edited path exists on this worktree (`git ls-files` over each); no glob is prescribed except `apps/web-platform/infra/**` in the existing workflow trigger.

## Observability

```yaml
liveness_signal:
  what: >-
    The alert's own existence/armed state in Better Stack (logtail_exploration_alert.bwrap_probe_rollback,
    paused=false), read live by the heartbeat-live-reconcile `logs_alert` arm. The feeding pipeline is
    observable (not alarmed) through the PASS-path marker `SANDBOX_PROBE_OK: bwrap sandbox verified`
    under the same ci-deploy tag, once per deploy.
  cadence: reconcile twice daily; alert evaluated every 60s over a 300s window
  alert_target: team email (account owner + betteruptime_team_member.ops); betteruptime_policy.uptime escalation on the paid tier
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf
error_reporting:
  destination: Better Stack Logs alert email on a matching row; Sentry/Resend are deliberately NOT in this path (the release-failure email is the leg that failed once)
  fail_loud: true — a rollback line alerts on one row (higher_than 0, treat_as_zero); an absent or paused alert is reported by the reconciler as SOLEUR_HEARTBEAT_RECONCILE_MISMATCH
failure_modes:
  - mode: marker reworded in ci-deploy.sh so the needle no longer matches
    detection: bwrap-probe-rollback-alert.test.sh reads the literal from the emitter's BWRAP_LINE assignment and reds in infra-validation CI
    alert_route: CI red on the PR (pre-merge)
  - mode: alert never applied (missing -target line) or later paused/deleted
    detection: the guard asserts both -target lines (the #5566 parity test does not cover logtail resources); the reconcile logs_alert arm reports logs-alert-absent / logs-alert-paused live
    alert_route: SOLEUR_HEARTBEAT_RECONCILE_MISMATCH (existing reconciler route)
  - mode: declared residuals — ci-deploy rows stop shipping (Vector allowlist drift), or logger is down so the script falls back to printf on the webhook stdout leg (SYSLOG_IDENTIFIER=webhook, not matched)
    detection: pull-only — absence of SANDBOX_PROBE_OK on a deploy day via the canary-probe-set.md query; the release-failure email and the workflow ::error:: annotation remain the routes. No dead-man alert is added (follow-up candidate recorded in decision-challenges.md)
    alert_route: pull-only query, by design
logs:
  where: Better Stack Logs source 2457081 (soleur-inngest-vector-prd) via Vector host_scripts_journald; local journald under SYSLOG_IDENTIFIER=ci-deploy
  retention: the source's retention (hot window plus s3Cluster archive; the live probe read 14 days)
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 7d --grep 'SANDBOX_PROBE_OK: bwrap sandbox verified'
  expected_output: SANDBOX_PROBE_OK
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD via Doppler soleur/prd_terraform (run under `doppler run -p soleur -c prd_terraform --`) — Better Stack log content has no unauthenticated read path (the ingest token is write-only), so no keyless probe verifies the same property"
```

`discoverability_test` is a declared waiver: preflight Check 10 reports SKIP-DECLARED (the command never runs there), which is why the corpus baseline in `preflight-discoverability-test.test.ts` is bumped as the reviewable diff line. The probe checks the feeding pipeline, not the alert itself (the alert's armed state is the reconciler's job); `--since 7d` because the marker only appears on a deploy.

## Infrastructure (IaC)

### Terraform changes

Existing root `apps/web-platform/infra/` (file `betterstack-logs-alerts.tf`): two resources, `logtail_exploration.bwrap_probe_rollback` and `logtail_exploration_alert.bwrap_probe_rollback`, on the already-pinned `BetterStackHQ/logtail` provider. No new provider, no new variable, no new sensitive input: the provider token and the source id literal (`local.vector_prd_source_id`) already exist. Workflow allowlist: the two `-target=` lines above.

### Apply path

(Existing infra) — pushed to main, `apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**` and applies the MAIN `-target` set; Better Stack API writes only, no SSH, no downtime, no blast radius beyond the new alert. This is the "existing infra workflow" the issue names; no bootstrap script or taint is involved.

### Distinctness / drift safeguards

`dev != prd` is not in play (Better Stack Logs source is prd-only, `-prd` in the name like every sibling). The drift guard pins: both names, `exploration_id` linkage, `values = [local.vector_prd_source_id]`, paging semantics, both `-target=` lines. State is the existing R2-backed root state; the alert holds no secret.

### Vendor-tier reality check

Free tier has no escalation policy: copy the sibling `escalation_target` ternary on `var.betterstack_paid_tier` verbatim (free: `team_name = "Your team"`, email only — the alert emails; it does not page a phone). Eight sibling Logs alerts already apply, so no count cap is in play. A plan-limit failure at apply would be surfaced by the apply run and escalated as a tier decision, never a dashboard click (`hr-all-infrastructure-provisioning-servers`).

## Encryption Posture

No persistent store and no new cross-component connection is introduced: the change adds two alert-definition resources on the already-provisioned Better Stack Logs source (2457081) through the existing `BetterStackHQ/logtail` provider, whose API connection is unchanged. Phase 2.11's skip condition applies; the heading is present only so the deepen-plan `.tf` trigger resolves to an explicit "nothing to declare" instead of a missing section. `logtail_exploration` and `logtail_exploration_alert` are already classified non-store resource types in `scripts/encryption-posture-ledger.json`.

## Guard Contract

### Guard 1 — bwrap-probe-rollback-alert drift guard

**Property.** A `DEPLOY_ROLLBACK: bwrap sandbox non-functional` row emitted by `ci-deploy.sh` under `SYSLOG_IDENTIFIER=ci-deploy` on any host is matched by an unpaused, applied Better Stack alert that emails on one row, and nothing that merely quotes the marker is.

**Assembly.** Every place the property quantifies over, each through a named chokepoint: (1) the **emitter** — the single `BWRAP_LINE="…"` assignment in `ci-deploy.sh` (the needle is *read from it*, not retyped); (2) the **tag** — the `readonly LOG_TAG="ci-deploy"` assignment; (3) the **predicate** — the heredoc `bwrap_probe_rollback_sql`, exactly two ANDed conjuncts plus `GROUP BY time`, no OR/negation/`host_name`; (4) the **exploration** block (`sql_query` via the one-line `replace(trimspace(local.…))`, `values        = [local.vector_prd_source_id]`); (5) the **alert** block (identity, `exploration_id` linkage, threshold semantics, escalation ternary, runbook URL); (6) the **apply allowlist** — both `-target=` lines in the MAIN plan of `apply-web-platform-infra.yml` (the only enforcement for logtail resources: `terraform-target-parity.test.ts` covers `terraform_data` only); (7) the **runbook anchor** — the slug in `bwrap_probe_rollback_runbook_url` resolves to a real heading in `canary-probe-set.md`. Registration in `infra-validation.yml` is enforced by `scripts/lint-orphan-test-suites.sh`, not re-asserted here. A second emitter of the phrase would not break this alert, so no emitter-uniqueness count is asserted (cut at plan review; it also would have failed on the pristine tree, `ci-deploy.test.sh` carries the literal four times).

**Mutation matrix.** Each row copies one source file into a scratch dir, mutates the copy, re-runs the guard against it via `BWRAP_GUARD_*` override variables, and must RED with the attributed `[FAIL]` string (not merely non-zero). Derived from the design, written before the guard.

| Row | Mutation | Must RED because |
| --- | --- | --- |
| R1 | Reword the marker in `ci-deploy.sh`'s `BWRAP_LINE` (`non-functional` → `nonfunctional`), TF untouched | the needle is read from the emitter; the alert would silently stop matching |
| R2 | Drop the `SYSLOG_IDENTIFIER = 'ci-deploy'` conjunct | quoting rows under another tag (inngest webhook logs) could alert |
| R3 | Replace `startsWith(...)` with `position(...) > 0` | a row that merely contains the phrase could alert |
| R4 | Add `AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'` as a third conjunct | silently excludes web-2 and web-1's pre-rename name (the luks-precedent regression the live probe found) |
| R5 | Append an `OR` clause after both conjuncts, every anchor still present | predicate widened with all anchors intact (a second member after a compliant first) |
| R6 | Remove one of the two `-target=` lines | an untargeted resource is never applied, and no other test sees it |
| R7a / R7b | `paused = true`; `value = 1` | armed-ness and one-row alerting are the point (each its own row) |
| R8 | Rename the runbook heading in the `canary-probe-set.md` copy | the alert's runbook link would dangle while every other check stays green |
| R9 | **Guard's own dispatch:** rename the `bwrap_probe_rollback_sql` locals key so the heredoc extractor returns empty | a guard reporting "0 checked" and exiting 0 is vacuous; the "heredoc found" row and the exact pass-count floor must RED |

**Harness rows.** Instrument control copied from the luks guard: the `ok()`/`no()` self-test, and the inner run against the PRISTINE tree must exit 0 before any mutation row is trusted. One must-PASS non-canonical input, differing in a way the contract permits: different whitespace/indentation inside the heredoc (legal, because the resource collapses it to one line) must stay GREEN — so a guard that rejects everything cannot pass. (Per plan-review: mutating the suite's own `no()`/floor and the extra must-PASS variants were cut as second-order checks on a copied harness.)

**Anchor.** The guard compares stored values (needle, names, counts) to files one diff can edit together, so it proves consistency, not integrity. Outside the commit: the needle is read from the **emitter**, which `ci-deploy.test.sh` pins independently; live arming is read from Better Stack itself by the reconciler's `logs_alert` arm. A pass-count floor is paired with named-row identity (every row attributed by `[FAIL]` string), so substituting one check for another that keeps the count fails.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/infra/betterstack-logs-alerts.tf` declares `logtail_exploration.bwrap_probe_rollback` and `logtail_exploration_alert.bwrap_probe_rollback`, SQL exactly the two-conjunct predicate above with no `host_name`; alert is `threshold`/`higher_than`/`0`/`check_period 60`/`query_period 300`/`treat_as_zero`/`paused = false`/`email = true` with the sibling escalation ternary.
- [x] `grep -cE '^\s*-target=logtail_exploration(_alert)?\.bwrap_probe_rollback \\$' .github/workflows/apply-web-platform-infra.yml` prints `2`.
- [x] `bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh` exits 0 and is registered as a step in `infra-validation.yml` (`bash scripts/lint-orphan-test-suites.sh` exits 0).
- [x] The guard's mutation rows R1-R9 (R7 as R7a/R7b) each fail with their attributed `[FAIL]` string and the harness rows hold (`bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh` prints its mutation summary with zero unexpected greens).
- [x] `bash apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` exits 0 with the M17 count at 9 (and the sibling guards `betterstack-send-failed-alert.test.sh`, `workspaces-luks-deadman-fired-alert.test.sh`, `registry-store-not-luks-alert.test.sh`, `inngest-step-524-alert.test.sh`, `inngest-luks-wrong-volume-alert.test.sh` still exit 0).
- [x] `terraform fmt -check` and `terraform validate` pass in `apps/web-platform/infra` (the heredoc SQL is NOT validated by `validate`; the live probe below covers it).
- [x] `plugins/soleur/test/workflow-file-size.test.ts` passes (apply workflow stays under 490,000 B).
- [ ] Live probe recorded in the PR body, counts only: positive control > 0 rows over 14 days, negative control (`…functionalX`) = 0; the final SQL text was probed, not a paraphrase.
- [x] `canary-probe-set.md`'s `rc` row names `soleur-bwrap-probe-rollback-prd`; the sentence "detection is pull-only until #9342 lands" no longer appears in the file (`grep -c 'pull-only until #9342' knowledge-base/engineering/operations/runbooks/canary-probe-set.md` prints `0`); the "Re-run failed jobs … never `apply-deploy-pipeline-fix.yml`" remediation sentence is retained.
- [x] `betterstack-log-query.md` carries a `bwrap_probe_rollback` standing-alarm bullet.
- [x] `bunx vitest run plugins/soleur/test/preflight-discoverability-test.test.ts` (or the repo's runner for that file) passes with `BASELINE_DECLARED_PROBES = 41`; markdownlint over the two edited runbooks passes.
- [ ] PR body contains `Closes #9342` and the four labels are on the PR; the title does not contain `Closes`.

### Post-merge (operator-free, automated)

- [ ] The `apply-web-platform-infra.yml` run for the merge commit concludes `success` and its apply output names both new resources (`gh run view <id> --log | grep bwrap_probe_rollback`).
- [ ] The next `heartbeat-live-reconcile` run reports no `logs-alert-absent` / `logs-alert-paused` for `soleur-bwrap-probe-rollback-prd`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. No UI surface, no user-facing copy, no spend (the alert is a free-tier Better Stack resource), no legal/regulated-data surface. Engineering/CTO concerns are carried by the plan itself (ADR-218 conformance, IaC routing, guard contract); CTO sign-off is not separately required because the brand-survival threshold is `none`.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the alert is an operator-facing detector and the deploy gate it watches is unchanged. The failure shape is *silence*: a future bwrap-probe rollback would again be noticed late, delaying a release by hours, never degrading the running app (the rollback leaves the previous version serving).

**If this leaks, the user's data is exposed via:** no vector — the alert SQL and `incident_cause` carry no user data; the matched line's `bwrap_err` text is redacted at emit (`_cred_err_tail`), and the alert email names the condition, never a row body.

**Brand-survival threshold:** none

`threshold: none, reason: the diff adds a stateless count alert over an already-shipped, already-redacted infra log line and edits CI allowlists/docs; it reads no user data, grants no access and changes no deploy behaviour.`

## Test Scenarios

- Guard GREEN on the pristine tree; each of R1-R9 RED with its attributed string; the whitespace must-PASS row GREEN.
- SQL, live: positive control (14-day window) > 0; `…functionalX` needle = 0.
- `terraform fmt -check` / `terraform validate` clean; `terraform plan` (CI, `infra-validation.yml`) shows exactly two additions and no change to existing alerts (single-line `replace` keeps the SQL diff-stable; a wrapped SQL would plan a perpetual diff).
- Sibling guards and the send-failed mutation battery unchanged-green except the deliberate M17 `8 → 9`; the discoverability corpus baseline moves `40 → 41` deliberately.

## Sharp Edges

- **No `host_name` conjunct, on purpose.** Do not "harmonise" with the luks sibling: `soleur-inngest-prd` (web-1 before 2026-09-19) and `soleur-web-2` carry real rows. R4 exists to make the harmonising edit red.
- **Single-line SQL at the resource site.** Terraform heredocs plan a perpetual diff against Better Stack's normalised SQL; keep `replace(trimspace(…), "/\\s+/", " ")`.
- **`startsWith`, not `position`/LIKE, and the tag in the same conjunction** — GitHub-webhook log rows quoting the marker ship to the same source under another `SYSLOG_IDENTIFIER`.
- **`terraform validate` does not validate the heredoc SQL.** Only the live probe does; do it against the final text.
- **The 9th exploration reds the send-failed mutation battery's M17 (`== 8`)** until bumped — easy to miss because it is a *different* guard from the one being added.
- **Citing lines:** the issue's line numbers (3556, ~121) are stale; cite content anchors in the PR and runbooks.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled here.
- The alert does not cover the `printf` fallback leg (webhook stdout) — declared in Observability, not an oversight.
- **Burst / dedup:** a bad deploy or CI retry loop writes one rollback line per attempt; rows inside the open incident's window extend it rather than opening a new one (the pattern the sibling comments describe — verify against Better Stack behaviour at the first real fire), and a failed re-run *after* the 10-minute auto-resolve opens a new incident. `recovery_period = 600` is the sibling's value, kept as a verbatim copy; the guard does not pin it.
- **Email, not paging:** on the free tier the channel is team email only (escalation applies on the paid tier); wording in the alert, runbook and PR says "alert"/"email", not "page the on-call".
- **`BASELINE_DECLARED_PROBES` counts plans, archive included:** re-count after the plan is final; archiving this plan later does not change it.
