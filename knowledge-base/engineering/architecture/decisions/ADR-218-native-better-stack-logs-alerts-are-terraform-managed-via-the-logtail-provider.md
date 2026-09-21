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
