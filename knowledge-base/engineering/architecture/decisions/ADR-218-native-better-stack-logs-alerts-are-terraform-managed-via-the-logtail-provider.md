---
title: "ADR-218: Native Better Stack Logs alerts are Terraform-managed via the logtail provider, for stateless per-bucket signals"
status: Accepted
date: 2026-09-13
supersedes: []
amends:
  - ADR-096
tags: [better-stack, logs, alerting, terraform, observability, paging]
---

# ADR-218: Native Better Stack Logs alerts are Terraform-managed via the logtail provider, for stateless per-bucket signals

## Status

Accepted — 2026-09-13. Implements #8097 (a follow-up filed from #8073, parent #7898 §2). The issue
stays open until `scripts/followthroughs/send-failed-alert-probe-8097.sh` returns `verdict=pass`
after the merge-triggered apply; the PR body carries `Ref #8097`, not `Closes`.

## Context

#8073 made the four web-1 monitor units (`disk-monitor`, `resource-monitor`,
`container-restart-monitor`, `cron-egress-alarm`) emit a PRIORITY-2 journald row —
`SOLEUR_<UNIT>_SEND_FAILED …` or `SOLEUR_<UNIT>_REFUSED …`, via each unit's `emit_refusal()` →
`logger -p user.crit` — whenever their own Resend email or Sentry event could not be delivered.
Vector Source 2 (`[sources.system_journald]`, PRIORITY 0–2) ships those rows to Better Stack Logs
source 2457081. They were queryable and nothing paged on them: a broken send path left the on-call
unpaged while the customer met the underlying disk / memory / container-restart / cron-egress
outage first.

Three facts shaped the mechanism:

1. **The detector must not live on the vendor being detected.** The failure class *is* the
   Sentry/Resend send path. ADR-096's default for log-content alarms — a GitHub-Actions cron poller
   surfacing an `action-required` issue with a Sentry self-liveness heartbeat — cannot page, and
   reports its own health through Sentry. Better Stack is the exit that survives a Sentry-side
   outage (`model.c4` `betterstack -> founder`).
2. **ADR-096 already carved this class out.** Its §Consequences pattern paragraph rejects the
   native Telemetry SQL-alert route for *stateful, newest-scoped* signals and names the exception:
   "a pure stateless per-bucket count with an email-acceptable surface." `count(rows matching) > 0`
   per bucket is exactly that.
3. **The provider premise was stale.** ADR-096 and `runbooks/betterstack-log-query.md` recorded
   that "the `better-uptime` TF provider has no log-alert resource." True for
   `BetterStackHQ/better-uptime` (still true at 0.22.0). But Better Stack ships a **second**
   provider, `BetterStackHQ/logtail` (v11.2.0 on 2026-09-04), whose `logtail_exploration` +
   `logtail_exploration_alert` resources are the native per-bucket alert as a first-class
   Terraform object — verified against the provider repository's `docs/resources/` and its
   `internal/provider/*.go`, not against ADR prose (`hr-verify-repo-capability-claim-before-assert`).

Two more premises were measured false at plan time and are recorded so they are not re-derived:
"the existing on-call policy" does not exist live (`GET /api/v2/policies` is empty; every
`betteruptime_policy` is `count = var.betterstack_paid_tier ? 1 : 0`, default false; every live
monitor has `policy_id: null, email: true`); and the warehouse held **zero** PRIORITY 0–2 rows
from `host = soleur-web-platform` in 14 days, which is consistent with both "nothing critical
happened" and "web-1's live Vector lacks Source 2". The second reading was refuted without SSH via
the deploy-status webhook (live `vector.toml` sha == the rendered committed config, and web-1 ships
Source-3 rows that postdate the file's mtime, so the running config carries Source 2 by
transitivity); the first reading stands unrefuted. The last unmeasured link — journald records
`logger -p user.crit` as `PRIORITY=2` on web-1 and Source 2 ships it — is what the synthetic probe
below proves.

## Decision

1. **A native Better Stack Logs alert, managed as Terraform, is the mechanism for a pure
   per-bucket count with an email-acceptable surface.** The ADR-096 poller pattern stays the
   default for stateful / newest-scoped signals and for signals whose surface must be a
   digest-visible GitHub issue. Both are legitimate; the signal class picks.
