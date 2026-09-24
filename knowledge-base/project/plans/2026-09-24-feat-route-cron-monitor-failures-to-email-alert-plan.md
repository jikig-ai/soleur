---
title: "observability: route Sentry cron-monitor failures to an email alert workflow (#8630)"
date: 2026-09-24
slug: feat-route-cron-monitor-failures-to-email-alert
branch: feat-one-shot-8630-cron-monitor-alert-workflow
issue: 8630
closes: 8630
type: feat
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
pr: 8694
lane: cross-domain
---

# observability: route Sentry cron-monitor failures to an email alert workflow

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Sentry has 59 cron-monitor detectors for the web-platform project. None of them is connected to an
alert workflow (`workflowIds: []`, measured 2026-09-23 during #8505), so the workflows that email the
operator are never run for a detector-bound cron failure. Five monitors are also muted.

**The provider can express the fix. Verdict: EXPRESSIBLE at the pinned `jianyuan/sentry` 0.15.7.**
The evidence is in §Provider-capability measurement. The link sits on the alert side:
`sentry_alert.monitor_ids` is the workflow's `detectorIds`, and `sentry_cron_monitor.id` is the
detector id. The provider's own canonical example binds `sentry_cron_monitor.default.id` in
`monitor_ids`.

The plan therefore takes the Terraform branch of #8630:

1. Add one `sentry_alert` named `cron-monitor-failure` in a new file,
   `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`. It binds every declared cron monitor
   through a declared routing map, and it emails `issue_owners` with fallthrough `ActiveMembers`,
   the same route as the 31 fully-owned issue rules.
2. Guard the routing map so that a new monitor cannot be left unrouted without a trace. Also guard
   the projection so that a monitor created in the same plan fails at PR time. Without that
   floor, the post-apply fidelity probe would turn `main` red after a complete apply.
3. Decide each muted monitor. Mute state is not expressible in the provider. Each decision is
   recorded with evidence. No write outside Terraform is performed.
4. Correct every runbook, code comment, C4 edge and ADR sentence whose truth changes.
5. Append the decision to ADR-031. This includes how ADR-031's own #6612 exit criterion (b) is
   met, since that criterion fires the moment this PR routes cron failures.

No existing alert rule is edited. `issue-alerts.tf` is not touched, so the frozen rules
`auth_per_user_loop` (566671) and `sandbox_startup_failure` (669246) are untouched by construction.

## Provider-capability measurement (the verdict this plan depends on)

Measured 2026-09-24 from the schema and source at the exact pin. No changelog was used.

| # | Probe | Result |
|---|---|---|
| M1 | `versions.tf` + `.terraform.lock.hcl` | `jianyuan/sentry` `version = "0.15.7"`, lock `version = "0.15.7"`. |
| M2 | `terraform init` with the 0.15.7 pin in a scratch dir, then `terraform providers schema -json` (Terraform v1.9.8) | Resources include `sentry_alert`, `sentry_cron_monitor`, `sentry_metric_monitor`, `sentry_uptime_monitor`. `sentry_alert.monitor_ids` is **required**: "The IDs of the monitors to create alerts for." The block description says: "Create an Alert for a Monitor … Monitors must be created separately using the `sentry_cron_monitor`, `sentry_metric_monitor`, or `sentry_uptime_monitor` resources." |
| M3 | `sentry_cron_monitor` schema | Attributes: `checkin_margin_minutes, description, enabled, failure_issue_threshold, id, max_runtime_minutes, name, organization, owner, project, recovery_threshold, schedule, timezone`. There is **no** workflow/alert attribute and **no** mute attribute. |
| M4 | Source `internal/provider/resource_cron_monitor_impl.go@v0.15.7` | It builds `ProjectMonitorRequestMonitorCheckInFailure` and posts it to `/0/organizations/{org}/projects/{project}/detectors/` (`internal/apiclient/api.yaml@v0.15.7`). `Fill` sets `m.Id.Set(data.Id)` from the detector. **So `sentry_cron_monitor.id` is the detector id.** |
| M5 | Source `internal/provider/resource_alert_impl.go@v0.15.7` | Create (`:801`) and Update (`:833`) send `DetectorIds: monitorIds`. Read (`:854`) sets `m.MonitorIds` from `data.DetectorIds`. **So `monitor_ids` is the workflow's `detectorIds`, which is the link #8630 needs.** |
| M6 | `examples/resources/sentry_alert/resource-00.tf@v0.15.7` | `monitor_ids = [ sentry_cron_monitor.default.id, sentry_metric_monitor.default.id, sentry_uptime_monitor.default.id, … ]`. The vendor's own example does this exact binding. |
| M7 | Does a provider cron-monitor update detach the workflow? getsentry/sentry `workflow_engine/endpoints/validators/base/detector.py` `update()` + `validators/utils.py` `connect_detectors_to_workflows` (HEAD `2775d16350`, 2026-09-23) | `workflow_ids` is popped only `if "workflow_ids" in validated_data`. Otherwise it is `None`, and `connect_detectors_to_workflows` begins `if workflow_ids is not None:`, so it is a no-op. The provider's detector request carries no `workflowIds` field (`grep -c workflowIds api.yaml` = 0). **So a `terraform apply` of a cron monitor cannot drop its routing.** |
| M8 | Newer provider | `gh release list -R jianyuan/terraform-provider-sentry`: v0.15.7 (2026-09-02) is the latest. `main` is 9 commits ahead. None of them adds a mute or workflow attribute to the cron monitor. |
| M9 | Empty `action_filters[].conditions` | This is schema-optional. `Fill` (`:950`, `:1340`) reads an empty list back as an empty list, not null, so `conditions = []` causes no perpetual diff. The Sentry-default workflow 566201 in the committed capture `phase34-live-workflows-capture-2026-09-09.json` carries `actionFilters[0].conditions: []`, so live Sentry accepts it. |
| M10 | Can the IaC token connect a **cron** detector? getsentry `workflow_engine/endpoints/validators/utils.py` (HEAD `2775d16350`) | Connecting a system-created detector (the issue stream) needs `{"org:write"}`. Connecting a user-created detector (a cron monitor) needs any of `{"org:write", "alerts:write"}` on its project. The IaC token already connects the system-created issue-stream detector on every `sentry_alert` write, most recently the #8505 create on 2026-09-23. So it holds `org:write`, which also satisfies the cron case. A `terraform plan` cannot show a 403, and this is the reason the plan does not need a separate write probe. |
| M11 | Does a cron failure reach **detector-bound** workflows at all? getsentry `monitors/logic/incident_occurrence.py:147-150` + `workflow_engine/processors/detector.py` `_get_detector_for_event` (HEAD `2775d16350`) | The occurrence is built with `evidence_data["detector_id"] = detector.id` whenever `get_detector_for_monitor(monitor)` returns one. The workflow engine resolves the event's detector from exactly that field (`issue_occurrence.evidence_data.get("detector_id")`) and evaluates that detector's workflows, as well as the issue-stream detector's. Every monitor here was created through the detectors API (M4), so each has a detector. **So hop 2 (occurrence to this workflow) is wired at the source.** Phase 0.3 confirms it on one live cron event. |

**Mute is NOT expressible.** There is no attribute in M3, and none in `api.yaml@v0.15.7` (`grep -ci mute` = 0).
Sentry mutes per **monitor environment** (`MonitorEnvironment.is_muted`). It is written by
`PUT …/monitors/{slug}/environments/{env}/` or by Sentry itself. `monitors/tasks/detect_broken_monitor_envs.py`
**auto-mutes** an environment after `NUM_DAYS_BROKEN_PERIOD = 14` days of an open incident, plus
`NUM_DAYS_MUTED_PERIOD = 14` days after the broken-notice email. `monitors/logic/incidents.py:123`
creates no occurrence while muted (`if not monitor_env.is_muted and incident`). The resolve path
never un-mutes. So a muted environment produces no issue for any workflow to act on, and it stays
muted after the cron recovers.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured) | Plan response |
|---|---|---|
| "A red heartbeat pages no one." | This is true for **detector-bound** routing: every cron detector has `workflowIds: []`. It is incomplete in one respect. getsentry `workflow_engine/processors/detector.py` `get_detectors_for_event_data` always adds the project's **issue-stream detector**, unless the group type is in option `workflow_engine.group.type_id.disable_issue_stream_detector` (default `[8001]`, metric issues only, `FLAG_AUTOMATOR_MODIFIABLE`). `MonitorIncidentType` (4001) has `default_priority = HIGH`. So a cron monitor's **first-ever** issue may already reach the Sentry-default workflow 566201 ("Send a notification for high priority issues", `new_high_priority_issue`). That workflow is bound to the issue stream, and its email action config (`{targetType: issue_owners}`) does not record the fallthrough. It fires on nothing after that first issue: a regressed group is already high priority. The captured `lastTriggered` was `null` on 2026-09-09. | Build per the ask. The source-level reading is recorded here; plan review cut a live probe of it because nothing built depends on the answer. The new workflow covers regressions and persistent failures, which no route covers today. The possible duplicate email on a brand-new monitor's first failure is accepted. |
| "5 monitors are muted (credit-probe, follow-through, bug-fixer, daily-triage, content-generator)." | Mute is per monitor environment. Sentry auto-mutes after about 28 days of an open incident and never auto-unmutes. The provider cannot express it (M3). | Every one of them is **routed anyway**: unmuting then pages with no further change. Each gets a measured decision (Phase 0). No mute state is written by this PR. |
| ADR-031 §#6612 amendment exit criterion (b): "give the leg its own monitor slug (or its own job) when … #8630 routes cron-monitor failures". | This PR is that trigger. The sentry leg of `scheduled-terraform-drift.yml` posts to the shared `scheduled-terraform-drift` slug. ADR-031 already records that "the job's Sentry check-in is NOT a channel for it" and that its vendor read failures reach the `[ERROR]` email (step `if: always() && steps.plan.outputs.exit_code != '0'`). | Phase 4: the sentry leg stops posting to the shared slug (a one-condition `if:` narrowing). The ADR amendment records this as the disposition of (b), with the two options it named as rejected alternatives. |
| "Correct runbooks that claim a red monitor pages." | In the expressible branch most such claims become **true** once routing is applied. The exceptions are the muted monitors and claims that name a mechanism or threshold that does not match. Some prose states the inverse ("routes to no workflow (#8630)"), and that goes stale. | Phase 5 is a per-hit disposition table built by an exhaustive sweep. Nothing is edited on keyword match alone. |

