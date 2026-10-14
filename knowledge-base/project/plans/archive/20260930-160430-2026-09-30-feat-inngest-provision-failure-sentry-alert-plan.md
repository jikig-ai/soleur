---
title: "infra(inngest): Sentry alert for non-pull provision-unit failures"
type: feat
date: 2026-09-30
slug: feat-inngest-provision-failure-sentry-alert
branch: feat-one-shot-9176-provision-failure-sentry-alert
issue: 9176
closes: 9176
pr: 9292
lane: single-domain
domain: engineering
brand_survival_threshold: aggregate pattern
---

# infra(inngest): Sentry alert for non-pull provision-unit failures

## Enhancement Summary

**Deepened on:** 2026-09-30. The run was kept proportionate to a one-resource change.
**Agents:** an observability-coverage reviewer and a verify-the-negative claims sweep (standard
tier), on top of plan-review (DHH, Kieran, code-simplicity, CTO) and the Phase 4.5 advisor consult.
**Halt gates passed:** 4.6 user-brand (aggregate pattern), 4.7 observability (Check 10 verb `grep`,
literal `2`), 4.8 PAT (no hits), 4.10 encryption posture, and 4.11 guard contract (`lint-guard-contract.py`
green, structural assembly). 4.5, 4.55 and 4.9 did not trigger.

### Key improvements

1. The observability layer citations are corrected. The host emitter and the phone-home are direct
   channels, not layers 1–6, so they are named as such. Layer 6 is cited only for the
   workflow-run and drift paths. The missing "apply rejects or drops the rule" mode is added, and so
   is the residual cron-monitor backstop.
2. The runbook plan now matches the real tooling. Disabling goes through Terraform, not the UI
   (drift treats a live DISABLED as a fault). There is a catch-all `why=` row, and the
   `bootstrap-failure-journal` rows plus a `.detail` read recipe are added.
3. The test's vitest classification is pinned: app-local, not `REPO_WIDE_SUITES`.
4. All 12 load-bearing repo claims were verified by the sweep (file:line), including the pull-fatal
   emit counts, `nc`-free root, projection-jq sorting and `--arg side live`, README/C4/ADR/runbook
   anchors, and tool existence.

### New considerations discovered

- The `discoverability_test` is a declaration probe only. A richer `jq` probe would trip Check 10's
  `|` reject.
- If both host channels fail before Vector exists, the only off-host signal is the cron monitors'
  missed check-ins.

## Overview

The dedicated inngest host's provisioning unit (`soleur-inngest-provision`, ADR-257, #8562/PR #9159)
reports every failed attempt to Sentry as a warning-level boot-stage event, and reports a
"degraded" bootstrap (SQLite-only, no latch) the same way. No alert rule matches either event, so
a provisioning failure that is not a registry pull miss reaches nobody: the scheduler stays dark
and the operator finds out from missed reminders. Only `inngest_pull_fatal` pages today, through
`sentry_alert.zot_mirror_fallback_rate`.

This plan adds **one** Terraform-managed rule, `sentry_alert.inngest_provision_failure`
(live name `inngest-provision-failure`), in `apps/web-platform/infra/sentry/issue-alerts.tf`. It
also adds the `alert-reference.json` entry the PR-time reference gate requires, the README count
bump the T25 ratchet requires, an op-contract vitest that binds the rule's filters to the emitter,
and doc updates: a runbook row, an ADR-257 amendment and the C4 edge prose that the change makes
false. Merging auto-runs `apply-sentry-infra.yml`, which creates the one rule. The operator
authorized that additive production write on 2026-09-30.

**The rule arms dark.** The emitter ships in `cloud-init-inngest.yml`, and that reaches the live
host only through the next operator-approved `inngest-host-replace` (ADR-257 §Status). Until then
the rule exists and matches nothing. That is harmless and expected. Post-merge verification is "the
rule exists live with the committed shape". It is not "the rule fired": the only way to make it
fire now is a synthetic Sentry event, which would page the operator and is an unauthorized
production write.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Four events to match: `provision_attempt_failed`, isolation-check FATAL, bootstrap failure, `provision-fsm-busy` | Only `provision_attempt_failed` reaches **Sentry**. `isolation-check-FAILED`, `provision-fsm-busy`, `bootstrap-exit-<rc>` and `bootstrap-failure-journal` go to the Better Stack phone-home only (`inngest-boot-phone-home.sh`, `cloud-init-inngest.yml`). Each of those arms sets `last_stage=<stage>` and `exit`s non-zero. The single `on_exit` trap then emits `soleur-boot-emit provision_attempt_failed warning "rc=$rc.attempt=$attempt.why=$last_stage.iid=$IID"`. | One `stage` filter covers all four. The failure class is carried in the `detail` tag as `why=<last_stage>`. There is no separate per-class condition, and none is possible without a phone-home → Sentry bridge, which would be the wrong layer. |
| "NON-pull" failures | A pull miss sets `last_stage=inngest_pull_fatal`, emits `soleur-boot-emit inngest_pull_fatal fatal` (paged by `zot_mirror_fallback_rate`) and then exits. So `on_exit` ALSO emits `provision_attempt_failed … why=inngest_pull_fatal`. Both arms (zot miss, no endpoint baked) do this. | Exclude it with `detail` **not-contains** `why=inngest_pull_fatal` (`match = "nc"`) under `logic_type = "all"`. Otherwise every pull miss pages twice on the same shared issue group. |
| (unstated) degraded bootstrap | `bootstrap_done_degraded` (Sentry, warning) fires when the bootstrap exits 0 but the host serves SQLite-only. No latch is written, the unit retries only on the next boot, and ADR-257 grants no reboot authority, so the state persists indefinitely. ADR-257 and the #8562 probe read it as FAIL. No rule pages it. | **Included** (decision D2 below). It is the same failure class as the issue ("provisioning did not reach the durable shape") and costs one list member. It is recorded as a taste decision in `decision-challenges.md` so `ship` surfaces it. |
| "Verify emitter tags in Sentry" | Read-only query (`SENTRY_ISSUE_RO_TOKEN`, org `jikigai-eu`, 2026-09-30): every `host_name:soleur-inngest` event lands in ONE shared issue group, `WEB-PLATFORM-4S` (group 132577803, "soleur-cloud-init boot stage", `unresolved`/`ongoing`). The latest event carries the tags `stage`, `detail`, `host_id`, `host_name=soleur-inngest`, `region=cloud-init` and `level`. There are **0** events for `stage:provision_attempt_failed`, `stage:bootstrap_done_degraded` or `stage:inngest_pull_fatal` in 90 days, which matches "delivered dark". | Filters key on `stage` + `detail`, both confirmed as real tag keys on live events from this emitter. |
| Does `sentry_alert` accept `match = "nc"`? | Provider v0.15.7 does not validate `tagged_event.match` (`internal/providergen/resources/alert.ts`: free string, only the `is`/`ns` value-null validator). Sentry's workflow handler (`workflow_engine/handlers/condition/tagged_event_handler.py`) validates against `MATCH_CHOICES`, which includes `NOT_CONTAINS = "nc"`. Its semantics are `not any(value in tag for tag in values)`, lowercased on both sides, so an absent tag passes. | Use `nc`. It is the first `nc` in this root, so AC-post-2 verifies the live rule round-trips it. |
| `apply-sentry-infra.yml` target set / destroy guard | Full-root plan since #6589: there is no `-target` allow-list. The CREATE gate diff-matches each planned create against `git diff <last_applied>..HEAD -- infra/sentry/*.tf`, so a new `resource "sentry_alert"` block in this PR's diff passes. The destroy gate sees 0 destroys. The create tripwire refuses only `sentry_issue_alert` creates and writes to `legacy_trigger_conditions` blocks. The monitor-binding gate needs the issue-stream detector, which the new rule binds via `data.sentry_project_issue_stream_monitor.web_platform.id`. | No workflow edit, so this is not UNTRUSTED-CI. One caveat: the CREATE gate's ancestry check fails if `main` applied a newer Sentry commit after this PR's merge ref was built. Remedy: update the branch and re-push. |
| Alert registries / census | (1) `alert-reference.json`: required, because `sentry-alert-reference-gate.sh` in `plan_pr` holds it equal to the plan projection, and `scheduled-sentry-alert-drift.yml` compares live Sentry to it daily. (2) README counts: T25 in `apps/web-platform/scripts/sentry-monitors-audit.test.sh` pins ``**N `sentry_alert` rules**`` and `(N alert rules total)`. (3) AC17 in `apply-sentry-infra.yml` derives counts from the `.tf` (no edit). (4) `assert-byok-rules-exist.sh`: BYOK rules only (no edit). (5) `NON_INNGEST_MONITORS` / cron routing parity: cron monitors only (no edit). (6) The C4 Sentry paging edge prose (the `sentry ->` relationship toward the human actor) says "34 of the 36 `sentry_alert` rules in issue-alerts.tf". c4-count-parity does not gate it, but the change falsifies it. | Edit (1), (2) and (6). (6) needs `bash scripts/regenerate-c4-model.sh`, since `c4-model-freshness.test.sh` byte-diffs `model.likec4.json`. |