2. **The `BetterStackHQ/logtail` provider is added to the web-platform root** (`main.tf`,
   `~> 11.2`; v11.0.0 replaced chart-level variables with per-alert `variable_value`, so nothing
   below it is usable) and **shares `var.betterstack_api_token`** with `betteruptime` — one global
   token serves both the Uptime and Telemetry APIs (read authority on `/api/v2/alerts`,
   `/api/v2/explorations` and `/v1/sources` was GET-probed 200 with that credential; write
   authority is documented and proven at first apply). No new variable.
3. **The first alert, `soleur-monitor-send-failed-prd`** (`apps/web-platform/infra/betterstack-logs-alerts.tf`):
   - Predicate: `PRIORITY = '2'` AND `startsWith(message, 'SOLEUR_')` AND
     `multiSearchAny(message, ['_SEND_FAILED', '_REFUSED'])` — literal needles, no `LIKE`, so the
     deliberate `SOLEUR_*_SEND_SKIPPED` class ("never pages on configuration") is excluded by
     construction. `PRIORITY = '2'` is load-bearing: it is what keeps the non-crit `_REFUSED`
     markers elsewhere in the fleet (`inngest-cutover-flip.sh` at `user.notice`,
     `resend-inbound-bootstrap.sh` with no `logger` at all) out of the rule without pinning unit
     tags. The exploration's source is a **literal** `2457081` (see Consequences on
     `logtail_source`).
   - Paging semantics: `higher_than 0`, `check_period 60`, `query_period 300` (≥ the timers'
     5-minute cadence, so a persisting failure holds one incident instead of flapping),
     `recovery_period 600`, `on_missing_data = treat_as_zero` — a count query with no rows returns
     no bucket, and that must read as healthy (0), never as "unknown", or an open incident could
     never observe recovery. `paused = false` is written as intent.
   - **Routing contract:** the same surface every sibling monitor and heartbeat uses — team email
     on the free tier (`escalation_target { team_name = "Your team" }`), escalating to
     `betteruptime_policy.uptime` when `var.betterstack_paid_tier` is true — the same ternary
     shape as `uptime-alerts.tf`'s `policy_id`. Provider v11.2.0's `escalation_target` fields are
     plain `Optional` with no `ExactlyOneOf`; nulls are skipped on write and not mirrored on read.
     `incident_cause` carries a full GitHub URL to the runbook (the one field most likely rendered
     in the email; a repo path is not clickable).
   - Omitted on purpose: `aggregation_interval`, `series_names*`, `source_variable` (all
     `Optional+Computed`; `aggregation_interval` is the one the API snaps to a bucket size, a
     perpetual diff).
4. **Verification traverses the real apply path, and closure is the readback's verdict.**
   `terraform_data.send_failed_alert_probe` (`server.tf`, same SSH connection block as
   `disk_monitor_install`) runs one `logger -p user.crit -t disk-monitor
   'SOLEUR_DISK_MONITOR_SEND_FAILED … synthetic=1 probe_rev=<rev>'` on web-1 through
   `apply-web-platform-infra.yml`'s SSH-provisioned step — the channel that delivers the monitor
   scripts themselves. The row reuses the real marker so it inherits the real routing (that *is*
   the test); the `synthetic=1 probe_rev=` suffix keeps it decodable. Its **only trigger is
   `local.monitor_send_failed_probe_rev`**, a digits-only literal (`lifecycle.precondition`): the
   SSH apply runs on every push to `main` that touches this root (`on.push.paths`), so a per-run
   nonce would page ops on every infra merge, and a predicate hash would page on a cosmetic heredoc
   re-flow. *Changed the SQL? Bump the rev.* A bump performs zero Better Stack API writes. The one
   re-fire without a bump: a failed provisioner taints the resource and the next apply re-runs it
   at the same rev. The exploration hands the API a **single-line** `sql_query`
   (`replace(trimspace(local…), "/\\s+/", " ")`) because the provider mirrors the string back with
   no diff suppression; whether the API normalises whitespace was NOT measured (AC9 stays a
   post-merge reading of the drift plan), so the flat form is the conservative choice.
   `scripts/followthroughs/send-failed-alert-probe-8097.sh` (daily via
   `scheduled-followthrough-sweeper.yml`) then reads back, in order — alert present and
   unpaused → **web-1-scoped** positive control over the same 14-day hot ∪ archive window
   (source 2457081 is shared with the inngest host; an unscoped control reads LIVE while web-1's
   Vector is dead, ADR-197) → the row keyed on `synthetic=1 probe_rev=<rev>` → an incident
   matched on `name` or `cause` anchored on the row's own `dt` − 600 s — on the sweeper's
   0 / 3 / 5 exit contract (never 1: to the sweeper 1 reopens a human-closed issue).