## Research Insights

**Premise Validation (Phase 0.6).** #8630 is OPEN with no linked PR. #7634 is OPEN; it covers the
undocumented `workflows/` write envelope for **operator scripts**. This plan writes through the
provider, the same in-band path the 33 existing `sentry_alert` rules use, so it uses no #7634 write
path and does not absorb #7634. #8505 is CLOSED (it measured the 59/5 figures). #8495, #7985, #8681,
#8682, #6437, #8349, #7619, #3829 and #6591 are OPEN and not absorbed. #6590 (the cron-monitor prune
design) is OPEN and interacts only through the routing guard: a pruned monitor's route is deleted
with it, and Terraform refuses a dangling reference anyway. Cited paths exist on `origin/main`
(`8766ff5664`): `versions.tf`, `cron-monitors.tf`, `issue-alerts.tf`,
`scripts/sentry-issue-alert-create-tripwire.sh`, `tests/scripts/lib/sentry-alert-projection.jq`,
`alert-reference.json`. The mechanism was checked against the ADR corpus: ADR-031's deferral of
`sentry_alert` concerned **project-wide** rules needing the issue-stream data source (§Decision,
Amendment 2026-07-17). It never rejected binding cron detectors. ADR-031 line 648 already models
the routing graph `monitor <-(slug)- cron detector -(workflowIds)-> workflow`.

**Property List (Phase 0.6b).**