## Research Insights

**Premise validation.** #9176 is OPEN, with no closing PR. PR #9159 (the provision unit) merged
2026-09-28T19:00:24Z. #8562 is OPEN (its delivery probe is pending the replace). The cited
`sentry_alert.zot_mirror_fallback_rate` exists and pages `stage eq inngest_pull_fatal`
(`issue-alerts.tf`, resource `zot_mirror_fallback_rate`). The cited emitter exists:
`cloud-init-inngest.yml` → `path: /usr/local/bin/soleur-inngest-provision` → `on_exit()`. No
premise is stale. The one correction is the four-events-to-one-Sentry-event reconciliation above.

**Property List** (Phase 0.6b):

- P1: A provisioning attempt on the dedicated inngest host that fails for a non-pull reason
  (isolation check, env/NIC missing, FSM busy, bootstrap exit, an unnamed arm, TimeoutStartSec kill)
  emails the operator.
- P2: A bootstrap that ends degraded (SQLite-only, no latch) emails the operator.
- P3: A pull miss pages exactly once per throttle window, through the existing rule. It is not
  double-paged by the new rule.
- P4: The new rule never matches the other stages in the shared always-hot boot-stage group
  (`inngest_zot` info, `private_nic_ok`, web-host stages).
- P5: A rename on either side (the emitter's stage literal or `detail` format, or the rule's filter
  value) fails CI, not production.

**Cut List:**

- Per-class Sentry conditions for `isolation-check-FAILED` / `provision-fsm-busy` / `bootstrap-*` →
  P1 → already covered by `provision_attempt_failed`'s `why=` (the trap fires on every non-zero exit).
- A new `soleur-boot-emit` call per failure arm (emitter change) → P1 → covered by the trap. It
  would also mint a `cloud-init-inngest.yml` change that needs a host replace to deliver.
- A `host_name eq soleur-inngest` filter → P4 → covered: `provision_attempt_failed` and
  `bootstrap_done_degraded` are emitted only by this host's provision script (`git grep` shows one
  emit site each).
- A follow-through / soak probe → no time-gated close criterion. "Fires on a real event" waits
  on the #8562 replace, whose probe is already enrolled.

**Relevant files:**

- `apps/web-platform/infra/sentry/issue-alerts.tf`: siblings `zot_mirror_fallback_rate` (the
  shared-group, `value = 0` rationale and the "mute the issue, never the rule" hazard) and
  `image_freshness_mismatch` / `git_data_host_key_pin_fault` (the most recent one-rule additions,
  appended at the end of the file).
- `apps/web-platform/infra/sentry/alert-reference.json`: `jq -S` sorted keys. The new key
  `inngest-provision-failure` sorts between `inbox-action-required-notify-failure` and `kb-db-error`.