5. **Alert self-health is one arm in an existing poller, not a new step.**
   `reconcile-live-heartbeats.ts` (twice daily from `scheduled-terraform-drift.yml`) gains a
   `logs_alert` arm: for every declared `logtail_exploration_alert` (discovered from the `.tf`,
   never listed), `GET telemetry.betterstack.com/api/v2/alerts` through the same injected fetch
   with a **second exact host pin** (never a suffix match), and a paused or absent alert prints
   `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH … live=logs_alert reason=logs-alert-paused|logs-alert-absent`
   followed by the routing tokens `resource=` and `route=` (#7884, ADR-117 amendment of
   2026-09-15) and, last, `detail="<paused_reason>"`, with rc = 2, carried by the existing deduped
   `heartbeat-reconcile-mismatch` issue. The untargeted drift plan is deliberately **not** the
   detector: the per-merge targeted apply re-arms `paused = false` silently, so a vendor pause
   shows in the plan only between infra merges.
6. **Deliberate exclusion: `SOLEUR_<UNIT>_HALT`.** All four units also emit a PRIORITY-2
   `SOLEUR_<UNIT>_HALT reason=xtrace-credential-bound issue=7797` from their top-of-file guard. A
   halted monitor leaves its condition unwatched — the same customer-meets-the-outage-first
   consequence #8097 names — but the issue's stated scope is `_SEND_FAILED` / `_REFUSED`, and the
   plan kept it. Recorded as User-Challenge UC-1 in
   `knowledge-base/project/specs/feat-one-shot-8097-betterstack-send-failed-alert/decision-challenges.md`;
   opting in is one more needle plus a rev bump.
7. **Opt-in policy for future classes.** A same-severity `SOLEUR_*` PRIORITY-2 class joins *this*
   alert by adding a needle (+ a guard row + a runbook decode row). A class needing different
   routing or severity gets its own `logtail_exploration_alert`, via the five-step checklist in
   `betterstack-logs-alerts.tf`'s header. This keeps the free-tier alert count at one until a
   second routing is actually needed.

Reconciling ADR-096's rejection (2) — "the operator surface must be a digest-visible GitHub
issue, not an ops@ email": here email **is** the surface, because independence from GitHub, Sentry
and Resend is the point of the signal; a firing is deliberately not digest-visible, and the
reconcile arm covers only the alert's own health, not its firings.

## Consequences

