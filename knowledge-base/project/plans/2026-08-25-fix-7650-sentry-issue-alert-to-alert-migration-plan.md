---
title: "fix: migrate sentry_issue_alert -> sentry_alert off the deprecated alert-rule API (#7650)"
issue: 7650
closes: 7650
type: fix
classification: infrastructure-iac
lane: cross-domain
branch: feat-one-shot-7650-phase2-sentry-alert-import
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-08-25
updated: 2026-09-04
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 reviewed. Every change here lands as Terraform config or workflow YAML and is applied
by the existing merge-triggered `apply-sentry-infra.yml`. There is no provisioning step, no SSH,
no dashboard step and no CLI state surgery in scope. The sentinel fires on §2.5 and §2.9, which
describe recovery gestures in order to FORBID them — naming a dangerous path so it is not taken
is the opposite of prescribing it, and is the false-positive shape the sentinel's own
actor+imperative model warns about. See `## Infrastructure (IaC)`.
-->

# Migrate off the deprecated alert-rule API (#7650)

## Decision headline

**[Updated 2026-09-04 — Phase 2 is UNBLOCKED, scope is 27, adoption is by config blocks.]**

Phases 0 and 1 are DONE and merged. The blocker recorded on 2026-09-02 — "the provider cannot
express a frequency TRIGGER" — was measured at `v0.15.5` and was correct then. Upstream PR 943
merged 2026-09-01, one day before `v0.15.7` was cut, and `trigger_conditions` now expresses
**five** types including `event_frequency_count` with its `{value, interval}` comparison.
`versions.tf` and `.terraform.lock.hcl` both pin `0.15.7`, the latest release.

The operator has folded the three `auth-*` **burst** rules in, so this is **27 of 29**, leaving
`auth-per-user-loop` and `sandbox-startup-failure` behind upstream 950.

This is an **adoption, not a re-creation.** Sentry already migrated all 29 rules server-side.

It lands as **one PR**: 27 `sentry_alert` blocks, 27 `import {}`, and 27
`removed { lifecycle { destroy = false } }`, applied on merge by the existing workflow.

Evidence: [`phase2-v0157-frequency-trigger-landed-scope-is-27.md`](../specs/fix-7650-sentry-alert-migration/phase2-v0157-frequency-trigger-landed-scope-is-27.md).

---

## Retractions and measurements — 2026-09-04

Seven premises this plan carried were wrong, and **three of them were in its own acceptance
criteria**. All are recorded rather than quietly edited. Everything below was measured on
Terraform `v1.10.5` — the version `apply-sentry-infra.yml:131` pins — using the `terraform_data`
**builtin** (`terraform.io/builtin/terraform`), which needs no provider registry and so runs in a
sandbox with no network.

### R1. `removed {}` does NOT refresh. It was never DOA.

**Retracted:** *"`removed {}` blocks are likely DOA — a plan/apply refresh of the removed
resource hits the 410."*

```
CONTROL (both resource blocks present):    2 "Refreshing state" lines
FORGET ARM (removed{} on one of them):     1 line — the forgotten address was NOT refreshed
                                           Plan: 0 to add, 0 to change, 0 to destroy.
```

Mechanism: HashiCorp PR 35458, *"core: do not refresh when forgetting instances"* —
`internal/terraform/node_resource_plan_orphan.go`, `if !n.skipRefresh && !forget`.

`removed {}` is therefore the construct **guaranteed** never to touch the deprecated `rules/`
endpoint — the opposite of the retracted claim.

### R2. `terraform import` requires the config block to already exist.

**Retracted:** *"Run `state rm` + `import` BEFORE the merge that lands the `sentry_alert` blocks."*

```
Error: resource address "null_resource.zzz" does not exist in the configuration.
Before importing this resource, please create its configuration in the root module.
```

`main` has zero `sentry_alert` blocks, so that sequencing **is not implementable**. Config-block
adoption reaches the same goal by construction.

### R3. The apply is NOT atomic. The property is idempotent roll-forward.

**Retracted:** *"a single atomic apply"*, *"no window in which state and config disagree"*.

Terraform applies are not transactional — independent nodes apply concurrently and state persists
incrementally, **including on error**. A failure on import #14 leaves 27 forgets done and 13
imports done: 14 live rules managed by nothing.

The design survives, for a reason that is **measured, not assumed**:

```
PROBE A — import{} whose address is ALREADY in state:            "No changes." rc=0
PROBE B — removed{} naming an address absent from state+config:  "No changes." (no error)
```

Both blocks are inert once satisfied, so **a re-run rolls forward**. That is why the blocks must
stay in config until verification passes — Phase 11's sequencing is load-bearing, not cosmetic.

### R4. An import PREPENDS a clause to the plan summary line.

**Retracted:** an earlier AC asserted `Plan: 0 to add, 0 to change, 0 to destroy.` on a plan
containing 27 imports.

```
Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
```

The bare form is what a plan with **no imports at all** prints — the AC would have passed only if
the `import{}` blocks silently did nothing. **A forget does not appear in the summary counts at
all**; it renders as a separate `Warning: Some objects will no longer be managed by Terraform`.
So the summary line cannot distinguish "27 forgets happened" from "nothing happened". Because the
literal is version-sensitive, AC2 asserts the **plan JSON**, which is the stable contract the
workflow already uses, and treats the summary line as corroboration.

### R5. `importing` sits at `.change.importing.id`, not `.importing.id`.

```json
{ "address": "…", "change": { "actions": ["update"], "importing": { "id": "ac59705f-…" } } }
{ "address": "…", "change": { "actions": ["forget"], "before": { … }, "after": null } }
```

An earlier AC used the wrong path; the verification command would have returned 0 on a correct
plan. The forget row's populated `before` and null `after` are what make the destroy filter's
`before - after` arithmetic register it (§2.3).

### R6. The destroy gate does NOT print forgotten addresses.

**Retracted:** *"the gate prints the addresses (`apply-sentry-infra.yml:418-419`)"* — which was
the justification offered for accepting a blanket ack.

```sh
addresses=$(terraform show -json tfplan | \
  jq -r '[.resource_changes[] | select(.change.actions == ["delete"]) | .address] | sort | .[]')
```

`["forget"] != ["delete"]`, so `$addresses` is **empty** for this PR's shape. Both the PASS and
FAIL branches print a blank list while claiming N destructive changes. The human-visible set the
ack was justified against does not exist. §2.3 is corrected, and the message-only jq is widened
(§2.4) — `resource_deletes` itself stays `delete`-only, because AC4's discrimination depends on it.

### R7. A file-level enum grep FAILS on a correct migration.

**Retracted:** an earlier AC asserted `grep -c 'IssueOwners\|"EQUAL"\|"IS_IN"'` over
`issue-alerts.tf` returns 0. Measured on the current file: **49** `IssueOwners`, **50** `"EQUAL"`.
Five of them are in the two survivors (`auth_per_user_loop`, `sandbox_startup_failure`), where
they are **correct** for `sentry_issue_alert`.

So the AC failed on a perfect migration — and it is the exact per-block-vs-per-file collapse this
plan lectures about in Trap 3 and demands in AC5. AC7 now uses the same block walker.

---

## Research Insights

### Premise Validation

| Cited premise | Verdict |
|---|---|
| #7650 | **OPEN.** Valid. |
| #4610 — predecessor migration | **CLOSED**, on a changelog-sourced false premise. Origin of the read-the-source rule. |
| #7634 — WRITE path unknown on `workflows/` | **OPEN — this PR resolves it for 27 rules.** [§2.7](#27-7634-is-crossed-not-stepped-over) |
| #4781 — auth rules drift to empty filters | **OPEN.** Folding three of four in is its remediation. |
| Upstream 950 | **Still open**; action-filter-only at `resource_alert_gen.go:318 @ v0.15.7`. |
| Upstream 943 | **Merged 2026-09-01**, in the v0.15.7 tree. |
| `v0.15.7` latest | `git ls-remote --tags` ends there (`364da964`). |
| Terraform supports the mechanism | `1.10.5`. `import {}` ≥1.5; `removed {}` + `destroy = false` ≥1.7. |

### Property List

