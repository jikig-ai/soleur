---
title: "fix(observability): the open cutover-flip silence incident is the Logs evaluator stuck at 0, not a silent flip unit; invert the alert with a canary (Ref #12726)"
type: fix
date: 2026-11-17
slug: fix-inngest-cutover-flip-silent-stuck-at-zero
branch: feat-one-shot-12726-flip-silent-prd-diagnosis
issue: 12726
closes: none
priority: p1-high
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: single-domain
---

# fix(observability): diagnose the open cutover-flip silence incident (Ref #12726)

**Merging PR-A changes production.** Its push-to-main apply updates `logtail_exploration_alert.inngest_cutover_flip_silent` in place and creates one canary alert pair in Better Stack. The merge is held for the owner's typed go (see Acceptance Criteria, Post-merge).

## Enhancement Summary

**Deepened on:** 2026-11-17
**Sections enhanced:** 9 (Overview, Proposed Solution, Technical Considerations, Files to Edit, Observability, Guard Contract, ADR, Acceptance Criteria, Risks)
**Agents used:** plan review (DHH, Kieran, code-simplicity, CTO devex), CTO rulings F1 to F6, then deepen-plan: a verify-the-negative and self-audit sweep, `soleur:engineering:review:observability-coverage-reviewer`, `soleur:engineering:review:test-design-reviewer`.

### Key Improvements