- **Drift guard + battery.** `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh`
  pins the predicate's three anchors and its needle **set**, discovers every `emit_refusal()`
  definer under `infra/` (a census of every crit-level `logger`/`systemd-cat` line across the
  non-test `infra/*.sh` and `cloud-init*.yml`, each classified as emit_refusal-routed, allowlisted
  non-paging, or unclassified — the last two red) and holds each to `logger -p user.crit` — or to a named non-crit
  allowlist with a reason (`resend-inbound-bootstrap.sh` defines `emit_refusal()` without
  `logger`; it runs in CI, so the plan's "four definers" was one short) — asserts every
  `SKIPPED` / `_HALT` literal matches no needle, pins the source id to `vector.toml`'s sink and
  the probe line's severity. Its mutation battery (every row attributed by FAIL string, incl. the
  floor's RED/GREEN pair; the row count is pinned inside the battery, not here) is registered in
  `infra-validation.yml`; an unrun battery is a claim.
- **`-target` allow-lists.** Two main-plan targets (`logtail_exploration.*`,
  `logtail_exploration_alert.*`) and one SSH-apply target (`terraform_data.send_failed_alert_probe`)
  in `apply-web-platform-infra.yml`; the #5566 guard (`terraform-target-parity.test.ts`) reds on
  any declared resource missing from them. `web-host-provisioner-parity.test.sh`'s zero-slack
  floor moves 16 → 17.
- **Lockfile.** `.terraform.lock.hcl` gains the `betterstackhq/logtail` block only (2 `h1:`
  platforms, matching the `better-uptime` sibling); `scheduled-terraform-drift.yml`'s init gains
  `-lockfile=readonly` like the apply workflow, so no provider can resolve outside the lockfile.
- **Deletion is not a `.tf` removal.** The per-merge apply is target-scoped, so removing the
  resources is a silent no-op live until the `[ack-destroy]` procedure runs (learning
  2026-07-17). The runbook says so.
- **`logtail_source` is not adopted (#8124).** The provider's `logtail_source` `token` attribute
  is `Computed` but not `Sensitive` (v11.2.0 `resource_source.go`), so a data-source read would
  land the ingest token unflagged in `terraform show -json` (the ARM step) and in the drift cron's
  plan text (pasted into a public issue). The source id is a literal pinned to the sink URI by the
  guard. ADR-198's premise — "no other Better Stack provider exists in the Terraform registry" —
  is therefore stale; it is **not** amended here (amending an ADR about a resource this decision
  does not adopt is text for its own sake), and #8124 owns the decision.
- **Host-key pinning on the SSH bridge stays a recorded exception (#8125).** The probe reuses the
  pre-existing `cf-tunnel-ssh-bridge` connection verbatim (TOFU, non-persistent `known_hosts`);
  identity rests on Cloudflare Access gating the tunnel. Unchanged by this decision.
- **Quota.** The probe adds one PRIORITY-2 row per rev bump. The alert consumes no log quota. The
  free-tier Telemetry alert-count cap is undocumented; one pre-existing paused onboarding alert
  stays unmanaged (same class as the unmanaged monitor in #7884). A plan-limit error fails the
  apply loudly through the "Email ops on a non-green apply run" step; recovery is deleting the
  paused onboarding alert (Telemetry API, `DELETE /api/v2/alerts/<id>`) or the paid tier — the
  `.tf` needs no change, the next infra merge re-applies.
- **Runbook.** `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md`;
  `betterstack-log-query.md` §"Standing alarms over this source" gains the native-alert row and
  corrects the provider-gap parenthetical. `model.c4`'s `betterstack` element gains one clause.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| ADR-096 poller → `action-required` issue + Sentry heartbeat | Cannot page; self-liveness through the vendor whose failure this alert must survive; ADR-096 itself exempts this signal class. |
| REST-created alert via `POST /api/v2/explorations/{id}/alerts` + a runbook (the issue's fallback) | A first-class TF resource exists; a REST object has state outside Terraform (bootstrap, drift and deletion by hand). |
| CI direct-ingest POST as the verification row (ADR-172 shape) | Bypasses web-1's Vector — the one unmeasured link. Pages just the same and proves less; cut, also from the runbook. |
| `'_HALT'` as a third needle | Outside the operator's stated scope; UC-1 records the challenge, a one-token change if adopted. |
| `SYSLOG_IDENTIFIER IN (four tags)` in the predicate | The issue asks for a convention-based rule; `PRIORITY = '2'` already excludes every non-unit `_REFUSED` marker and the guard catches a future `user.crit` emitter outside the documented set. |
| A separate PR for the probe | The alert is created by the main apply minutes before the SSH apply fires the probe in the same run; `query_period = 300` covers the ordering, and a rev bump re-fires without redesign. |
| `data "logtail_source"` for the source id | Unflagged ingest token in plan/show JSON — see Consequences and #8124. |
| A predicate hash as the probe trigger | Two keys where one does the job; a whitespace re-flow would page. The literal rev is the honest contract. |
| `critical_alert = true` | No sibling sets it; no quiet hours on the free tier. Named in the runbook as the paid-tier knob. |

## References

- #8097 (this decision), #8073 (the emitters), #7898 §2 (parent), #8124 (`logtail_source`
  deferral), #8125 (host-key pinning deferral), #6616 (web-1 `host_name` stale render), #7884
  (unmanaged monitor precedent), #6291 (ADR-096 poller precedent), #5566 (coverage guard), #7539
  (SSH green-skip channel).
- ADR-096 (amended: the provider-gap sentence), ADR-172 §2 (readback rule), ADR-197 (a zero is
  not absence), ADR-198 (stale premise, owned by #8124), ADR-130 (credential coverage probe).
- Provider: `github.com/BetterStackHQ/terraform-provider-logtail` v11.2.0 —
  `docs/resources/exploration.md`, `exploration_alert.md`; `internal/provider/alert_shared.go`,
  `resource_source.go`. Vendor: `betterstack.com/docs/logs/api/getting-started/` (global tokens
  accepted on the Telemetry API).
- Plan: `knowledge-base/project/plans/archive/20260913-190954-2026-09-12-feat-betterstack-send-failed-alert-rule-plan.md`.

## Amendment — 2026-09-18 (#6894): the second Logs alert

This ADR's Decision 3 and its Quota consequence both rest on there being exactly one
Terraform-managed `logtail_exploration_alert` ("keeps the free-tier alert count at one until a
second routing is actually needed"). #6894 adds the second —
`logtail_exploration_alert.inngest_luks_wrong_volume` — and it is the case that clause anticipated
rather than an exception to it: a different signal class (a probe row's resolved device alias), a
different routing rationale (the store silently returning to the plaintext volume, which no uptime
or Sentry signal can see), and its own runbook. It followed this ADR's five-step recipe, including
the live probe with a positive control before the SQL was written.

Two things it does differently, both deliberate and both worth reading before a third is added:

- **It ships PAUSED**, via `paused = !var.inngest_luks_cutover_complete`. Before the cutover the
  condition it watches is the CORRECT state, so an armed rule would page continuously between merge
  and the cutover — and a rule that pages when nothing is wrong is one that gets muted before it
  matters. It is the only alert in this file whose paused state is variable-driven.
- **That required a reconciler change**, because `reconcileLogsAlerts` treated any live-paused
  declared alert as drift. It now reads the declared `paused` and treats a non-literal-`false`
  declaration as intent (`plugins/soleur/lib/heartbeat-live-reconcile.ts`). Without it the drift
  cron would have raised a `logs-alert-paused` mismatch twice daily for the whole window — a
  standing false page introduced by an alert that exists to prevent a silent failure.

The free-tier count is now two. A third still needs the same argument this one made: name the
signal class, show no existing alert covers it, and probe the predicate live before writing it.

## Amendment — 2026-09-20 (#8296): the reconciler resolves a var-driven `paused`

The 2026-09-18 amendment above recorded that `reconcileLogsAlerts` "treats a non-literal-`false`
declaration as intent". That sentence is no longer true and is superseded here rather than
edited (dated records are append-only). Since #8296:

- `parseLogsAlertBlocks` takes the same `InfraVariables` map the heartbeat and monitor arms have
  taken since #7884, and `resolvePausedIntent` resolves a declared `paused` of the shape
  `var.<name>` / `!var.<name>` against that variable's DECLARED DEFAULT. A declaration that
  resolves to `paused = false` is armed, and a live pause on it is reported as `logs-alert-paused`
  — Decision 5's original invariant, restored for this alert.
- A declaration that does NOT resolve (unknown variable, non-boolean default, any other
  expression shape) stays exempt and quiet. This is a deliberate polarity choice, documented on
  the `pausedResolvesFalse` field: the monitor arm THROWS for a non-literal `paused`; this arm
  does not, because a false page on an alert the operator paused on purpose is how a real page
  gets muted later.
- Resolution reads SOURCE defaults only. A Doppler `TF_VAR_*` override is invisible to it, so an
  override that pauses an alert whose default arms it is reported as drift — intended; it is the
  only detector a forgotten override has. The drift workflow's triage text names the check.

The 2026-09-18 clause "It ships PAUSED" is falsified by PR-2 of #8296 (the ledger flip), which
carries its own amendment; this one is scoped to the reconciler sentence, which PR-1 falsifies.

## Amendment — 2026-09-21 (#8296): "It ships PAUSED" is falsified at the arm

Appended, not edited. The 2026-09-18 amendment's clause "It ships PAUSED" (via
`paused = !var.inngest_luks_cutover_complete`) was true until the cutover. It no longer is.
PR-1 of #8296 flipped the variable's declared default to `true`, and the push apply of
`b53173a04` (run 35605929787) armed the alert. The live alert `soleur-inngest-luks-wrong-volume-prd`
(id `2988582970`) read back `paused=false`, `paused_reason=null`, at 2026-09-21T14:18:56Z.
It had read `paused=true` before that apply.

The `paused` attribute is still an expression, not a literal, so the reconciler behaviour recorded
in the 2026-09-20 amendment applies: a live pause on this alert is now reported as drift. This is
the amendment the 2026-09-20 one pointed forward to. That forward pointer named the wrong PR: it said
PR-2 of #8296 falsifies "It ships PAUSED", but PR-1 and its push apply did; PR-2 only records it.

One known gap is open: `on_missing_data = "treat_as_zero"` reads a probe pipeline that has gone
silent as healthy, so this alert cannot page on a dead producer. The paging fix is tracked in #8516.

## Amendment — 2026-09-23 (#8611, ADR-243): three more Logs alerts

Appended, not edited. #8611 adds three `logtail_exploration_alert` resources to
`betterstack-logs-alerts.tf`, which takes the Terraform-managed Logs alert count from **3 to 6**
(#6894 made two; #8408's `registry_store_not_luks` made three, without an amendment here). The
free-tier alert-count cap recorded above as undocumented is still undocumented. If an apply is
refused on count, that refusal is the measurement, and it lands here.

The 2026-09-18 amendment asked the next alert to name its signal class and show that no existing
alert covers it:

- **`inngest_step_524`**: this one IS the stateless per-bucket class the Decision describes. It
  counts inngest-server rows per 15 min whose `message.error` carries a lost-step-response text
  (the 524 and the two spike-measured stream-drop texts). No existing alert reads inngest-server's
  step-transport errors.
- **`claude_cost_daily_burn`**: this one is **not** per-bucket. It is a **whole-window sum**:
  one row per evaluation, summing `cost_usd` over a trailing 24 h (`query_period` 86400) and
  filtered on the `dt` column. With a `{{time}}` bucket, a trailing day would split across two
  calendar buckets. No existing alert reads spend.
- **`claude_cost_capture_dark`**: this one is **not** per-bucket either. It is an **absence
  alarm**: `lower_than 1` over `treat_as_zero`, so silence fires. It is the first Logs alert in
  this file built to page on a dead producer, the gap the 2026-09-21 amendment leaves open for the
  LUKS alert (#8516). It watches only the cost-marker path.

So the Decision's framing of native Logs alerts as "stateless per-bucket signals" now covers
four of the six. The two exceptions are recorded in ADR-243 §3, and their shapes are pinned by
`apps/web-platform/test/infra/inngest-step-524-alert.test.sh`.

## Amendment — 2026-09-27 (#8706): the seventh Logs alert

Appended, not edited. #8706 adds `logtail_exploration_alert.luks_monitor_host_timer_dark`
(`soleur-luks-monitor-host-timer-dark-prd`) to `betterstack-logs-alerts.tf`. That takes the
Terraform-managed Logs alert count from 6 to **7**. The 2026-09-18 amendment asks the next alert to
name its signal class, show that no existing alert covers it, and probe the predicate live:

- **Signal class: an absence alarm**, like `claude_cost_capture_dark`. `lower_than 1` over
  `treat_as_zero`, so silence fires. It counts web-1's host-unit rows reading
  `OK: /mnt/data is LUKS-backed` over a trailing 27 h.
- **Why no existing alert covers it.** `betteruptime_heartbeat.workspaces_luks` has two pushers:
  the host timer and the daily `workspaces-luks-verify.yml` job. One live pusher keeps a shared
  beat `up`, which is how the host timer stayed uninstalled for about nine weeks. This alert keys on
  `_SYSTEMD_UNIT=luks-monitor.service`, which the verify job's rows never carry.
- **Live probe (2026-09-27, 7-day window, hot and archive union).** As written: `0` (the dark state
  it must page on). Control A, the unit swapped for `inngest-heartbeat.service`: `39228`. Control
  B, the unit conjunct dropped: `9` (the verify job's rows, which the unit conjunct excludes).
- **`query_period = 97200` (27 h)** is the first value outside {300, 900, 5400, 86400} in this file.
  It covers a legitimate 24 h 30 min gap between two timer runs plus margin. Better Stack's docs list
  no bounds, so it was measured: a throwaway PAUSED alert was created on the live API with it, read
  back `query_period:97200 confirmation_period:0` (not clamped), and deleted.
- **Host-scoped to web-1.** The predicate carries
  `JSONExtractString(raw, 'host_name') = 'soleur-web-platform'`. web-2 (`soleur-web-2`) ships to the
  same source (measured 2026-09-27), and the unit is web-1-only by design (ADR-119 §(d)).

The Decision's "stateless per-bucket signals" framing now covers four of the seven. The runbook is
[`workspaces-luks-cutover-6604.md`](../../operations/runbooks/workspaces-luks-cutover-6604.md#host-timer-liveness-alert-8706).

## Amendment — 2026-10-01 (#9342): the ninth Logs alert

`soleur-bwrap-probe-rollback-prd` (`logtail_exploration_alert.bwrap_probe_rollback`) alerts on the blocking
bwrap probe's `DEPLOY_ROLLBACK: bwrap sandbox non-functional` row, emitted by `ci-deploy.sh` under
`SYSLOG_IDENTIFIER=ci-deploy`.

- **Signal class.** A stateless per-bucket count, the same class as `monitor_send_failed`; no existing alert
  covers it. Live-probed 2026-10-01 over 14 days: 19 matching rows, and 0 for the needle with a suffix added.
- **Count.** Nine Logs alerts now apply (#8408 was the third, #9045 the eighth). The free-tier cap is still
  unmeasured, and the main-plan apply is where a refusal on count would surface.
- **Deliberate divergence from the dead-man sibling.** No `host_name` conjunct: web-2 and web-1's
  pre-2026-09-19 name (`soleur-inngest-prd`) carry the same rows, and a host conjunct would silence them.
- **Enforcement.** Both `-target=` lines are enforced only by the alert's own drift guard
  (`apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh`); `terraform-target-parity.test.ts`
  checks `terraform_data` only.

## Amendment — 2026-10-04 (#9391): the tenth Logs alert

`soleur-ghcr-hostsfile-deny-lost-prd` (`logtail_exploration_alert.ghcr_hostsfile_deny_lost`) alerts when a
host reports that its hosts-file GHCR deny is no longer in force: value `0` of `ghcr_blocked` from either of two
emitters, a web host's `ci-deploy` row `GHCR_DENY ghcr_blocked=<value>` (`SYSLOG_IDENTIFIER=ci-deploy`, whole
message) or the registry host's `SOLEUR_ZOT_DISK` heartbeat head. It is PR-2 of the Zot / ADR-096 wrap-up. The
deny is an accident guard on name resolution (ADR-096), not an egress control, and deploy pulls are zot-only
since #8036, so a loss is not a deploy or user outage.

- **Signal class.** A stateless per-bucket count, the same class as `monitor_send_failed`; no existing alert
  covers it (the Sentry op `ghcr_deny_lost` watches the firewall carve from inside the app container, a
  different property, which is why this alert is named `…hostsfile…`). `unknown` (ghcr.io does not resolve)
  is deliberately not matched: a blind probe is silent here, and silence is not health.
- **Live probe (2026-10-04, 14-day window, hot table UNION archive, counts only).** The fields shipped on
  2026-09-28 (registry heartbeat, #9147) and 2026-09-30 (web `GHCR_DENY`, #9169), so the window holds about six
  and four days of emissions. As written: one web row (web-1, 2026-09-30) and no registry row. Positive
  controls with the needle changed to value `1`: 97 web rows (web-1 49, web-2 48) and 1,669 registry rows, so
  both arms are live SQL and web-2 reports. A loose variant with no identifier scoping and no equality returns
  14, so the scoping excludes 13 rows that merely quote the marker (inngest GitHub-webhook payload logs,
  identifier `doppler`). Registry rows carry no `host_name` key (288 of 288 sampled rows), so the host is the
  in-message `host=` token.
- **Count.** Ten Logs alerts now apply (#9342 was the ninth). The free-tier cap is still unmeasured. A refusal
  on count fails the whole push apply, not only this alert. Either lift the cap (the Quota bullet's route: the next infra merge
  re-applies) or drop the two resources: a refused apply can leave the exploration created
  without its alert, and removing it from the `-target`-scoped apply needs the `[ack-destroy]` procedure.
- **Paging.** `higher_than 0` with the `registry_store_not_luks` windows (check 300, query 900, recovery
  1800): the registry heartbeat is every five minutes, so one 900-second bucket holds up to three rows; the
  web arm is sampled once per validated `ci-deploy.sh` invocation, so any one row alerts. Resolution after quiet
  minutes is not a fix; the incident text says so.
- **Deliberate divergence from the dead-man sibling.** No `host_name` conjunct: web-1, web-2 and the registry
  host all carry these rows.
- **Residuals.** (1) The web arm is a sample, not a monitor: an idle host, or one whose `ci-deploy.sh`
  predates #9169, is silent. (2) Both arms are self-reports from the host being monitored, so a host-root
  compromise that re-points ghcr.io can report `1`; this is a drift alarm, not a tamper-evident control.
  (3) Arm R is fail-quiet when the `zot_last_err=` field is absent or the row's JSON does not parse (a `"` or backslash in a volume-borne `resize_ok`/`block_size_gb` has no `=`, so it passes `cut` and breaks the body), where `registry_store_not_luks` is
  fail-loud on the same row. A volume-borne `resize_ok`/`block_size_gb` cannot forge the head: the host reads
  them with `cut -d= -f2`, so the value cannot contain the `=` that both the `ghcr_blocked=` and `zot_last_err=` markers
  carry.
- **Merge consequence.** When `apply-web-platform-infra.yml` is enabled, merging a change under
  `apps/web-platform/infra/` triggers the push apply, which creates this alert and carries any backlog since
  the last apply; when it is disabled, no apply runs and the alert stays absent. That enablement is
  operator-owned state, recorded with a date in `cron-egress-blocked.md` ("Known residual: web-1 until the
  apply workflow runs"), not here.
- **Enforcement.** Both `-target=` lines are enforced only by the alert's own drift guard
  (`apps/web-platform/test/infra/ghcr-blocked-alert.test.sh`, run by `infra-validation.yml`);
  `terraform-target-parity.test.ts` checks `terraform_data` only. Runbook and per-host repair route:
  `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md#hosts-file-deny-lost-better-stack-alert`.
- **Merge consequence, update 2026-10-04.** The enabled-versus-disabled wording in the Merge
  consequence bullet above describes the pre-apply state, including its "the alert stays absent"
  half, which no longer holds. `apply-web-platform-infra.yml` was enabled once, dispatched as
  `manual-rerun` on main `9e6412fb3` (run 37209725107, success), and set back to
  `disabled_manually`; that run created `soleur-ghcr-hostsfile-deny-lost-prd` and its exploration
  (7 added, 0 changed, 0 destroyed non-SSH) together with the backlog since the previous apply.
  The drift reconciler's `logs_alert` arm read declared 10 against live 11 on 2026-10-04 with no
  `logs-alert-absent` or `logs-alert-paused` row (the extra live alert is the hand-made, paused
  "Output utilization high"). The apply was not refused on count, so the free-tier cap, still
  unmeasured in the Count bullet above, is at least 11. While the workflow is paused again, a
  later merge under `apps/web-platform/infra/` triggers no apply, as that bullet says for the
  disabled state.