- P1. A failed or missed check-in on any routed, unmuted cron monitor reaches the operator's inbox.
- P2. A flapping monitor cannot flood the inbox (at most one email per monitor per 24 h).
- P3. A cron monitor added later cannot be silently left unrouted.
- P4. A cron monitor created in the same PR as its route fails loudly at PR time, not as a red `main` after apply.
- P5. Every muted monitor has a recorded, evidence-backed decision, and the gap in what is expressible is on record.
- P6. No runbook, C4 edge, code comment or ADR sentence states a paging behaviour that is false after this lands.
- P7. The shared drift slug cannot page and then auto-resolve on a sentry-leg failure (ADR-031 #6612 criterion (b)).

**Cut List (Phase 0.6b).**

- One `sentry_alert` per monitor (59 workflows): buys nothing over P1 that a single workflow does not.
  Each new monitor would add a new `sentry_alert` address to the AC17 declared/observed bijection and
  to the census. Cut.
- Binding the issue-stream detector with an `issue_category = cron` action filter (no per-monitor
  list): covers P1 and P3 without a map, and without the P4 problem. Cut as the primary mechanism for
  three reasons. It depends on a Sentry-side, automator-modifiable option (`disable_issue_stream_detector`)
  that this repo cannot see or pin. The audit's Class A (`workflowIds` empty) would keep reporting all
  59 as unrouted, which is false and would need a new predicate. The projection allowlist
  (`condition_kinds: ["tagged_event"]`) would need a new kind on both sides. Recorded as the rejected
  alternative in the ADR amendment.
- A repo-side "muted monitor" audit class: P5 is met by the per-monitor decision table. Sentry
  itself emails members when it auto-mutes ("N of your Cron Monitors have been muted",
  `detect_broken_monitor_envs.py`). Cut. If the table later shows mutes recurring unseen, that is
  the re-evaluation trigger.
- Destroy-and-recreate to clear a mute: `cron-monitors.tf` records (#3958 residual, above
  `workspaces_luks_verify`) that a removed monitor is **deactivated, not deleted**. Re-adding the name
  adopts the existing object, mute included. It also needs `[ack-destroy]`. Cut.
- A new seat-billed monitor slug for the drift sentry leg (ADR option "own slug"): P7 is met by not
  posting the sentry leg to the shared slug, at no cost. Cut (see Phase 4).

**Value-proposition measurement (0.6c):** not triggered. The justification is detection, not a
cost saving. Cost delta: `sentry_alert` carries no seat charge
(`2026-05-15-sentry-iac-billing-and-quirks.md` Gotcha 3: only cron monitors are seat-billed), and no
monitor is added.

**Relevant files (verified).**

- `apps/web-platform/infra/sentry/cron-monitors.tf`: 59 `resource "sentry_cron_monitor"` blocks, and
  only those. `sentry-monitor-iac-parity.test.ts` reads every top-level `name = "…"` in this file as a
  monitor slug and pins that count to `^resource "sentry_cron_monitor"`. So a second resource
  carrying `name =`, such as a `sentry_alert`, would break it. A `locals` block would not. The new
  file keeps this one single-purpose, which is the reason for it (DHH, plan review).
- `apps/web-platform/infra/sentry/issue-alerts.tf`: the `anthropic_credit_exhausted` block (#8505)
  is the shape to mirror. It uses `enabled = true` explicitly, `frequency_minutes = 1440`, lifecycle
  triggers plus `event_frequency_count {1h, 0}`, an email `issue_owners`/`ActiveMembers` action, and
  `ignore_changes = [environment]`.
- `tests/scripts/lib/sentry-alert-projection.jq` `tf_rule`: floors `monitor_ids` to `type == "array"`
  only. A partially-unknown set passes that check. Measured in a scratch root with `terraform_data`:
  `toset(["known-1", terraform_data.new.id])` renders in `planned_values` as `["known-1", null]` with
  `after_unknown: [false, true]`. **`def excluded` is not touched.**
- `.github/workflows/apply-sentry-infra.yml`: the create gate (`sentry-create-gate.sh`, diff-matched
  to an added block, which passes), the tripwire (refuses only `sentry_issue_alert` creates and
  legacy-trigger `sentry_alert` writes, which pass), the reference gate (the committed
  `alert-reference.json` must equal the plan projection, so it needs regeneration), the AC17
  declared/observed set (globs `./*.tf`, so the new file is counted; there is no `for_each`/`count`,
  which AC17 forbids), and the post-apply fidelity probe (its reference is projected from the apply
  plan, `:866-881`).
- `apps/web-platform/scripts/sentry-monitors-audit.test.sh` T25 derives `n_salert` across
  `infra/sentry/*.tf`, and the README must carry the bold phrase "34 `sentry_alert` rules".
- `apps/web-platform/scripts/sentry-monitors-audit.sh:1380-1390`: the Class A report calls
  "`class_a_count == cron_detector_count` HOLDS" a true fact about the org, and calls its failure
  "Routing changed … confirm it was intended". After this PR, the healthy steady state is
  `class_a_count == 0`.
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`: the heartbeat-step
  shape guard (#7834) requires `if:` to **contain** `always()`, plus `continue-on-error: true`. The
  Phase 4 narrowing keeps both.
- `plugins/soleur/test/c4-count-parity.test.sh`: rows C1-C7 do not count `sentry_alert`, and Phase 4
  changes no `monitor-slug:` value, so C5 is unchanged.
- `knowledge-base/engineering/architecture/diagrams/model.c4:764` (`sentry -> founder`): "The cron
  monitors open an issue on a missed/failed check-in … both of which then fire that same email route."
  This is false today and becomes true only for routed, unmuted cron monitors. The uptime half stays
  unverified.

**Institutional learnings applied.**

- `2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md`: a "pages" claim is three hops (the
  emit keeps what the rule filters on, the rule exists, the rule routes to a person). Here: hop 1 is
  the cron occurrence (suppressed while muted), hop 2 is this workflow, hop 3 is the
  `ActiveMembers` fallthrough. The post-apply check reads all three.
- `2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target.md`:
  adding a `sentry_alert` means adding the block **and** regenerating `alert-reference.json`.
- `2026-05-15-sentry-iac-billing-and-quirks.md`: no seat cost for alerts. A re-added monitor adopts
  its old object.
- `2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods.md`: control volume with
  lifecycle triggers plus `frequency`, not with severity.
- The #8050 projection header: "A projected attribute unknown at plan time … is fixed in a follow-up
  PR". The Guard 2 floor makes that policy fire at PR time for `monitor_ids`.

**CLI verification (#2566).** Every Terraform token below was verified against the 0.15.7 schema
dump (M2). The `curl` and `jq` read shapes mirror the live-verified recipe in
`knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` (`organizations/$SENTRY_ORG/monitors/`)
and the `workflows/` read measured in #7634 (2026-08-19).

**Functional overlap (1.5b):** 3/3 registries queried. No community skill or agent routes Sentry
cron alerts through Terraform. Nothing installed. **Community discovery (1.5):** no uncovered stack
(Terraform/TypeScript/bash).

## Implementation Phases

### Phase 0 — Read-only measurement (work phase, before any edit)

All reads use the read-only paths already documented. No write to Sentry happens in this phase or
in this PR.

- 0.1 **Per-monitor state for all 59.** `GET organizations/{org}/monitors/?per_page=100` (paginated):
  record `slug`, `status`, and each environment's `isMuted`, `status` and `lastCheckIn`. Then list
  the muted ones. If the set differs from the five named in #8630, the measured set wins, and the
  difference is recorded. **Also list every unmuted monitor that is red now.** The new route will
  not email about these until their next regression (§1.2), so this list, in the #8630 comment, is
  how the existing backlog reaches the operator. It is a list only; fixing or tracking each red
  cron is outside #8630 (plan review).
- 0.2 **For each muted environment:** `GET …/monitors/{slug}/checkins/?per_page=20`. Record the last
  `ok` check-in, and whether any `ok` check-in is newer than the start of the open incident.
- 0.3 **Hop 2 on live data (CTO review).** Read the latest event of one cron issue
  (`GET projects/{org}/{project}/issues/?query=issue.category:cron&sort=new&limit=1`, then that
  issue's latest event) and record whether its occurrence carries `evidenceData.detector_id`, and
  whether that id equals the monitor's detector id. If it is absent, M11 does not hold live.
  **Stop**: the detector-bound design cannot fire, and the issue-stream plus `issue_category`
  alternative (§Cut List) becomes the design. That change goes back through plan review; it is not
  improvised in the work phase.
- 0.4 Post the measurement (0.1-0.3) plus the provider verdict (M1-M11) as a comment on #8630
  **before** the PR is marked ready.

(The earlier 0.4 probe of the Sentry-default workflow's `lastTriggered` was cut at plan review: it
was "a finding, not a gate", and nothing built depends on it. §Research Reconciliation keeps the
source-level reading.)

### Phase 1 — The workflow (`apps/web-platform/infra/sentry/cron-monitor-alerts.tf`, new)

```hcl
# apps/web-platform/infra/sentry/cron-monitor-alerts.tf  (sketch — the work phase writes the full header)
locals {
  # label => "<reason> (#<issue>)". Declared-unrouted cron monitors. EMPTY at merge.
  # Not read by any resource: it is the reviewed record Guard 1 checks against.
  # The one legitimate use: a monitor created in the same PR, whose detector id is unknown at plan
  # time (Guard 2 refuses to project it). Route it in the follow-up PR after its first apply.
  cron_monitor_alert_unrouted = {}
}

resource "sentry_alert" "cron_monitor_failure" {
  organization      = var.sentry_org
  name              = "cron-monitor-failure"
  enabled           = true
  frequency_minutes = 1440
  # ONE element per `resource "sentry_cron_monitor"` in this root, minus the unrouted map.
  # Guard 1 (sentry-cron-monitor-routing-parity.test.ts) holds the two sets equal.
  monitor_ids = [
    sentry_cron_monitor.cron_action_required_sla.id,
    sentry_cron_monitor.scheduled_terraform_drift.id,
    # ... all 59, generated by the derivation command below, sorted by label ...
  ]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = []
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}
```

- 1.1 Generate the route entries from the monitors that are actually declared, never by hand:
  `grep -hoE '^resource "sentry_cron_monitor" "[a-z0-9_]+"' apps/web-platform/infra/sentry/*.tf | awk -F'"' '{print $4}' | LC_ALL=C sort`.
  That yields 59 labels today, and each becomes one `sentry_cron_monitor.<label>.id,` element.
  An inline list rather than a label-to-id map (plan review): the id reference already names its
  label, so a map key could only disagree with its value.
- 1.2 **Trigger rationale** (goes in the file header). The cron occurrence fingerprint is
  `crons:{monitor_env.id}` (getsentry `monitors/models.py` `build_occurrence_fingerprint`), so each
  monitor environment is **one** issue group for its whole life:
  - `first_seen_event` fires on its first incident.
  - `regression_event` fires on each failure after a recovery.
  - `reappeared_event` fires when an issue the operator archived "until escalating" escalates. For a
    cron issue that means the cron failed again after the operator archived it. Without this trigger,
    archiving a cron issue would silence it for good.
  - `frequency_minutes = 1440` throttles actions **per group** (the per-workflow, per-group action
    status). So a flapping monitor emails at most once per 24 h. The accepted cost (CTO review): a
    monitor that recovers and fails again within 24 h of its last email sends no second email. The
    first email already reached the operator, and the Sentry issue shows the regression.
  - **No `event_frequency_count` re-page, deliberately** (scoped advisor consult, Phase 4.5). With
    it, every monitor that is chronically red at apply time would email on day one and then daily,
    which teaches the operator to filter the new alert before it has caught a single new failure.
    Without it, a persistent failure emails once, at its start. The reminder for a long outage is
    Sentry's own broken-monitor email at 14 days and its mute notice at about 28 days
    (`detect_broken_monitor_envs.py`). The chronically-red backlog that exists at apply time is
    surfaced once, by Phase 0.1's list, instead of by email. Revisit only if a persistent failure
    is later missed because it emailed just once.
  The provider hard-codes `any-short` for the triggers, so any single trigger fires.
- 1.3 Expected first-apply volume: **no burst.** A monitor whose incident is already open at apply
  time does not fire until it recovers and fails again (then `regression_event`). #8495's two
  watchdogs (`scheduled-inngest-health`, `scheduled-zot-restart-loop`) are **routed**: their missed
  check-ins are real (GitHub is not starting the runs), they recover and fail again several times a
  day, and the throttle caps them at one email per day each. They are also the first live proof that
  the route works (AC16). #8495 is not absorbed. The accepted cost (CTO devex review) is about two
  known-noise emails a day until #8495 lands. The recorded exit: if #8495 is still open 14 days
  after the first observed fire, move the pair to `cron_monitor_alert_unrouted` citing #8495 in a
  follow-up PR, so this noise does not become the operator's reason to filter the alert.
  The email goes to every active org member: cron issues have no owners, so `issue_owners` always
  falls through to `ActiveMembers`. With one operator that is the right audience. With more members
  it is everyone.
- 1.4 `environment` stays unset, which is the root's convention. Every heartbeat posts with no
  `environment`, so all monitor environments are Sentry's default `production`.
  `.github/actions/sentry-heartbeat/action.yml` and `_cron-shared.ts` `postSentryHeartbeat` build no
  environment parameter.
- 1.5 `terraform fmt -check` and `terraform validate` (`init -backend=false`) pass locally, as
  `infra-validation.yml` runs both.

### Phase 2 — Guards (tests before the code they guard: `cq-write-failing-tests-before`)

- 2.1 **Guard 1: routing parity**, in a new file
  `apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`. The existing
  `sentry-monitor-iac-parity.test.ts` is 571 lines long, and its helpers read only `cron-monitors.tf`
  (Kieran). Parse line by line after dropping `#` comment lines. For monitors, match
  `^resource "sentry_cron_monitor" "<label>"` across all `infra/sentry/*.tf`. For routes, match lines
  from `^\s*monitor_ids\s*=\s*\[` to the next `^\s*\]`. For unrouted, match lines from
  `^\s*cron_monitor_alert_unrouted\s*=\s*\{` to the next `^\s*\}`. Anchoring on the start of the
  line keeps the file's own header prose from matching (`cq-assert-anchor-not-bare-token`). Write
  it RED against the pre-Phase-1 tree first. The failure text names the fix: add
  `sentry_cron_monitor.<label>.id` to `monitor_ids`, or add `<label> = "<reason> (#N)"` to
  `cron_monitor_alert_unrouted`, and it gives the §1.1 derivation command. Details are in §Guard
  Contract.
- 2.2 **Guard 2: the unknown-detector floor** in `tests/scripts/lib/sentry-alert-projection.jq`
  `tf_rule`, placed right after the existing `monitor_ids` array floor:
  `if ($v.monitor_ids | any(. == null)) then error("\($a): monitor_ids carries \([...] | length) element(s) unknown at plan time — a monitor created in this plan cannot be routed in the same apply (its detector id does not exist yet); list it in local.cron_monitor_alert_unrouted in cron-monitor-alerts.tf with a (#N) reason and route it in a follow-up PR after the first apply") else . end`.
  Fixture rows go in `tests/scripts/test-sentry-alert-reference-gate.sh`, which already builds plan
  documents with `monitor_ids` (its fixture builder, ~lines 54-57). Give `sensitive_values.monitor_ids`
  the same length as `monitor_ids`. Through the gate script the floor surfaces as **rc 1**
  (`sentry-alert-reference-gate.sh` exits 1 on a jq error), so matrix rows use the suite's `_red`
  helper plus the exact error text. One extra row calls `jq -f` directly and expects **rc 5**. Raise
  the suite's `EXPECTED_TESTS` by the number of rows added. Write the rows before the floor.
- 2.3 Why Guard 2 is needed and not merely tidy: without it, a future "add monitor 60 and route it"
  PR projects `detectorIds: [..., null]`. The PR-time reference gate then goes green once the author
  commits that projection. The post-apply probe compares live (the real id) with a reference
  projected from the apply plan (`null`), and `main` goes red after a **complete** apply. That is
  the #8050 class, and this plan would otherwise introduce it.

### Phase 3 — Reference, counts and prose tied to the new rule

- 3.1 `apps/web-platform/infra/sentry/alert-reference.json`: regenerate it from CI. Push, and the
  `plan_pr` reference gate goes red and uploads `sentry-alert-reference-expected-<run>`. Download it
  with `gh run download <run> -n sentry-alert-reference-expected-<run>`, copy it into place, and
  re-push. Assert the diff is exactly one added key (`cron-monitor-failure`) with 59 `detectorIds`.
  Any other key changing means live drift or a projection defect: stop and investigate.
- 3.2 `apps/web-platform/infra/sentry/README.md`: change the bold "33 `sentry_alert` rules" to
  "34" (T25), and add the routing note to the "59 cron monitors" bullet. Add a short "Adding or
  removing a cron monitor" procedure, covering all of the steps (CTO devex review):
  - **PR 1** declares the monitor and adds `<label> = "route after first apply (#N)"` to
    `cron_monitor_alert_unrouted`. `#N` is the monitor's own tracking issue, and that issue gets a
    one-line "route after first apply" note.
  - **PR 2**, after PR 1's apply, moves the label into `monitor_ids`. It regenerates
    `alert-reference.json` from the CI artifact, because `detectorIds` changes.
  - **Removing a monitor** deletes its `monitor_ids` element in the same PR, and that PR also
    regenerates `alert-reference.json`.
  - The rule is called **"the two-PR rule"** everywhere, and the channel is called "email" (CTO devex
    naming).
- 3.3 `apps/web-platform/infra/sentry/cron-monitors.tf` header: one paragraph pointing new monitors at
  `cron-monitor-alerts.tf` and at the two-PR rule. Comments only; no resource is added to this file.
- 3.4 `apps/web-platform/scripts/sentry-monitors-audit.sh` Class A: after this PR the healthy
  state is `class_a_count == 0`. The work is larger than editing the report strings (Kieran):
  - **A new jq step** lists the unrouted slugs, reusing the existing `cron_detector_slugs` binding
    (structured slug first, `.name` as fallback).
  - **The report block** (`} > "$out_file"`) lists those slugs as bullets. It drops the "HOLDS: no
    cron monitor … routes" framing that treats all-unrouted as normal.
  - **One `::warning::` annotation** naming the slugs, written to stderr **outside** the report
    redirect like the script's other warnings. This makes a pending route under the two-PR rule
    visible on every apply run.
  - **Tests first** in `apps/web-platform/scripts/sentry-monitors-audit.test.sh`. T19 today asserts
    that no slug is listed (a negated `grep -qE` for the `m1` bullet); it must be **inverted** to assert that
    the unrouted slug is listed, not merely reworded. Adjust T3/T15 if their strings move, and add a
    row asserting the `::warning::` goes to stderr and not into the report file.

  The Class A **predicate** (`workflowIds` empty) does not change.

### Phase 4 — ADR-031 #6612 exit criterion (b): the drift sentry leg leaves the shared slug

- 4.1 In `.github/workflows/scheduled-terraform-drift.yml`, change the `Sentry check-in (final)`
  step (`monitor-slug: scheduled-terraform-drift`, `uses: ./.github/actions/sentry-heartbeat`) from
  `if: always()` to `if: always() && matrix.directory != 'apps/web-platform/infra/sentry'`.
  `continue-on-error: true` and terminality stay as they are, so the #7834 shape guard still passes.
- 4.2 Why this meets (b): the harm (b) names is "a shared slug would then page and auto-resolve
  within minutes". With the sentry leg no longer posting to the slug, its failure cannot flip it.
  ADR-031 already states that this check-in "is NOT a channel for" the sentry leg: its failures reach
  the per-leg `[ERROR] Terraform plan failed for …` email (`if: always() && steps.plan.outputs.exit_code != '0'`),
  and that path is unchanged. The job's liveness still comes from the other two legs' check-ins.
  This is a **coverage reduction** for the sentry leg on the monitor channel, and the amendment says
  so: the `[ERROR]` email is its safety net, not the monitor.
- 4.2a The other two legs (`apps/web-platform/infra`, `infra/github`) keep posting to the shared
  slug, so one leg's `error` can still be followed by another leg's `ok`. That is **accepted and
  recorded**. Criterion (b) was written about the sentry leg's vendor-caused plan failures. A
  failure of either of the other two legs is a genuine drift-check failure, and it now pages before
  a sibling's `ok` resolves the issue. The email is sent at the `error`, so the later resolve does
  not unsend it.
- 4.3 Rejected, and recorded in the amendment: a separate `scheduled-terraform-drift-sentry` monitor
  (a 60th seat-billed monitor, a new resource, a matrix-expression `monitor-slug:`, and, under
  Guard 2, a second PR to route it), and "accept it" (it contradicts a criterion the ADR set the
  same day).
- 4.4 Test: add a row to `sentry-monitor-iac-parity.test.ts`'s existing heartbeat block. Select the
  step by job `drift-check` **and** step name `Sentry check-in (final)`, because the file has a
  second heartbeat step, in `heartbeat-live-reconcile` (Kieran). Assert that its `if:` excludes the
  sentry leg. The must-PASS row is the existing #7834 shape guard.

### Phase 5 — Paging-claim corrections (fix only what becomes false)

Plan review cut this to the property P6 asks for. Claims that are true once routing is live stay as
they are.

- 5.1 Find candidates with
  `git grep -n -iE '(monitor|heartbeat|check-?in)[^|]{0,120}\b(pages?|paged|paging|RED\b)' -- knowledge-base/engineering/operations/ apps/web-platform/infra/sentry/ knowledge-base/engineering/architecture/diagrams/model.c4`
  plus `git grep -n '#8630'`.
- 5.2 Edit only three kinds of claim:
  - A claim about a **muted** monitor (per the Phase 0.1 list) that says it pages. Correct it to
    "routed but muted: sends no email until unmuted".
  - A claim that a cron monitor **routes nowhere**. Correct it.
  - A claim naming the **wrong threshold or channel**, checked against the `.tf`.

  List the edited lines in the PR body. The disposition table and the pointer edits to claims that
  are already true were cut at plan review.
- 5.3 Known edits (verified 2026-09-24):
  - `runbooks/cloud-scheduled-tasks.md:527-529`: "turns RED too but is muted and routes to no
    workflow (#8630)". Change it to "routed, but muted", and keep "do not rely on it to page" while
    the monitor stays muted.
  - `runbooks/cloud-scheduled-tasks.md:487-491` §Alerting: the paragraph is the runbook's one
    statement of how cron failures alert. Add one sentence (CTO devex review): a persistent failure
    emails **once** at its start; the next reminder is Sentry's broken-monitor email at 14 days; and
    a muted monitor sends nothing.
  - Recheck each muted monitor named in Phase 0.1 against the other known hits
    (`cloud-scheduled-tasks.md:510,542`, `oauth-probe-failure.md:34`, `github-app-drift.md:20`,
    `kb-template-health.md:17`, `workspaces-luks-cutover-6604.md:307`, `inngest-server.md:600,607,2003`).
    Edit a hit only if it concerns a muted monitor.
  - `model.c4:764` `sentry -> founder`: see §C4.
- 5.4 `apps/web-platform/infra/sentry/cron-monitors.tf:803` "a dead cron in this set paged nowhere" is
  a historical statement about unknown slugs before the 2026-06-11 backfill. It stays.

### Phase 6 — ADR, C4, issue comments

- 6.1 Append `**Amendment (2026-09-24, #8630) — cron detectors route to one email workflow**` to
  `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`. It is append-only:
  no earlier sentence is edited. Plan review trimmed it to the decisions, with a link to this plan
  for the evidence (M1-M11 and the rejected alternatives):
  - the verdict (expressible at 0.15.7) and the one-workflow design
  - the two-PR rule, and why it exists (Guard 2 and the #8050 contract)
  - that mute cannot be expressed in the provider, and that Sentry auto-mutes
  - the disposition of exit criterion (b), including the sentry leg's coverage reduction and the
    accepted shared-slug behaviour of the other two legs
  - the revisit option from the CTO review: a live-to-live `detectorIds` check that would retire
    the two-PR rule if pending route PRs pile up

- 6.2 C4: see §Architecture Decision (ADR/C4).
- 6.3 The comment on #8630 (Phase 0.4) carries the measurement and the muted-monitor decision table.
  Any "unmute" decision is tracked per §Muted-monitor decisions.

## Muted-monitor decisions

Mute is not Terraform-expressible (M3). This PR writes no mute state and adds no write path outside
Terraform. Every muted monitor is **included in `monitor_ids`**, so an unmute starts emailing with
no further change.

The decision rule is applied to each monitor from the Phase 0 data:

| Measured state | Decision | Action in this PR |
|---|---|---|
| Still failing (the latest check-ins are `error`/`missed`, and no `ok` has come since the incident started) | **Stay muted.** Unmuting a known-broken cron sends a daily email about a failure that is already known, and Sentry re-mutes it after about 28 days anyway. The fix is the cron's own repair. | Name the root-cause tracking issue (find an existing one first, e.g. credit exhaustion on #8505's lineage). File one only if none exists. Record "unmute when the cron recovers" on that issue. |
| Recovered (an `ok` check-in newer than the incident start, and the latest status `ok`) | **Unmute.** A recovered monitor that stays muted is silent forever, because Sentry never auto-unmutes. | Not executed here. The only write paths are the monitor-environment REST `PUT` and Sentry's web app. Both are writes to prod alerting config outside Terraform, which this PR's brief forbids and which need a per-command go-ahead (`hr-menu-option-ack-not-prod-write-auth`). File **one** tracking issue listing the monitors to unmute, with the Phase 0 evidence and the existing recipe (`runbooks/cloud-scheduled-tasks.md` §"After a PROLONGED (multi-day) outage"). Reference it as `Tracks #N` in the PR body (`wg-block-pr-ready-on-undeferred-operator-steps`). |

The recorded hypothesis, to be confirmed or refuted by Phase 0: the five named monitors
(`scheduled-anthropic-credit-probe`, `scheduled-follow-through`, `scheduled-bug-fixer`,
`scheduled-daily-triage`, `scheduled-content-generator`) are Anthropic-dependent crons auto-muted
during the 2026-09 credit-exhaustion window (#8505). This is not assumed.

## PR body first line

`Merging this mutates production: apply-sentry-infra.yml auto-applies the Sentry root on push to
main (paths: apps/web-platform/infra/sentry/**), creating the cron-monitor-failure workflow.`

## Files to Create

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`
- `apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` (Guard 1)

## Files to Edit

- `apps/web-platform/infra/sentry/alert-reference.json` (regenerated from CI, Phase 3.1)
- `apps/web-platform/infra/sentry/README.md`
- `apps/web-platform/infra/sentry/cron-monitors.tf` (header comment only)
- `tests/scripts/lib/sentry-alert-projection.jq` (`tf_rule` floor only; `def excluded` untouched)
- `tests/scripts/test-sentry-alert-reference-gate.sh`
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` (Phase 4.4 row only)
- `apps/web-platform/scripts/sentry-monitors-audit.sh` (Class A: unrouted-slug listing and one `::warning::`)
- `apps/web-platform/scripts/sentry-monitors-audit.test.sh`
- `.github/workflows/scheduled-terraform-drift.yml` (one `if:`)
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` (append-only amendment)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (`sentry -> founder` edge prose)
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md`
- `knowledge-base/engineering/operations/runbooks/oauth-probe-failure.md`
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 24 to 25,
  with the PLACEMENT/TRUTH/NO SUBSTITUTE comment its failure text asks for. This plan's
  `discoverability_test` declares `credentials_required`, and the ratchet counts every declaring plan,
  so the bump belongs in this PR.
- further runbooks only where Phase 5.2 finds a muted-monitor claim

## Open Code-Review Overlap

Checked 2026-09-24 against 76 open `code-review` issues, for every path in the two lists above.
One match:

- #8595 (monitor registry guard gaps: stale `NON_INNGEST_MONITORS` entries, no cadence parity).
  **Acknowledge.** Its fix lives in `function-registry-count.test.ts`. It names
  `sentry-monitor-iac-parity.test.ts` only in a "related gap" note about cadence parity, which #8450
  has since added to this file (the `GHA schedule cron ↔ monitor crontab parity` describe block).
  This plan adds a separate describe block for routing parity and touches neither registry.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-031** (append-only; see Phase 6.1). No new ADR: this extends ADR-031's paging model and
closes the gap its line-648 routing graph already names. It does not create a new substrate or trust
boundary.

### C4 views

All three model files were read for this plan:
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.

- **Actors and systems checked:** `founder` (the operator, who receives the email), `sentry`,
  `github` (the heartbeat emitter), `webapp` (the Inngest heartbeat emitter), `betterstack` (the
  second paging exit). All are already modeled. There is no new actor, external system, container or
  store: the email route is Sentry's existing `sentry -> founder` edge.
- **Relationship that changes:** the prose of `sentry -> founder` (`model.c4:764`). Its closing
  sentence claims cron monitors "then fire that same email route". Replace it with the true
  statement: cron-monitor issues reach email through `sentry_alert.cron_monitor_failure`, which is
  bound to every routed cron detector. Muted monitor environments produce no issue, and so no page.
  The uptime detectors are bound to no workflow; do not claim a route for them. Also update the
  counts the edge cites ("29 of the 31 IaC rules in issue-alerts.tf" is scoped to that file and stays
  true; add that the root now carries one more `sentry_alert`, in `cron-monitor-alerts.tf`).
- **Counts** (`github -> sentry` C1-C7) do not move: no monitor is added and no slug changes. Run
  `bash plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`
  and `c4-render.test.ts` after the edit.

### Sequencing

It lands whole in this PR. The amendment describes the applied state. Its muted-monitor rows
describe the measured state at authoring time.

## User-Brand Impact

- **If this lands broken, the user experiences:** a cron that protects a user surface (for example
  the GitHub App drift guard, which the Art. 30 register names as an Art. 33 latency primitive, or
  the Inngest watchdog) goes red, and the operator is still not emailed. That is today's state,
  continued silently under a false "now routed" belief. Or the operator's inbox floods and real pages
  get skimmed past (bounded here to one email per monitor per 24 h).
- **If this leaks, the user's data is exposed via:** nothing new. Cron-issue emails carry the
  monitor slug, check-in times and status. The emitters attach no user payload to check-ins, and the
  recipients are the org's active members, the same audience as every existing rule.
- **Brand-survival threshold:** `aggregate pattern`. The change adds a detection route and edits no
  existing one (`issue-alerts.tf` untouched). A single failure of this route reproduces the status
  quo rather than harming a user. The harm is the aggregate of undetected cron failures over time.

## Observability

```yaml
liveness_signal:
  what: "sentry_alert.cron_monitor_failure (Sentry workflow 'cron-monitor-failure') bound to every routed cron detector; its lastTriggered advances on each fire, and the audit's Class A count reads 0"
  cadence: "per failed/missed check-in (per-group action throttle 1440 min); the audit runs on every apply-sentry-infra.yml plan"
  alert_target: "operator email via Sentry (issue_owners -> ActiveMembers fallthrough)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitor-alerts.tf"
error_reporting:
  destination: "Sentry web-platform project (the cron issue itself, MonitorIncidentType 4001)"
  fail_loud: "apply-sentry-infra.yml red on apply/plan/gate failure; sentry-alert-live-fidelity.sh FAIL line naming cron-monitor-failure on any live divergence (detectorIds, actions, triggers)"
failure_modes:
  - mode: "the workflow is deleted or edited through Sentry's web app (a detector detached, the email action removed)"
    detection: "post-apply and daily scripts/sentry-alert-live-fidelity.sh (scheduled-sentry-alert-drift.yml) field-for-field against alert-reference.json; the scheduled-terraform-drift.yml sentry leg (12h full-root plan, exit 2 files an infra-drift issue)"
    alert_route: "infra-drift GitHub issue + the fidelity probe's failure email"
  - mode: "a new sentry_cron_monitor is declared without a route"
    detection: "Guard 1 (sentry-monitor-iac-parity.test.ts) red at PR time"
    alert_route: "PR check failure"
  - mode: "a monitor is routed in the same PR that creates it (detector id unknown at plan)"
    detection: "Guard 2 (sentry-alert-projection.jq tf_rule floor) errors in the plan_pr reference gate"
    alert_route: "PR check failure naming the address and the unrouted-map remedy"
  - mode: "a routed monitor environment is auto-muted by Sentry (about 28 days of continuous failure)"
    detection: "Sentry's own muted-monitors email to members (detect_broken_monitor_envs.py); the 14-day broken-monitor email before it"
    alert_route: "operator email from Sentry (vendor mechanism)"
  - mode: "a detector loses its workflow binding without the workflow changing"
    detection: "sentry-monitors-audit.sh Class A > 0 lists the unrouted slugs (Phase 3.4) on every apply-sentry-infra.yml run"
    alert_route: "the audit report (sentry-audit-gate / apply job summary)"
logs:
  where: "Sentry issue stream (cron issues) and the workflow's lastTriggered; the apply-sentry-infra.yml run logs and step summary"
  retention: "Sentry plan retention (the project default); GitHub Actions logs 90 days"
discoverability_test:
  command: "bash scripts/sentry-alert-live-fidelity.sh"
  expected_output: "PASS (all"
  credentials_required: "Sentry IaC token (Doppler prd SENTRY_IAC_AUTH_TOKEN exported as SENTRY_AUTH_TOKEN, with SENTRY_ORG and SENTRY_API_HOST set), read-only — the property is the LIVE content of the cron-monitor-failure workflow (its detectorIds binding and email action) compared field-for-field against alert-reference.json, and no unauthenticated Sentry endpoint exposes a workflow"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Sentry org workflow object 'cron-monitor-failure' (vendor-hosted alert config; no user data, only detector ids, trigger and action config)"
    mechanism: "provider-managed:Sentry-SOC2-Type-II"
    evidence: "Sentry security & compliance https://sentry.io/security/ (retrieved_on 2026-09-24); the same store already holds this root's 33 workflows"
    defends_against: "exposure of Sentry's storage medium or backups"
    does_not_defend: "a leaked SENTRY_IAC_AUTH_TOKEN or an org member session reading or editing the workflow; the workflow is config, and anyone with alerts:write can change routing"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: vendor-internal storage; only the attestation is observable"
  - store: "apps/web-platform/infra/sentry terraform.tfstate (R2 backend) — gains one sentry_alert row holding the 59 detector ids (no secret values)"
    mechanism: "provider-managed:Cloudflare-R2-SOC2-Type-II"
    evidence: "the existing R2 backend attestation used by this root (https://developers.cloudflare.com/r2/reference/data-security/, retrieved_on 2026-09-24)"
    defends_against: "R2 storage-medium exposure"
    does_not_defend: "a leaked R2 access key or any principal allowed to run terraform state pull"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: vendor-internal storage"
in_transit:
  - connection: "terraform (GitHub runner) -> Sentry API (workflow create/read)"
    enforced_at: "apps/web-platform/infra/sentry/main.tf (provider \"sentry\" base_url on the org subdomain, HTTPS; default TLS verification)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised runner holding SENTRY_IAC_AUTH_TOKEN in process memory"
    disclosed_as: "not-publicly-claimed"
  - connection: "Sentry -> operator mailbox (notification email; existing vendor route, unchanged)"
    enforced_at: "vendor-side (Sentry outbound mail); no repo code sets it"
    tls: "SMTP with opportunistic STARTTLS (vendor-controlled)"
    cert_verification: "off"
    does_not_defend: "an on-path attacker downgrading STARTTLS between Sentry's MTA and the receiving MX; the mailbox provider reading content"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "The Sentry to mailbox hop is the pre-existing notification route that all 33 current rules use; this PR adds no new connection class, and the email carries no user data (a monitor slug and check-in status only)"
  tracking_issue: "#8630"
  reevaluate_when: "a cron issue email is made to carry user-identifying content, or Sentry documents enforced TLS for notification mail"
  expires_on: "2026-12-20"
```

## Guard Contract

### Guard 1 — cron-monitor routing parity

**Property.** Every `sentry_cron_monitor` declared anywhere in the Sentry root is either listed in
`sentry_alert.cron_monitor_failure.monitor_ids` as `sentry_cron_monitor.<label>.id` or listed in
`local.cron_monitor_alert_unrouted` with a reason citing `#<n>`. No monitor is in both lists or in
neither, and every element of `monitor_ids` is such a reference.

**Assembly.** There are three sites, and each one is read.

- **Declared monitors:** every `^resource "sentry_cron_monitor" "<label>"` in **all**
  `apps/web-platform/infra/sentry/*.tf`, not only `cron-monitors.tf`.
- **Routed set:** the elements of the `monitor_ids` list in `cron-monitor-alerts.tf`. This is the
  one place ids reach Sentry.
- **Unrouted set:** the keys of `cron_monitor_alert_unrouted`.

Comment lines are dropped before matching.

**Mutation matrix** (rows 5, 8 and 9 and harness rows H1 and H2 were cut at plan review: they
guarded a map that no longer exists, or a dangling reference `terraform validate` already refuses):

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one element from `monitor_ids` | RED, naming the label |
| 2 | The guard reads zero `.tf` files or zero monitors (its own dispatch) | RED (anti-vacuity: declared count ≥ 1 and equal to an independent `^resource "sentry_cron_monitor"` count across `*.tf`) |
| 3 | Add two new `sentry_cron_monitor` blocks to `cron-monitors.tf` and route only the first | RED, naming the second |
| 4 | Declare an unrouted `sentry_cron_monitor` in `uptime-monitors.tf` (a sibling file) | RED |
| 6 | Put a label in both `monitor_ids` and `unrouted` | RED |
| 7 | An unrouted entry whose reason has no `#\d+` | RED |
| 10 | A `monitor_ids` element that is not a `sentry_cron_monitor.<label>.id` reference (for example a string literal) | RED |

**Harness rows.** Each fixture row asserts the **specific** offending label in the checker's
result, not merely a non-empty result, so a checker that returns early fails. Must-PASS
non-canonical inputs:

- (P1) `monitor_ids` in a different order, with different whitespace and a trailing comment
- (P2) a fixture with one monitor in `unrouted` under a valid `(#1234)` reason and absent from
  `monitor_ids`

**Anchor.** The guard compares `.tf` with `.tf` inside one commit, so a single diff can delete a
monitor and its route together. That is legitimate, and the full-root destroy gate
(`[ack-destroy]`) is the outside anchor for a monitor deletion. A single diff can also move a live
monitor into `unrouted` under any issue number, and the guard cannot check that issue offline. The
outside signal is the Class A listing and its `::warning::` on every apply run (Phase 3.4). This
is stated as a known limit, not claimed as integrity.

### Guard 2 — unknown-detector projection floor

**Property.** No `sentry_alert` whose `monitor_ids` contains an element unknown at plan time is ever
projected into an alert reference. The projection errors, naming the address and the remedy.

**Assembly.** `tf_rule` in `tests/scripts/lib/sentry-alert-projection.jq` is the only reader of
`monitor_ids` on the TF side. The live side reads `detectorIds`, which are never unknown. Its call
sites: `scripts/sentry-alert-reference-gate.sh` (the PR-time gate) and the apply job's pre-apply
projection (`apply-sentry-infra.yml:880`). Both inherit the floor through the one definition, and
neither needs an edit.

**Mutation matrix** (plan review cut the rows that tested hypothetical broken variants of a
one-line floor):

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the floor, with a plan fixture whose `monitor_ids` is `["1", null]` | RED: `_red` rc 1 plus the named-address error through the gate script |
| 2 | Same fixture with ≥ 2 rules, where the unknown one is **not** first by name, and a floor that only checks the first rule or the first element | RED |
| 3 | The error message drops the remedy pointer (`cron_monitor_alert_unrouted`) | RED (the row asserts that substring) |
| 4 | Direct `jq -f sentry-alert-projection.jq --arg side tf` on the row 1 fixture | rc 5 |

**Harness rows.** A row asserts the exact rc (1 through the gate, 5 through jq directly) and the
error text, never just "non-zero". `EXPECTED_TESTS` is raised by the number of rows added, so a
dropped row turns the suite red. Must-PASS:

- (P1) a two-rule plan with every id known, in reverse order
- (P2) the live-shape side with the same ids, which must still compare equal

**Anchor.** The floor lives in the projection module. A change to that module matches
`apply-sentry-infra.yml`'s path filter (`tests/scripts/lib/sentry-alert-projection.jq`), so an edit
that weakens it runs the reference gate and the post-apply probe on the same push. Nothing here is
a stored value checking itself: the floor is exercised against every real plan.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` declares exactly one
  `resource "sentry_alert" "cron_monitor_failure"` with an inline `monitor_ids` list of
  `sentry_cron_monitor.<label>.id` references,
  `frequency_minutes = 1440`, `enabled = true`, exactly the three lifecycle triggers (`first_seen_event`,
  `reappeared_event`, `regression_event`; no `event_frequency_count`), one action filter with
  `conditions = []`, and email `issue_owners`/`ActiveMembers`. Verify with
  `grep -c '^resource "sentry_alert"' apps/web-platform/infra/sentry/cron-monitor-alerts.tf` = 1
  (anchored: `issue-alerts.tf:68` shows that a comment matches the unanchored form).
- [ ] AC2. `monitor_ids` has one element per declared `sentry_cron_monitor`, and
  `cron_monitor_alert_unrouted` is `{}`. Guard 1
  (`./node_modules/.bin/vitest run test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`
  from `apps/web-platform`) is green on the real tree, and every matrix row and must-PASS row is a
  named test.
- [ ] AC3. Guard 2's floor is in `tf_rule`. Its matrix rows and must-PASS rows are in
  `tests/scripts/test-sentry-alert-reference-gate.sh`, and `bash tests/scripts/test-sentry-alert-reference-gate.sh`
  passes with the raised `EXPECTED_TESTS`. The `def excluded` line is byte-identical to `origin/main`:
  `git diff origin/main -- tests/scripts/lib/sentry-alert-projection.jq | grep -cE '^[-+]def excluded'`
  = 0. Anchored, so that the comment mentioning `def excluded` near line 258 cannot trip it.
- [ ] AC4. `issue-alerts.tf` is byte-identical to `origin/main` (`git diff --quiet origin/main -- apps/web-platform/infra/sentry/issue-alerts.tf`).
- [ ] AC5. The `plan_pr` job of `apply-sentry-infra.yml` is green: the plan shows exactly one create
  (`sentry_alert.cron_monitor_failure`) and no update, replace or destroy. The create gate, the
  tripwire and the reference gate pass.
- [ ] AC6. `alert-reference.json` differs from `origin/main` by exactly one added top-level key,
  `cron-monitor-failure`. Checked two ways:
  - `diff <(jq -S 'del(.["cron-monitor-failure"])' apps/web-platform/infra/sentry/alert-reference.json) <(git show origin/main:apps/web-platform/infra/sentry/alert-reference.json | jq -S .)`
    prints nothing.
  - `jq '.["cron-monitor-failure"].detectorIds | length' apps/web-platform/infra/sentry/alert-reference.json`
    equals `cat apps/web-platform/infra/sentry/*.tf | grep -c '^resource "sentry_cron_monitor"'` (59 at
    authoring).
- [ ] AC7. The README T25 counts pass: the README carries the bold phrases "34 `sentry_alert` rules"
  and "59 cron monitors".
  `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` is green, including the updated
  Class A strings.
- [ ] AC8. The drift workflow's final sentry-heartbeat `if:` is
  `always() && matrix.directory != 'apps/web-platform/infra/sentry'`, and the #7834 heartbeat shape
  guard and the new Phase 4.4 row are green.
- [ ] AC9. `terraform fmt -check -recursive` and `terraform validate` pass for the sentry root, and
  `infra-validation.yml` is green.
- [ ] AC10. `git grep -n 'routes to no workflow (#8630)'` returns nothing, and the PR body lists
  every line Phase 5.2 edited.
- [ ] AC11. The ADR-031 amendment is appended and the ADR diff is additions only:
  `git diff --numstat origin/main -- knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md | awk '{print $2}'`
  prints `0`. The earlier `grep '^-[^-]'` form missed deleted bullet lines and blank lines. The C4 `sentry -> founder` edge is
  corrected, and the c4-count-parity, c4-code-syntax and c4-render tests are green.
- [ ] AC12. The #8630 comment (Phase 0.4) is posted with M1-M11 and the Phase 0 measurements. Any
  "unmute" decision has one tracking issue referenced `Tracks #N` in the PR body.
- [ ] AC13. Before every push: `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`
  and `bash scripts/lint-diagnosis-claims.sh` pass. `python3 scripts/lint-guard-contract.py` passes
  on this plan.

### Post-merge (automated verification)

- [ ] AC14. The `apply-sentry-infra.yml` push run on `main` is green through `Terraform apply`, AC17
  and the `sentry_alert live fidelity` probe (the reference includes `cron-monitor-failure`).
- [ ] AC15. `sentry-monitors-audit.sh` on that run reports `class_a_count` equal to the size of
  `cron_monitor_alert_unrouted`, which is 0.
- [ ] AC16. Within 24 h of the apply, the discoverability command prints `PASS (all`, and the
  workflow shows a fire for a **named** monitor: the group history
  (`GET organizations/{org}/workflows/{id}/group-history/`, or `lastTriggered` if that endpoint is
  unavailable) names the cron issue of `scheduled-inngest-health` or `scheduled-zot-restart-loop`.
  Both recover and miss again several times a day (#8495), so a `regression_event` fire is expected
  within hours. That observes hop 2 to hop 3 live instead of inferring it. If no fire is observed
  within 24 h, that is a finding. Investigate before closing #8630.
- [ ] AC17. One `gh workflow run scheduled-terraform-drift.yml` after merge
  (`wg-after-merging-a-pr-that-adds-or-modifies`): the sentry leg's `Sentry check-in (final)` step
  is skipped, the other two legs' steps run, and the `scheduled-terraform-drift` monitor gets its
  check-in.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO (`soleur:engineering:cto`). The direction is sound: one detector-bound workflow
in its own file, no new substrate, and the #8505 shape. It confirmed in the repo that the apply is
full-root (so there is no `-target=` list to register the rule in), that the heartbeat is a
single terminal post (so dropping the sentry leg's check-in cannot leave one open), and that the drift
matrix has the `directory` key the Phase 4 `if:` uses. Its findings and what was done with them:

- Hop 2 was unproven. Resolved at source: M11 (`incident_occurrence.py` sets
  `evidence_data.detector_id`). Phase 0.3 adds a live confirmation with a stop rule.
- `event_frequency_count` on IssuePlatform groups was unmeasured. Resolved by removing the trigger
  (the scoped advisor consult reached the same conclusion on noise grounds).
- The burst estimate was wrong. Resolved, since there is no burst without the re-page trigger (§1.3).
- The 24 h throttle suppresses a second email for a quick regression. Now documented (§1.2).
- A pending entry in `cron_monitor_alert_unrouted` is visible only in a job summary. Class A now
  also emits a `::warning::` annotation (Phase 3.4).
- A live-to-live `detectorIds` check as a way to retire the two-PR rule. Recorded in the ADR
  amendment as the revisit option (Phase 6.1).
- The other two drift legs keep shared-slug semantics. Accepted and recorded (Phase 4.2a).

**Scoped advisor consult (Phase 4.5, `advisor` tier):** said to stage `event_frequency_count`
behind Phase 0's number. Applied as removal, with a one-time backlog list in Phase 0.1. Said to
fix the unknown-id problem in the projection instead of with a process rule. Rejected, with the
reason recorded under Alternative Approaches. Said to state the Phase 4 coverage reduction
explicitly. Applied (4.2).

### Plan review (2026-09-24)

The panel was DHH, Kieran, code-simplicity and the CTO (devex lens). Every finding was applied except
the four judgment calls recorded in
`knowledge-base/project/specs/feat-one-shot-8630-cron-monitor-alert-workflow/decision-challenges.md`
(DC-1 to DC-4).

- **Mechanical fixes applied:**
  - AC1, AC3, AC6 and AC11 verification commands corrected
  - Guard 1 moved to its own file, with line-anchored parsing
  - Guard 2 rc semantics corrected, with `EXPECTED_TESTS` raised
  - Phase 3.4 scope corrected: a jq step, a stderr warning, and T19 inverted
  - the `cron-monitors.tf` locals claim corrected
  - the `reappeared_event` rationale added
  - the heartbeat test step selector corrected
  - the README gets the full new-monitor procedure
  - Guard 1's failure text names the remedy
- **Cuts applied:**
  - the label-to-id map, replaced by an inline `monitor_ids` list
  - Guard 1 rows 5, 8, 9 and H1-H2, and Guard 2 rows 2-4
  - Phase 0.4 and per-red-monitor issue filing
  - the Phase 5 disposition taxonomy and pointer edits
  - the ADR amendment slimmed to its decisions

## Test Scenarios

- Guard 1: matrix rows 1-4, 6, 7 and 10, and must-PASS rows P1-P2 (vitest,
  `sentry-cron-monitor-routing-parity.test.ts`).
- Guard 2: matrix rows 1-4 and must-PASS rows P1-P2 (`tests/scripts/test-sentry-alert-reference-gate.sh`).
- Class A (tests first):
  - all routed gives "0 of N"
  - 1 of 2 unrouted lists that slug (T19, inverted)
  - the `::warning::` goes to stderr and not into the report file
- The drift heartbeat `if:` excludes the sentry leg, and the other legs' heartbeat shape is unchanged.
- A live plan (`plan_pr`) shows one create and zero other changes.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| One `sentry_alert` per monitor | 59 workflows. A new address per monitor in the AC17 bijection and the census. It needs `for_each`, which AC17 forbids in this root. |
| Issue-stream detector plus an `issue_category = cron` filter | No per-monitor map, and no same-PR unknown id. But it relies on an automator-modifiable Sentry option this repo cannot pin. Class A would falsely report all cron detectors unrouted. It needs a new projection kind on both sides. Recorded in the ADR amendment. |
| Adding `event_frequency_count {1h, 0}` to re-page persistent failures daily (the #8505 shape) | Chosen against by the scoped advisor consult. It sends a day-one email for every chronically-red monitor and then one per day each, which trains the operator to filter the alert. The backlog is triaged once in Phase 0.2 instead, and Sentry's 14-day broken-monitor email covers long outages. |
| Keep a same-PR route for new monitors by re-projecting the post-apply probe's reference from post-apply state, or by projecting unknown ids as `pending` (scoped advisor consult) | Either one changes the #8050 contract, under which the reference is true by construction the moment the `.tf` changes. The committed `alert-reference.json` would carry a placeholder that the daily probe (which reads the committed copy) cannot resolve until a later commit rewrites it, and no PR-time path can write that commit. The two-PR rule costs one small route PR per new monitor, and Class A lists every pending route on each apply. |
| Collapse the 59 monitors into one `for_each` resource so `monitor_ids` derives itself | This needs 59 `moved` blocks against live state. AC17 in `apply-sentry-infra.yml` forbids `for_each`/`count` in this root, because its declared/observed bijection reads resource addresses from the `.tf` text. Out of scope. |
| Unmute via the monitor-environment REST `PUT` in this PR | This is a write to prod alerting config outside Terraform. The brief forbids it, and it needs a per-command go-ahead. It is tracked instead. |
| Destroy and recreate a monitor to clear its mute | A re-added name adopts the deactivated object (#3958 residual in `cron-monitors.tf`), and it needs `[ack-destroy]`. |
| A new `scheduled-terraform-drift-sentry` monitor (ADR option for (b)) | A 60th seat-billed monitor and a matrix-expression slug. The sentry leg's failures already reach the `[ERROR]` email. |
| Excluding #8495's two noisy watchdogs | Their misses are real (the runs do not start), and the throttle bounds them to one email per day. Excluding them would hide a genuine degradation of the Inngest-down watchdog. |

## Non-Goals

- Uptime-monitor routing (4 `sentry_uptime_monitor` detectors, also unbound). Documented in-place in
  the C4 edge and the ADR amendment as unrouted. #8630 is scoped to cron detectors. Whether the
  4 uptime detectors need their own route is a separate question, left to the next change to
  `uptime-monitors.tf`, and the amendment says so. Binding them into `cron-monitor-failure` would
  make Guard 1's "every element is a `sentry_cron_monitor`" rule false.
- #8495 (GitHub cron cadence), #7985 (frozen rules), #7634 (script write envelope), #8681/#8682
  (drift-leg token and debounce), #6590 (the prune), #6591 (monitor-value telemetry).
- Unmuting any monitor (tracked, not executed).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  deepen-plan or `soleur:work`.
- **Never route a monitor in the PR that creates it.** Guard 2 refuses it. Use `cron_monitor_alert_unrouted`
  and follow up after the first apply.
- **`cron-monitors.tf` must stay pure `sentry_cron_monitor`.** Its parity test reads every
  top-level `name =` as a monitor slug. The alert and the unrouted map go in `cron-monitor-alerts.tf`.
- **Anchor every grep at the start of the line.** The new file's header will quote `monitor_ids`,
  `cron_monitor_alert_unrouted` and `resource "sentry_alert"` in prose.
- **`conditions = []` must be explicit.** Omitting it plans `null`, and the projection floors
  `action_filters[].conditions` to an array.
- **Regenerate `alert-reference.json` only from the CI artifact.** Hand-editing 59 ids from state is
  the drift source #8050 retired.
- **The first apply does not email about the existing backlog.** Monitors already red stay silent
  until their next regression. Phase 0.1's list is the only place that backlog is surfaced, so it
  must be complete.
- **Muted means silent, even when routed.** Every runbook sentence that says a monitor pages must be
  checked against the Phase 0 mute list, not against routing alone.