- `apps/web-platform/infra/sentry/README.md`: line 5 count (37 → 38; "35 are fully
  Terraform-owned (34 in `issue-alerts.tf`" → 36/35) and the history paragraph ("…#8572 added
  `git_data_host_key_pin_fault`, taking it to 37").
- `apps/web-platform/infra/cloud-init-inngest.yml`: the `soleur-boot-emit` definition (tag set;
  DETAIL charset `tr -cd 'A-Za-z0-9=.:_-'`, cut at 120) and `soleur-inngest-provision` (`on_exit`,
  the `last_stage=` assignments, `bootstrap_done_degraded`, and both `inngest_pull_fatal` arms).
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`: already pins the emitted
  line format (`emit provision_attempt_failed warning rc=1.attempt=1.why=…`). This PR does not touch
  the emitter.
- `apps/web-platform/test/sentry-image-freshness-alert-op-contract.test.ts`: template for the new
  op-contract test (strips `#` comments, scopes to the resource block, checks frequency uniqueness).
- `.github/workflows/apply-sentry-infra.yml`: full-root plan, CREATE gate, reference gate, AC17,
  post-apply fidelity.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` § "Provision unit (#8562)":
  stage table rows `provision_attempt_failed (Sentry, **warning**, not paged)` and
  `bootstrap_done_degraded`.
- `knowledge-base/engineering/architecture/decisions/ADR-257-…md`: Decision 5 ("its alert rule is a
  tracked deferral") and Consequences ("Non-pull failures do not page").
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the `sentry -> founder` edge ("34 of
  the 36") and the `inngest -> sentry` edge (already names `provision_attempt_failed` at warning).

**Live measurements (read-only, 2026-09-30):**

- Live workflow frequencies (`GET /organizations/jikigai-eu/workflows/`): 5, 10–28, 30, 31, 60–63,
  240, 1440–1442, plus two vendor-default `Send…` rows at 0. **120 is unused** in both the `.tf` root
  and live.
- `GET /workflows/?query=provision` returns 0, so the name `inngest-provision-failure` is free.
- `SENTRY_ISSUE_RO_TOKEN` (Doppler `soleur/prd`) can read both `/workflows/` and `/issues/`.
  `SENTRY_API_TOKEN` cannot resolve short ids. The post-merge check uses the RO token.

**Institutional learnings applied:**

- `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`: Sentry dedups on
  action shape + filter match + frequency, not conditions. Hence an unused `frequency_minutes`.
- `2026-07-15-sentry-event-frequency-threshold-unreachable-…md` and the zot rule's #6285 block:
  `value = 0` is the only fleet-independent threshold.
- `best-practices/2026-05-30-routing-through-shared-tag-filtered-alert-primitive-needs-all-filter-tags.md`:
  every tag an `all` filter names must be on the emitted event. Verified live for `stage` and
  `detail`.
- `2026-07-09-sentry-fallback-rate-alarm-pre-bootstrap-emitter-and-issue-group-grouping.md` and the
  zot comment: the boot-stage group is shared and always hot. Muting the ISSUE silences every boot
  stage of every host, so for this rule the only safe noise lever is the rule's own
  `frequency_minutes` (or disabling the rule).
- `bug-fixes/2026-06-02-sentry-auth-alert-rules-drifted-to-empty-filters-…md`: verify the live
  rule's filters after apply. An `nc` condition that failed to round-trip would leave `stage in`
  alone, which is still safe (it would double-page pull misses). The inverse, a filter that drops
  `stage`, would page every boot stage. The post-merge AC reads both conditions back.
- `2026-06-12-…register-new-sentry-alert-in-apply-target.md`: superseded by #6589 full-root. The
  modern equivalent is the reference gate plus T25.

**CLAUDE.md / AGENTS.md conventions:** `cq-assert-anchor-not-bare-token` (the test strips comments
and anchors on code); `hr-no-ssh-fallback-in-runbooks` (every verification step is API/grep);
`hr-menu-option-ack-not-prod-write-auth` (the apply write is authorized by the operator's recorded
2026-09-30 authorization, scoped to this one rule).

**Functional overlap:** community registries have no Terraform-`sentry_alert` artifact (report-only
check; nothing installed).

**Shared-group delayed-evaluation check (verified against Sentry source, 2026-09-30).** A count
trigger (`event_frequency_count`) is a "slow" condition, so Sentry's workflow engine enqueues the
workflow for delayed evaluation. The concern: a later non-matching event in the same always-hot
group (for example an `inngest_zot` info event) might overwrite the queued failing event and get
the page skipped. It does not. `workflow_engine/processors/workflow.py`
`evaluate_workflows_action_filters` evaluates the fast `tagged_event` filters **at enqueue time,
against the real event**, and records the passing filter group in `passing_if_group_ids`.
`buffer/batch_client.py` `DelayedWorkflowItem.buffer_key` includes `passing_if_group_ids`. So an
event whose filters fail is keyed `wf:group:when::`, a matching event is keyed
`wf:group:when::<dcg>`, and neither overwrites the other. Only another *matching* event can replace
the queued one, which is harmless. `zot_mirror_fallback_rate`, `web_terminal_boot_fatal` and
`image_freshness_mismatch` use the same shape. The provider (0.15.7) offers no every-event trigger
(`trigger_conditions`: `event_frequency_count`, `first_seen_event`, `issue_resolved_trigger`,
`reappeared_event`, `regression_event`), and the first-seen/regression family never fires on a
long-lived group. So `event_frequency_count value = 0` is the only trigger that works here.

**Forgery / suppression (accepted, documented).** The DSN is semi-public. A forged
`stage=provision_attempt_failed` event pages once. It also starts this rule's 120-minute per-issue
throttle on the shared group, which could mask a real failure for up to 2 h. That is true of every
tag-keyed rule in this root (`git_data_host_key_pin_fault` records the same residual). The Better
Stack phone-home row (`provision-attempt-exit-<rc>`, written with a Doppler-held token, not the
DSN) is the corroboration channel, and the runbook row says so.

**Scoped advisor consult (Phase 4.5):**

- (a) Give failure events their own issue group through a fingerprint in the emitter. **Declined:**
  it edits `cloud-init-inngest.yml`'s shared `soleur-boot-emit`, which other stages and the zot
  soak count on (`inngest-boot-emitter.test.sh` pins the event format). That goes past the
  one-resource scope. The motivating overwrite hazard is refuted above.
- (b) Pin `host_name eq soleur-inngest`. **Declined as a runtime filter:** it is one more literal
  that could go dark. Replaced with test T8, which fails CI if the other boot template emits
  either stage.
- (c) Confirm `in` / `nc` serialization. `in` is already live on `spawn_agent_dead_letter` and
  `git_data_host_key_pin_fault`. `nc` is covered by Risks plus AC-post-2.
- (d) The test forces every future warning stage to page. **Kept, with an escape:** the test
  carries an explicit `EXEMPT_WARNING_STAGES` list (empty today), so a non-paging warning stage is
  a deliberate, reviewed test edit rather than a silent gap.

## Proposed Solution

### The rule (appended after `image_freshness_mismatch` in `issue-alerts.tf`)

```hcl
resource "sentry_alert" "inngest_provision_failure" {
  organization      = var.sentry_org
  name              = "inngest-provision-failure"
  enabled           = true
  frequency_minutes = 120
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "stage", match = "in", value = "bootstrap_done_degraded,provision_attempt_failed" } },
        { tagged_event = { key = "detail", match = "nc", value = "why=inngest_pull_fatal" } },
      ]
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

The leading comment block (house style: a `# ── … (#9176) ──` banner) must state:

