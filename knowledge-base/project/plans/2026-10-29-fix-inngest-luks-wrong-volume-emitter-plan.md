---
title: "infra(observability): the LUKS wrong-volume alert SQL anchors the probe marker but does not check the emitter"
type: fix
date: 2026-10-29
slug: fix-inngest-luks-wrong-volume-emitter
branch: feat-one-shot-8874-luks-wrong-volume-emitter
issue: 8874
priority: p3
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# infra(observability): the LUKS wrong-volume alert SQL anchors the probe marker but does not check the emitter

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

**Does merging this alone mutate production?** Yes — `betterstack-logs-alerts.tf` is under `apps/web-platform/infra/**`, so the merge fires the push-triggered apply, which updates the live exploration's stored SQL in Better Stack. The PR body's first line must state this (the merge click is the authorization act).

## Enhancement Summary

**Deepened on:** 2026-10-29
**Agents used:** none — this deepen ran inside a pipeline subagent with no Task/Agent tool, so the §4 halt gates, the precedent-diff, and the verify-the-negative pass were executed inline by the planning agent instead of fanned out.

### Key improvements

1. **`Ref #8874`, not `Closes`** — the live change lands at the merge-triggered apply, so an auto-close at merge could mark the issue resolved before the apply ran or failed (the ops-remediation rule; "ARMING HAPPENS ON THE APPLY, NOT AT MERGE" is this file's own statement of it). Post-apply step closes the issue explicitly.
2. **`discoverability_test` is a literal grep, not the guard suite** — a `.test.sh` command matches preflight Check 10's 15-second-cap suite reject (#8412); the declared probe now greps the conjunct (`grep -c` → `1`).
3. **Guard-floor arithmetic re-verified** — 13+1 presence and 10+3 mutation rows → `_floor=27` / `MUT_SKIP` floor 14; the comment's `presence + mutation` decomposition updated to match.
4. **Merge-mutates-production disclosure** — the apply fires on merge; the PR body's first line must say so.

### New considerations discovered

- `scripts/lint-betterstack-emitter-read.sh` (#8875's census) never enters this `.tf` — its population is files that invoke `betterstack-query.sh`, and a file that only *declares* SQL is outside it. No census edit needed.
- `terraform_data.send_failed_alert_probe`/`monitor_send_failed_probe_rev` is the send_failed alert's own re-verification trigger; this alert has no such probe and needs no rev bump — verification is the pre-merge live-probe plus drift plan readback.
- Open scope-out #11388 (drift guards pin literals but not effective-config paths) overlaps these files; acknowledged, not folded in — it is a pre-existing family-wide structural item deferred from PR #11374's own review.

## Overview

The Better Stack Logs alert `logtail_exploration_alert.inngest_luks_wrong_volume` pages when the dedicated Inngest host's hourly probe row reports `/mnt/data` backed by a by-id alias that is not the LUKS-encrypted volume's — the tripwire for Redis writes landing unencrypted after the cutover. Its predicate (`local.inngest_luks_wrong_volume_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf`) selects rows by a start-of-message marker anchor plus `host_role=dedicated`, but not by the journald emitter — the same defect class #8846 fixed in every bash/jq/python consumer under #8873, deferred here only because a web-platform Terraform apply was in flight. #8874 re-enables the work: add the emitter conjunct, extend the drift guard, live-probe the new predicate, and let the normal apply path carry it to Better Stack.

## Research Insights

**Premise Validation (Phase 0.6).** Every cited reference was re-verified on 2026-10-29: issue #8874 is `OPEN`; #8846 is `CLOSED`, resolved by PR #8873 ("select dedicated-host probe rows by emitter plus anchor in every consumer", merged 2026-09-27); the deferral blocker PR #8831 is `MERGED` (2026-09-27T10:21Z) — the gate the issue conditioned on ("once #8831 has merged") is cleared. `local.inngest_luks_wrong_volume_sql` still exists at `apps/web-platform/infra/betterstack-logs-alerts.tf` with the exact three conjuncts the issue describes (marker at position 1, 'host_role=dedicated ', negated devid match). Collision pre-check: open PR #11519 names #8874 but is this branch's own auto-created WIP draft — not a foreign collision; the other `test-all.sh` processes belong to unrelated worktrees. The proposed mechanism (an emitter conjunct) is the repo's settled convention, not a rejected alternative: the sibling probe-class SQLs in the same file already select `JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = '<emitter>'` as their first conjunct after the time filter (`faithful_canary_sandbox_broken_sql` — whose three-conjunct shape was itself a CTO ruling recorded in ADR-218 — `egress_gw_probe_silent_sql`, `egress_gw_probe_fail_sql`, the `luks-monitor`, `ci-deploy`, and `web-nic-guard` explorations). The convention is probe-class, not file-universal: other siblings pin emitter-equivalent fields instead (`egress_gw_deny_spike_sql` pins `CONTAINER_NAME`), and `inngest_luks_key_probe_fail_sql` pins none — a same-class residual filed as follow-up.

**Property List (Phase 0.6b).** The asks restated as observable properties: (1) a row counted by this alert is always one the probe itself emitted — a row that merely *quotes* the marker under any other `SYSLOG_IDENTIFIER` (the `doppler` event log is the measured offender) can never satisfy the predicate; (2) the change is proven against live data before it is applied, not just by reading the SQL; (3) the change reaches Better Stack through the declared apply path, not a side channel.

**Cut List (Phase 0.6b).** Nothing cut — the issue names exactly one mechanism (the emitter conjunct) and no existing mechanism covers property (1): the marker anchor only excludes today's quoting rows because they happen to begin with `{`; that is an accident of webhook payload formatting, not a control.

**Relevant file paths.**

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `inngest_luks_wrong_volume_sql` local (marker anchor, host_role scope, negated devid match) and its `LIVE-PROBED 2026-09-18` comment block; `logtail_exploration` + `logtail_exploration_alert` resources below it. The file's header ("TO ADD ANOTHER LOGS ALERT") prescribes live-probing new predicates via `betterstack-query.sh` with a positive control because `terraform validate` never checks the SQL body.
- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — the drift guard: 13 whole-line/substring presence assertions + 10 copy-mutating `mutate_red` rows, floors `_floor=23` / `_floor=13` under `MUT_SKIP`, an instrument self-test, and a pristine-tree control run. Registered in `.github/workflows/infra-validation.yml` (`run: bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`).
- `.github/workflows/apply-web-platform-infra.yml` — push-triggered apply on `apps/web-platform/infra/**`; both resources are already in the main `-target=` allowlist (`logtail_exploration.inngest_luks_wrong_volume`, `logtail_exploration_alert.inngest_luks_wrong_volume`), so merging IS the apply path.
- `scripts/betterstack-query.sh` — the live-probe transport: raw-SQL mode substitutes `$BS_TABLE`/`$BS_TABLE_S3` over `remote()` + `s3Cluster` (hot window alone is ~40 min; a real window needs the archive union); credentials via `doppler run -p soleur -c prd_terraform`.
- `.github/workflows/scheduled-terraform-drift.yml` — `terraform plan -detailed-exitcode` over this root is the post-apply live-vs-declared readback.
- `scripts/lib/inngest-probe-row.sh` — the canonical emitter+anchor definition (#8873): `SYSLOG_IDENTIFIER == "inngest-server-probe"` AND `startswith("SOLEUR_INNGEST_SERVER_PROBE ")`; `INNGEST_PROBE_EMITTER` is the literal this SQL conjunct must match.
- `scripts/lint-betterstack-emitter-read.sh` — the #8875 census guard: population = tracked files that invoke `betterstack-query.sh`; a `.tf` that only *declares* SQL never enters it, so this change needs no census edit (checked 2026-10-29).

**Institutional learnings applied.**

- `2026-09-27-a-presence-check-after-source-is-satisfied-by-the-environment.md` (#8846/#8873): "a log row's identity is its emitter, never its message content" — the doppler event log on the same host quotes the marker verbatim whenever GitHub webhooks deliver issue/PR text about the probe; measured 50 quoting rows vs 6 real probe rows in one 6h window.
- `knowledge-base/engineering/operations/post-mortems/2026-09-25-inngest-watchdog-false-p1-*.md`: the same blind spot filed hourly false P1 pairs for two days — the class this alert's predicate is being hardened against.
- `inngest-luks-cutover-6894.md` runbook: readbacks always filter `SYSLOG_IDENTIFIER=inngest-server-probe` and warn that a quoted line can be the newest row `--grep` returns.

**External research.** Skipped — the predicate shape is pinned by the issue text, sibling SQLs in the same file, and `inngest-probe-row.sh`'s canonical definition; nothing external to decide.

## Problem Statement / Motivation

`local.inngest_luks_wrong_volume_sql` currently counts a row as evidence when (a) the message field *begins with* the `SOLEUR_INNGEST_SERVER_PROBE` marker, (b) the message contains 'host_role=dedicated ', and (c) the message does NOT contain 'data_mount_devid=<the live encrypted alias> '. What it never checks is **who emitted the row**. The Inngest server's own event log ships to the same Better Stack source under `SYSLOG_IDENTIFIER=doppler` and quotes the marker verbatim whenever a GitHub issue, PR, or comment about the probe is webhooked in — the defect #8846 measured live (50 quoting `doppler` rows vs 6 real probe rows in one 6h window) and fixed in every bash/jq/python consumer under PR #8873. This SQL is the one consumer that PR left alone, deferred because the web-platform apply was in flight (#8831, merged 2026-09-27 — the deferral condition is now met).

Today the anchor alone saves the alert only because every quoting `doppler` row happens to begin with `{` — a webhook-payload formatting accident, not a control. The first quoting row whose message begins with the marker text (an event-log entry echoing a probe line, a webhook payload reshaped by an Inngest version bump) satisfies all three conjuncts on a host where the devid field is absent — and the negated devid predicate then reads the row as **wrong-volume**, paging on a forgery. In the other direction the same shape can also mask: a mis-authored predicate change is invisible until it either false-pages or goes quietly blind. The emitter conjunct closes the class structurally — the row's identity becomes its emitter, per the #8873 learning.

## Proposed Solution

Add the issue-prescribed conjunct as the first predicate after the time filter — the position every sibling exploration in this file gives its emitter check (`faithful_canary_sandbox_broken_sql`, `egress_gw_*_sql`, the `luks-monitor`/`ci-deploy`/`egress-gw-probe` SQLs):

```sql
  inngest_luks_wrong_volume_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'
      AND position(JSONExtractString(raw, 'message'), 'SOLEUR_INNGEST_SERVER_PROBE') = 1
      AND position(JSONExtractString(raw, 'message'), 'host_role=dedicated ') > 0
      AND position(JSONExtractString(raw, 'message'), 'data_mount_devid=${local.inngest_luks_wrong_volume_alias} ') = 0
    GROUP BY time
  SQL
```

The marker anchor, `host_role` scope, and negated devid match are unchanged — the conjunct narrows *which journald emitter* may satisfy them, mirroring `INNGEST_PROBE_EMITTER`/`inngest_probe_row` in `scripts/lib/inngest-probe-row.sh`. Update the local's comment block in the same edit: extend the `LIVE-PROBED` record with the new measurement (date, window, counts per control below) and one line on why the emitter conjunct exists (quoting `doppler` rows; the `{`-prefix exclusion is incidental, per #8846).

Then live-probe the new predicate before merge, land it through the merge-triggered apply, and read it back through drift detection.

## Technical Considerations

- **One-line blast radius, two failure directions.** A syntax error in the heredoc breaks the exploration query itself (Better Stack reports a broken alert rather than a count — visible as drift/absence, not silence); a wrong emitter literal makes the count permanently zero, which `treat_as_zero` reads as healthy. The drift guard's presence assertion plus the pre-merge live-probe cover both directions.
- **`web-1` rows are unaffected.** The co-located web host emits the same marker under the *same* emitter tag; 'host_role=dedicated ' remains the conjunct that excludes them (measured 11 of 22 probe rows on 2026-09-18). The emitter conjunct is additive discrimination, not a substitute for the host scope.
- **No consumer census impact.** `scripts/lint-betterstack-emitter-read.sh` (#8875) censuses files that *invoke* `betterstack-query.sh`; this `.tf` declares SQL text and stays outside its population.
- **Alias interpolation untouched.** `inngest_luks_wrong_volume_alias` still derives from `hcloud_volume.inngest_redis_luks.id`; `plugins/soleur/test/terraform-target-parity.test.ts`'s G2E edge assertions (`local` interpolates the resource id, the exploration carries the local) are unaffected.
- **Provider diff shape.** The exploration's `sql_query` is `replace(trimspace(local…), "/\\s+/", " ")` — the apply produces an in-place update of `logtail_exploration.inngest_luks_wrong_volume` (the alert references it by `exploration_id`, unchanged).
- **Sequencing constraint already satisfied.** The issue required applying only once #8831's apply settled; it merged 2026-09-27. Nothing else is in flight on this root's apply workflow that this diff must avoid — the change touches one `locals` block, not any resource another PR is likely to restructure (verified against open PRs via the collision pre-check).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (checked 2026-10-29) | Plan response |
|---|---|---|
| "the SQL anchors the probe marker but does not check the emitter" | Confirmed: three conjuncts, none on `SYSLOG_IDENTIFIER`. | Add the conjunct as prescribed. |
| "that PR merged 2026-09-27 so the gate is cleared" (pipeline restatement of the deferral) | PR #8831 `MERGED` 2026-09-27T10:21Z; #8846 `CLOSED` via PR #8873 same day. | Proceed — the deferral condition is met. |
| "all 36 inngest event-log rows that quote the marker begin with `{`" (2026-09-25 measurement) | Consistent with the #8846 learning (event-log messages are strings; quoting rows are JSON-shaped webhook payloads). Stale-ness risk is exactly why the fix is structural, not measurement-dependent. | The conjunct removes reliance on the `{'-prefix accident; the live-probe re-measures the emitter breakdown in the current window. |

## Implementation Phases

### Phase 1 — Predicate + comment + guard (one commit)

1. `apps/web-platform/infra/betterstack-logs-alerts.tf`: insert `AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` as the first conjunct under `WHERE time BETWEEN {{start_time}} AND {{end_time}}` in `local.inngest_luks_wrong_volume_sql`. Extend the `LIVE-PROBED` comment block: new dated entry naming this change, and one line stating the conjunct exists because `doppler` event-log rows quote the marker verbatim (#8846) and the brace-prefix exclusion is incidental. terraform fmt -check` on the file.
2. `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`:
   - Header "WHAT THIS FILE PROTECTS": add a bullet — the row set is pinned to the probe's own emitter, so a `doppler` event-log row that merely quotes the marker can never count (#8874/#8846).
   - New presence row (after the marker-anchor row): the extracted `LOCAL_SQL` contains the literal `JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` (fixed-string `grep -cF`, same shape as the marker row).
   - Three new `mutate_red` rows on the TF copy: (a) the conjunct line deleted; (b) the emitter literal flipped to `'doppler'`; (c) the equality rewritten as a containment check `position(JSONExtractString(raw, 'SYSLOG_IDENTIFIER'), 'inngest-server-probe') > 0`. All three must drive the inner run red via the new presence row.
   - Floors: `_floor=23` → `_floor=27`, `MUT_SKIP` floor `13` → `14`, and the `23 = 13 presence + 10 mutation` comment updated to `27 = 14 presence + 13 mutation`.
3. Run `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` locally — expect `27 passed, 0 failed`.

### Phase 2 — Live-probe the new predicate (pre-merge, required by #8874)

Mirror the local's documented method against the ClickHouse table (raw-SQL mode; hot `remote()` UNION `s3Cluster` archive so the window is real; `dt` column for the window filter — the convention this file's probe comments use):

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  'SELECT count() AS n FROM (
     SELECT * FROM remote($BS_TABLE)    WHERE dt >= now() - INTERVAL 48 HOUR
     UNION ALL
     SELECT * FROM s3Cluster(primary, $BS_TABLE_S3) WHERE dt >= now() - INTERVAL 48 HOUR
   ) WHERE <PREDICATE> FORMAT JSONEachRow'
```

with `<PREDICATE>` successively:

- **A — population:** `JSONExtractString(raw,'SYSLOG_IDENTIFIER') = 'inngest-server-probe' AND position(JSONExtractString(raw,'message'),'SOLEUR_INNGEST_SERVER_PROBE') = 1 AND position(JSONExtractString(raw,'message'),'host_role=dedicated ') > 0` → expect `n > 0` (~11 dedicated rows/24h is the historical rate; this establishes the denominator).
- **B — emitter breakdown:** `position(JSONExtractString(raw,'message'),'SOLEUR_INNGEST_SERVER_PROBE') = 1` alone, `GROUP BY JSONExtractString(raw,'SYSLOG_IDENTIFIER')` → shows exactly which emitters carry marker-anchored rows today; any non-`inngest-server-probe` count here is the population the conjunct newly excludes.
- **C — quiet control:** the full new predicate with the LIVE alias (read `data_mount_devid` off the newest dedicated probe row from the runbook's readback first) → expect `n=0`.
- **D — positive control:** the same predicate with the devid needle swapped to a wrong alias (e.g. `scsi-0HC_Volume_0`) → expect `n` equal to A's count — proves the predicate still counts real probe rows rather than silently matching nothing.

Record the window and all four numbers into the `.tf` comment block (Phase 1's edit carries a dated `LIVE-PROBED` entry; Phase 2 fills in its counts).

### Phase 3 — Apply through the normal path (merge-triggered)

1. PR body carries `Ref #8874`, **not** `Closes` — the live change lands at the merge-triggered apply, so an auto-close at merge could mark the issue resolved while the apply had not run or had failed (the repo's own rule for this file: "ARMING HAPPENS ON THE APPLY, NOT AT MERGE").
2. The push-triggered `apply-web-platform-infra.yml` run on the merge SHA applies both targeted resources (already in the `-target=` allowlist — no workflow edit). Read the apply log: it must show `logtail_exploration.inngest_luks_wrong_volume` updated in place.
3. Post-apply close: once the apply run lands both resources, close the issue with a comment naming the apply run and the pre-merge live-probe numbers (`gh issue close 8874 -c "…"`). The standing `scheduled-terraform-drift.yml` `terraform plan -detailed-exitcode` over this root is the continuous backstop that reports any residual live-vs-declared diff; it does not gate closure.
4. Optional same-day sanity: re-run control C (quiet control) once post-apply.

## Files to Edit

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — one conjunct added to `local.inngest_luks_wrong_volume_sql`; `LIVE-PROBED` comment extended.
- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — one presence assertion, three `mutate_red` rows, floor counts + header bullet.

## Files to Create

- None. (`knowledge-base/project/specs/<branch>/tasks.md` and `decision-challenges.md` are pipeline artifacts, not plan deliverables.)

## Open Code-Review Overlap

- `#11388` (drift guards pin literal params but not effective-config paths) touches `betterstack-logs-alerts.tf` and this guard family. **Disposition: acknowledge** — it is a pre-existing, family-wide structural enumeration (override files, meta-arguments, `removed`/`moved` blocks, provider bumps) explicitly deferred from PR #11374's own review; folding it in would grow a one-conjunct fix into a guard-framework refactor. It remains open and unchanged by this plan.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the blast radius is a false `soleur-inngest-luks-wrong-volume-prd` page to the ops email channel, or (worse direction) a silently zero-count alert that could miss a real unencrypted-store regression *if* a second, independent fault also occurred. No user-facing artifact changes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — the change adds a read predicate to an existing internal alert; it touches no user data surface and adds no credential.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** consistent with the sibling #8846 plan's `aggregate pattern` on the same alert family — no single user's artifact can be harmed by this diff alone; the credible harm requires a compounding second fault (a blind alert missing a later unencrypted-store regression, or false pages getting muted — alarm-integrity erosion), which is a pattern harm rather than one diff reaching a user's data. The encrypted store it watches holds all tenants' scheduler state, so a realized incident is inherently a class-wide condition, not a single-user one.

## Observability

```yaml
liveness_signal:
  what: "Better Stack Logs alert soleur-inngest-luks-wrong-volume-prd evaluates the edited predicate; the inngest-server-probe timer emits the measured row hourly"
  cadence: "alert evaluation every 300s over a 5400s window; probe emission hourly (OnUnitActiveSec=1h)"
  alert_target: "Better Stack team email (free tier) / betteruptime_policy.uptime escalation (paid tier)"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (logtail_exploration_alert.inngest_luks_wrong_volume)"

error_reporting:
  destination: "Better Stack incident → email + push channels declared on the alert resource"
  fail_loud: "count(*) > 0 pages; probe silence is covered by the sibling betteruptime_heartbeat.inngest_server_probe (uptime-alerts.tf), not this alert"

failure_modes:
  - mode: "a marker-quoting row under a foreign emitter reaches the count (the #8846 defect class)"
    detection: "this change — the SYSLOG_IDENTIFIER conjunct; drift guard presence + mutation rows pin it"
    alert_route: "guard drift → infra-validation.yml CI failure; a live false page → incident email"
  - mode: "applied SQL diverges from declared (apply skipped, partial, or overwritten)"
    detection: "scheduled-terraform-drift.yml terraform plan -detailed-exitcode; the logs-alert arm of reconcile-live-heartbeats.ts (logs-alert-paused/absent)"
    alert_route: "drift issue filing + twice-daily reconcile report"

logs:
  where: "Better Stack Logs source soleur-inngest-vector-prd (id 2457081) via journald → Vector"
  retention: "hot window ~40min + s3Cluster archive (~90 days per sibling probe comments)"

discoverability_test:
  command: grep -c "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'" apps/web-platform/infra/betterstack-logs-alerts.tf
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Better Stack Logs warehouse table for source 2457081 (pre-existing; this plan adds no store)"
    mechanism: "provider-managed: Better Stack Telemetry managed ClickHouse (remote() + s3Cluster archive) — unchanged by this diff"
    evidence: "scripts/betterstack-query.sh header (the warehouse read path); no repo-owned disk holds these rows"
    defends_against: "not a store this diff creates — the predicate narrows WHICH existing rows count toward an alert"
    does_not_defend: "a leaked BETTERSTACK_QUERY_* pair still reads the same rows; unchanged, pre-existing"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: a query-predicate edit carries no new at-rest invariant to verify"
in_transit:
  - connection: "CI/operator shell -> Better Stack ClickHouse HTTP SQL API (the live-probe read path)"
    enforced_at: "scripts/betterstack-query.sh — https://$BETTERSTACK_QUERY_HOST with curl --fail-with-body"
    tls: "https; system curl default TLS negotiation"
    cert_verification: "on"
    does_not_defend: "credential theft still reads the warehouse (pre-existing, unchanged)"
    disclosed_as: "not-publicly-claimed"
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `local.inngest_luks_wrong_volume_sql` only: one conjunct + comment. No new resources, no new providers, no new variables, no new sensitive inputs. The live-probe's read credentials are the existing `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` Doppler secrets (`soleur/prd_terraform`), read-only.

### Apply path

Merge-triggered push apply on `apply-web-platform-infra.yml` (`on.push.paths` covers `apps/web-platform/infra/**`; both resources already sit in the main `-target=` allowlist). Expected effect: in-place update of `logtail_exploration.inngest_luks_wrong_volume`; the alert resource re-plans unchanged (`exploration_id` reference, not content). Blast radius: Better Stack configuration only — zero host impact, zero downtime.

### Host fan-out

Not applicable — neither changed resource is a `terraform_data` SSH provisioner; no host is contacted.

### Distinctness / drift safeguards

Single `prd` root; `dev` shares no state. Post-apply convergence is independently re-verified by `scheduled-terraform-drift.yml`'s `terraform plan -detailed-exitcode` (provider reads live state back) and the twice-daily `logs-alert` reconciler.

### Vendor-tier reality check

No new Better Stack resources — the free-tier limits that gate `betteruptime_policy` are untouched.

## Guard Contract

### Guard 1 — emitter conjunct on the wrong-volume alert predicate

**Property.** Every row counted by the alert is one the probe itself emitted — a row that merely quotes the marker under any `SYSLOG_IDENTIFIER` other than `inngest-server-probe` can never satisfy the predicate.

**Assembly.** The WHERE conjunct list of `local.inngest_luks_wrong_volume_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` — the single chokepoint: the exploration's `sql_query` is `replace(trimspace(local.inngest_luks_wrong_volume_sql)…)`, so every counted row flows through this one predicate, and the drift guard's extracted `LOCAL_SQL` reads exactly that local. The guard side is `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`, invoked solely by `.github/workflows/infra-validation.yml` (`run: bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` conjunct | RED — the new presence assertion fails (new `mutate_red` row) |
| 2 | Flip the emitter literal to `'doppler'` | RED — presence needle no longer matches (new `mutate_red` row) |
| 3 | Rewrite the equality as containment `position(JSONExtractString(raw, 'SYSLOG_IDENTIFIER'), 'inngest-server-probe') > 0` | RED — the presence needle is exact-text, a weaker comparator fails it (new `mutate_red` row) |
| 4 | Guard-side: delete the new presence assertion while the conjunct stays | FATAL — assertion floor: `_ran` drops below the raised floor (dispatch/vacuity row) |
| 5 | Move the conjunct below the `host_role` line (permitted reorder) | must-PASS — the contract pins the conjunct's presence, not its ordinal position |

**Anchor.** The emitter literal is cross-pinned outside this diff: `apps/web-platform/infra/inngest.test.sh` asserts `LOG_TAG="inngest-server-probe"` on the probe's own emitter unit and `inngest-probe-row.sh` defines `INNGEST_PROBE_EMITTER` — a coherent weakening would have to move the probe's own tag in three files, not just this pair.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add `AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` to the SQL" [issue #8874] | Phase 1 item 1 / Files-to-Edit `betterstack-logs-alerts.tf` | mapped |
| 2 | "live-probe it the way the local's comment block documents (positive control plus quiet control)" [issue #8874] | Phase 2 (controls A–D) | mapped |
| 3 | "apply it through the normal path" [issue #8874] | Phase 3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `betterstack-logs-alerts.tf` conjunct + `LIVE-PROBED` comment | asks 1–2 (the comment extension is how the probe results persist where the local documents them) | asked |
| `inngest-luks-wrong-volume-alert.test.sh` rows + floors | — | inferred — justification: the drift guard pins the source of this alert; a predicate it does not assert can be reverted silently (the guard is the only mechanism asserting this SQL's conjuncts) |
| Phase 3 drift/readback verification | "apply it through the normal path" | asked |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform/infra`, `apps/web-platform/test` (one app root)
- Planned files: 2 | Estimated changed lines: ~50
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] `local.inngest_luks_wrong_volume_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` contains the exact conjunct `AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` as its first predicate after the time filter; marker anchor, `host_role` scope, and the negated devid predicate are unchanged.
- [x] The local's comment block carries a dated `LIVE-PROBED` entry with the four Phase-2 measurements and the one-line rationale for the emitter conjunct.
- [x] `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` exits 0 reporting `27 passed, 0 failed` with floors updated (27 / 14 under `MUT_SKIP`); the three new `mutate_red` rows each go red on their mutation.
- [x] Phase-2 live-probe executed and recorded: population `> 0`, emitter breakdown enumerated, quiet control `= 0`, positive control equal to the population count.
- [ ] Post-merge, the `apply-web-platform-infra.yml` run on the merge SHA applies `logtail_exploration.inngest_luks_wrong_volume` and `logtail_exploration_alert.inngest_luks_wrong_volume` successfully (apply log shows the exploration updated in place).
- [ ] After the apply run lands, #8874 is closed with a comment naming the apply run and the live-probe numbers; PR body carried `Ref #8874` (never `Closes` — the live change lands post-merge, on the apply).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Test Scenarios

- **Guard RED rows (unit-level, drift guard):** Given the mutated `.tf` copy, when the emitter conjunct is (a) deleted, (b) flipped to `'doppler'`, or (c) weakened to a containment check, then `inngest-luks-wrong-volume-alert.test.sh` reports FAIL on the emitter presence row.
- **Guard must-PASS row:** Given a `.tf` copy where the conjunct is reordered below the `host_role` line, when the guard runs, then it still passes — the contract pins presence, not position.
- **Live-probe controls (integration):** Given `doppler run -p soleur -c prd_terraform` injects `BETTERSTACK_QUERY_*`, when controls A–D run against the ClickHouse hot∪archive table, then A `> 0`, B enumerates emitters, C `0`, D equal to A — and all four numbers land in the `.tf` comment.
- **Apply convergence (integration):** Given the PR merges, when `apply-web-platform-infra.yml` runs on the merge SHA, then both resources apply cleanly and the subsequent drift `terraform plan` is empty for them.

## Context

- **Emitter tag provenance:** the probe's journald tag is set by `LOG_TAG="inngest-server-probe"` in the probe script (pinned by `apps/web-platform/infra/inngest.test.sh`); the canonical jq contract is `scripts/lib/inngest-probe-row.sh` (`INNGEST_PROBE_EMITTER` + `inngest_probe_row`).
- **Why `= 'inngest-server-probe'` and not a `LIKE`/`position` form:** sibling SQLs and the issue text both use exact equality on the decoded field; a containment match would admit tags like `inngest-server-probe-staging` — exact equality is the conservative form.
- **`treat_as_zero` interaction:** unchanged — the alert still cannot see probe silence by design (documented `#8516` comment on the resource); that absence-of-signal case is owned by `betteruptime_heartbeat.inngest_server_probe`.
- **AI-generated files:** none — both edits are hand-shaped against pinned literals; the test additions follow the file's existing `mutate_red` recipe verbatim.

## References

- Issue: #8874 (this plan's ask, verbatim in Scope Check); defect class: #8846 / PR #8873; deferral blocker: PR #8831 (merged 2026-09-27); class-wide census guard: #8875 (`scripts/lint-betterstack-emitter-read.sh` — not in scope per its discovery rule).
- Runbook: `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (emitter-filtered readback recipe), `betterstack-log-query.md` (standing-alarms row for this alert).
- Post-mortem: `knowledge-base/engineering/operations/post-mortems/2026-09-25-inngest-watchdog-false-p1-event-log-probe-rows-postmortem.md`.
- Learning: `knowledge-base/project/learnings/security-issues/2026-09-27-a-presence-check-after-source-is-satisfied-by-the-environment.md`.
- ADR-218 (native Better Stack Logs alerts are Terraform-managed via the logtail provider); ADR-142 (the LUKS cutover this alert watches).
- Sibling plan: `knowledge-base/project/plans/archive/20260927-123658-2026-09-25-fix-inngest-probe-row-emitter-selection-plan.md`.