1. The 27 rules keep firing on exactly the events, thresholds and windows they fire on today.
2. No duplicate live paging rule is ever created.
3. No live paging rule is destroyed, **or orphaned** — left live with nothing managing it.
4. Every one of the 27 `name` strings survives byte-for-byte.
5. `terraform plan` stops depending on the deprecated read path for 27 of 29 resources.
6. The three `auth-*` burst rules stop being **authored** in a drift-prone posture (#4781), and
   drift on any of the 27 becomes **detectable**, not only repairable.
7. A future edit cannot silently reintroduce any of the above.

### Cut List

| Mechanism | Property | Why cut |
|---|---|---|
| A name-fidelity guard and a `.tf`-vs-live definition diff | 1, 4 | The import-time plan quantifies over every attribute of every imported resource. An earlier revision cut these and then re-added them as ACs; the contradiction resolves in favour of the cut. |
| A one-time `workflow_dispatch` running `state rm` + `import` | 2, 3 | **Cut by R2** — not implementable against `main`; against the feature ref it reintroduces the divergence window. |
| A `legacy_trigger_conditions` guard **suite** | 1 | Its assembly reads `terraform state list`, but the surface it was routed to (`scripts/test-all.sh`) has no R2 credentials — it could only ever have tested fixtures while claiming to assert state. Kept as AC12, executed by the workflow, which does have credentials. |
| A live-comparison guard **suite** | 1 | Its precondition (an apply issued an Update) is one this PR's `0 to change` guarantees will not happen. Its script is repurposed for the §2.9 ongoing probe — a real need, not speculative reuse. |
| A multi-condition-trigger lint with a `# any-short intended` opt-in | 7 | Would ship **pre-suppressed on 13 of 27 blocks**, teaching that the marker is boilerplate — the failure it exists to prevent. Replaced by the ADR amendment plus an inline comment at the authoring site, which reaches the author at the moment of authorship. |
| Merging `forget` into `resource_deletes` | 3 | Destroys the discrimination AC4 needs. A separate counter is the right shape (Guard C). |
| A "surgery completed" marker file | 3 | `terraform state list` is the authority; a second progress signal resolves fail-open on disagreement. |
| A CI probe re-measuring R1 | R1 | R1 is measured directly above, and `plan_pr` is the real gate: if `removed{}` refreshed, it would 410 and red before merge. |

**Three guards survive**, each wired to a surface that can actually run it.

### Value-Proposition Measurement

Deprecated-read-path exposure goes from **29 of 29** — measured, CI run 32362401543
(2026-08-20T11:09:07Z) took 410 on 29 of 29 reads and failed `terraform plan` — to **2 of 29**.

### Applicable institutional learnings

- [`2026-08-19-i-proposed-deleting-a-control-because-terraform-appeared-to-own-it.md`](../learnings/2026-08-19-i-proposed-deleting-a-control-because-terraform-appeared-to-own-it.md)
  — per-resource vs per-file `ignore_changes`. **Read before cutting anything from
  `configure-sentry-alerts.sh`.**
- [`2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`](../learnings/2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md)
  — `base_url` stays the org subdomain. Also the mechanism behind the `monitor_ids` correlated
  rebind in [§2.6](#26-the-correlated-monitor_ids-rebind).
- The `apex_move_orphans` tripwire in `apply-web-platform-infra.yml` — the precedent for a
  failure an ack must deliberately not discriminate. Guard A is modelled on it.

---

## Research Reconciliation — supplied vs measured

| Claim as supplied | Measured reality | Response |
|---|---|---|
| "`apply-web-platform-infra.yml` has the import/state-surgery pattern to mirror." | **False.** Zero `terraform import`/`state rm`/`state mv` invocations in that file; the precedent is `apply-github-infra.yml:242-305`. | Moot under config-block adoption. Recorded so the next reader does not re-follow the pointer. |
| "The create-gate would catch it." | **The create gate does not exist on the apply path.** `scripts/sentry-create-gate.sh` is invoked once, `apply-sentry-infra.yml:409`, inside `plan_pr`. `apply` computes `$resource_creates` via the shared `eval` at `:799` and **never reads it**. The PR-side gate is **diff-matched** (`:58`), so it passes on a PR that adds the blocks. | Right warning, wrong reason. Guard A supplies it, correctly scoped. |
| "lifecycle -> `trigger_conditions`, logic_type any-short" | No `logic_type` exists under `trigger_conditions`; the provider **hardcodes** the trigger group (`resource_alert_impl.go:803`, `:835`). `action_filters[].logic_type` is **not** uniform — 4 of 27 are `any-short`. | Mapping corrected; the hardcode goes to the ADR and an inline comment. |
| `sentry_alert` shape | **No `project` attribute**; `frequency_minutes` is **top-level and required**. | `project = …` disappears from all 27. |
| Enum vocabulary | `tagged_event.match` has **no enum validator** (`resource_alert_gen.go:658-663`); live values are lowercase `eq`/`in`. `target_type` is `issue_owners`. | A carried-over `"EQUAL"` passes `validate` and `plan` and matches nothing live. The import diff catches it. |

### The frequency-source trap, measured in both directions

| rule | `issue-alerts.tf` | `configure-sentry-alerts.sh` | **LIVE** |
|---|---|---|---|
| `auth-signout-burst` | 60 | 60 (`:178`) | **60** |
| `auth-exchange-code-burst` | 61 | 60 (`:154`) | **61** |
| `auth-callback-no-code-burst` | 62 | 60 (`:160`) | **62** |

The `.tf` values 61 and 62 are **live**, and the dedup rationale is real and file-wide. The
divergence runs the other way: **the script would rewrite live 61→60 and 62→60 if it ran.** The
script is the drift source — which strengthens the case for retiring its ownership (§2.2).

---

## Scope: 27, derived not asserted

```sh
doppler run -p soleur -c prd -- bash -c '
  curl -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
    "https://$SENTRY_API_HOST/api/0/organizations/$SENTRY_ORG/workflows/?per_page=100"' \
  > wf-all.json

jq -r '.[]
  | select(.name != "Send a notification for high priority issues")
  | select([.triggers.conditions[].type] | any(. == "event_unique_user_frequency_count") | not)
  | "\(.name)\t\(.id)"' wf-all.json | sort
# => 27 rows
```

| | N | Disposition |
|---|---|---|
| Live workflows | 30 | |
| `Send a notification for high priority issues` (566201) | -1 | Sentry's own default. **Never import** (#7142). |
| `auth-per-user-loop` (566671), `sandbox-startup-failure` (669246) | -2 | `event_unique_user_frequency_count` — action-filter-only. Upstream 950. |
| **In scope** | **27** | 16 lifecycle + 11 frequency, incl. the three `auth-*` bursts. |

### Trap 2, re-measured

```sh
jq -r '[.[] | .triggers.conditions[]
        | if (.comparison|type)=="object" then (.comparison|keys|join(","))
          else "SCALAR:\(.comparison|type)" end]
       | group_by(.) | map({k:.[0],n:length})' wf-all.json
# => [{"k":"SCALAR:boolean","n":44},{"k":"interval,value","n":13}]
```

44 booleans, all lifecycle types. 13 objects, all frequency types, every one exactly
`{interval, value}` with **no `filters` key**. **Zero bare booleans**, so nothing falls into
`legacy_trigger_conditions`, where the threshold would be unrecoverable
(`resource_alert_impl.go:896-898`; write reconstructs `true` at `:740`).

### Trap 3, resolved per resource block

- **25 blocks**: `ignore_changes = [environment]` only — Terraform owns their filters.
- **4 blocks** (the `auth-*` set): the full five-attribute list — Terraform owns nothing.

**Three of those four move into the first set here.** A stale mental model of "the auth four" is
now wrong in a way that reads plausible.

---

## The mapping, measured at v0.15.7

| Live API | `sentry_alert` @ v0.15.7 | Source |
|---|---|---|
| lifecycle trigger types | `trigger_conditions[]`, empty-object form | `resource_alert_gen.go:99,108,117,126` |
| `event_frequency_count`, **object** comparison | `trigger_conditions[].event_frequency_count = { value, interval }` | `:135-162`; interval enum at `sentrydata.go:1179-1187` |
| same, **bare boolean** | `legacy_trigger_conditions`, threshold **unrecoverable** | `resource_alert_impl.go:896-898`, `:740` |
| `event_unique_user_frequency_count` | **not expressible as a trigger** | `:318`; upstream 950 |
| `triggers.logicType` | **no attribute**; hardcoded `any-short` | `resource_alert_impl.go:803`, `:835` |
| `actionFilters[].logicType` | `action_filters[].logic_type` ∈ `any` `any-short` `all` `none` | `:173`; `sentrydata.go:1171-1176` |
| `tagged_event {key, match, value}` | `action_filters[].conditions[].tagged_event`, **`match` lowercase** | `:645-670` |
| email action | `action_filters[].actions[].email`, `target_type = "issue_owners"` | `:765-800` |
| `config.frequency` | **top-level** `frequency_minutes` (int64, required) | `:87` |
| `detectorIds` | `monitor_ids` (set of string, required) | `:82` |
| `project` | **no such attribute** | `:49-1188` |

### The hardcoded trigger logic type

Both request builders pin the trigger group to `any-short`, and the read path has no field for
the live value. **On the first apply that issues an Update, a rule's live `triggers.logicType`
becomes `any-short` regardless of what it was — and `terraform plan` cannot show it.**

Inert for our 27, measured: every `all` group holds **exactly one** condition (14 of 27), and a
one-condition group evaluates identically either way; every multi-condition group (13 of 27) is
**already** `any-short`. Not inert for the future — hence the ADR and the inline comment, rather
than a lint that would ship suppressed on half its corpus.

---

## Phase 0 — COMPLETE (2026-08-26): PASS

[`phase0-fidelity-evidence.md`](../specs/fix-7650-sentry-alert-migration/phase0-fidelity-evidence.md).
Sentry had already migrated all 29 rules server-side. All 30 workflows bind detector `1213799`.
Frequency is a first-class trigger in the API; `actionFilters` carry `tagged_event` only (65/65).

## Phase 1 — COMPLETE and merged: destroy-guard extension

`destroy-guard-filter-sentry.jq:111-117` + `:139-144` over five surfaces, mutation-proven by
`test-destroy-guard-counter-sentry.sh` T10-T14, with `sentry_alert` in `COVERED_TYPES` at
`test-destroy-guard-sentry-scope-guard.sh:72`.

---

## Phase 2 — author the 27 and adopt them in one merge

### 2.0 The mechanism

```hcl
removed {
  from = sentry_issue_alert.auth_exchange_code_burst
  lifecycle { destroy = false }
}

import {
  to = sentry_alert.auth_exchange_code_burst
  id = "jikigai-eu/566682"          # organization/workflow-id
}
```

1. **No divergence window.** The forget and the import are in the same plan as the config that
   justifies them.
2. **One writer.** `main.tf:16` sets `use_lockfile = false` and `concurrency.group` is keyed by
   `github.ref`, so two paths on different refs would write the **same unlocked object**. One
   apply path removes that.
3. **`plan_pr` is a credentialed rehearsal** — it extracts R2 credentials from Doppler
   `prd_terraform` (`:251-264`) and plans with `SENTRY_AUTH_TOKEN`, performing the real import
   reads.
4. **Recovery is idempotent roll-forward** (R3), measured by probes A and B.

**The import diff is the fidelity gate.** A divergent attribute renders as `["update"]` carrying
`change.importing`, and the "to change" count rises. The destroy guard cannot see that — it counts
deletes, creates and nested shrink, not updates — so an equal-length rewrite (`interval`
`15m`→`1h`, `value` `5`→`3`, `frequency_minutes` `60`→`61`) yields `{0,0,0}` and a green gate
while silently rewriting a live paging threshold.

**Two boundaries on that gate, both of which cost an earlier revision its correctness:**

- **It covers every attribute the SCHEMA carries — not every attribute.** The hardcoded
  `triggers.logicType` is outside the schema and therefore outside this gate, by construction.
- **`plan_pr` is not the plan that executes.** The `apply` job **re-plans from scratch** against
  live state at merge time (`:657` onward) and applies that. The apply-side gate branches only on
  `destroy_count` — there is **no `0 to change` assertion on the apply path at all**. So an
  attribute divergence introduced between the PR plan and the merge sails through and rewrites a
  live paging threshold: exactly the failure class this plan exists to prevent. **AC10 moves the
  assertion into the apply job**, before `terraform apply`. That is the single largest hole the
  review round found, and it is one jq expression.

**If any of the 27 renders as `update` rather than `no-op`, stop.** Two causes: an **authoring
divergence** (fix the `.tf`), or a **provider read-back gap** (an attribute written but not read —
a permanent perpetual diff). The R5 probe shows the second shape concretely.

### 2.1 Author the 27 from a committed live capture

Commit the capture under `knowledge-base/project/specs/fix-7650-sentry-alert-migration/`, so the
blocks are re-derivable and §2.9's probe has a baseline.

```hcl
data "sentry_project_issue_stream_monitor" "web_platform" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
}

# DELIBERATELY NOT auth-signout-burst. That rule's frequency happens to be 60, which is
# also the value configure-sentry-alerts.sh hardcodes for all three — so an example built
# on it is the one example that cannot expose the frequency-source trap. This one is 61.
resource "sentry_alert" "auth_exchange_code_burst" {
  organization      = var.sentry_org
  name              = "auth-exchange-code-burst"  # byte-for-byte from the live payload
  enabled           = true
  frequency_minutes = 61                          # config.frequency, TOP-LEVEL, PER RULE.
                                                  # 60/61/62 signout/exchange/callback.
                                                  # The script says 60 for all three; live wins.
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  # Exactly ONE trigger condition. The provider hardcodes this group's logic type to
  # `any-short` (resource_alert_impl.go:803 create, :835 update) and exposes no attribute
  # for it, so a SECOND entry here silently becomes OR — and no plan can show you that.
  # Adding one is a deliberate act: see ADR-031 §Amendment 2026-09-04.
  trigger_conditions = [
    { event_frequency_count = { value = 5, interval = "15m" } },
  ]

  action_filters = [
    {
      logic_type = "all"                     # per rule; 4 of 27 are "any-short"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "auth" } },
        { tagged_event = { key = "op", match = "eq", value = "exchangeCodeForSession" } },
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

Binding rules:

- **`ignore_changes = [environment]` and nothing else, on all 27.** This is what makes tag drift
  self-healing on the next apply, and it is the compensating control `assert-byok-rules-exist.sh`
  relies on. Carrying the `auth-*` empty-placeholder posture forward would launder an open
  recurrence guard (#4781) into a new resource type.
- **No `project`.** **`match` lowercase.** **`target_type = "issue_owners"`.**
- **`fallthrough_type = "NoOne"` for `byok_cap_exceeded` alone**; `ActiveMembers` for the other 26.
- **Preserve every `name` byte-for-byte.**
- Delete the 27 corresponding `sentry_issue_alert` blocks in the same commit — a `removed{}`
  naming an address that still has a resource block is a configuration error. Keep
  `auth_per_user_loop` and `sandbox_startup_failure`.
- `data.sentry_project.web_platform` stays: 55 references in `cron-monitors.tf`, 4 in
  `uptime-monitors.tf`.

Re-run the Trap-2 comparison-shape measurement **before** authoring and paste it into the PR — a
precondition on the authoring step, not a post-condition.

### 2.2 Retire the script's ownership of the three burst rules

**Read the 2026-08-19 learning before cutting anything here.**

`configure-sentry-alerts.sh` **is not deleted** — it remains the executable definition for
`auth-per-user-loop`. It **is** edited: it upserts all four through the deprecated `rules/`
endpoint (`:121-123`, `:132-134`) and is the drift source for two of the three frequencies.

- Delete **only** the three burst stanzas (`:151-154`, `:157-160`, `:175-178`). Keep
  `auth-per-user-loop` (`:165-168`).
- Rewrite the header enumeration at `:5-9`, which lists four rules.
- Fix the docstring at `apps/web-platform/test/auth/sentry-tag-coverage.test.ts:8`.
- Update the ownership table in the 2026-08-19 learning; post the split to #4781.

**Split ownership is itself the hazard** — the next drift incident's repair procedure would
otherwise point at a script that no longer defines three of the rules it names.

### 2.3 Ack posture — corrected

**Verified against the real filter, on real Terraform output.** A forget row has
`actions == ["forget"]` and `after == null`; the filter selects on `index("delete") | not` — true
for a forget — and `sentry_issue_alert_blocks_count(null)` is 0, so the full v2 sum lands in
`nested_deletes`:

```
$ jq -f tests/scripts/lib/destroy-guard-filter-sentry.jq <one-forget fixture>
{ "resource_deletes": 0, "resource_creates": 0, "nested_deletes": 4 }
```

Against a **real** `terraform show -json` forget plan on a clause-less type the same filter
returns `nested_deletes: 0` — Guard C's hole, demonstrated rather than argued.

So `destroy_count > 0` across 27 forgets and the merge commit must carry a pre-staged
`[ack-destroy]`, on its own line in a commit **BODY** (never a subject — GitHub prefixes subjects
with `*` followed by a space when composing the squash body, breaking the line anchor).

**Per R6, the gate prints nothing for this shape.** The earlier justification — "the ack is safe
because the gate shows the human which addresses are affected" — was false. Two consequences:

- The message-only jq is widened to `index("delete") or index("forget")` so the set is actually
  displayed (§2.4). `resource_deletes` itself stays `delete`-only.
- Until then the ack is paired with `resource_deletes == 0` **and** the Guard B bijection (AC3),
  which is what actually proves the 27 leaving management are the 27 being re-adopted.

**The merge method is load-bearing and unasserted.** `sentry-squash-ack-detect.sh` predicts the
squash-body composition, and `:455-463` asserts `squash_merge_commit_message == COMMIT_MESSAGES` —
but nothing asserts the PR is squash-merged at all. A merge-commit merge yields
`Merge pull request #N from …` with no body, so the apply-side `HEAD_MSG` has no ack: **PR green,
apply red**, with `main` holding 27 `sentry_alert` blocks and state holding 27
`sentry_issue_alert`. Note also that under `GITHUB_TOKEN` the squash-mode read returns empty
(administration scope is not grantable) and the gate **warns and proceeds** — so the composition
premise is unverified on the PR side by design. AC5 pins the merge method.

### 2.4 Make `forget` first-class in the destroy counter (Guard C)

The hole is a `forget` on a type with **no nested clause** — `sentry_cron_monitor` and
`sentry_uptime_monitor` expose zero array-of-blocks, so a `removed{}` on either is counted by
**nothing**. Unreachable today; reachable the moment this PR makes `removed{}` idiomatic here.

**Add a fourth key `resource_forgets`, and sum it into `destroy_count`.** The second half is not
optional: `scripts/sentry-destroy-counts.sh:66` computes
`destroy_count=$((resource_deletes + nested_deletes))` and the gate at `:808` branches on
`$destroy_count` alone — a counter that reports but does not feed the sum is a **report, not a
gate**, and a `sentry_cron_monitor` forget would still print `PASS (plan destroys nothing)`.

The new formula, stated explicitly because its 30-line script header is a monument to exactly this
class of silent arithmetic drift:

```
destroy_count = resource_deletes + nested_deletes + resource_forgets
```

**Do NOT merge `forget` into `resource_deletes`** — AC4's discrimination depends on separation.

Five sites move together:

| Site | Change |
|---|---|
| `tests/scripts/lib/destroy-guard-filter-sentry.jq` | add `resource_forgets`. **jq preserves object-construction order**, so its position determines the literal every consumer compares |
| `scripts/sentry-destroy-counts.sh` | validate the fourth counter (`:55`); add it to `destroy_count` (`:66`) |
| `tests/scripts/test-destroy-guard-counter-sentry.sh` | **whole-object literal comparisons** at `:174`/`:191` break on a fourth key — convert to per-field assertions. Its `_run_gate` also **re-implements** `dcount=$((rdel + ndel))` by hand, a third copy of the arithmetic |
| `tests/scripts/test-sentry-destroy-counts.sh` | T3 (`:71`) asserts the two-term sum; expectation and test name both move |
| `apply-sentry-infra.yml:809` + `:419` | the operator message itemizes two terms and would understate its own verdict; and the address jq is widened per R6 |

**Class-wide, not widened here:** `destroy-guard-filter.jq` (GitHub root) counts neither forget nor
creates; `destroy-guard-filter-web-platform.jq` is internally split (`:137` not counting forget,
`:359` counting it). Three sibling filters, three postures, nothing adjudicating. File a follow-up.

### 2.5 Recovery is roll-forward. Three gestures are traps.

An earlier revision prescribed a state artifact as "the rollback path". **That is wrong in a way
that would make an incident worse**, and it is corrected here rather than dropped.

**Trap 1 — reverting the PR is the most destructive action available.** A revert restores 27
`resource "sentry_issue_alert"` blocks while state holds 27 `sentry_alert`. The resulting
full-root plan is **27 creates of `sentry_issue_alert`** (duplicate live paging rules, minted
through the *deprecated write path*) **plus 27 deletes of `sentry_alert`** (destroying the live
rules). Revert is the reflexive incident response and it is the worst available one here.
Guard A reds the create direction and `resource_deletes = 27` reds the destroy direction, so it is
caught — but that safety is one gate deep and must not be relied on.

**Trap 2 — restoring the pre-apply state points the wrong way.** After merge, `main` carries no
`sentry_issue_alert` blocks for the 27. Restoring re-adds 27 addresses with no config, so the next
full-root plan computes **27 destroys of live paging rules through the deprecated write path** —
both catastrophic and 410-wedged. It is also off-mechanism: it requires a forced state push
against an unlocked object, which is the CLI surgery this design was chosen to eliminate.

**Trap 3 — the documented escape hatch is closed for this PR.** The apply-side gate reads
`HEAD_MSG: ${{ github.event.head_commit.message }}` (`:665`), and **`head_commit` does not exist
on a `workflow_dispatch` event** — so `HEAD_MSG` is empty, `ack_destroy=false`, and any
`destroy_count > 0` reds. Meanwhile the push trigger is path-filtered, so a fresh ack commit must
*simultaneously* carry `[ack-destroy]` in its body **and** touch `infra/sentry/**` or the jq
filter. The workflow header advertises `workflow_dispatch` as the manual re-run path; for this PR
it is unusable, on exactly the runs that would need it.

**So the recovery table is short, and every row is automated:**

| Failure | Recovery |
|---|---|
| Partial apply (R3) | **Re-run the failed job on the original run.** Same event payload, ack intact, blocks still in config, both inert once satisfied (probes A, B). This is the only gesture that works and it must be in the PR body. |
| A divergent authored attribute, pre-merge | Caught by AC2 on `plan_pr`. Fix the `.tf`. |
| A divergent attribute at merge time | Caught by AC10 on the apply path — the assertion this plan adds. |
| A threshold destroyed by a legacy round-trip | Detected by AC12/AC16 and by the §2.9 probe; the repair is a write. |

The `terraform state pull` artifact is kept as **forensics** — useful for diffing what the apply
did — with an explicit short retention, captured both before and after the apply so an orphaned
state is diffable. It is **not** listed as a rollback capability.

**R2 object versioning, branch pre-declared:** R2 has no bucket-versioning API, so
`list-object-versions` is expected to return unimplemented. If it does, `infra/github/README.md`
§"Phase 5 — Rollback" documents a capability that does not exist **for every root on
`soleur-terraform-state`** — file that as its own issue with a named owner.

### 2.6 The correlated `monitor_ids` rebind

All 27 blocks share one `data.sentry_project_issue_stream_monitor` ("do not branch it per rule
class"). That is right, and it creates a **correlated failure the counters cannot see**: if the
data source ever resolves to a different or empty id — a project-slug change, or the EU-host slug
rewrite the 2026-05-17 learning documents — Terraform plans **27 updates at once**.

`resource_deletes`, `resource_creates`, `nested_deletes` and `resource_forgets` are all **0** for
that shape. The destroy gate is green, Guard A and Guard C are silent, and every one of the 27
rules unbinds from the issue stream simultaneously: **a total paging blackout behind a clean
plan summary.**

AC11 pins it: the resolved monitor id must equal the `1213799` recorded in the committed capture,
asserted in **both** `plan_pr` and `apply`. One equality check against a correlated blackout.

### 2.7 #7634 is crossed, not stepped over

**The provider's `workflows/` write path IS the write shape #7634 was waiting on**, and this PR
exercises it against 27 live rules. Record it as a resolution and **re-narrow #7634 to
`auth-per-user-loop`**.

The residue, stated plainly: that rule has a writer that works only on a **dying** endpoint and a
provider that **cannot express its trigger** (upstream 950 open). **When `rules/` is fully retired
it becomes unwritable by any mechanism available to us.** Not a reason to delay this PR — a reason
the residue must be visible in #7634 rather than implied by its absence.

It is also a standing **AP-001** deviation, shrunk 4→1, which belongs in the ADR amendment.

### 2.8 Sweep the artifacts this falsifies

| File | Stale content | Fix |
|---|---|---|
| **`apps/web-platform/scripts/assert-byok-rules-exist.sh:33-43`** | *"`issue-alerts.tf` DOES contain `ignore_changes = [conditions_v2, …]` — but on the four `auth-*` resources, which are a DIFFERENT four rules, managed by `configure-sentry-alerts.sh`"* | Update the auth-\* set **four → one**. Keep the distinction, the warning and the per-resource-block instruction. **Strongest row:** this PR *inverts* the paragraph, so left alone it is affirmatively **false about the exact distinction it exists to protect** — in a file that records having been "briefly 'corrected' into a falsehood on 2026-08-19 before being restored… the mistake is one grep away from being made again". **Do not weaken it.** |
| `scripts/followthroughs/sentry-brownout-frequency-7650.sh:83` | *"the migration is 25 + 4…"* | 27 + 2. **Executable output read mid-incident** — after this PR it points at the wrong repair |
| `apps/web-platform/infra/sentry/README.md` | adoption-path prose for the deferred state | Describe the adopted state and the mechanism |
| `tests/scripts/test-destroy-guard-sentry-scope-guard.sh:3-16` | *"Currently: …three types"*, *"A FOURTH type arriving"* | Four are covered; the prose misleads about whether `sentry_alert` is |
| `apps/web-platform/scripts/sentry-monitors-audit.sh:1312` | *"That adoption is complete (29 sentry_issue_alert resources…)"* | 2 remain. **Downgraded, and the earlier justification here was wrong:** `:1312` is a **bash comment** inside the `{ … } > "$out_file"` block; comments are not emitted, only the `printf` lines are. Verified at `:1298-1320`. A code-comment nit, not a compliance item |

**Two rows removed on review:** the v0.15.5 spec supersede banner is **already done** (listed as
work while being finished work), and the `versions.tf` note is **cut** — a second drift-capable
record of a fact the ADR amendment already holds, which is the objection this plan's own Cut List
used against a marker file.

### 2.9 Ongoing drift detection — the gap none of the guards close

Every mechanism above is change-time. After this lands, nothing detects a rule that exists, plans
clean, and has stopped firing — the failure mode for a plane whose symptom is silence:

- `assert-byok-rules-exist.sh` runs only post-apply on a `paths:`-filtered workflow. No commits
  under `infra/sentry/**` for three months means no run for three months. It covers **4 of 27**,
  existence-and-enabled only, and is documented fail-open to duplicates (`:29-30`).
- `sentry-audit-gate.yml` is `on: pull_request`. Change-time.
- **`scheduled-terraform-drift.yml`'s matrix is `apps/web-platform/infra` and `infra/github`. The
  Sentry root is not in it.**
- The brownout follow-through counts markers, not rule state, and decays toward zero once this
  lands.
- §2.2 removes the one independent re-assertion path the three burst rules had.

`assert-byok-rules-exist.sh`'s own SCOPE header already names the residue — *"out-of-band UI
mute/drift undetected until the next apply … covered by the deferred recurring-liveness-cron
option"* — and this PR makes that residue larger.

**Ship the probe.** One read-only `GET /api/0/organizations/{org}/workflows/?per_page=100` — the
same call the scope derivation makes, on the **non-deprecated** endpoint — diffed against the
committed capture. For all 27 rather than 4, that single call detects: deletion, `enabled: false`,
name drift, a changed `comparison.{value,interval}`, a changed `tagged_event` key/match/value, a
`logicType` flip, and a `monitor_ids` unbind. Its three env vars are already repo secrets wired at
`apply-sentry-infra.yml:830-834`. Cost: one workflow file, zero new vendor, zero new credential.

Route it per ADR-033 (Inngest cron → `workflow_dispatch`), opening/updating an issue on drift.
It is what makes Property 6's *detectable* half real, and it is the standing #4781 detector.

**Do not** add the Sentry root to `scheduled-terraform-drift.yml`'s matrix instead: that leg would
`terraform plan` the full root, still refreshing the two surviving `sentry_issue_alert` resources
through the deprecated endpoint, and that workflow carries none of the brownout retry — so it
would go red on Sentry's brownout calendar rather than on drift.

---

## Phase 3 — verification

- [ ] **3.1** Full-root plan no-op, no 410s, all four Sentry types.
- [ ] **3.2** `assert-byok-rules-exist.sh` lists all four `EXPECTED_RULES`, enabled.
- [ ] **3.3** The brownout retry **stays**, byte-unchanged in both jobs (AC9). At 27/29 the
      full-root plan still refreshes the two remaining resources through the deprecated endpoint.
      **This PR's own exposure is already 2/29, not 29/29**, because the `removed{}` blocks mean
      the other 27 are not refreshed (R1) — which is what keeps the brownout-deadlock case narrow.
- [ ] **3.4** Remove the retry only once **zero** `sentry_issue_alert` remain — now dependent
      solely on upstream 950.

**The deadlock case, stated rather than discovered:** `sentry-destroy-gate-verdict.sh:36` requires
`plan_pr` to be `success` or `skipped`, and `[skip-sentry-apply]` only affects the apply job. A
brownout wider than the retry budget therefore blocks this PR — the PR whose purpose is to cut
that exposure. Narrow (2/29, per 3.3) but real, and the PR body must name it so it is recognised
rather than debugged.

---

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — Scope and block counts.** The derivation returns 27; `issue-alerts.tf` declares 27
   `resource "sentry_alert"`, 27 `import {`, 27 `removed {`, and 2 `resource "sentry_issue_alert"`
   (`auth_per_user_loop`, `sandbox_startup_failure`).
2. **AC2 — The plan JSON is the fidelity gate.** On `plan_pr`'s plan JSON:
   `[.resource_changes[] | select(.change.actions != ["no-op"] and .change.actions != ["forget"])] | length == 0`;
   exactly 27 rows with `.change.actions == ["forget"]`; exactly 27 with `.change.importing.id`
   (**note the path — R5**); every `importing.id` equal to that rule's captured workflow id.
   The summary line — `Plan: 27 to import, 0 to add, 0 to change, 0 to destroy.` (**note the
   `to import` clause — R4**) — is corroboration, not the assertion, because it is
   version-sensitive. **"The destroy guard passed" does not satisfy this AC.**
3. **AC3 — Forget↔import bijection.** The set of `["forget"]` addresses equals the set of
   `.change.importing.id`-bearing addresses under the `sentry_issue_alert.X` → `sentry_alert.X`
   mapping — **membership, not just cardinality**. Dropping one `import{}` while keeping its
   `removed{}` is a one-line rebase artifact that orphans a live paging rule, and counting 27 and
   27 as independent scalars does not catch it.
4. **AC4 — Ack posture, both halves.** `scripts/sentry-squash-ack-detect.sh` exits 0 on the PR's
   branch commits (the *predictor*, which is what is checkable pre-merge); and
   `scripts/sentry-destroy-counts.sh` on the real plan JSON reports `resource_deletes=0`,
   `resource_creates=0`, `resource_forgets=27`. `resource_deletes == 0` is what proves nothing is
   destroyed.
5. **AC5 — The merge method is squash.** Asserted, not assumed — a merge-commit merge produces a
   body with no ack and reds the apply after `main` has already taken the config (§2.3).
6. **AC6 — `ignore_changes` per resource block.** A block walker anchored on
   `/^resource "sentry_alert"/` — **not** the Trap-3 walker, which is anchored on
   `sentry_issue_alert` and returns nothing here — returns `[environment]` for all 27, and for
   `byok_art_33_breach` specifically. Invisible to AC2, because `lifecycle` is not a plan attribute.
7. **AC7 — Enum translation, per block.** `IssueOwners`, `"EQUAL"`, `"IS_IN"` appear **zero** times
   **within the 27 `sentry_alert` blocks**, extracted by the same walker as AC6. **A file-level
   grep fails on a correct migration** — measured: 49 and 50 occurrences remain in the file, five
   of them legitimately in the two survivors (R7).
8. **AC8 — Authored from the committed capture.** The capture is committed, and every
   `frequency_minutes`, `value`, `interval`, `match`, `key`, `logic_type` and `fallthrough_type`
   matches **it** — not a plan-time literal, since live may drift between plan date and merge.
   The capture is what makes `auth-exchange-code-burst = 61` and `auth-callback-no-code-burst = 62`
   checkable rather than asserted.
9. **AC9 — The brownout retry is byte-unchanged** in both `plan_pr` and `apply`. This PR edits
   that file in both jobs; §3.3 makes the retry the mitigation for the two survivors, and nothing
   currently asserts it survived.
10. **AC10 — The apply path carries the `0 to change` assertion.** The same plan-JSON check as
    AC2 runs in the `apply` job against `/tmp/sentry-apply-plan.json` **before**
    `terraform apply`, and is not `[ack-destroy]`-reachable. Without it, "the thing reviewed is
    the thing that executes" is false: the apply re-plans, and its only gate is `destroy_count`,
    which the blanket ack greens by design.
11. **AC11 — `monitor_ids` resolves to the captured detector.** The resolved
    `data.sentry_project_issue_stream_monitor.web_platform.id` equals the `1213799` in the
    capture, in **both** jobs. A correlated rebind plans 27 updates with all four counters at 0
    (§2.6).
12. **AC12 — Guard Contract matrices green**, all three guards including harness rows, **and the
    new suite is registered in `scripts/test-all.sh`** — nothing under `tests/scripts/` is
    auto-discovered (every sibling is hand-registered; `:1043-1082`, `:1446-1459`). An
    unregistered suite is an orphan that reads as green.
13. **AC13 — `configure-sentry-alerts.sh` owns exactly one rule, and it is
    `auth-per-user-loop`.** A count of 1 pointing at the wrong rule does not satisfy this.
14. **AC14 — The PR body carries the recovery gesture and the caveats.** Specifically: re-run the
    failed job (the only working recovery — §2.5); revert is forbidden; a clean plan is **not**
    evidence the deprecation lifted; two resources still read the deprecated path; and the
    brownout-deadlock case (§3.3).

### Post-merge

15. **AC15 — Full-root plan no-op**, no 410s, all four types present.
16. **AC16 — Destroy guard on the real plan JSON:** `resource_deletes=0`, `resource_creates=0`,
    `nested_deletes=0`, `resource_forgets=0`; type-scope guard passes with `SENTRY_STATE_TYPES`
    injected from the plan's own types (`.tf UNION state`).
17. **AC17 — 27 adopted, 2 remain**, and **no orphan**: `terraform state list` shows 27
    `sentry_alert.` and 2 `sentry_issue_alert.`. A partial apply leaves fewer, and this is the
    assertion that fails loudly on it rather than on the next unrelated push.
18. **AC18 — No legacy fallthrough.** `legacy_trigger_conditions` empty for all 27 in state.
19. **AC19 — Live fidelity for all 27**, via the §2.9 probe against the committed capture — not
    against state or the `.tf`, both of which the apply rewrote. This generalises what an earlier
    revision asserted for 11 frequency rules and one Art. 33 rule: **12 lifecycle-triggered rules
    had no post-apply read-back of any kind**, so a rewritten tag key or dropped email action
    would have left them present, enabled, green, and paging nobody.
20. **AC20 — Art. 33 semantic fidelity.** `byok-art-33-breach` live shows both tag filters
    (`feature`/`byok-delegations`, `art_33_breach`/`true`), all three lifecycle triggers,
    action-filter logic `all`, issue-owners **and** `fallthrough_type` `ActiveMembers`, and
    `frequency_minutes == 5` — all compared against the capture.
21. **AC21 — `assert-byok-rules-exist.sh`** lists all four `EXPECTED_RULES`, ENABLED.
22. **AC22 — The §2.9 probe is live and scheduled**, and opens an issue on divergence.

### Phase 11 precondition (follow-up PR)

23. **AC23 — Before the cleanup PR that removes the `import{}`/`removed{}` blocks:**
    `terraform state list | grep -c '^sentry_alert\.'` on `main` is **27**. If a partial apply
    left any address un-imported, removing its `import{}` turns it into a planned **create** of a
    live-colliding rule. AC15-AC22 must have passed on `main` — **not** the pre-merge criteria an
    earlier revision named here, which cannot "pass on main" at all.

---

## Guard Contract

Three guards. Five were proposed; two are in the [Cut List](#cut-list) — one could not reach state
from the surface it was routed to, the other guarded a write `0 to change` guarantees will not
happen.

### Guard A — no unexplained CREATE reaches the apply, and `sentry_issue_alert` creates halt unconditionally

**Property.** (i) The `apply` job never performs a pure create it cannot explain from the merge
diff — today it performs *no* create check at all. (ii) No run ever creates a
`sentry_issue_alert` again, and no ack waves that through.

**Assembly.** Every `.resource_changes[]` entry whose `actions` contain `"create"`, in **both**
`plan_pr` and `apply`. Both, because `sentry-create-gate.sh` is invoked exactly once —
`apply-sentry-infra.yml:409`, inside `plan_pr` — and `apply` computes `$resource_creates` at
`:799` and **never reads it**.

**The scope correction is the point.** **Dropping an `import{}` block produces a `sentry_alert`
create, not a `sentry_issue_alert` create**, because the config block is present with nothing in
state behind it. An earlier revision scoped this guard to `sentry_issue_alert` only — protecting
the direction that cannot happen from this mechanism, and greening the one that can, with its own
matrix row saying so. So (i) ports the diff-matched gate into `apply`, covering `sentry_alert`,
`sentry_cron_monitor` and `sentry_uptime_monitor` while keeping add-a-monitor silent; (ii) sits on
top as the narrow un-ackable statement, modelled on `apex_move_orphans`.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | `["create"]` on `sentry_issue_alert` | RED, naming the address |
| 2 | Same, plus `[ack-destroy]` in the commit message | **RED** — the ack must not reach this tripwire |
| 3 | `["create"]` on `sentry_alert` with **no** matching `+resource` line in the merge diff | RED — the case a dropped `import{}` produces |
| 4 | `["create"]` on `sentry_alert` **with** a matching `+resource` line | GREEN — adding a new alert stays a normal, silent flow |
| 5 | `["create","delete"]` (a `create_before_destroy` replace) on `sentry_issue_alert` | RED — assemble on `index("create")`, not exact array equality; the ordering is not fixed |
| 6 | Zero resource changes | RED — vacuity floor on the guard's own dispatch |
| 7 | `["update"]` on `sentry_issue_alert` | GREEN — the two survivors still get updated |
| 8 | Invocation deleted from **`plan_pr` only** | RED |
| 9 | Invocation deleted from **`apply` only** | RED — rows 1-7 run against one fixture, so a single invocation would otherwise satisfy the matrix while reproducing the very asymmetry this guard closes |
| 10 | Tripwire placed **after** `terraform apply` | RED — by then the resource exists; it must run on the plan artifact with the apply gated on its exit |

**Harness rows.** (a) Delete the assertion body, keep the `pass` accounting → the suite must RED,
not report `0 passed, 0 failed` and exit 0. (b) A must-PASS fixture with three unrelated
diff-matched creates across two other types must pass.

### Guard B — the forget↔import bijection

**Property.** Every address leaving Terraform's management in this plan is re-adopted by exactly
one import, and every import corresponds to exactly one forget. No live paging rule is orphaned.

**Assembly.** Two sets from the same plan document: `{ addresses | .change.actions == ["forget"] }`
and `{ addresses | .change.importing.id != null }`, related by the name mapping. One chokepoint,
so neither set can be assembled from a stale list.

This is the guard whose absence let a one-line edit pass everything else: drop one `import{}` and
the remaining 26 addresses are each individually well-formed, so every per-address check finds
nothing wrong. Only the **pairing** is violated.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove one `import{}`, keep its `removed{}` (27 forgets, 26 imports) | RED, **naming the unpaired address** |
| 2 | Remove one `removed{}`, keep its `import{}` | RED, naming the unpaired address |
| 3 | Equal counts, mismatched membership — forget `X`, import `Y` | RED. Cardinality alone passes; membership is the property |
| 4 | The **second** pair is broken, the first intact | RED — stopping at the first member is itself the failure class |
| 5 | Zero forgets **and** zero imports | RED — vacuity floor; an empty plan trivially satisfies set equality |
| 6 | 27 matched pairs | GREEN |

**Harness rows.** (a) Replace the address extractor with one returning a constant pair → RED.
(b) A must-PASS fixture with **3** matched pairs rather than 27 must pass — varying cardinality,
not content, is what catches a hardcoded 27.

### Guard C — `forget` counted for every type, separately from `delete`, and fed into the gate

**Property.** No resource of any Sentry type leaves Terraform's management without tripping the
destroy gate.

**Assembly.** Every `.resource_changes[]` entry whose `actions` contain `forget`, across **all**
types in `.tf UNION state`. The dispatch chain is three layers and the property is only true if
all three move: the jq filter's top-level object; `scripts/sentry-destroy-counts.sh` (`:55`
validation, `:66` sum); and the gate at `apply-sentry-infra.yml:808` branching on
`$destroy_count`. A fourth copy of the same arithmetic lives in
`test-destroy-guard-counter-sentry.sh`'s `_run_gate` and must move with them.

**Mutation matrix.** Expectations are stated at the **gate's verdict** (exit status), not the
counter's output — a matrix asserting one layer above the deciding layer is green by construction.

| # | Mutation | Expected |
|---|---|---|
| 1 | `["forget"]` on `sentry_cron_monitor`, through the gate | **Gate exits non-zero.** Asserting only `resource_forgets = 1` would pass while the gate printed `PASS (plan destroys nothing)` |
| 2 | `["forget"]` on `sentry_uptime_monitor` | Gate exits non-zero |
| 3 | `["forget"]` on `sentry_issue_alert` | Counted in `resource_forgets` **and** `nested_deletes`, `resource_deletes` stays **0** — the AC4 discrimination |
| 4 | `resource_forgets` implemented but **not summed into `destroy_count`** | RED — the mutation that would otherwise leave the hole open and certified closed |
| 5 | `forget` folded into `resource_deletes` | RED — AC4 becomes unsatisfiable |
| 6 | Zero resource changes | `resource_forgets = 0`, gate exits 0, and the script still emits all **five** keys — a missing key breaks the caller's `eval` and reads as 0 |
| 7 | The address-display jq left at `["delete"]`-only on a forget-only plan | RED — per R6 the operator message would claim N destructive changes and list nothing |

**Harness rows.** (a) Remove the `resource_forgets` assertion, keep the `pass` count → RED.
(b) A must-PASS plan with two `["update"]` rows and no forgets yields `resource_forgets = 0`.

**Instrument note, all three guards.** Mutations land in files of 27 near-identical blocks — the
canonical shape where a file-wide `sed` without `/g` rewrites only the *first*. Every "second
member" row is therefore the row most likely to be silently applied to the first and go RED for
the wrong reason. Scope each mutation to its target's line range, assert its placement, and
require the RED message to **name** the offending address in every such row.

---

## Observability

`SOLEUR_*` is a host-journald convention — every source in
`apps/web-platform/infra/vector.toml` is a `journald`/`host_metrics` source scoped to the Hetzner
host's `SYSLOG_IDENTIFIER` — and these markers are emitted on a GitHub runner whose stdout no
Vector source ships.

```yaml
liveness_signal:
  what: "the scheduled drift probe (2.9) diffs all 27 live rules against the committed capture and finds no divergence"
  cadence: "daily, via the Inngest cron -> workflow_dispatch route (ADR-033)"
  alert_target: "opens/updates a GitHub issue on divergence, the scheduled-terraform-drift.yml pattern"
  configured_in: "the new scheduled drift workflow; scripts/sentry-alert-live-fidelity.sh"

error_reporting:
  destination: "GitHub issue opened by the drift probe; workflow-run log and ::error:: annotations on apply-sentry-infra.yml"
  fail_loud: true

failure_modes:
  - mode: "A migrated rule goes dark weeks later — exists, plans clean, matches nothing"
    detection: "the 2.9 scheduled probe: deletion, enabled:false, name drift, changed comparison value/interval, changed tagged_event, logicType flip, monitor_ids unbind — for all 27, not the 4 in EXPECTED_RULES"
    alert_route: "GitHub issue opened/updated by the probe"
  - mode: "A live paging rule orphaned by a dropped import{} block, or by a partial apply"
    detection: "Guard B on the PR plan JSON; AC17 on state post-merge"
    alert_route: "reds plan_pr before merge; reds the post-merge verification"
  - mode: "An authored attribute diverges from live"
    detection: "AC2 on plan_pr AND AC10 on the apply path — the apply re-plans, so the PR-side check alone does not cover the merge window"
    alert_route: "reds plan_pr; halts the apply before terraform apply"
  - mode: "A correlated monitor_ids rebind unbinds all 27 at once"
    detection: "AC11 — all four destroy counters read 0 for this shape, so no existing gate sees it"
    alert_route: "reds both jobs"
  - mode: "A frequency threshold destroyed by a legacy round-trip"
    detection: "AC18 on state; AC19 against the committed capture post-apply. terraform plan cannot see this class"
    alert_route: "reds post-merge verification; the 2.9 probe catches it on the next run"
  - mode: "A duplicate live paging rule created through the deprecated write path"
    detection: "Guard A, in both plan_pr and apply"
    alert_route: "plan_pr: red required check. apply: red run PLUS an if:failure() issue-open step — the apply arm has no operator route today and must not keep that posture for this mode"
  - mode: "A resource dropped from management via removed{} on a clause-less type"
    detection: "Guard C — resource_forgets, counted for every type and summed into destroy_count"
    alert_route: "the gate exits non-zero"
  - mode: "Brownout wider than the retry budget"
    detection: "outcome=exhausted marker; scripts/followthroughs/sentry-brownout-frequency-7650.sh exits 1 iff exhausted > 0"
    alert_route: "the follow-through sweeper marks FAIL and comments on #7650"

logs:
  where: "GitHub Actions run logs for apply-sentry-infra.yml and the scheduled drift workflow, via gh run view --log"
  retention: "GitHub's default Actions log retention"

discoverability_test:
  command: "bash scripts/sentry-destroy-counts.sh tests/scripts/fixtures/tfplan-sentry-forget.json"
  expected_output: "resource_deletes=0 / resource_creates=0 / nested_deletes=4 / resource_forgets=1 / destroy_count=5, exit 0"
```

**No `credentials_required`.** An earlier revision pointed this at the brownout meter, which needs
`GH_TOKEN` and verifies a **pre-existing** signal this PR makes less relevant (29/29 → 2/29) while
touching none of the failure modes above. A credentialed waiver taken where an unauthenticated
substitute verifies the same property is what the waiver rule rejects. The probe above is
credential-free, network-free, runs on a committed fixture, and exercises this plan's own new
signal — Guard C's counter and the gate arithmetic.

**Layer citation.** **Layer 6** — the workflow-run log plus `::error::` annotations, consumed
synchronously on the PR by `plan_pr` and asynchronously by the drift probe's issue. Explicitly
**not layers 1-5**: no Vector source ships GitHub-runner stdout (all sources are host
`journald`/`host_metrics`). Not layer 7: nothing runs on a customer machine. An earlier revision
called this "layer-less", which overshot — a run log with an `::error::` annotation *is* layer 6.

### Soak follow-through enrollment

```
<!-- soleur:followthrough script=scripts/followthroughs/sentry-brownout-frequency-7650.sh earliest=<merge+7d> secrets=GH_TOKEN -->
```

`GH_TOKEN` is already exported by `scheduled-followthrough-sweeper.yml`, so no workflow edit is
required — but the directive must name it, because the sweeper's `env -i` sandbox passes through
only what the directive declares.

**Two corrections to fold in while editing that script.** It requests
`--json databaseId,conclusion,createdAt` and consumes **only `databaseId`** — so a run of
`apply-sentry-infra.yml` that fails on Guard A, the ack gate, or `terraform apply` yields
`exhausted=0` → exit 0 → the sweeper posts PASS and can auto-close #7650. Either read the
`conclusion` it already fetches, or stop describing it as metering the workflow's liveness. And
its `--limit 40` window is run-count-based with no time bound on a `paths:`-filtered workflow, so
it can span a year; bound it on the `createdAt` it also already fetches.

---

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/sentry/issue-alerts.tf` | 27 `sentry_issue_alert` deleted; 27 `sentry_alert` added; 27 `import {}` + 27 `removed { lifecycle { destroy = false } }`; 2 untouched; the issue-stream data source |

No new provider, no version bump, no new variable — **no `TF_VAR_*` to provision**, so
`hr-tf-variable-no-operator-mint-default` does not engage. Sensitive inputs unchanged:
`SENTRY_IAC_AUTH_TOKEN` (repo secret, injected as `SENTRY_AUTH_TOKEN`) and the R2 backend keys
from Doppler `soleur/prd_terraform` — a **different** config, without which `terraform init` fails
with an EC2 IMDS error.

### Apply path

**(a) — config-only, applied by the existing merge-triggered full-root apply.** No dispatch, no
CLI state surgery, no host, no SSH, no dashboard step.

Blast radius: 27 live paging rules. **No Sentry-side write occurs for them during this apply** —
`removed{}` does not refresh and does not delete (R1); `import{}` is a read. Downtime: none.

### Distinctness / drift safeguards

- `ignore_changes = [environment]` on all 27 and nothing else.
- Guards A, B, C close the create, orphan and forget directions.
- AC10 closes the apply-side fidelity gap; AC11 closes the correlated-rebind gap.
- **One apply path means exactly one writer** against an unlocked R2 object.
- **Residual, pre-existing, not closed here:** the `apply` job's `if:` still admits
  `workflow_dispatch` on any ref while `concurrency.group` is keyed by `github.ref`. This PR does
  not use that path; file a follow-up to restrict the job to `refs/heads/main`.
- **Concurrent readers:** another open Sentry PR's `plan_pr` runs in a different concurrency group
  and can read the R2 object mid-mutation, producing meaningless counts. A false-gate risk, not
  data loss.
- **Import-id freshness:** `plan_pr` reads live ids at PR time; `apply` re-plans at merge time. A
  rule deleted-and-recreated in between gets a new id. A **stale** id fails the import loudly; a
  **reused** id succeeds and shows changes — which is why AC10 exists. Recovery is regenerate the
  capture and re-derive the ids.
- **Sentry token `workflows/` write scope** is exercised for the first time by the first Update
  after adoption. Verify it as a preflight rather than discovering it mid-apply.
- **`plan_pr`'s `timeout-minutes: 15`** was never re-derived against a plan carrying 27 live
  import reads plus up to 210 s of retry sleep. Measure it.

### Vendor-tier reality check

No tier gate. `sentry_alert` is generally available — the 30 objects already exist and are being
adopted.

---

## Encryption Posture

```yaml
at_rest:
  - store: "Terraform state — R2 bucket soleur-terraform-state, key web-platform/sentry/terraform.tfstate"
    mechanism: "Cloudflare R2 server-side encryption (AES-256), provider-managed keys"
    evidence: "apps/web-platform/infra/sentry/main.tf backend block; pre-existing store, unchanged"
    defends_against: "offline disclosure of the object store's physical media"
    does_not_defend: "anyone holding the AWS key pair in Doppler soleur/prd_terraform reads the state in cleartext; R2 provider-side compromise; object VERSIONING is unverified (2.5), so point-in-time recovery is not established"
    disclosed_as: "not user data — alert routing configuration; out of scope for PA-8's disclosure surface"
    live_verification: "the list-object-versions probe in 2.5"
  - store: "the terraform state pull forensics artifact (2.5) — NEW egress surface introduced here"
    mechanism: "GitHub Actions artifact storage, encrypted at rest by GitHub"
    evidence: "the artifact-upload steps added in 2.5"
    defends_against: "loss of the pre- and post-apply state for incident diffing"
    does_not_defend: "it takes the WHOLE root's state out from behind the R2 credential boundary into storage readable by anyone with repo read, and carries every resource in the root — cron monitors, uptime monitors and their assertion_json, org and project internals — not just the 27 alerts"
    disclosed_as: "internal infrastructure state; not a personal-data surface. Mitigated by an explicit short retention rather than the default"

in_transit:
  - connection: "Terraform provider -> Sentry API, https://${var.sentry_org}.sentry.io/api/"
    tls: "TLS 1.2+, Go stdlib defaults via the provider's HTTP client"
    cert_verification: "on"
    does_not_defend: "a compromised Sentry-side endpoint, or a token exfiltrated from the repo secret"
    disclosed_as: "Article 30 PA-8 — Functional Software GmbH, EU/DE region; unchanged"
  - connection: "Terraform backend -> Cloudflare R2 S3 endpoint"
    tls: "TLS 1.2+, AWS SDK defaults"
    cert_verification: "on"
    does_not_defend: "credential compromise in Doppler soleur/prd_terraform"
    disclosed_as: "internal infrastructure state; not a personal-data surface"
```

No `exception` block: no plaintext store, no disabled certificate verification.

---

## Downtime & Cutover

None of the three downtime trigger classes fires. The section is written anyway, because the
availability question this plan raises is **"does paging go dark during the cutover"**.

**It does not — with one stated proviso.** Every one of the 27 live objects is adopted, never
touched: `removed{}` does not refresh (R1) and does not call delete; `import{}` is a read. No
instant exists where a rule is deleted.

**The proviso, which an earlier revision stated unconditionally:** this holds *provided the
apply-time plan is `0 to change`*. If it is not, Terraform writes through
`resource_alert_impl.go:835`/`:740` and the rule's *definition* is replaced server-side — the
object stays live, its semantics do not. That proviso needed a gate, not a sentence: **AC10**.

There is also an instant where rules are live but **unmanaged** — a partially-persisted apply
between the forgets and the imports (R3). Not downtime; detected by AC17 and recovered by re-run.

**Zero-downtime is the default by construction.** No maintenance window, no residual downtime.

**The real availability risk is silent darkening** — a rule that stays "up" while matching
nothing. A fidelity failure, handled by AC2, AC10, Guard B, AC18-AC20, and §2.9.

**Network-outage gate (deepen-plan 4.5):** the keyword scan matches once, on "unreachable" in a
note about the provider registry being unreachable from the planning sandbox. Incidental prose,
not a connectivity symptom; and no resource in this root carries a `provisioner` or
`connection { type = "ssh" }` block. Gate evaluated, does not apply.

---

## User-Brand Impact

**If this lands broken, the user experiences one of two things, and an earlier revision named only
the first:**

**Silence.** A production error class that used to page — a BYOK cross-tenant key leak, a KB sync
failure, a boot-stage fatal on a host with no SSH — occurs, Sentry ingests it, and no email
arrives. No error page, no degraded screen, no symptom at all until the failure compounds into
something the user notices directly. Invisible by construction, which is why the guards detect
silence rather than errors and why §2.9 exists.

**Or its opposite: over-paging.** This plan's own Risks table calls 27 duplicate live paging rules
the worst case. #4781 records the mechanism as **measured**: the repo's learnings misclassified
"triggered by auth-callback-no-code-burst" as a coincidental red herring on **five** separate
occasions. Alert fatigue is the documented path by which a real breach page is discarded — on the
same channel that carries the Art. 33 page.

**If this leaks, the user's workflow is exposed via:** over-notification rather than disclosure.
The realistic shape is the #4781 recurrence — a rule whose filters blank out matches every issue
and emails full Sentry error context (PA-8 §(c): may incidentally include a pseudonymised
`user_id`, request paths and headers) to the `IssueOwners -> ActiveMembers` fallthrough. At N=1
seat that is noise; at N>1 it is over-disclosure to every seat, which `issue-alerts.tf:274-276`
documents as an accepted risk that must be revisited **before the first non-founder Sentry seat**.
That precondition is currently ungated, and this PR re-authors all 27 recipient blocks — the
cheapest moment that will ever exist to revisit it. Secondarily, the `state pull` artifact widens
who can read the root's state (see Encryption Posture).

**Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true`;
`user-impact-reviewer` is invoked at review time.

The threshold is not ceremony. `byok-art-33-breach` is the rule Article 30 PA-8 §(b)(ii) names as
the **anchor of the GDPR Art. 33 72-hour breach-notification clock**. If it stops firing,
awareness is never constructively established, the clock never starts, and the exposure is not
"72 hours late" — it is unbounded, plus an Art. 5(2) accountability failure because the register
asserts a control that was not operating.

**Two peers deserve the same treatment and an earlier revision gave them none:**
`workspaces-luks-drift` and `git-data-boot-fatal` (`stage=luks_open`) page on **at-rest encryption
failing over identifiable user data**, on a host with deny-all ingress, no SSH, no console and no
log shipper — by construction the only trace. Neither is in `EXPECTED_RULES`. AC19 now covers all
27 rather than leaving them to the generic gate.

---

## Domain Review

**Domains relevant:** engineering, legal.

### Engineering

**Status:** reviewed
**Assessment:** the migration adopts objects that already exist, so fidelity risk is lower than a
re-creation — but the *mechanism* is the design, and the mechanism originally supplied was not
implementable (R2). Folded in: the apply job has no create gate and the tripwire was scoped to the
wrong type (Guard A); nothing asserted the forget↔import pairing (Guard B); a `forget` on a
clause-less type is counted by nothing and a counter that does not feed `destroy_count` is a
report rather than a gate (Guard C); **the apply re-plans, so the fidelity assertion had to move
onto the apply path (AC10)**; a correlated `monitor_ids` rebind is invisible to all four counters
(AC11); the apply is not atomic and the property is idempotent roll-forward (R3); and revert and
state-restore are both traps rather than recovery paths (§2.5).

### Legal

**Status:** reviewed
**Assessment:** legally **neutral in substance, load-bearing in mechanism**.

- **No Article 30 register edit.** PA-8 names no Terraform resource type; its closest text is the
  class-level *"Sentry monitor classes processed (post-2026 split): issue alerts … and cron
  monitor check-ins"*, and a `sentry_alert` still produces an issue alert. No maintenance trigger
  fires. Same for `docs/legal/privacy-policy.md`, `data-protection-disclosure.md` and
  `gdpr-policy.md` — **no canonical edit, so no mirror edit, so none of the five
  `docs/legal/**` CI gates engage.** Stated plainly rather than manufacturing a reason to edit.
- **One CRITICAL condition, folded in as AC6/AC20.** `assert-byok-rules-exist.sh` asserts
  existence-and-enabled, **not** filter shape, justified by Terraform owning the filters so drift
  self-heals on the next apply. That is the entire compensating control for filter drift on the
  Art. 33 rule, and it survives only if the replacement block declares its attributes populated
  with `ignore_changes = [environment]` alone. **If `byok-art-33-breach` cannot land that way, it
  must not be migrated at all.** The silent direction is the dangerous one. §2.9 is what finally
  makes it detectable — and note the self-healing argument requires an apply to *occur*, which a
  `paths:`-filtered workflow does not guarantee.
- **The #4781 drift has a real compliance angle** — Art. 32(1)(d) control-effectiveness, measured
  across five misclassifications, on the channel that carries the Art. 33 page.
- **Documentation currency (Art. 5(2)):** the v0.15.5 spec carries a dated banner; the
  `sentry-monitors-audit.sh:1312` prose is a code comment, corrected in §2.8 rather than inflated.
- No Art. 33 or Art. 34 notification is warranted; no DPA action; no recipient update.

*Draft compliance analysis, not legal advice.*

### Product/UX Gate

Not applicable. The mechanical UI-surface override does not fire. Product assessed **NONE**.

---

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` returned **63** issues. Each planned
path was matched against every issue body with a standalone `jq --arg` containment test. **None.**

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| An authored attribute diverges from live at **merge** time, after the PR plan. | **AC10** — the `0 to change` assertion on the apply path. The largest hole the review round found. |
| An authored attribute diverges pre-merge. | AC2 on a credentialed `plan_pr`; AC8 authored from the committed capture. |
| A dropped `import{}` orphans a live paging rule while every per-address check stays green. | **Guard B** — bijection, membership not cardinality. |
| A partial apply leaves N rules managed by nothing. | R3 roll-forward, measured. **Re-run the failed job** — the only working gesture (§2.5). AC17 fails loudly on the orphan. The blocks stay in config until AC15-AC22 pass (AC23). |
| A correlated `monitor_ids` rebind unbinds all 27 with every counter at 0. | **AC11**, in both jobs. |
| 27 duplicate live paging rules through the deprecated write path. | **Guard A**, correctly scoped to `sentry_alert` creates too, with the un-ackable `sentry_issue_alert` tripwire on top. |
| A `forget` on a clause-less type slips the gate. | **Guard C**, with `resource_forgets` summed into `destroy_count`. |
| A blanket `[ack-destroy]` waves through an unintended delete — and per R6 the gate shows nothing. | AC4 pairs it with `resource_deletes == 0`; Guard B proves the 27 leaving are the 27 returning; §2.4 widens the display jq. |
| A merge-commit merge greens the PR and reds the apply. | **AC5** asserts the merge method. |
| A migrated rule goes dark weeks later. | **§2.9** — the only ongoing detector, all 27 rather than 4. |
| Revert or state-restore taken as the recovery path. | §2.5 names both as traps; AC14 puts the real gesture in the PR body. |
| `configure-sentry-alerts.sh` runs afterwards and rewrites live 61→60 / 62→60. | §2.2; AC13 asserts one stanza remains and that it is the right one. |
| The provider's hardcoded `any-short` ORs a future multi-condition trigger group. | ADR amendment plus the inline comment at the authoring site. Inert for all 27 today — measured. |
| The retry is edited away while this PR touches both jobs. | **AC9** — byte-unchanged. |
| A brownout blocks this PR indefinitely. | §3.3 — narrow, because `removed{}` already cuts this PR's own exposure to 2/29; named in the PR body so it is recognised. |
| A clean plan read as evidence the deprecation lifted. | AC14. |

---

## Sharp edges

- **A clean plan is not evidence of vendor state.** Equally consistent with "it worked" and "this
  ran outside a brownout window".
- **Read the provider source at the tag, not the changelog.** A changelog-sourced claim closed
  #4610 on a false premise and cost four months; the shape recurred twice more inside #7650.
- **Read Terraform's own behaviour from a measurement, not from prose.** Seven premises here were
  confidently stated, load-bearing and false (R1-R7) — and **three were in this plan's own
  acceptance criteria**: the summary literal, the `importing` JSON path, and a file-level enum
  grep that fails on a correct migration.
- **`plan_pr` is not the plan that executes.** The apply re-plans. Any assertion that matters must
  exist on both paths.
- **The destroy gate cannot see an update**, and for a forget-only plan it **prints nothing** —
  its address jq selects `["delete"]`.
- **`0 to change` covers every attribute the schema carries — not every attribute.**
- **`[ack-destroy]` names no address set**, must be paired with `resource_deletes == 0`, and must
  sit in a commit **BODY**, never a subject.
- **`workflow_dispatch` has no `head_commit.message`**, so it can never carry the ack.
- **A counter that does not feed `destroy_count` is a report, not a gate.**
- **Revert and state-restore both compute destroys of live paging rules through the deprecated
  write path.** Recovery is roll-forward.
- **`scripts/test-all.sh` discovers nothing under `tests/scripts/`.** Every suite is
  hand-registered; an unregistered suite is an orphan that reads as green.
- **`ignore_changes` inverts ownership and the file holds two disjoint sets.** Three of the four
  `auth-*` blocks change sets here.
- **The retry has a shelf life.** When the family is fully retired it exhausts and fails, which is
  correct. Raising the attempt count is not a response to that.

---

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **`import {}` + `removed { lifecycle { destroy = false } }` on the branch** | **ADOPTED.** No divergence window, one writer against an unlocked object, `plan_pr` is a credentialed rehearsal, recovery is idempotent roll-forward (R3). |
| **One-time `workflow_dispatch` running `state rm` + `import`** | **REJECTED — not implementable, and unsafe where it was.** `import` requires the config block (R2); against the feature ref it reintroduces the window; worst case is 27 duplicate live rules created **ungated**. |
| **`removed {}` as previously assessed ("DOA")** | **Wrong** (R1), measured. It is the one construct guaranteed never to touch the deprecated endpoint. |
| **`terraform state mv` between the two types** | **Structurally impossible** — the schemas share only `name`/`organization`/`id` (`issue-alerts.tf:27-28`). |
| **State restore, or PR revert, as rollback** | **REJECTED as actively harmful** — both compute destroys or duplicate creates through the deprecated write path (§2.5). |
| **Migrate only the 16 lifecycle rules** | **Superseded.** Rested on frequency triggers being unexpressible — true at `v0.15.5`, false at `v0.15.7`. |
| **Migrate all 29, restructuring the two `event_unique_user_frequency_count` rules as action filters** | **Rejected, not deferred.** An action filter only narrows something a trigger started, and none of the five trigger types means "every event". |
| **Add the Sentry root to `scheduled-terraform-drift.yml`'s matrix** for ongoing detection | **Rejected.** It would plan the full root, still refreshing the two survivors through the deprecated endpoint, with none of the brownout retry — red on Sentry's calendar rather than on drift. §2.9's API diff instead. |
| **Delete `configure-sentry-alerts.sh`** | **Rejected.** It remains the definition for `auth-per-user-loop`. |
| **Bump past `v0.15.7`** | **Not available.** |

---

## Test Scenarios

The executable view — command, expected output, and which surface runs it. Guard matrices are in
the Guard Contract; anything that merely restates an AC is dropped.

| # | Surface | Command | Expected |
|---|---|---|---|
| 1 | local | the scope derivation `jq` | exactly 27 rows |
| 2 | local | the comparison-shape `jq` | `44` boolean / `13` `interval,value`; zero bare-boolean `event_frequency_count` |
| 3 | local | a block walker anchored on `/^resource "sentry_alert"/` | `[environment]` for all 27; and zero `IssueOwners`/`"EQUAL"`/`"IS_IN"` **within those blocks** (49/50 remain file-wide, correctly) |
| 4 | local | `terraform validate` on the authored root **plus a deliberately conflicting fixture** | valid config passes; a block declaring two of the five trigger types **fails** — without the negative arm this is a syntax check, not an `ExactlyOneOf` check |
| 5 | PR | the AC2 plan-JSON check | zero non-`no-op`/non-`forget` rows; 27 forgets; 27 `.change.importing.id`; ids match the capture |
| 6 | PR | Guard B's bijection check | set equality; RED names the unpaired address |
| 7 | PR | `scripts/sentry-destroy-counts.sh` on the PR plan JSON | `resource_deletes=0`, `resource_creates=0`, `resource_forgets=27` |
| 8 | PR | the AC11 monitor-id equality check | resolves to `1213799` |
| 9 | PR | `bash tests/scripts/test-sentry-alert-adoption-guards.sh` **via `scripts/test-all.sh`** | registered and green — an unregistered suite is an orphan |
| 10 | PR | `test-destroy-guard-counter-sentry.sh` | green after `:174`/`:191` become per-field assertions |
| 11 | PR | `test-sentry-destroy-counts.sh` | green after T3 (`:71`) moves to the three-term `destroy_count` |
| 12 | PR | `test-destroy-guard-regex-parity.sh` | still exactly **7** pinned sites — asserted by count, not prose |
| 13 | PR | `grep -c 'upsert_rule ' configure-sentry-alerts.sh` **and** confirm the survivor | 1, and it is `auth-per-user-loop` |
| 14 | PR | `git diff` on the retry blocks in both jobs | byte-unchanged (AC9) |
| 15 | PR | `c4-code-syntax.test.ts`, `c4-render.test.ts` | green after the `model.c4:619` edit |
| 16 | apply | the AC10 plan-JSON check, **before** `terraform apply` | zero `["update"]` rows on `sentry_alert` |
| 17 | post-apply | full-root plan | `0 to add, 0 to change, 0 to destroy`, no 410s, all four types |
| 18 | post-apply | `terraform state list` | 27 + 2, no orphan |
| 19 | post-apply | the §2.9 probe against the capture | all 27 match, incl. `byok-art-33-breach` field-by-field |
| 20 | scheduled | the §2.9 probe | no divergence; opens an issue if there is |

---

## Files to Edit

| Path | Why |
|---|---|
| `apps/web-platform/infra/sentry/issue-alerts.tf` | 27 blocks re-authored; 27 `import{}` + 27 `removed{}`; the data source; the inline trigger-logic comment |
| `apps/web-platform/infra/sentry/README.md` | adoption-path prose and the mechanism |
| `.github/workflows/apply-sentry-infra.yml` | Guard A in both jobs; **AC10's apply-side `0 to change`**; AC11's monitor-id check in both jobs; the `if: failure()` issue-open step on the apply arm; the `state pull` forensics artifacts; the destroy-gate message (`:809`) and the address jq (`:419`) |
| `apps/web-platform/scripts/configure-sentry-alerts.sh` | delete the three burst stanzas; rewrite the header |
| `apps/web-platform/scripts/assert-byok-rules-exist.sh` | the `:33-43` paragraph — auth-\* set four → one. **Do not weaken it** |
| `apps/web-platform/scripts/sentry-monitors-audit.sh` | stale adoption-count comment at `:1312` |
| `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` | docstring names the wrong count and owner |
| `scripts/followthroughs/sentry-brownout-frequency-7650.sh` | stale `25 + 4`; read the `conclusion` it already fetches; bound the window on `createdAt` |
| `scripts/sentry-destroy-counts.sh` | validate the fourth counter; add it to `destroy_count` |
| `scripts/test-all.sh` | **register the new suite** — nothing under `tests/scripts/` is auto-discovered |
| `tests/scripts/lib/destroy-guard-filter-sentry.jq` | add `resource_forgets`; do **not** merge `forget` into `resource_deletes` |
| `tests/scripts/test-destroy-guard-counter-sentry.sh` | Guard C fixtures; convert the whole-object literals at `:174`/`:191`; reconcile `_run_gate`'s hand-rolled `dcount` |
| `tests/scripts/test-sentry-destroy-counts.sh` | T3 (`:71`) — the three-term `destroy_count` |
| `tests/scripts/test-sentry-create-gate.sh` | `sentry_alert` fixtures for Guard A |
| `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` | header prose lags the code |
| `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` | dated amendment |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | falsified `sentry -> founder` edge at `:619` |
| `knowledge-base/project/learnings/2026-08-19-i-proposed-deleting-a-control-because-terraform-appeared-to-own-it.md` | ownership table |

## Files to Create

| Path | Why |
|---|---|
| `tests/scripts/test-sentry-alert-adoption-guards.sh` | Guards A and B, matrices and harness rows |
| `scripts/sentry-alert-live-fidelity.sh` | the §2.9 drift probe — diffs live `workflows/` against the capture. Serves AC19/AC20 |
| `.github/workflows/scheduled-sentry-alert-drift.yml` | schedules the probe per ADR-033, opening/updating an issue on drift |
| `tests/scripts/fixtures/tfplan-sentry-forget.json` | the credential-free fixture the `discoverability_test` runs against |
| `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-<date>.json` | the capture the 27 blocks are authored from and the probe's baseline (AC8) |
| `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-v0157-frequency-trigger-landed-scope-is-27.md` | **already created** |
| `knowledge-base/project/specs/feat-one-shot-7650-phase2-sentry-alert-import/tasks.md` | task breakdown |

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-031-sentry-as-iac.md` with `**Amendment (2026-09-04, #7650)**`, continuing its
2026-07-17 / 2026-08-19 chain:

- The deferral in §Amendment 2026-07-17 is **executed for 27 of 29**.
- **The ownership model changes for 27 live paging rules**; `configure-sentry-alerts.sh` is
  retained for `auth-per-user-loop` alone — a standing **AP-001** deviation shrunk 4→1 (§2.7).
- **`forget` enters the destroy gate's plan vocabulary**, and `destroy_count` gains a third term
  — a behavioural change applying to every future `removed{}` in this root.
- The provider's **hardcoded `any-short` trigger group** as a standing constraint, with citations.
- The residue: `auth-per-user-loop` becomes unwritable once `rules/` is retired.

**Also worth a short standalone ADR, cross-referenced:** the *mechanism* — config-block adoption,
including "the blocks stay in config until verification passes, then a follow-up PR removes them",
which is the sequencing that makes roll-forward work (R3). The repo now holds **two competing
adoption patterns with nothing adjudicating between them**: CLI per-address idempotent import at
`apply-github-infra.yml:242-305` versus config blocks here.

### C4 views

Read against all three of `model.c4`, `views.c4`, `spec.c4`. **External human actors:** `founder`,
unchanged. **External systems:** `sentry` (`model.c4:316-318`) — no new vendor, endpoint or
residency; `betterstack` untouched. **Containers/data stores:** none added or removed.
**Actor↔surface relationships:** the `sentry -> founder` edge persists with identical semantics.

No element or relationship is added, so `views.c4` needs no `include` change. **One description is
falsified:** `model.c4:619` says *"Issue alerts route `actions_v2` notify_email -> target_type
IssueOwners … 28 of the 29 IaC rules"*. After this lands, 27 of 29 route via `sentry_alert`'s
`action_filters[].actions[].email` with `target_type = "issue_owners"`; only 2 use `actions_v2`.
**Preserve** the `byok_cap_exceeded`/`NoOne` carve-out and the 30th-rule paragraph verbatim.

Run `c4-code-syntax.test.ts` and `c4-render.test.ts` after the edit.

### Sequencing

Nothing is soak-gated. The amendment and the C4 correction ship **in this PR**.

Refs #7650. Refs #7634. Refs #4781. Closes #7650.