1. PR-B (the follow-through script) is cut: two dated read-only tracker reads at apply +25 min and +4 h replace it, and PR-C opens on the F2-amended trigger (the first of: +4 h read shows the canary fired, +25 min read shows it absent after more than 20 min live and unpaused, apply +24 h) (CTO F1, F2 amended 2026-11-18; tracker #12878).
2. If the canary never fires, the response is the egress rule (keep the alert armed, poller #12190 next, LUKS deadman meanwhile), not a guessed predicate change (CTO F3). There is no family-wide `lower_than` ban; the flip guard pins its own operator, value and `treat_as_zero` (CTO F4).
3. Guard 1 now closes the static `replace()` no-op hole (whole-line pin, exactly-once host matched to the bootstrap host, consumer counts, anti-collision) and anchors every mutation to its own block.
4. The Observability section cites layer 3 on every failure mode and names a new residual: while the false incident 1051496324 stays open, the alert most likely cannot page on a real silence. The resolve prompt (AC18) is now offered whether or not the canary fired.

### New Considerations Discovered

- `relay_probe_silent_sql` uses a different value form from egress; only the egress form has a proven canary, so the flip copies egress.
- `scripts/betterstack-query.sh` reads rows only; alert state needs the Telemetry alerts API, and incident state the Uptime incidents API, with the token on stdin.
- The workflow applies a saved plan, so the canary `-target=` lines go in the plan step only.

## Overview

Better Stack incident 1051496324 (`soleur-inngest-cutover-flip-silent-prd`, started 2026-11-12T23:45:00Z, still `Started` on 2026-11-17) is mirrored by #12726. The brief asked for the evidence to be pulled from Better Stack and Sentry without SSH, for the measured cause to be named, and for any in-repo fix to ship as a PR that says "Ref #12726".

**Measured cause: the flip unit never went silent.** The Better Stack Logs evaluator reads `Current value: 0` for this `lower_than 1` alert while the identical query returns 2 to 3 rows in every 900 s window. This is the third `lower_than` silence-alert incident in this account opened on healthy data (1045365287, egress 1047829421, this one); a fourth, egress 1031046761, began as a true positive and then stayed open 24 days after the rows returned. The incident was born at the alert's first evaluation after the re-arm (PR #12709), the same shape as incident 1045365287 on 2026-11-02 (#11869). The vendor-internal mechanism is not observable through the API (neither the incident object nor the alert object carries an evaluated value), so the mechanism stays INFERRED, as ADR-218's 2026-11-05 amendment already records for egress.

**The fix** (CTO rulings R1 to R7, the split ruling, and the plan-review rulings F1 to F6, all 2026-11-17) follows the #12180 precedent. The alert is inverted: it reports 1 when the production host sent no object-typed flip row in the window and pages on `higher_than 0`. A throwaway canary proves the evaluator can deliver a non-zero value for the `JSONType` predicate, which the egress canary never exercised. The flip guard pins its own operator, value and `treat_as_zero`, and one dated ADR-218 amendment records the convention (no family-wide ban, F4). The work is split into two PRs:

- **PR-A (this plan's build):** the inversion, the canary pair, the guard and census updates, the ADR-218 amendment, and the comment and runbook rewrites. It is the only production-changing merge.
- **Two dated tracker reads, no script (F1):** at apply +25 min and apply +4 h, each posted as a comment on the tracker issue. The +4 h read is armed in-session with Monitor at the apply.
- **PR-C (the canary retirement PR, tracker #12878; CTO F2 amended 2026-11-18):** retire the canary, the #12189/#12270 way (it keeps the two canary `-target=` lines for its own destroying apply; a follow-up removes them). The canary-removal PR opens at the FIRST of (i) the first tracker read at or after apply +4 h showing the canary incident exists (it fired); (ii) under F3, the +25 min read showing the canary absent while its alert has been live and unpaused for more than 20 min; (iii) apply +24 h, whatever the read shows. The other conditions (no production incident since the apply floor, 1051496324 resolved, the production alert unpaused at `higher_than 0`, object rows present) gate CLOSING #12726 and #12878, not canary removal. If the canary incident recovered, that is a finding for #12190 that blocks closing #12726, not retirement.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief or incident text) | Reality (measured 2026-11-17) | Plan response |
|---|---|---|
| "no JSON inngest-cutover-flip row from the production Inngest host for 15+ min" (incident cause) | 11 to 12 object rows per hour in every hour from 2026-11-12 17:00Z to 2026-11-17 15:00Z. Largest gap between consecutive object rows since 17:10Z Nov 12 is 370 s, against a 900 s window. | The incident is a false positive. The plan fixes the detector, not the flip unit. |
| Candidate causes in the incident text: a revoked, rotated-alone or invalid flip token; a boot-time flip-file write abort; Vector not shipping | Every object row in the last hour is `reason=noop-done`, so the flip token reads Doppler and the script runs. Rows land within seconds in the hot table, so Vector ships. The host booted 17:04Z Nov 12 and has emitted continuously. | All three ruled out by measurement. |
| The incident "started 2026-11-12T23:45Z" | The re-arm apply (run 43333522781) modified the alert at 2026-11-13T00:01:47Z. Before that the alert was paused. | The start time precedes the un-pause: the incident was born at the first evaluation and back-dated, as on 2026-11-02. |
| #12695 "born dark" host | That host (iid 175746057) was destroyed on 2026-11-12. The current host (iid 175859399) passed its isolation check and runs. #12689 tracks the admitted-name fix. | Not this incident. Reconciled, no action here. |
| #11820 (silence alert residuals) | The alert exists and is armed. Replace-window suppression is still open on #11820. | Unchanged; suppression stays out of scope. |
| #12158 / commit 866b08fd51 (new inngest write path) | It changes the arm-token write path used by `op=rollback`/`op=resume`, not the flip unit's read on every tick. The flip unit's `noop-done` rows prove its read path works. | Not causal. No action. |

## Research Insights

### Premise Validation (Phase 0.6)

- #12726: OPEN, labels `priority/p1-high`, `action-required`, `ci/betterstack-incident`; 461 mirror comments, the latest at 2026-11-17T15:46Z, all "Still open". No human comment.
- #12695: OPEN. Its RCA (comment 2026-11-12) is confirmed to mechanism: the destroyed host parked at `isolation-check-FAILED` and never reached bootstrap. That host is gone; the incident here began 6.5 h after the replacement host came up.
- #11820, #12158: OPEN, p3. #12689: OPEN, p2. None closed by a PR.
- Collision pre-check: `SOLEUR_COLLISION exit=10 prs=12865 foreign=none`. PR #12865 is this branch's own draft PR, so there is no foreign collision.
- Mechanism vs ADR corpus: ADR-218's 2026-11-05 amendment (#12180) adopted the inverted missing-count shape for sub-900 s host-roster absence alerts and recorded the canary pattern. The tf comment on this alert pre-records the response: "if the evaluator reads 0 while rows arrive again, the response is the #12180-class measured predicate change, not another silent pause." The plan's mechanism is the one the ADR adopted, not one it rejected.

### Property List (Phase 0.6b)

1. P1: An open flip-silence incident on healthy data does not recur for the reason measured here.
2. P2: A flip unit that fails before the script's first emit (or a dark host) still opens an incident within about 15 minutes.
3. P3: There is positive evidence that the evaluator can deliver a non-zero value for the exact predicate shape used (`JSONType` plus the host pin).
4. P4: The open incident 1051496324 is closed only after the measured read shows rows arriving, and only with the owner's go.
5. P5: The recorded architecture (ADR-218, runbooks, tf comments, guards) matches the shipped alert shape.

### Cut List (Phase 0.6b)

- Re-pausing the alert: buys no listed property (it removes P2). Already rejected by the tf comment and by CTO R1.
- A feeder-fed heartbeat replacing the alert (#12190 pattern): would serve P2, but at hours of latency (hourly feeder, about 66 min archive lag). It stays the fallback on #12190.
- A new `SOLEUR_*` marker: no property needs it; the diagnosis was fully readable from existing rows (CTO R6).
- Replace-window suppression: not in the property list; stays on #11820.

### Value-Proposition Measurement (Phase 0.6c)

Not a cost or performance saving. Skipped.

### Measured evidence (read-only, 2026-11-17 ~15:50Z)

All queries ran through `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh` on source 2457081 (table `t520508_soleur_inngest_vector_prd_3_logs`, hot UNION archive, `_row_type = 1` on the archive arm, deduped on `dt`). The query scripts are in the session scratchpad and are restated in the tasks file so they can be re-run.

- Last 60 minutes, by message type, host `soleur-inngest-prd`: 136 string rows (doppler `Using DOPPLER_CONFIG_DIR...` and `Using DOPPLER_ENABLE_VERSION_CHECK...` lines), 10 object rows (all `reason=noop-done`).
- Hourly object rows, 2026-11-12 17:00Z to 2026-11-17 15:00Z: 11 or 12 every hour (10 in the partial current hour). No hour is missing.
- Largest gaps between consecutive object rows since 17:10Z Nov 12: 370, 366, 366, 365, 364, 362, 360, 360 s.
- The alert's exact SQL replayed on 900 s windows ending 2026-11-12 23:45:00, 2026-11-13 00:05:00, 00:10:00 and 2026-11-15 12:00:00: values 3, 2, 2, 3.
- Incident API (read-only token `BETTERSTACK_API_TOKEN_READONLY`): 1051496324 `status=Started`, `resolved_at=null`, metadata `Current value: 0`, `Operator: lower_than`, `Threshold value: 1`. It is the only open incident in the account.
- Silence-alert incident history since 2026-11-05: 1047829421 (egress, `lower_than`, value 0, resolved via API), 1048111600 (egress, `lower_than`, value 0, resolved with `resolved_by` null), 1048213461 (egress canary, `higher_than`, value 2, resolved), 1051496324 (flip, `lower_than`, value 0, open). Since the egress inversion was applied on 2026-11-06, neither `egress_gw_probe_silent` nor `relay_probe_silent` (same inverted shape, #12292) has opened an incident.
- Heartbeats (read-only): `soleur-inngest-luks-key-probe-deadman-prd` is armed (`paused=false`, `status=up`, period 3600, grace 7200). It is fed hourly from the Logs archive by `scripts/deadman-heartbeat-feeder.sh` (target `inngest-luks-key-probe`, window 93600 s).
- Re-arm apply: run 43333522781, `logtail_exploration_alert.inngest_cutover_flip_silent: Modifications complete after 3s` at 2026-11-13T00:01:47Z.
- Sentry was not needed: the flip unit's own rows decide the question. The born-dark host's `provision_attempt_failed` events (group 132577803) belong to the destroyed host and are already in #12695.

### Relevant files

- `apps/web-platform/infra/betterstack-logs-alerts.tf`: the alert block (`inngest_cutover_flip_silent_sql` local, the exploration and the alert, from the `# inngest_cutover_flip_silent — the flip unit stopped writing` comment to the resource end). The egress precedent is at `egress_gw_probe_silent_sql`; `relay_probe_silent_sql` is the second inverted alert.
- `apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh`: 577 lines, 61 assertions, floor 61, `PRESENCE_ROWS=32`, `MUT_ROWS_EXPECTED=29`. It pins the SQL whole (`EXPECT_SQL`) and `lower_than`/`value = 1`.
- `apps/web-platform/test/infra/egress-gw-alert.test.sh`: the precedent for pinning an inverted canon, a canary derived by `replace()`, block-for-block canary/production equality, and the `lower_than`/`value = 1` revert mutants.
- `apps/web-platform/infra/betterstack-alert-structure.test.sh`: census floors (`CENSUS_FLOOR_ALERTS=22`, `CENSUS_FLOOR_EXPLORATIONS=22`, `GUARD_CENSUS_FLOOR=19`), `INTENDED_DESTROYS`.
- `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`: `EXPECT_BLOCKS=22`.
- `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh`, `apps/web-platform/test/infra/logtail-pair-census.awk`, `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/heartbeat-live-reconcile.test.ts`, `plugins/soleur/test/inngest-alerts-push-probe.test.ts`: read the alerts file; each must be re-run and any count re-derived from its printed output.
- `.github/workflows/apply-web-platform-infra.yml`: the MAIN plan `-target=` allowlist (`-target=logtail_exploration.inngest_cutover_flip_silent` and `-target=logtail_exploration_alert.inngest_cutover_flip_silent`).
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (the `logtail_exploration_alert.inngest_cutover_flip_silent` bullet) and `knowledge-base/engineering/operations/runbooks/inngest-server.md` (the "Silence alert (#11820), ARMED" bullet).
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`: latest amendment "2026-11-13 (#10538)".

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-11-06-an-absence-alert-on-a-zero-filling-evaluator-must-count-the-missing-and-the-fix-narrowed-its-own-input.md`: the template. Count the missing, keep `treat_as_zero`, prove delivery with a canary, and write vendor behaviour that was not observed as unknown.
- `knowledge-base/project/learnings/2026-11-02-a-cadence-i-measured-over-all-rows-was-written-as-the-cadence-of-the-rows-the-alert-counts.md`: measure over the alert's own predicate (object rows only) and scope every universal negative to its observed window. Applied in the evidence above.
- `knowledge-base/project/learnings/2026-11-02-three-hand-copied-lists-and-an-alert-claim-that-outran-its-emitter.md`: the alert census lives in several suites; find them by running them, not by memory.
- `knowledge-base/project/learnings/2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`: the canary needs its own `-target` pair; its later removal needs the destroy ack (PR-C).
- `knowledge-base/project/learnings/2026-10-15-i-claimed-every-covering-suite-had-run-and-the-bounded-gate-found-three-regressions-of-mine.md`: a new suite or a new reader of `betterstack-query.sh` must be registered in the shard manifests and the emitter-read allowlist. PR-A adds neither (the follow-through script was cut, F1), so the rule binds only the census re-runs.
- `knowledge-base/project/learnings/2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`: the canary must be shown able to fire, and every mutation row must prove it changed the file.

### External research

None. The repo carries a working precedent for exactly this shape, and the vendor evaluator is not documented in a way that would decide anything.

### Functional overlap

`soleur:engineering:discovery:functional-discovery`: no community artifact covers this diagnosis or the Terraform shape. Nothing installed.

### CLAUDE.md conventions

`Ref #N`, never Closes/Fixes, for an issue that the vendor mirror closes. Content anchors, not line numbers (`cq-cite-content-anchor-not-line-number`). Any Better Stack write needs the owner's per-command go (`hr-menu-option-ack-not-prod-write-auth`). Pull data yourself (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Problem Statement

The flip-silence alert is the last `lower_than` alert in `betterstack-logs-alerts.tf`. On this account the evaluator reads 0 for every `lower_than` silence alert measured so far, so this alert opens a false incident at its first evaluation and holds it open while rows keep arriving. The false incident has three costs. It trains the reader to ignore this alert. It hides a real silence, because one cannot tell from the incident whether the unit is dark. And it files a "Still open" mirror comment every 15 minutes (461 so far) on a P1 action-required issue.

## Proposed Solution

### The inverted alert (PR-A)

The SQL becomes the ADR-218 host-count canon with a roster of one:

```sql
SELECT toDateTime({{end_time}}) AS time,
       greatest(toInt64(1) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0) AS value
FROM {{source}}
WHERE dt BETWEEN {{start_time}} AND {{end_time}}
  AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') IN ('inngest-cutover-flip')
  AND JSONExtractString(raw, 'host_name') = 'soleur-inngest-prd'
  AND JSONType(raw, 'message') = 'Object'
```

The alert moves to `operator = "higher_than"`, `value = 0`. Kept unchanged: `alert_type = "threshold"`, `check_period = 300`, `query_period = 900`, `confirmation_period = 0`, `recovery_period = 900`, `on_missing_data = "treat_as_zero"`, `paused = false`, email only, `critical_alert = false`, the escalation ternary, the runbook URL. No `GROUP BY`: an aggregate without one always returns one row, so a fully dark window returns 1, not "no data". `incident_cause` keeps its wording and adds that the value is 1 when the production host sent no object row in the window.

The `greatest(toInt64(1) - toInt64(count(DISTINCT ...)), 0)` form is kept on purpose even though the roster is one host: it is the exact value expression of `egress_gw_probe_silent_sql`, the only inverted shape with a proven canary (incident 1048213461, value 2). `relay_probe_silent_sql` uses a second form (`toInt64(N) - least(toInt64(N), toInt64(uniqExact(...)))`) with no canary of its own; copying the egress form keeps the flip alert on the proven one. A plain `1 - count()` would be a third shape with no proven canary. The tf comment says so in one line.

### The canary pair (PR-A)

`logtail_exploration.inngest_cutover_flip_silent_canary` and `logtail_exploration_alert.inngest_cutover_flip_silent_canary`. The canary SQL is derived with `replace()` from the production local, changing only the host pin to `'soleur-inngest-canary-absent'` (no host emits it), and keeping `JSONType`. So it reads 1 on every evaluation and must open an incident that never recovers. The alert block is identical to production apart from name, exploration and `incident_cause`. The canary `incident_cause` starts at byte 0 with the plain-ASCII sentence "CANARY, expected to stay open; do not resolve or close its mirror issue", inside the first 300 bytes after `sanitize` (the mirror runs `head -c 300` on the sanitized cause). Both resources get their own `-target=` lines in the apply workflow's MAIN plan. The canary's mirror issue number is recorded on the tracker at the +25 min read, so nobody acts on it.

**Decision rule, fixed now (CTO F3, replacing R3's predicate swap):** at apply completion plus 25 minutes, if the canary alert is live, unpaused and its `created_at` is older than 20 minutes but no canary incident exists, the evaluator cannot evaluate this predicate shape. An absent canary does not single out one cause: the shape differs from the proven egress canon in three ways (`IN ('inngest-cutover-flip')` on the tag instead of `=`, the `host_name` pin, and the `JSONType` discriminator), and the tf comment records that egress showed the same stuck-at-0 without any `JSONType`. So the response is the egress rule: keep the production alert armed in the inverted shape, raise the heartbeat poller (#12190) to the next work item, and name the LUKS deadman as the interim control. Never revert, never guess a predicate. If the free-tier alert cap refuses the canary at apply, a hotfix PR removes the canary and the change ships with the false-silence residual accepted and named (CTO dissent on R3).

### Guards and records (PR-A)

- The flip guard pins the new canon, its own `operator = "higher_than"`, `value = 0` and `on_missing_data = "treat_as_zero"` on both alerts, the canary derivation, and canary/production equality; new mutation rows revert each. There is no family-wide `lower_than` ban (CTO F4): the structure suite's header contract reserves attribute value pins for per-alert guards, and the evidence covers only silence alerts.
- The ADR-218 amendment, the tf comment rewrite and the two runbook bullets record the shape, the canary rule, the convention, and the residual.

### Tracker reads and canary retirement (PR-C)

Out of PR-A's build, named on the tracker (CTO split condition 1). There is no follow-through script (CTO F1): the incident mirror already files a canary firing and any new production incident as issues, and the two remaining checks (alert shape and pause state, and rows arriving) are read-only calls a dated tracker comment can hold.

Each read (apply +25 min and apply +4 h) records, read-only: the production alert (present, `paused=false`, `higher_than 0`); incident 1051496324 (open or resolved); any production incident started after the apply floor; the canary incident and the canary alert's `created_at` (the apply floor); and the count of object rows in the trailing 900 s. Retirement (CTO F2 amended 2026-11-18, tracker #12878): the canary-removal PR opens at the FIRST of (i) the first tracker read at or after apply +4 h showing the canary incident exists (it fired); (ii) under F3, the +25 min read showing the canary absent while its alert has been live and unpaused for more than 20 min; (iii) apply +24 h, whatever the read shows. The other conditions (no production incident since the apply floor, 1051496324 resolved, the production alert unpaused at `higher_than 0`, object rows present) gate CLOSING #12726 and #12878, not canary removal. If the canary incident recovered, that is a finding for #12190 that blocks closing #12726, not retirement.

## Technical Considerations

- **Update in place.** The only ForceNew attribute on the alert is `exploration_id`, which does not change; the exploration's `sql_query` change is also in place. Per-merge apply plan expected: 2 to add (canary pair), 2 to change, 0 to destroy.
- **The three failure arms the alert covers** (tf comment, #11820): arm 1, the flip unit failing at the Doppler CLI before the script's first emit (revoked, rotated-alone or invalid flip token); arm 2, the boot-time flip-file write abort in the cloud-init runcmd list; arm 3, the LUKS key-continuity probe going silent with the unit. Separately, the alert also reads 1 when the host is dark or Vector stops shipping the tag.
- **The false-silence residual (accepted, CTO R2/R7).** With `treat_as_zero`, an evaluator error or timeout also reads 0, which the inverted alert reads as healthy. Compensating controls, each scoped to what it can see:
  - The canary, for this exact predicate shape, only while it lives. After PR-C retires it, the evaluator-error residual has no positive control; the ADR amendment records that.
  - The LUKS key-probe deadman (`soleur-inngest-luks-key-probe-deadman-prd`, about 26 h to fire) for arms 1 and 3: the probe runs only from the unit's terminal arms. It does NOT cover a Vector-only outage, because its feeder predicate (`KEYPROBE_PRED` in `scripts/deadman-heartbeat-feeder.sh`) also counts the curl phone-home leg (`shipper=cloud-init-phone-home stage=luks-key-probe`), which bypasses Vector. Its coverage of arm 2 is unverified.
  - The server-probe heartbeat (`soleur-inngest-server-probe-prd`) for a dark host.
  - The heartbeat poller (#12190) is the fallback if the evaluator proves blind.
- **A second unexcluded mechanism** (ADR-218, 2026-11-05 amendment, "INFERRED, not measured"): partial visibility or lag of rows in the evaluator's window reads 1 under either operator. Under the inverted shape it would show up as a NEW production incident on healthy data. AC17 reads for it; if such an incident appears while rows are present, the tracker records partial visibility as the INFERRED cause (CTO F6), and the response is the poller (#12190), never a revert.
- **The canary's own noise (accepted cost, CTO F2, #12180 precedent).** `scripts/betterstack-incident-mirror.sh` files every open incident as one `ci/betterstack-incident` issue with `action-required` and `priority/p1-high`, and posts "Still open" on it every run. The canary reproduces that on its own mirror issue for its whole life: about 4 to 5 hours of "Still open" comments between the apply and PR-C (at most about 24 h under the F2-amended rule). The tracker names that issue as expected and not to be acted on; PR-C's apply ends it.
- **The canary vs any `post-deploy-incident-soak` window (known artefact, CTO R-soak 2026-11-18; the same note goes on tracker #12878).** `scripts/followthroughs/post-deploy-incident-soak.sh` FAILs on any Better Stack incident whose `started_at` falls in its 24 h window and on any `ci/`-labelled issue created in it, with no name exclusion. The canary produces one of each (its incident and its `ci/betterstack-incident` mirror issue). So any post-deploy-incident-soak whose 24 h window covers the canary incident's start or its mirror issue's creation FAILs, and a FAIL that cites `soleur-inngest-cutover-flip-silent-canary-prd` or its mirror issue is this known artefact, not a regression of the soaked PR. No code change to the soak probe (ruled); no live tracker ran that soak at review time.
- **The canary's warning bytes.** The mirror cuts the cause with `head -c 300` after `sanitize` (`scripts/betterstack-incident-mirror.sh`, the `cause="$(sanitize "$cause" | head -c 300)"` line), so the limit is bytes. The warning is plain ASCII and starts at byte 0.
- **Incident 1051496324 will probably not clear by itself.** The egress anchor incident needed an API resolve after its inversion. Whether an in-place update closes an open incident is unverified vendor behaviour.
- **NFR impact:** observability only (detection fidelity for the Inngest host). No performance or security change.

## Files to Edit (PR-A)

- `apps/web-platform/infra/betterstack-logs-alerts.tf`: new SQL in `inngest_cutover_flip_silent_sql`; `operator`/`value` on the alert; `incident_cause` addition; new `inngest_cutover_flip_silent_canary_sql` local (derived with `replace()`), canary exploration and alert; rewrite the "WAS PAUSED PENDING #11869", "WINDOW" and "INCIDENT LIFECYCLE" comment paragraphs into a record of what was done, plus the false-silence residual.
- `.github/workflows/apply-web-platform-infra.yml`: two `-target=` lines for the canary pair in the MAIN plan step, next to the production pair. The workflow plans once into a saved `tfplan` file (`terraform plan ... -out=tfplan`) and a later step consumes that file, so the lines go in the plan step only.
- `apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh`: header text; `EXPECT_SQL`; operator/value rows; no-`GROUP BY` row; canary rows; new mutation rows; `PRESENCE_ROWS`, `MUT_ROWS_EXPECTED` and the assertion floor re-derived from a run.
- `apps/web-platform/infra/betterstack-alert-structure.test.sh`: census floors re-derived from its printed output (+1 alert, +1 exploration). No new row: its header contract ("No family-wide attribute VALUE pins") stays as it is (CTO F4).
- `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`: `EXPECT_BLOCKS` re-derived (+1).
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`: its M17 row asserts `s.count("    values        = [local.vector_prd_source_id]") == 22` and a comment lists the twenty-two; the canary exploration makes it 23 (the egress precedent, commit d1f7602ef8, edited this file).
- `.github/workflows/infra-validation.yml`: the flip guard's step comment says "both -target lines", which is stale once the canary adds two more; update it to name the four (the egress precedent edited its step comment). It does not mention `lower_than`. The run line itself does not change.
- Every other suite that reads the alerts file (list under Relevant files): run each; edit only those whose printed counts move.
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`: one short dated amendment, appended after "2026-11-13 (#10538)" (CTO F5). The 2026-11-05 amendment's "today only `egress_gw_probe_silent`" is a status note, so it gets a bracketed status pointer, not a scope change.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: rewrite the `inngest_cutover_flip_silent` bullet in the egress form (`higher_than 0`, missing-count, the canary, the resolve rule).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: rewrite the "Silence alert (#11820), ARMED" bullet: an open incident while rows arrive points to the poller (#12190), never a revert; a resolve needs the owner's go.

## Files to Create (PR-A)

None. (`knowledge-base/project/specs/feat-one-shot-12726-flip-silent-prd-diagnosis/{tasks.md,decision-challenges.md}` are planning artifacts.)

## Implementation Phases (PR-A)

1. **RED first.** Edit the flip guard to the target shape (new canon, `higher_than`/0/`treat_as_zero` on both alerts, canary rows, the replace()-no-op and exact-count rows, new mutation rows). Run it; it must fail on the current tree for the expected reasons.
2. **GREEN.** Edit `betterstack-logs-alerts.tf` (SQL, operator, value, cause, canary local and pair) and the two `-target` lines. Run the flip guard to green.
3. **Census.** Run every suite that reads the alerts file; re-derive each moved count from its printed output, never by hand arithmetic.
4. **Records.** Write the tf comment rewrite, the ADR-218 amendment, the two runbook bullets. Run the flip guard again (it reads both runbooks) and `lint-infra-no-human-steps.py --changed --base origin/main`.
5. **Plan check.** `terraform validate` and a read-only `terraform plan` with the MAIN `-target` list, recipe from `infra-credential-tiers-8209.md` §Local Terraform invocation (prd_terraform read pair). Expect 2 to add, 2 to change, 0 to destroy. If no plan can run locally, record the CI plan from the PR instead.
6. **Tracker.** File the tracker issue (Class R) before PR-A is marked ready (CTO split condition 1). It names the two reads and what each records, the canary decision rule (F3), the PR-C gate (F2 amended, AC20), the canary's mirror issue as an accepted cost, and the earliest time of the +4 h read, so a later session can run it if this one ends.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/betterstack-logs-alerts.tf` in the existing root (R2 backend unchanged). Provider `logtail` as already pinned. No new variable, no new sensitive value.

### Apply path

The per-merge push apply (`apply-web-platform-infra.yml`, MAIN plan with an explicit `-target=` list). In place for the production pair, create for the canary pair. No host is touched, no downtime. Reversible by a revert PR (the revert would restore the misfiring shape, so the ADR records "poller, never a revert" as the response to a recurrence).

### Host fan-out

Not applicable: no `terraform_data` or SSH provisioner is involved.

### Distinctness / drift safeguards

Production source only (`local.vector_prd_source_id`); the host pin keeps a dev or web host from satisfying either alert. No `lifecycle` or `ignore_changes` on either pair (the flip guard already reds on one).

### Vendor-tier reality check

The Logs-alert cap on the free tier is undocumented. The canary raises the managed count by one (to 23). If the apply is refused, the pre-decided response is a hotfix PR that removes the canary (CTO dissent on R3).

## Observability

```yaml
liveness_signal:
  what: "Better Stack Logs alert soleur-inngest-cutover-flip-silent-prd: value 1 when no object-typed inngest-cutover-flip row from soleur-inngest-prd arrived in 900 s; plus canary soleur-inngest-cutover-flip-silent-canary-prd, which is expected to stay open"
  cadence: "evaluated every 300 s over a 900 s window; the flip unit emits one noop row per 300 s"
  alert_target: "email via the Better Stack escalation target (free/paid ternary); the incident mirror files a ci/betterstack-incident issue"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (inngest_cutover_flip_silent, inngest_cutover_flip_silent_canary)"

error_reporting:
  destination: "Better Stack incident list (read-only API) and the GitHub incident mirror (scripts/betterstack-incident-mirror.sh)"
  fail_loud: "a production incident named soleur-inngest-cutover-flip-silent-prd with metadata Operator higher_than and Current value 1"

failure_modes:
  - mode: "arm 1: flip unit fails at the Doppler CLI before the script's first emit (revoked, rotated-alone or invalid flip token)"
    detection: "layer 3 (Vector journald shipper on the Inngest host, apps/web-platform/infra/vector.toml rendered by inngest-bootstrap.sh, to Logs source 2457081) -> Logs alert reads 1 (no object row from the host in 900 s); backstop: layer 3 rows read through the query API by scripts/deadman-heartbeat-feeder.sh -> LUKS key-probe deadman heartbeat lapses after about 26 h"
    alert_route: "email plus the mirror issue; deadman heartbeat email"
  - mode: "arm 2: boot-time flip-file write abort in the cloud-init runcmd list"
    detection: "layer 3 (Vector journald shipper on the Inngest host, apps/web-platform/infra/vector.toml rendered by inngest-bootstrap.sh, to Logs source 2457081) -> Logs alert reads 1; the LUKS deadman's coverage of this arm is unverified (accepted residual)"
    alert_route: "email plus the mirror issue"
  - mode: "arm 3: LUKS key-continuity probe silent with the unit"
    detection: "layer 3 (Vector journald shipper on the Inngest host, apps/web-platform/infra/vector.toml rendered by inngest-bootstrap.sh, to Logs source 2457081) -> Logs alert reads 1; layer 3 rows read by scripts/deadman-heartbeat-feeder.sh -> LUKS deadman (about 26 h)"
    alert_route: "email plus the mirror issue; deadman heartbeat email"
  - mode: "Inngest host dark"
    detection: "layer 3 (Vector journald shipper on the Inngest host, apps/web-platform/infra/vector.toml rendered by inngest-bootstrap.sh, to Logs source 2457081) -> Logs alert reads 1; layer 3 rows read by scripts/inngest-probe-heartbeat-feeder.sh -> soleur-inngest-server-probe-prd heartbeat lapses"
    alert_route: "email plus the mirror issue; heartbeat email"
  - mode: "Vector stops shipping the inngest-cutover-flip tag while the host runs"
    detection: "layer 3 itself is the broken leg -> Logs alert reads 1 (no rows arrive). The LUKS deadman does not see this arm: its feeder also counts the curl phone-home leg, which bypasses Vector"
    alert_route: "email plus the mirror issue"
  - mode: "real silence while the false incident 1051496324 is still open (an open incident most likely absorbs new value-1 evaluations: no new incident, no new email)"
    detection: "not by this alert until 1051496324 is resolved; covered meanwhile by the two heartbeat feeders, which read layer 3 rows through the query API and so do not depend on the Logs evaluator (accepted residual, bounded by AC18)"
    alert_route: "deadman and server-probe heartbeat email"
  - mode: "partial visibility or lag in the evaluator's window (ADR-218 2026-11-05, unexcluded)"
    detection: "layer 3 (Vector journald shipper on the Inngest host, apps/web-platform/infra/vector.toml rendered by inngest-bootstrap.sh, to Logs source 2457081) rows present while a new production incident opens, read by AC17 value 3"
    alert_route: "the tracker comment; response is the poller #12190, never a revert"
  - mode: "evaluator cannot evaluate this predicate shape (would read 0, healthy, under the inverted shape)"
    detection: "layer 3 (Vector journald shipper on the Inngest host, apps/web-platform/infra/vector.toml rendered by inngest-bootstrap.sh, to Logs source 2457081) -> canary Logs alert has no open incident 20 minutes after it is live and unpaused (AC17 value 4)"
    alert_route: "the apply +25 min and +4 h reads recorded on the tracker; response is the egress rule (poller #12190 next, LUKS deadman interim)"
  - mode: "evaluator error or timeout reads 0 under treat_as_zero (accepted residual)"
    detection: "the canary while it lives; after PR-C, the two heartbeat feeders (they read layer 3 rows through the query API, independent of the evaluator) for arms 1 and 3 and a dark host only, not arm 2 (unverified) and not a Vector-only outage; fallback is the heartbeat poller #12190"
    alert_route: "heartbeat email"
logs:
  where: "Better Stack Logs source 2457081 (table t520508_soleur_inngest_vector_prd_3_logs, hot) and its _s3 archive"
  retention: "hot window about 40 minutes, archive per the Better Stack plan; read with scripts/betterstack-query.sh"

discoverability_test:
  command: grep -c -e 'resource "logtail_exploration_alert" "inngest_cutover_flip_silent_canary"' apps/web-platform/infra/betterstack-logs-alerts.tf
  expected_output: "1"
```

### Soak follow-through enrollment

The 4 h soak conditions (canary fired, production alert live and `higher_than 0`, incident 1051496324 resolved, no new production incident since the apply floor minus 300 s, object rows in the trailing 900 s) gate closing #12726 and #12878, not the canary's removal, which follows the F2-amended trigger (AC20). Per CTO F1 the 4 h read is NOT enrolled in the follow-through sweeper: there is no script. Its enrollment is (a) a Monitor until-loop armed in-session at the apply that fires at apply +4 h and runs the read, and (b) the tracker's stated earliest time, so a later session runs it if this one ends. The fail-safe is structural: under the F2-amended rule PR-C opens at the latest at apply +24 h, whatever the reads show, so a missed read bounds the canary's noise at about a day and never leaves the production alert blind; closing #12726 and #12878 still needs the soak conditions.

## Encryption Posture

```yaml
at_rest: []
# No persistent store is introduced. The change edits two existing Logs alert resources and adds a
# canary pair in the same vendor account; it stores no new data and creates no new log sink.
in_transit:
  - connection: "GitHub Actions apply job (logtail provider) -> Better Stack Telemetry API"
    enforced_at: "apps/web-platform/infra/main.tf provider \"logtail\" (api_token only; no TLS override anywhere under apps/web-platform/infra/, grep for insecure/skip_tls finds only the unrelated cloudflare-lb.tf allow_insecure = false)"
    tls: "HTTPS, provider default Go TLS client"
    cert_verification: "on"
    does_not_defend: "a leaked BETTERSTACK_API_TOKEN, which can rewrite or pause any alert; a compromised apply runner"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — flip-silent alert shape guard (`inngest-cutover-flip-silent-alert.test.sh`)

**Property.** The flip-silence alert pages exactly when no object-typed `inngest-cutover-flip` row from `soleur-inngest-prd` reached the prd source in the window, in a shape whose evaluator zero reads healthy (`higher_than 0`, `value = 0`, `treat_as_zero`, pinned on both alerts, CTO F4), and its canary is the production query with only the host pin swapped.

**Assembly.** The chokepoints are the `inngest_cutover_flip_silent_sql` heredoc (the only producer of both SQL strings, since the canary local is derived from it by `replace()`), the two `logtail_exploration_alert` blocks (`inngest_cutover_flip_silent`, `inngest_cutover_flip_silent_canary`) and their explorations, the MAIN plan `-target=` slice of `apply-web-platform-infra.yml`, the emitter tag in `inngest-cutover-flip.sh`, the host literal in `inngest-bootstrap.sh`, and the guard's own registration in `infra-validation.yml`.

**replace() is static text to the guard.** The guard never evaluates HCL, so it closes the no-op hole with presence rows rather than by computing the canary SQL (the egress `CANARY_LINE` form, commit d1f7602ef8):

- the `replace()` line is pinned as one whole line (`grep -cFx` equals 1): `inngest_cutover_flip_silent_canary_sql = replace(local.inngest_cutover_flip_silent_sql, "'soleur-inngest-prd'", "'soleur-inngest-canary-absent'")`;
- on the flattened production local (`LOCAL_SQL`), `'soleur-inngest-prd'` appears exactly once, and it equals the host the guard already reads from `inngest-bootstrap.sh` (`BS_HOST`), so the existing host-rename row also covers the search text;
- the production local has exactly 2 consumers (the production exploration and the `replace()` line) and the canary local exactly 1 (the canary exploration);
- `soleur-inngest-canary-absent` appears nowhere under `apps/web-platform/infra/` except the `replace()` line (anti-collision: no host or Vector config may emit it);
- the canary `incident_cause` starts with `CANARY, expected to stay open; do not resolve or close its mirror issue` (byte 0);
- each name literal (`soleur-inngest-cutover-flip-silent-prd`, `soleur-inngest-cutover-flip-silent-canary-prd`) appears exactly twice (exploration and alert), and exactly one alert carries `exploration_id = logtail_exploration.inngest_cutover_flip_silent.id`;
- the `inngest_cutover_flip_silent*` resource headers number exactly 4 (2 alerts, 2 explorations), counted across every `*.tf` under `apps/web-platform/infra/` in the effective HCL text (review round 1: a commented-out header no longer counts, one behind a same-line `/* */` does; not anchored to line start). PR-C moves this to 2.

**Header contract.** The guard's header text states the new canon and the pinned triple. `PRESENCE_ROWS`, `MUT_ROWS_EXPECTED` and the assertion floor are re-derived from a run of the guard after the rows below land, never by hand.

**Row anchoring.** Every mutation on `operator`, `value`, `check_period` or `on_missing_data` is anchored to its own resource block (the existing A4/A13 regex form). A file-wide replace would land on one of the other alerts and report SURVIVED for the wrong reason. Rows that share the whole-SQL comparison (3, 4, 5) each assert their own expected `[FAIL]` text: the value-expression row, the no-`GROUP BY` row, the roster-literal row.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `operator` reverted to `"lower_than"` on the production alert | RED |
| 2 | `value` reverted to `1` on the production alert | RED |
| 3 | SQL value expression reverted to `count(*) AS value` | RED (value-expression row) |
| 4 | a `GROUP BY time` appended to the production SQL | RED (no-`GROUP BY` row) |
| 5 | `toInt64(1)` changed to `toInt64(0)` in the production SQL (the value would be 0 forever) | RED (roster-literal row) |
| 6 | the canary local stops deriving from the production local (a hand-copied SQL string) | RED |
| 7 | the canary's `replace()` swaps the tag instead of the host pin | RED |
| 8 | the `replace()` search text drifts (`"'soleur-inngest-prod'"`) while the production SQL is unchanged (the `replace()` becomes a no-op) | RED |
| 8b | the `replace()` replacement set to the real host `'soleur-inngest-prd'` | RED |
| 8c | the canary exploration's `sql_query` pointed at `local.inngest_cutover_flip_silent_sql` | RED |
| 9 | the canary alert's `check_period` drifts from production's (block equality) | RED |
| 9b | the production alert alone gains a changed attribute (block equality, production side) | RED |
| 9c | the canary alert alone gains an extra attribute (proves the strip step hides no real difference) | RED |
| 10a | `operator = "lower_than"` set on the canary alert | RED |
| 10b | `on_missing_data` changed on the canary alert (the production half is existing row A4) | RED |
| 11 | one canary `-target=` line removed | RED |
| 12 | the `JSONType` discriminator dropped (existing row A1, still RED) | RED |
| 13 | the guard's run step made `continue-on-error` (its own dispatch; existing row A5) | RED |
| 14 | a fifth `inngest_cutover_flip_silent*` resource header added | RED |
| 14a | the canary alert's `name` changed from `soleur-inngest-cutover-flip-silent-canary-prd` (AC17 and the mirror lookup key on it) | RED |
| 14b | a decoy exploration and alert pair under a different label carrying the canary name | RED |
| 15 | text inserted before the CANARY warning in the canary `incident_cause` | RED |
| 16 | `soleur-inngest-canary-absent` added to another file under `apps/web-platform/infra/` | RED |
| 17 | must-PASS: the production SQL reflowed across different line breaks and indentation | PASS |
| 18 | must-PASS: a comment line inside the production alert block that mentions `lower_than` (the record of the old shape; any operator count reads non-comment lines only) | PASS |

**Instrument self-test (not a battery row).** The existing `mutate()` helper counts a mutation that did not land as a failure, so a deliberately non-landing battery row would keep the suite red forever. The self-test runs once before the battery instead: it feeds the landing heredoc a program that matches nothing, requires the inner python to exit non-zero, and records `ok`. It is a presence row, not a `MUT_ROWS_EXPECTED` row.

Rows 3, 4 and 12 stay although DHH proposed trimming them: each reverts a distinct way the alert goes silent-blind, and the egress guard pins the same three (`egress-gw-alert.test.sh`). See `decision-challenges.md`.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-218 with one short dated amendment, "2026-11-17 (#12726): the flip-silence alert reports a missing count" (CTO F5). It does not widen anything: the 2026-11-05 (#12180) scope, "sub-900 s host-roster absence alerts on a multiplexed source", already covers a pinned roster of one on the prd Vector source. It records: the measured evidence above; the rule applied to this alert; the convention that each absence alert's own guard pins `higher_than 0`, `value = 0` and `treat_as_zero` (no family-wide pin, F4); the false-silence residual and its compensating controls, including that after the canary's retirement the evaluator-error residual has no positive control; the canary, its decision rule (the egress rule, F3) and its planned retirement in PR-C; and "an open incident with rows arriving means the poller (#12190), never a revert". The 2026-11-05 amendment's "today only `egress_gw_probe_silent`" status note gets a bracketed pointer. No ADR-282 amendment: ADR-282 never states the alert's shape, and what the alert detects does not change (CTO R4).

### C4 views

No C4 impact, checked. The three model files were checked for the elements this change touches. The external system `betterstack` (model.c4, `betterstack = system "Better Stack"`) is modelled. The edge `inngest -> betterstack` ("Ships journald + host_metrics via Vector ... to Logs source 2457081") is modelled. No new actor, system, container or access relationship is introduced: the change edits an alert inside an already-modelled vendor. `model.c4` names no per-alert operator. `plugins/soleur/test/c4-count-parity.test.sh` was run on this tree: 13 passed, 0 failed. Re-run it after PR-A's census change, because the managed Logs alert count moves from 22 to 23.

### Sequencing

The ADR amendment lands in PR-A and describes the shipped state, including the canary's planned retirement. PR-C adds no amendment (CTO F5): stating the retirement up front would make a second amendment a deploy log.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The indirect path: a broken inverted alert stays quiet while the flip unit fails before its first emit, so a rollback path on the sole Inngest scheduler host is dead without a page until the LUKS deadman fires (about 26 h). Scheduled agent runs keep working in that window; recovery from a later scheduler fault is slower.
- **If this leaks, the user's data is exposed via:** no vector. The change edits alert SQL over operator telemetry rows that carry no user data.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** an alert-shape change with no user data and no user-facing surface; a regression degrades detection latency on operator infrastructure, bounded by the canary and the LUKS deadman.

*Scope-out override:* `threshold: none, reason: the diff touches apps/web-platform/infra/ only to change a Better Stack alert's SQL and comparator and to add a canary alert; it reads operator telemetry, stores nothing, and no user-facing path consumes it.`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "diagnose #12726 — Better Stack incident `soleur-inngest-cutover-flip-silent-prd` (incident id 1051496324, started 2026-11-12T23:45Z)" [brief] | Overview, Research Reconciliation, Measured evidence | mapped |
| 2 | "Self-pull the evidence from Better Stack/Sentry (no SSH, no operator fetch)" [brief] | Measured evidence (betterstack-query.sh and the read-only incident API) | mapped |
| 3 | "name the measured cause" [brief] | Overview "Measured cause" | mapped |
| 4 | "ship any in-repo fix or missing SOLEUR_* marker as a PR that says \"Ref #12726\" (never Closes/Fixes)" [brief] | PR-A Files to Edit; AC "PR body says Ref #12726"; no SOLEUR_* marker needed (CTO R6) | mapped |
| 5 | "the diagnosis must read and reconcile against before naming a cause — #12695 ... #11820 ... #12158 ... and #12689" [brief, collision context] | Research Reconciliation rows | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Inverted SQL and comparator in `betterstack-logs-alerts.tf` | "ship any in-repo fix" | asked |
| Canary pair and its `-target` lines | — | inferred — justification: CTO R3; without it the inverted alert can be blind on the untested `JSONType` predicate and nothing would show it |
| Flip guard updates | — | inferred — justification: the guard pins the old canon and would red on the fix; the drift pin rots otherwise |
| Flip guard pins its own operator, value and `treat_as_zero` | — | inferred — justification: CTO F4 (replaces R7(b)'s family-wide ban); stops a fifth recurrence on this alert |
| Census and count re-derivations | — | inferred — justification: the suites red on a +1 alert pair |
| ADR-218 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; records the evidence, convention, residual and canary (CTO F5) |
| Runbook and tf comment rewrites | — | inferred — justification: both say the predicate is unchanged and the stuck-at-0 can recur; they would be false after the fix |
| Tracker issue with the two dated reads and the PR-C gate | — | inferred — justification: CTO split condition 1 and F1/F2; the canary needs an owner between merges |

### Split Assessment

- Subsystems touched (PR-A): 3 — apps/web-platform, .github, knowledge-base
- Planned files (PR-A): about 9 | Estimated changed lines: about 600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — PR-A (inversion, canary, guards, ADR, runbooks) / PR-C (canary retirement, opened on the F2-amended trigger: the first of the +4 h read showing it fired, the +25 min read showing it absent, apply +24 h). Ruled by the CTO agent on 2026-11-17 (split ruling, amended by F1: PR-B cut); the split is driven by the soak, not by size.

## Acceptance Criteria

<!-- founder-stated check: the brief's own words were "name the measured cause" and "a PR that says Ref #12726"; AC1 and AC2 are those checks. -->

### Pre-merge (PR-A)

- [ ] AC1: The PR body states the measured cause in one paragraph (evaluator reads 0 on a `lower_than` alert while 2 to 3 rows per window arrive; max gap 370 s; incident born at the first evaluation after the 2026-11-13T00:01:47Z un-pause) and cites the read-only commands that produced each number.
- [ ] AC2: The PR body says `Ref #12726` and contains no `Closes`/`Fixes`/`Resolves` keyword for 12726, 12695, 11820, 12158 or 12689: `gh pr view <N> --json body --jq .body` piped to `grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #(12726|12695|11820|12158|12689)'` prints `0`.
- [ ] AC3: The PR body's first line answers "does merging this alone change production?": yes, the per-merge apply updates the flip alert in place and creates the canary pair.
- [ ] AC4: `bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh` exits 0 and its summary line reports the re-derived assertion floor; every Guard 1 mutation row (1 to 18 with the lettered rows) is present and reports as listed, and the instrument self-test passes.
- [ ] AC5: `bash apps/web-platform/infra/betterstack-alert-structure.test.sh` exits 0 with its census floors re-derived; its header contract text is unchanged (`git diff origin/main -- apps/web-platform/infra/betterstack-alert-structure.test.sh` touches only the floor values).
- [ ] AC6: With comment lines stripped (`grep -v '^[[:space:]]*#' apps/web-platform/infra/betterstack-logs-alerts.tf`), the count of `operator *= *"higher_than"` is the `origin/main` count from the same command plus 2, and the count of `operator *= *"lower_than"` is `0` (measured on `origin/main` 2026-11-17: higher_than `21`, lower_than `1`; expected after the change: higher_than `23`, lower_than `0`).
- [ ] AC7: The production SQL, collapsed to one line, equals the Proposed Solution SQL; the canary SQL equals it with only `'soleur-inngest-prd'` replaced by `'soleur-inngest-canary-absent'` (asserted by the flip guard, not by hand).
- [ ] AC8: Both canary `-target=` lines are in the MAIN plan slice of `apply-web-platform-infra.yml`, and `plugins/soleur/test/terraform-target-parity.test.ts` passes.
- [ ] AC9: Every suite listed under Relevant files that reads the alerts file passes; each moved count (census floors, `EXPECT_BLOCKS`, any other) was re-derived from that suite's printed output, and the PR body lists old and new value per suite.
- [ ] AC10: The ADR-218 amendment exists with the heading given above, contains no "widen" wording (`grep -ci 'widen'` over the new amendment's text prints `0`), and names the canary's planned retirement; the 2026-11-05 amendment's "today only" status note carries a bracketed pointer to it; `plugins/soleur/test/c4-count-parity.test.sh` passes after the change.
- [ ] AC11: No stale shape claim survives in the three files that carry one, checked one file per grep. Each of these prints `0`:
  - `grep -c -e 'predicate is UNCHANGED' -e 'stuck-at-0 can recur' apps/web-platform/infra/betterstack-logs-alerts.tf`
  - `grep -c -e 'predicate is UNCHANGED' -e 'stuck-at-0 can recur' knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
  - `grep -c -e 'predicate is UNCHANGED' -e 'stuck-at-0 can recur' knowledge-base/engineering/operations/runbooks/inngest-server.md`

  (Measured on 2026-11-17: the tf file and `betterstack-log-query.md` carry "predicate is UNCHANGED"; both runbooks carry "stuck-at-0 can recur".)
- [ ] AC12: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes.
- [ ] AC13: A CI `terraform plan` for the MAIN target list (or a local read-only plan) shows 2 to add, 2 to change, 0 to destroy, and the PR body quotes the plan line.
- [ ] AC14: The tracker issue (Class R) exists before PR-A is marked ready and carries `Ref #12726`. It names: the two reads and the six values each records (AC17); the earliest time of the +4 h read; the PR-C gate (AC20); the canary decision rule (the egress rule, AC19); and the canary's coming mirror issue as an accepted cost, not to be acted on.
- [ ] AC15: The prepush secret scan runs clean before every push.

### Post-merge (owner-authorized steps)

- [ ] AC16: **Owner authorizes:** `gh pr merge <N> --squash --auto` for PR-A, as a typed go naming that exact command (or a valid standing delegation). No merge while another merge is queued. After the merge, a Monitor until-loop watches the `apply-web-platform-infra.yml` push run to a conclusion (`hr-dispatch-async-must-arm-watch`), and the session emits a resume prompt naming the run id, the tracker, and the two read times.
- [ ] AC17: At apply completion plus 25 minutes, the session reads (read-only, under `doppler run -p soleur -c prd_terraform`) and posts as one dated comment on the tracker (CTO split condition 2, F1). Values 1 and 5 come from `GET https://telemetry.betterstack.com/api/v2/alerts?per_page=50`; values 2 to 4 from `GET https://uptime.betterstack.com/api/v3/incidents`; value 6 from `scripts/betterstack-query.sh`. The read-only token goes on stdin, never argv, in the `canary-probe-set.md` form (`printf 'Authorization: Bearer %s\n' "$BETTERSTACK_API_TOKEN_READONLY" | curl --disable --noproxy "*" -sS --max-time 30 --header @- <url>`), one URL per call, summarised with `jq`:
  1. the production alert: present, `paused=false`, `operator=higher_than`, `value=0`;
  2. incident 1051496324: open or resolved;
  3. any `soleur-inngest-cutover-flip-silent-prd` incident started after the apply floor (value 5) minus 300 s; if one exists while object rows are present, the comment records partial visibility in the evaluator window as the INFERRED cause, and the response is the poller (#12190), never a revert; a resolve needs the owner's go (CTO F6);
  4. the canary incident `soleur-inngest-cutover-flip-silent-canary-prd` (exists or absent) and the number of its mirror issue, found by the mirror's body marker: `gh issue list --label ci/betterstack-incident --state open --json number,body --jq '.[] | select(.body | contains("betterstack-incident id=<canary incident id>")) | .number'`;
  5. the canary alert object's `created_at`, which is the apply floor for value 3 and for the +4 h read;
  6. the count of object rows from `soleur-inngest-prd` in the trailing 900 s.
- [ ] AC17a: If the apply run fails or applies only part of the target list (for example the vendor cap refuses the canary), the +25 min read is replaced by a read of what did apply, posted on the tracker, and a hotfix PR is opened (remove the canary, or complete the change). Merging that hotfix is its own owner go row: `gh pr merge <hotfix N> --squash --auto`, typed, naming the command.
- [ ] AC17b: At the apply, a Monitor until-loop is armed to fire at apply +4 h. When it fires, the session repeats the AC17 read and posts it as a second dated tracker comment. If the session has ended, the tracker's earliest time lets a later session run it. PR-C opens on the F2-amended trigger either way, at the latest at apply +24 h (AC20).
- [ ] AC18: **Owner authorizes** (only if AC17 shows the inverted alert live, object rows arriving and 1051496324 still open; offered in the canary-absent branch too, because while it stays open the alert most likely cannot page on a real silence). The prompt to the owner is self-contained: "Incident 1051496324 (`soleur-inngest-cutover-flip-silent-prd`) is a false positive: the inverted alert is live, its canary <fired | did not fire>, and N object rows arrived in the last 900 s (tracker comment <link>). While it stays open, a real flip failure most likely opens no new incident. Resolving it lets the mirror close #12726. To approve, type: go `POST https://uptime.betterstack.com/api/v2/incidents/1051496324/resolve`." The call uses the write token only after that typed go. After it, the incident mirror closes #12726 on its next run.
- [ ] AC19: If AC17 shows the canary absent (canary alert live, unpaused, `created_at` older than 20 minutes, no canary incident), the egress rule applies (CTO F3): the production alert stays armed in the inverted shape, #12190 (heartbeat poller) is raised to the next work item with the measured reads attached, and the LUKS deadman is named on the tracker as the interim control. No revert, no predicate change. The AC18 resolve prompt is still put to the owner.
- [ ] AC20: PR-C (canary retirement, tracker #12878) follows the F2-amended rule (CTO 2026-11-18): the canary-removal PR opens at the FIRST of (i) the first tracker read at or after apply +4 h showing the canary incident exists (it fired); (ii) under F3, the +25 min read showing the canary absent while its alert has been live and unpaused for more than 20 min; (iii) apply +24 h, whatever the read shows. The other conditions (no production incident since the apply floor, 1051496324 resolved, the production alert unpaused at `higher_than 0`, object rows present) gate CLOSING #12726 and #12878, not canary removal. If the canary incident recovered, that is a finding for #12190 that blocks closing #12726, not retirement. PR-C's flip-guard exact-count row moves from 4 to 2 headers; it needs the target-scoped destroy ack for the canary pair.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled R1 to R7 and the split on 2026-11-17, then F1 to F6 on the plan-review findings the same day (all recorded in `decision-challenges.md`). Invert the alert to the ADR-218 host-count canon with a roster of one; keep `treat_as_zero`, `JSONType` and the host pin; add a throwaway canary that swaps only the host pin; pin the operator, value and `treat_as_zero` in the flip guard, not family-wide; write one short ADR-218 amendment; hold the merge and the incident resolve for the owner's typed go; replace the follow-through script with two dated tracker reads; retire the canary in PR-C after the +4 h read passes; if the canary never fires, follow the egress rule. No new `SOLEUR_*` marker.

Product, Marketing, Legal, Operations, Finance, Sales and Support: no implications. The change is internal alerting with no user-facing surface, no data processing and no cost line beyond one Logs alert slot.

## Test Scenarios

- Scenarios 1 to 3 below are one-time live evidence for the PR body, not repeatable tests: they depend on the network and on live data. Scenario 3 runs a changed predicate as a stand-in, so it does not exercise the shipped SQL.
- Given the new SQL and a 900 s window holding 2 object rows from `soleur-inngest-prd`, when the query runs, then the value is 0 (integration, read-only, via `betterstack-query.sh` with `{{...}}` substituted).
- Given a window with no matching row (simulate with the canary's host pin), when the query runs, then the value is 1 (integration, read-only).
- Given a window holding only string-typed doppler rows under the tag, when the query runs, then the value is 1 (the `JSONType` discriminator; integration, read-only, a window filtered to `JSONType = 'String'` used as the stand-in).
- Given each Guard 1 mutation row, when the suite runs, then it reports the listed RED or PASS (unit, the guard's own mutation battery).
- Regression: given the tree after the change, the comment-stripped count of `operator *= *"lower_than"` over the alerts file is `0` (unit, AC6).
- API verify (post-merge, read-only, token on stdin): `doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://uptime.betterstack.com/api/v3/incidents?per_page=50&resolved=false"' | jq -r '.data[].attributes.name'` lists `soleur-inngest-cutover-flip-silent-canary-prd`.

## Open Code-Review Overlap

2 open code-review issues touch files this plan edits:

- #12784 (anchor `inngest_luks_wrong_volume` needles on both sides) touches `betterstack-logs-alerts.tf`. **Acknowledge:** a different alert's predicate; folding it in would widen a production-changing merge beyond its ruling.
- #7098 (audit `run:` bodies whose `set` omits `-e`) touches `apply-web-platform-infra.yml`. **Acknowledge:** a repo-wide lint audit; this plan adds two `-target=` lines and no `run:` body.

## Dependencies & Risks

- **Vendor alert cap.** Undocumented; a refused canary create blocks the per-merge apply. Pre-decided response: hotfix PR removing the canary.
- **Canary absent.** The evaluator cannot evaluate this predicate shape (three confounders, not one); the response is the egress rule (AC19).
- **A new production incident on healthy data.** Partial visibility in the evaluator window (INFERRED, ADR-218 2026-11-05); the response is the poller, never a revert (AC17 value 3).
- **Incident does not self-clear.** Expected; AC18 handles it with the owner's go.
- **Merge queue.** Push nothing while a merge is queued (standing limit).
- **Precedent diff (deepen-plan 4.4).** Against `egress_gw_probe_silent_sql` on `origin/main`, the proposed SQL keeps the value expression, `FROM {{source}}` and `dt BETWEEN` verbatim, and differs in four places: the roster constant (`toInt64(1)` vs `toInt64(${length(var.web_hosts)})`); the tag test (`IN ('inngest-cutover-flip')` vs `= 'egress-gw-probe'`, kept from the current flip SQL); the added host pin (`host_name = 'soleur-inngest-prd'`, which egress does not have because it counts every web host); and the added `JSONType(raw, 'message') = 'Object'`. The last three are the confounders the canary tests at once (CTO F3); an absent canary does not say which one failed.

  ```text
  egress : greatest(toInt64(${length(var.web_hosts)}) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0)
           WHERE dt BETWEEN .. AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'
  flip   : greatest(toInt64(1) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0)
           WHERE dt BETWEEN .. AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') IN ('inngest-cutover-flip')
             AND JSONExtractString(raw, 'host_name') = 'soleur-inngest-prd'
             AND JSONType(raw, 'message') = 'Object'
  ```

- **Untouched work.** The AC-chain follow-through merged on main as 338de186f6 is not touched by any file in this plan.

## References

- Incident 1051496324; mirror #12726; prior false positive #11869 (incident 1045365287); egress precedent #12180 (PR #12186, commit d1f7602ef8), canary retirement #12189 and #12270; re-arm PR #12709 (commit f55750d8f1), apply run 43333522781.
- Related open: #12695, #11820, #12158, #12689, #12190, #12271. Related closed: #11266 (LUKS key-continuity probe delivery). The relay alerts' inverted shape came in PR #12292 (merged).
- ADR-218 amendments 2026-11-05 (#12180), 2026-11-06 (#12189), 2026-11-07 (#12270).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one declares `none` with its scope-out bullet.
- Merging PR-A IS the production change: there is no separate dispatch, so the merge click is the per-command authorization (`hr-menu-option-ack-not-prod-write-auth`). Do not treat "it is the normal CD path" as a go.
- Every count a suite pins is re-derived from that suite's printed output after the change. Do not add +1 by hand: the egress session found the census in five places only by running the sibling suites.
- The canary's warning sentence must start at byte 0 of its `incident_cause`, in plain ASCII, inside the first 300 bytes after `sanitize`: the mirror runs `head -c 300` (bytes, not characters) on the sanitized cause.
- Measure any figure written into the ADR or a comment over the alert's own predicate (object rows), not over the tag, and scope every "never" to its observed window.
- The guard never evaluates `replace()`: a search string missing from its input makes the canary a copy of production that never fires. The whole-line `replace()` pin, the exactly-once host row and rows 8, 8b and 8c close that hole; do not drop them as redundant.