- the emitter (`soleur-inngest-provision` `on_exit` → `soleur-boot-emit`), the tag set, and the
  fact that the four failure classes arrive as one stage distinguished by `why=` in `detail`;
- **why `logic_type = "all"` is load-bearing**: under `any`, the `nc` condition alone would pass for
  every event in the shared boot-stage group (`inngest_zot` info, `private_nic_ok`, web-host stages)
  and page on every boot;
- why the pull miss is excluded (paged by `zot_mirror_fallback_rate`; both pull-fatal arms emit
  `inngest_pull_fatal` before exiting). Both matching emit sites always pass a non-empty `detail`
  (T5 pins both lines), so the absent-tag case does not arise. For the record, Sentry's
  `match_values` returns true for `nc` over an empty value set;
- `value = 0` (see `zot_mirror_fallback_rate`) and the shared-group note: **never mute
  `WEB-PLATFORM-4S`**, because that silences every boot stage of every host. Quiet this rule by
  raising `frequency_minutes` or disabling it;
- `frequency_minutes = 120` rationale: a persistently failing unit retries without limit (ADR-257
  measured about 26 events an hour at first and about 4 an hour once backed off), so the rule
  re-pages at most every 2 h (about 12 emails a day while dark). Hourly got a monitor muted (#8704).
  The first failure pages immediately. (No hand-kept "taken" list: T7 enforces uniqueness.);
- `nc` is a case-insensitive **substring** match, so a future stage named `inngest_pull_fatal_*`
  would also be excluded — keep pull-fatal stage names distinct;
- known benign pages: `rc=143` from a shutdown or reboot that lands mid-attempt on an unlatched
  host, and a single transient failure that the next retry heals. Both page once and are
  self-evidently transient from `why=` / `attempt=`;
- the rule arms dark until the next `inngest-host-replace` delivers the unit (ADR-257 §Status);
- events carry `rc`, `attempt`, `why` (a stage name) and `iid`, with no user content.

**Decisions:**

- **D1: one rule, `stage in` + `detail nc`, `all`.** This is the minimum filter that covers P1–P4
  (see the Cut List).
- **D2: include `bootstrap_done_degraded`.** This is a taste decision and goes to
  `knowledge-base/project/specs/archive/20260930-160430-feat-one-shot-9176-provision-failure-sentry-alert/decision-challenges.md`.
  Rationale: the degraded state persists until a reboot nobody schedules, and it is the same "host
  did not reach durable shape" class. To reverse it, drop one list member.
- **D3: `frequency_minutes = 120`**, unused both in the root and live.
- **D4: no `host_name` filter** (Cut List). **No emitter change**, so there is no
  `cloud-init-inngest.yml` edit, no host replace and no bootstrap tag.

## Implementation Phases

### Phase 1: Contract test first (RED)

1.1 Create `apps/web-platform/test/sentry-inngest-provision-failure-alert-op-contract.test.ts`
modeled on `sentry-image-freshness-alert-op-contract.test.ts`. Strip whole-line `#` comments from
both `issue-alerts.tf` and `cloud-init-inngest.yml`. Scope the emitter to the
`path: /usr/local/bin/soleur-inngest-provision` block (up to the next `\n  - path:`). Assertions:

- T1: the resource block exists and is non-empty (own-dispatch floor: every later assertion reads
  this block).
- T2: `logic_type = "all"` inside the block (it has exactly one action filter, so the positive
  match is sufficient).
- T3: the stage `in` set, parsed and split on `,`, **equals** the set of `soleur-boot-emit <stage>
  warning` stages written as literals in the provision block. Derived, not hardcoded: a new warning
  stage reds the test until the rule covers it. The test also asserts the derived set is non-empty
  and contains `provision_attempt_failed`, and it FAILS on any non-literal call
  (`soleur-boot-emit "$…`) inside the provision block, because a wrapper like the NIC-wait block's
  `emit()` would hide stages from the derivation. If a future non-paging warning stage is ever
  wanted, the author adds an explicit exemption list in that same edit (none today — YAGNI).
- T4: the `nc` condition is exactly `key = "detail", match = "nc", value = "why=inngest_pull_fatal"`.
- T5: the emitter still builds `detail` as `…why=$last_stage…` in `on_exit`
  (`soleur-boot-emit provision_attempt_failed warning "rc=$rc.attempt=$attempt.why=$last_stage.iid=$IID"`),
  the `bootstrap_done_degraded warning "why=$_degraded…` emit line is present, and the
  `soleur-boot-emit` DETAIL charset keeps `=` and `_` (the `tr -cd 'A-Za-z0-9=.:_-'` literal).
  This binds the RULE's `nc` value to the emitter; `cloud-init-inngest-provision-unit.test.sh` pins
  only the emitted line, not the rule's dependency on it.
- T6: in the provision block, `count("last_stage=inngest_pull_fatal") ==
  count("soleur-boot-emit inngest_pull_fatal fatal") == 2` (the zot-miss and no-endpoint arms).
  Order-insensitive on purpose; this is what makes the exclusion safe (every attempt excluded by
  `nc` has already emitted the fatal stage the zot rule pages). The zot rule's own condition and
  its two emit literals stay pinned by the existing
  `sentry-zot-mirror-fallback-alert-op-contract.test.ts` — not duplicated here.
- T7: `event_frequency_count = { interval = "1h", value = 0 }` in the block, and
  `^\s*frequency_minutes\s*=\s*120\b` matches exactly once across
  `apps/web-platform/infra/sentry/*.tf` (anchored like the image-freshness template, so an unrelated
  `120` elsewhere cannot trip it).
- T8: each stage in the rule's `in` set appears as `soleur-boot-emit <stage>` in
  `cloud-init-inngest.yml` and in no other boot template (`cloud-init.yml` count 0). Measured
  2026-09-30: `git grep -e 'soleur-boot-emit provision_attempt_failed' -e 'soleur-boot-emit
  bootstrap_done_degraded' -- apps/web-platform/infra` gives 2 hits, both in `cloud-init-inngest.yml`.
  This replaces a runtime `host_name` filter: a second emitter host reds CI instead of paging under
  the inngest name. Limitation: a variable-stage emit (`cloud-init.yml`'s `soleur-boot-emit "$stage"
  fatal`) is not attributed. `sentry-web-terminal-boot-fatal-op-contract.test.ts` shows the
  attribution pattern if that ever matters.

The `alert-reference.json` entry is NOT re-asserted here: the `plan_pr` reference gate is the
authority for it, and the daily drift job holds it equal to live Sentry.

The test reads only `../infra/...` files inside `apps/web-platform`, so it is app-local: it runs in
the `unit` vitest project (`include: ["test/**/*.test.ts", …]`) and is gated on diffs that touch
`apps/web-platform/` (this one does, and so does any future emitter or rule edit). It must NOT be
added to `REPO_WIDE_SUITES`, because `test/repo-wide-containment.test.ts` recomputes membership from
each file's `..` depth and would flag it (the sibling image-freshness and pin-fault tests are
likewise absent from that list).

Run it on the unchanged tree and confirm RED (T1 fails).

### Phase 2: The rule + registries (GREEN)

2.1 Append the resource and comment block after `image_freshness_mismatch` in
`apps/web-platform/infra/sentry/issue-alerts.tf`.
2.2 Hand-author `alert-reference.json["inngest-provision-failure"]`, sorted between
`inbox-action-required-notify-failure` and `kb-db-error`. Mirror the `image-freshness-mismatch`
shape: `actionFilters[0].conditions` = the two `tagged_event` comparisons in the projection's
canonical order. `sentry-alert-projection.jq`'s `normalise` sorts conditions with
`sort_by(tostring)`, so the `detail`/`nc` condition comes BEFORE `stage`/`in`, regardless of `.tf` order,
`logicType "all"`, `detectorIds ["1213799"]`, `enabled true`, `frequency 120`, `name`,
`triggerConditions [{comparison:{interval:"1h",value:0},type:"event_frequency_count"}]` and
`triggerLogicType "single"`. Validate it is canonical with
`jq -S --arg side reference -f tests/scripts/lib/sentry-alert-projection.jq apps/web-platform/infra/sentry/alert-reference.json | diff - apps/web-platform/infra/sentry/alert-reference.json`.
The PR's `plan_pr` reference gate is the authority. On mismatch it prints the exact expected
document, which gets pasted back.
2.3 README (`apps/web-platform/infra/sentry/README.md`): on line 5, 37 → 38 in both
``**N `sentry_alert` rules**`` and `(N alert rules total)`, append `#9176` to the issue list, and
change "35 are fully Terraform-owned (34 in `issue-alerts.tf`" to 36 / 35. In the history paragraph,
append after the #8572 clause: "; #9176 added `inngest_provision_failure`, taking it to 38".
2.4 Run the new vitest (GREEN) and T25:
`bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` (or just its T25 block), plus
`terraform fmt -check apps/web-platform/infra/sentry` and
`terraform -chdir=apps/web-platform/infra/sentry validate` (`init -backend=false`).

### Phase 3: Docs the change makes false

3.1 Runbook `knowledge-base/engineering/operations/runbooks/inngest-server.md`, § "Provision unit
(#8562)":

- Stage table: `provision_attempt_failed` (Sentry, **warning**, not paged) → **paged** by
  `inngest-provision-failure` (except `why=inngest_pull_fatal`, paged by `zot-mirror-fallback-rate`);
  `bootstrap_done_degraded` row → paged by `inngest-provision-failure`.
- A short "Reading an `inngest-provision-failure` page" block. The email subject is the shared
  group title ("soleur-cloud-init boot stage", the same as the pull-fatal page), so identify it by
  the rule name and the `stage`/`detail` tags. Map each `why=` value to its existing SSH-free next
  step: `isolation-check-FAILED` and `provision-env-MISSING` → the existing rows; `provision-fsm-busy`
  → read FSM state with `inngest-host-state.yml`; `bootstrap-exit-*` / `bootstrap-failure-journal` →
  the Better Stack `bootstrap-failure-journal` phone-home row for that `iid` (add stage-table rows for
  `bootstrap-exit-<rc>` and `bootstrap-failure-journal`, plus a variant of the existing
  `betterstack-query.sh … life.txt` recipe that prints `.detail` for that stage, since today's recipe
  prints only `.stage`); `rc=143` → a kill at `TimeoutStartSec` or at shutdown (benign if the next
  attempt succeeds); **any other `why=`** (`provision-nic-ABSENT`, `pre-zot-pull`,
  `pre-bootstrap-run`, `flip-assets-*`, `isolation-check-passed`, `provision-attempt-start`) → the
  attempt died after that stage; read that attempt's rows in `life.txt`.
- Read commands for BOTH stages:
  `scripts/sentry-issue.sh --host-events soleur-inngest --stage provision_attempt_failed` and
  `--stage bootstrap_done_degraded`.
- A degraded bootstrap pages once per boot and never re-pages: treat it as open until
  `bootstrap-done` appears for the same `iid`.
- The 120-min throttle is per shared issue group, so a benign page (for example `rc=143`, or a
  forged event from the semi-public DSN) can hide a real failure for up to 2 h. Corroborate with
  the Better Stack `provision-attempt-exit-<rc>` row.
- The sanctioned quiet lever is the RULE, changed in Terraform: raise `frequency_minutes`, or set
  `enabled = false`, and regenerate `alert-reference.json` in the same PR. Never disable it in the
  Sentry UI (the daily drift job treats a live `DISABLED` as a fault and asks for re-enable), and
  never mute `WEB-PLATFORM-4S`.

3.2 ADR-257: add in-place `> **Superseded 2026-09-30 (#9176):** …` pointer lines under Decision 5
("its alert rule is a tracked deferral") and under the Consequences bullet "Non-pull failures do not
page", stating that `sentry_alert.inngest_provision_failure` now pages non-pull attempt failures and
degraded bootstraps, while pull misses stay on `zot_mirror_fallback_rate`. No new section.

3.3 C4 `knowledge-base/engineering/architecture/diagrams/model.c4`: on the Sentry paging edge,
"34 of the 36 `sentry_alert` rules in issue-alerts.tf" → "35 of the 37". Then run
`bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json`. CI's C4 tests
(`c4-model-freshness`, `c4-count-parity`, `c4-code-syntax`, `c4-render`) are the check.

### Phase 4: Ship

Push, and let CI's `plan_pr` confirm the reference gate, the CREATE gate (1 create:
`sentry_alert.inngest_provision_failure`), destroy 0, and the tripwire and binding gates.
Admin-merge on green (no workflow files are edited). Post-merge ACs follow below.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf`: new `sentry_alert.inngest_provision_failure` + comment block.
- `apps/web-platform/infra/sentry/alert-reference.json`: new `inngest-provision-failure` entry.
- `apps/web-platform/infra/sentry/README.md`: counts 37 → 38, 35 → 36, 34 → 35, and the history paragraph.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: stage-table rows + a page-reading block.
- `knowledge-base/engineering/architecture/decisions/ADR-257-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md`: two in-place Superseded pointers.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: one count edit on the Sentry paging edge.
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json`: regenerated.

## Files to Create

- `apps/web-platform/test/sentry-inngest-provision-failure-alert-op-contract.test.ts`
- `knowledge-base/project/specs/archive/20260930-160430-feat-one-shot-9176-provision-failure-sentry-alert/tasks.md`
- `knowledge-base/project/specs/archive/20260930-160430-feat-one-shot-9176-provision-failure-sentry-alert/decision-challenges.md` (D2)

The diff adds no systemd unit state-change line under `apps/web-platform/infra/`, so
`ci-deploy.test.sh` is not required. No `.github/workflows/*` file is edited.

## Open Code-Review Overlap

None. The open `code-review` issues were checked against every path above, plus `cloud-init-inngest.yml`
and `ADR-257`.

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) silence: the rule never fires, and a
  host whose provisioning keeps failing leaves every user's scheduled jobs and reminders not
  running until the operator notices from a missed reminder (today's state, so no regression); or
  (b) a page storm: a filter that matched the whole shared boot-stage group would email on every
  boot of every host, and the operator would mute it, which also buries real pages.
- **If this leaks, the user's data is exposed via:** nothing new. The rule reads existing events
  whose tags carry a return code, an attempt counter, a stage name and a cloud instance id. There
  is no user content, and the email goes to the existing issue-owner/ActiveMembers route.
- **Brand-survival threshold:** `aggregate pattern`. A dark scheduler affects all users'
  scheduled work, not one user's data. Mode (b) is guarded by T2/T3/T4 and the post-merge
  read-back.

## Observability

```yaml
liveness_signal:
  what: "the live Sentry workflow named inngest-provision-failure (enabled, frequency 120, stage-in + detail-nc filters)"
  cadence: "checked after every apply-sentry-infra.yml run (post-apply fidelity) and daily by scheduled-sentry-alert-drift.yml against alert-reference.json"
  alert_target: "drift or a disabled rule -> the drift workflow's issue filing (existing); the rule itself emails issue owners -> ActiveMembers"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (sentry_alert.inngest_provision_failure) + alert-reference.json"
error_reporting:
  destination: "Sentry issue WEB-PLATFORM-4S (shared soleur-cloud-init boot-stage group) -> email via inngest-provision-failure; Better Stack phone-home rows provision-attempt-exit-<rc> / bootstrap-done-DEGRADED carry the same failure"
  fail_loud: "yes: every failed provision attempt exits non-zero and on_exit emits provision_attempt_failed (Sentry) plus the phone-home row before cleanup"
failure_modes:
  - mode: "non-pull provision attempt failure (isolation check, env/NIC missing, FSM busy, bootstrap exit, unnamed arm, TimeoutStartSec kill)"
    detection: "stage=provision_attempt_failed with detail why=<last_stage> (not inngest_pull_fatal)"
    alert_route: "not a numbered layer (1-6 are app/Vector/webhook surfaces; layer 3 Vector is not installed until the bootstrap succeeds): direct host emitter soleur-boot-emit -> Sentry store API -> Sentry alert inngest-provision-failure -> email issue_owners/ActiveMembers; corroborated by the direct Better Stack phone-home curl row provision-attempt-exit-<rc>"
  - mode: "degraded bootstrap (SQLite-only, no latch)"
    detection: "stage=bootstrap_done_degraded, detail why=.redis-inactive and/or .no-durable-execstart"
    alert_route: "not a numbered layer: direct host emitter soleur-boot-emit -> Sentry alert inngest-provision-failure (pages once per boot); corroborated by the direct Better Stack phone-home row bootstrap-done-DEGRADED"
  - mode: "pull miss"
    detection: "stage=inngest_pull_fatal (fatal) plus provision_attempt_failed why=inngest_pull_fatal"
    alert_route: "not a numbered layer: direct host emitter -> Sentry alert zot-mirror-fallback-rate (unchanged); excluded from inngest-provision-failure by detail nc"
  - mode: "apply rejects or drops the rule (e.g. nc refused by the API, rule never created)"
    detection: "red apply-sentry-infra.yml run for the merge SHA (its if: failure() issue filer fires); scheduled-sentry-alert-drift.yml reports DELETED or RENAMED for a reference name missing live; AC-post-2 projection diff"
    alert_route: "layer 6 (workflow run log) + the filed GitHub issue"
  - mode: "rule drifts, is disabled, or loses a filter in Sentry"
    detection: "scheduled-sentry-alert-drift.yml compares live /workflows/ to alert-reference.json (DISABLED is reported as a live fault); apply-sentry-infra.yml post-apply fidelity"
    alert_route: "layer 6 (workflow run log) + the drift workflow's filed issue"
  - mode: "Sentry POST from the host fails"
    detection: "soleur-boot-emit phones home sentry-emit-FAILED stage=<stage> rc=<rc>"
    alert_route: "not a numbered layer: direct Better Stack phone-home row (no page). Residual: if the phone-home ALSO fails before Vector exists, SOLEUR_INNGEST_BOOT_TRACE_LOST never leaves the host; the off-host backstop is the missed check-ins on the Sentry cron monitors (cron-monitors.tf) for the scheduled jobs the dark host stops running"
logs:
  where: "Sentry events (tags stage/detail/host_id/host_name/region) in project web-platform; Better Stack inngest boot-trace source"
  retention: "Sentry plan event retention (90 days queried 2026-09-30); Better Stack source retention"
discoverability_test:
  command: "grep -c inngest-provision-failure apps/web-platform/infra/sentry/alert-reference.json"
  expected_output: "2"
```

The probe proves the rule is declared in the live-bound reference (the key line plus the `name`
line), not that it is enabled with frequency 120. A `jq` projection would check more, but its `|`
fails preflight Check 10's byte-level shell-active reject. `enabled`/`frequency` are covered by the
reference gate, the daily drift job and AC-post-2.

## Guard Contract

### Guard 1: inngest-provision-failure op-contract (`sentry-inngest-provision-failure-alert-op-contract.test.ts`)

**Property.** Every warning-level Sentry stage that the inngest provision script emits pages the
operator through `inngest-provision-failure`, except an attempt that already emitted the fatal
pull-miss stage. The new rule matches nothing outside those stages.

**Assembly.** The chokepoint is the set of `soleur-boot-emit <stage> <level>` calls inside the
`path: /usr/local/bin/soleur-inngest-provision` block of `cloud-init-inngest.yml`. The `on_exit`
trap is the one site for `provision_attempt_failed`; the others are `bootstrap_done_degraded`,
`inngest_zot` and two `inngest_pull_fatal` arms. A non-literal call (a wrapper) is itself a red
(T3), so the literal scan cannot silently miss a member. On the rule side, the chokepoint is the
`inngest_provision_failure` block in `issue-alerts.tf`. The test derives the emitted stage set from
the file. It does not enumerate members.

**Mutation matrix** (run locally during work; not recorded in the PR body).

| # | Mutation | Must go RED |
|---|---|---|
| M1 | rename the resource label (own dispatch: `tfBlockFor` returns "") | T1, and every block-scoped row |
| M2 | `logic_type = "any-short"` | T2 |
| M3 | add a new `soleur-boot-emit foo_failed warning` in the provision block (second member after compliant ones) | T3 |
| M4 | route one provision-block emit through a wrapper (`soleur-boot-emit "$1" "$2" "$3"`) | T3 |
| M5 | delete the `detail nc` condition | T4 |
| M6 | delete `soleur-boot-emit inngest_pull_fatal fatal` from the SECOND pull-fatal arm only (the no-endpoint arm) | T6 |
| M7 | `frequency_minutes = 28` (collides) | T7 |
| M8 | add `soleur-boot-emit provision_attempt_failed warning x` to `cloud-init.yml` | T8 |

**Harness rows.** H1 (must RED): move the `nc` condition line into a `#` comment inside the block.
The comment strip makes T4 red, so a comment cannot satisfy a code anchor. H2 (must PASS, not the
canonical): swap the order of the two `.tf` conditions. T3/T4 match by key, not position, so the
swapped block stays green. H3 (must RED): an empty derived stage set (the provision-block slice
misses) reds the non-empty floor rather than passing `∅ == ∅`.

**Anchor.** Not a stored-value guard. The one stored copy (`alert-reference.json`) is held by the
`plan_pr` reference gate to the Terraform plan projection and by the daily drift job to live
Sentry, both outside this test.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/issue-alerts.tf`: one new `sentry_alert` in the existing Sentry root
(R2 backend, provider `jianyuan/sentry` 0.15.7 unchanged). No new variables, secrets or providers.

### Apply path

`apply-sentry-infra.yml` applies the full root on push to main (path filter `apps/web-platform/infra/sentry/**`).
Expected plan: 1 to add, 0 to change, 0 to destroy. There is no downtime or host impact. Kill switch:
`[skip-sentry-apply]` in the merge commit message (not used; the operator authorized the apply).

### Distinctness / drift safeguards

The PR-time reference gate plus the daily drift probe; `lifecycle.ignore_changes = [environment]`
like its siblings. dev/prd: this root targets the single prd Sentry org `jikigai-eu`, with no dev
counterpart (unchanged).

### Vendor-tier reality check

The org already runs 37 `sentry_alert` rules (38 live workflows including the vendor defaults).
Issue alerts are not tier-gated.

## Encryption Posture

```yaml
at_rest:
  - store: "none new; the change adds one alert rule definition in Sentry and no data store"
    mechanism: "no store introduced; the rule definition lives in Sentry's existing config and in the existing R2 Terraform state"
    evidence: "Files to Edit/Create: one sentry_alert block, a JSON reference entry, docs, one vitest"
    defends_against: "no new data-at-rest exposure is created by this change"
    does_not_defend: "the existing Terraform state in R2 and Sentry's own storage are unchanged; their postures are outside this change"
    disclosed_as: "no new disclosure; the existing Sentry processing is unchanged"
    live_verification: "GET /organizations/jikigai-eu/workflows/?query=inngest-provision-failure after apply (AC-post-2)"
in_transit:
  - connection: "existing edges only: inngest host -> Sentry store API (soleur-boot-emit, HTTPS) and Sentry -> operator email"
    tls: "HTTPS to the DSN host (https://<ingest>/api/<id>/store/); email via Sentry's mail provider"
    cert_verification: "on"
    does_not_defend: "a holder of the public DSN can forge an event carrying these tags, trigger a page, and start the 120-min per-issue throttle that masks a real failure for up to 2 h (true of every tag-keyed rule in this root; corroborate against the Better Stack phone-home row)"
    disclosed_as: "existing Sentry processing, unchanged"
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-257** (no new ADR). Its Decision 5 recorded the non-pull alert rule as a tracked
deferral, and this closes it. The amendment is a plan task (Phase 3.2), not a follow-up.

### C4 views

All three files (`model.c4`, `views.c4`, `spec.c4`) are in scope. The actors, systems and
relationships involved are already modeled: the operator (`founder`), `sentry`, the inngest host
(`inngest`), `betterstack`, the `inngest -> sentry` boot-emitter edge and the `sentry -> founder`
paging edge. No element or relationship is added, and no `view include` changes. One description
becomes false and is fixed in Phase 3.3: the `sentry -> founder` count ("34 of the 36" → "35 of the
37"). The `inngest -> sentry` edge describes emission only, makes no paging claim, and is left
unchanged (the append was cut in plan review). `c4-count-parity.test.sh` and `c4-model-freshness.test.sh` must be green
after `scripts/regenerate-c4-model.sh`.

### Sequencing

The ADR stays `adopting`. Its flip to `accepted` belongs to the #8562 delivery probe, unchanged.

## Plan Review Revisions (2026-09-30)

Panel: DHH, Kieran and code-simplicity reviewers, plus the CTO on the devex lens. The threshold is
`aggregate pattern`, so the 3-agent baseline applied. Every applied item is Mechanical.

- **Cut:** old T7/T8 (the zot rule's condition and fatal coverage), because
  `sentry-zot-mirror-fallback-alert-op-contract.test.ts` already pins both. Also cut old T10 (the
  reference mirror), because the `plan_pr` reference gate is the authority. Also cut the
  `EXEMPT_WARNING_STAGES` constant (YAGNI), T2's negative clause, the C4 `inngest -> sentry`
  prose append, the ADR amendment section (only the in-place pointers remain), the rule
  comment's hand-kept frequency list, the vacuous AC-post-3, and recording the mutation battery in
  the PR body.
- **Fixed (Kieran):** the reference conditions are authored in the projection's `sort_by(tostring)`
  order (`detail` first), and validated with the projection jq. The frequency-uniqueness row is
  anchored on `^\s*frequency_minutes\s*=\s*120\b`, because `cron-monitors.tf` carries
  `checkin_margin_minutes = 120`. AC-post-2 is now a deterministic projection diff. T5 also pins the
  `bootstrap_done_degraded` emit line.
- **Added (CTO):** T3 fails on a wrapper (non-literal) emit, so the derivation cannot silently miss
  a stage. T6 is order-insensitive (counts). The runbook gets a page-reading block: identify the
  page, a `why=` → action map, read commands for both stages, "degraded pages once", the throttle
  masking window, and the sanctioned quiet lever.
- **Declined:**
  - DHH wanted to cut T5. Kept: it binds the RULE's `nc` value to the emitter's `why=` format, which
    no other suite does.
  - DHH wanted to cut `decision-challenges.md`. Kept: headless taste routing requires it.
  - DHH wanted to cut T8 (formerly T11). Kept in simplified form: two templates, not a directory
    walk.

## Acceptance Criteria

### Pre-merge

- [x] AC1: the new op-contract vitest is RED on the base tree (T1: resource absent) and GREEN
  after Phase 2 (`cd apps/web-platform && npx vitest run test/sentry-inngest-provision-failure-alert-op-contract.test.ts`).
- [x] AC2: mutations M1–M8 and H1/H3 each redden the named row, and H2 stays green (run locally
  during work; not recorded in the PR body).
- [x] AC3: T25 green: `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` reports the T25
  block passing with README ``**38 `sentry_alert` rules**`` / `(38 alert rules total)`.
- [x] AC4: `terraform fmt -check` clean and `terraform validate` (`init -backend=false`) green on
  `apps/web-platform/infra/sentry`.
- [ ] AC5: CI `plan_pr` in `apply-sentry-infra.yml` green. The reference gate passes, the CREATE gate
  lists exactly `sentry_alert.inngest_provision_failure`, and the destroy count is 0.
- [ ] AC6: C4 tests green after regeneration (`c4-model-freshness`, `c4-count-parity`,
  `c4-code-syntax`, `c4-render`).
- [ ] AC7: the PR body's **first line** answers "does merging this alone change production?": "Merging
  auto-applies one additive Sentry alert rule (`apply-sentry-infra.yml`), and nothing else." The body
  has `Closes #9176` and states "arms dark until the next inngest-host-replace (ADR-257)". The
  body names `bootstrap_done_degraded` paging as a deliberate addition beyond the issue's list
  (DC-1 in `decision-challenges.md`). The diff touches no workflow file: `git diff --quiet origin/main...HEAD -- .github/workflows/` exits 0.
  `apply-sentry-infra.yml` is the only push-triggered workflow that applies this root. The others
  whose `paths:` cover `infra/sentry/` (`infra-validation.yml`, `sentry-audit-gate.yml`) contain no
  apply step.

### Post-merge (operator-authorized apply; no other production write)

- [ ] AC-post-1: the `apply-sentry-infra.yml` run for the merge SHA concludes `success`, with AC17 and
  post-apply fidelity green (`gh run list --workflow apply-sentry-infra.yml --branch main -L 3 --json headSha,conclusion`).
- [ ] AC-post-2: the live rule equals the committed reference (read-only, `SENTRY_ISSUE_RO_TOKEN`
  from Doppler `soleur/prd`, never printed). Project the live workflow with the same jq the gates use
  and diff it against the committed entry:
  `curl -s -H "Authorization: Bearer $TOK" "https://sentry.io/api/0/organizations/jikigai-eu/workflows/?query=inngest-provision-failure" | jq -S --arg side live -f tests/scripts/lib/sentry-alert-projection.jq | jq -S '."inngest-provision-failure"' > /tmp/live.json`
  then `jq -S '."inngest-provision-failure"' apps/web-platform/infra/sentry/alert-reference.json | diff - /tmp/live.json`
  exits 0. This proves `name`, `enabled`, `frequency 120`, the `all` logic and both conditions
  (including the first-ever `nc`) round-tripped. Run it inside `doppler run -p soleur -c prd -- sh -c '…'`
  so `$TOK` is expanded after Doppler sets it.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change (one internal
paging rule plus docs). No user-facing surface, no copy, no pricing or legal implication.

## Test Scenarios

- The op-contract rows T1–T8 plus the Guard Contract mutation matrix (M1–M8, H1–H3).
- The existing `cloud-init-inngest-provision-unit.test.sh` (unchanged) continues to pin the
  emitted line format that T5 relies on.

## Dependencies & Risks

- **`nc` round-trip.** This is the first `nc` in the root. The provider passes it through, and
  Sentry's schema accepts it (`MATCH_CHOICES`). If the apply rejected it, the apply run goes red
  post-merge with nothing created. Fix-forward: drop the `detail` condition in a follow-up PR and
  accept pull double-pages. Either way no page storm is possible, because `stage in` is the
  always-present positive filter.
- **CREATE-gate ancestry.** If another Sentry PR applies first, update the branch and re-push.
- **Shared issue group.** Mitigated by `all` logic (T2) and documented in the rule comment and
  the runbook.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold fails `deepen-plan` Phase 4.6. This one is filled.
- Do not put a stage literal in a `.tf` comment and treat it as coverage. The test strips comments
  (H1).
- `alert-reference.json` conditions are in the projection's canonical `sort_by(tostring)` order
  (`detail` before `stage`), not `.tf` order.
- Never mute `WEB-PLATFORM-4S` to quiet this rule. That group carries every boot stage of every host.

## Review Amendments (2026-09-30)

The 10-agent review superseded four claims above; the shipped artifacts carry the corrected form.

- **P2, Phase 3.1 "pages once per boot", and the Observability row's "(pages once per boot)":** a
  degraded bootstrap pages only if this rule has not paged in the prior 2 h. The throttle is per
  rule per issue group and shared by both stages, and the degraded stage is never re-emitted, so
  the common fail-then-degraded sequence suppresses it until the next boot. The runbook now tells
  the operator to confirm `bootstrap-done` for the same `iid` after any page. The structural fix (a
  second rule) exceeds the one-rule production write authorized for this PR and is recorded as
  DC-2 in `decision-challenges.md`.
- **"ADR-257 measured about 26 events an hour":** ADR-257 estimates it. The unit's own comment
  derives ~8 attempts in the first hour and ~4/h backed off; the rule comment cites that.
- **The guard test:** T1–T8 as planned pinned only what must be present. Review showed an extra
  AND-ed condition, a second action filter, `enabled = false`, a dropped action and several
  emit-call spellings all left it green. The shipped test also pins absence (exactly two
  conditions, one filter, one action, the full reference entry, every emit call's shape, a
  directory-derived `.tf` list, and every infra file for stray stage names); a 28-row battery
  covers the reviewers' mutations.
