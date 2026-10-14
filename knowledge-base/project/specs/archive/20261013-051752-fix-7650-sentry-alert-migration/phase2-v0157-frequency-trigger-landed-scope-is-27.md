# Phase 2 re-measurement at provider `v0.15.7` — the frequency trigger landed, scope is 27

Measured 2026-09-04. Read-only against the live org and against the provider source at the
pinned tag. **This supersedes the scope of
[`phase2-provider-cannot-express-frequency-triggers.md`](./phase2-provider-cannot-express-frequency-triggers.md),
which was measured at `v0.15.5` and was correct then.**

Every provider claim below cites `path:line @ v0.15.7`. None is sourced from the CHANGELOG,
the release notes, or the registry docs page — that substitution is what closed #4610 on a
false premise and cost four months, and it recurred twice more inside #7650.

Tag identity, so the citations are re-checkable:

```
v0.15.7 = 364da9648577533c482c82d88a76ca63bca985f6, committed 2026-09-02 23:43:17 +0100
git ls-remote --tags https://github.com/jianyuan/terraform-provider-sentry.git | sort -V | tail -1
  => v0.15.7   (no newer tag exists)
```

Upstream PR 943 merged 2026-09-01, i.e. **one day before** the tag was cut. Its code is in the
tag's tree, verified directly rather than by ancestry argument.

---

## 1. What changed between `v0.15.5` and `v0.15.7`

`trigger_conditions` expresses **five** types now, not four.
`internal/provider/resource_alert_gen.go:92-162 @ v0.15.7`, nested attributes at :99, :108,
:117, :126, :135:

```go
99:  "first_seen_event":       schema.SingleNestedAttribute{  // Attributes: map[string]schema.Attribute{}
108: "issue_resolved_trigger": schema.SingleNestedAttribute{  // Attributes: map[string]schema.Attribute{}
117: "reappeared_event":       schema.SingleNestedAttribute{  // Attributes: map[string]schema.Attribute{}
126: "regression_event":       schema.SingleNestedAttribute{  // Attributes: map[string]schema.Attribute{}
135: "event_frequency_count":  schema.SingleNestedAttribute{  // {value, interval}
```

Each `ConflictsWith` the other four — exactly-one-of per list element.

The trigger-side `event_frequency_count` carries two required fields and **no `filters`**
(`resource_alert_gen.go:142-162 @ v0.15.7`):

| field | type | constraint |
|---|---|---|
| `value` | int64 | required, `int64validator.AtLeast(0)` |
| `interval` | string | required, enum `1m` `5m` `15m` `1h` `1d` `1w` `30d` (`internal/sentrydata/sentrydata.go:1179-1187`) |

The action-filter-side `event_frequency_count` (`resource_alert_gen.go:380`) is a *different*
attribute that does have `filters`. Do not conflate them: the trigger read path raises a hard
diagnostic on any non-empty trigger `filters`
(`resource_alert_impl.go:768-776`, `"event_frequency_count filters are not supported"`).

`event_unique_user_frequency_count` is still **action-filter-only**
(`resource_alert_gen.go:318 @ v0.15.7`, nested under `action_filters[].conditions[]`). It
appears nowhere in the `trigger_conditions` block. Consistent with upstream issue 950 being
open.

---

## 2. The boolean-comparison trap is REAL and UNFIXED at v0.15.7

`resource_alert_impl.go:893-902 @ v0.15.7`:

```go
case "event_frequency_count":
    comparison, err := triggerCondition.Comparison.AsOrganizationWorkflowTriggerConditionComparison1()
    if err != nil {
        if _, boolErr := triggerCondition.Comparison.AsOrganizationWorkflowTriggerConditionComparison0(); boolErr == nil {
            legacyTriggerConditions = append(legacyTriggerConditions, triggerCondition.Type)
            continue
        }
        diags.AddError("Failed to parse event_frequency_count trigger condition", err.Error())
        return diags
    }
```

The discriminator is a try-unmarshal type probe, not a discriminator field
(`apiclient.gen.go:2203-2207`: `Comparison0 = bool`, `Comparison1 = map[string]interface{}`).
Routing, exactly:

| live `comparison` shape | destination | threshold |
|---|---|---|
| object `{"value":N,"interval":"..."}` | `trigger_conditions[].event_frequency_count` | **survives** |
| bare boolean `true` | `legacy_trigger_conditions` (List of String) | **unrecoverable** |
| neither | hard read error | n/a |
| any other trigger type, any shape | `legacy_trigger_conditions` via `default:` (`:913-915`) | n/a |

And the loss is **sticky**, because the write path reconstructs every legacy entry's
comparison as a hardcoded `true` (`resource_alert_impl.go:738-749 @ v0.15.7`):

```go
if err := comp.FromOrganizationWorkflowTriggerConditionComparison0(true); err != nil { ... }
outTriggerConditions = append(outTriggerConditions, apiclient.OrganizationWorkflowTriggerCondition{
    Type:            inLegacyTriggerCondition,
    Comparison:      comp,          // literally `true`
    ConditionResult: true,
})
```

So a bare-boolean `event_frequency_count` can never be promoted back to a real threshold by
this provider. **A clean `terraform plan` is fully compatible with this state** — the lost
value lives only server-side and never appears in the `.tf`, so there is no diff to count.
That is why §5 makes `legacy_trigger_conditions == []` a hard gate rather than an observation.

### Re-measured: none of ours is a bare boolean

```sh
jq -r '[.[] | .triggers.conditions[]
        | if (.comparison|type)=="object" then (.comparison|keys|join(","))
          else "SCALAR:\(.comparison|type)" end]
       | group_by(.) | map({k:.[0],n:length})' wf-all.json
# => [{"k":"SCALAR:boolean","n":44},{"k":"interval,value","n":13}]
```

All 44 boolean comparisons are lifecycle types (`first_seen_event` / `reappeared_event` /
`regression_event`, plus the two high-priority types on Sentry's own default), for which
boolean is the correct and only shape. All 13 object comparisons are the frequency types
(11 `event_frequency_count` + 2 `event_unique_user_frequency_count`), and every one carries
exactly the key set `{interval, value}` — **no `filters` key anywhere**, so the trigger read
path's filters rejection never fires for us.

---

## 3. Three schema facts the plan's earlier mapping got wrong

These are not nits; each one changes what gets authored.

**(a) There is no `project` attribute on `sentry_alert`.** Top-level attributes
(`resource_alert_gen.go @ v0.15.7`) are `id` :49, `organization` :57, `enabled` :65,
`name` :72, `environment` :77, `monitor_ids` :82, `frequency_minutes` :87,
`trigger_conditions` :92, `action_filters` :164, `legacy_trigger_conditions` :1188.
Targeting is via `monitor_ids` alone. The 29 existing `sentry_issue_alert` blocks each pass
`project = data.sentry_project.web_platform.slug`; that line disappears. The data source
itself stays — `cron-monitors.tf` references it 55 times and `uptime-monitors.tf` 4 times.

**(b) `frequency_minutes` is TOP-LEVEL and REQUIRED (int64), not nested under
`action_filters`.** The earlier mapping line "`actions_v2` + `frequency` ->
`action_filters[].actions` + `frequency_minutes`" is right about the actions and wrong about
where the frequency goes.

**(c) `action_filters` is REQUIRED with `listvalidator.SizeAtLeast(1)` (:164-172);
`trigger_conditions` is optional+computed (:92).** Every one of the 27 has exactly one
action filter, so (c) is satisfied — but it means `action_filters` cannot be omitted to
"author the trigger first".

Two enum corrections, both places where the `sentry_issue_alert` v2 vocabulary does **not**
carry over:

| attribute | `sentry_issue_alert` (v2) | `sentry_alert` @ v0.15.7 | source |
|---|---|---|---|
| email recipient | `target_type = "IssueOwners"` | `target_type = "issue_owners"` | `resource_alert_gen.go:773-779`, enum `["issue_owners","team","user"]` |
| tag match | `match = "EQUAL"` / `"IS_IN"` | `match = "eq"` / `"in"` | `resource_alert_gen.go:658-663` — plain required `StringAttribute`, **no enum validator** |

`fallthrough_type` is unchanged CamelCase — enum `["AllMembers","ActiveMembers","NoOne"]`
(`resource_alert_gen.go:788-800`), and is required only when `target_type = "issue_owners"`.

**The `tagged_event.match` row is the dangerous one.** It has no enum validator, so a carried-over
`"EQUAL"` passes `terraform validate`, passes `terraform plan` against a fresh config, and only
manifests as a live filter that matches nothing — a silently darkened paging rule. The live
values are lowercase `eq` (57 occurrences) and `in` (8), measured directly.

---

## 4. The undocumented one: the provider HARDCODES the trigger group's logic type

There is **no `logic_type` attribute anywhere under `trigger_conditions`** — the only
`logic_type` in the schema is `action_filters[].logic_type` (`resource_alert_gen.go:173`).
Both request builders pin the trigger group to `any-short`:

```
internal/provider/resource_alert_impl.go:803 @ v0.15.7   (create)
internal/provider/resource_alert_impl.go:835 @ v0.15.7   (update)
        Triggers: apiclient.OrganizationWorkflowTrigger{
            LogicType:  apiclient.OrganizationWorkflowTriggerLogicTypeAnyShort,
            Conditions: triggerConditions,
        },
```

The read path reads the trigger group (`:856`) but the model has no field to store its logic
type, so the live value is discarded on read and overwritten on write.

Consequence: **on the first apply that issues an Update for a given alert, its live
`triggers.logicType` is set to `any-short` regardless of what it was — and `terraform plan`
cannot show this, because the attribute does not exist in the schema.** Green signal, live
mutation, opposite sides of the same command.

For our 27 this is inert, and that is a measurement rather than an assumption:

```sh
jq -r '.[] | "\(.name)\t\(.triggers.logicType)\t\([.triggers.conditions[]]|length)"' wf-all.json
```

Every group whose live `logicType` is `all` holds **exactly one** condition (14 of the 27),
and a one-condition group evaluates identically under `all` and `any-short`. Every
multi-condition group (13 of the 27, all three-condition lifecycle sets) is **already**
`any-short`. So no rule's firing behaviour changes.

It is not inert for the future: a rule authored later with two trigger conditions intended as
AND becomes OR, silently, with a clean plan. §5 Guard 3 makes that mechanical instead of
prose, and the ADR-031 amendment records it.

---

## 5. The three gates this measurement implies

1. **`legacy_trigger_conditions` must be empty on every imported `sentry_alert`.** A non-empty
   list means a trigger fell through §2's routing and its threshold is gone. Cheapest possible
   discriminator, and nothing else can see it.
2. **The live `comparison` object must still be an object after apply.** Gate 1 is a structural
   proxy read from Terraform state; this reads the invariant itself from the API.
3. **No alert may hold >1 `trigger_conditions` entry unless `any-short` is the intended
   semantics**, per §4.

---

## 6. Scope: 27, derived not asserted

30 live workflows. The exclusion set is two rules, not three groups:

| excluded | id | why |
|---|---|---|
| `Send a notification for high priority issues` | 566201 | Sentry's own default. `new_high_priority_issue` / `existing_high_priority_issue` are not expressible, and it is not ours to manage (tracked separately as #7142). |
| `auth-per-user-loop` | 566671 | `event_unique_user_frequency_count` — action-filter-only at v0.15.7 (§1). Upstream 950. |
| `sandbox-startup-failure` | 669246 | same |

`30 - 3 = 27`. The three `auth-*` **burst** rules are IN scope: their triggers are
`event_frequency_count` with object comparisons, which §1 makes expressible.

Regenerate — this form excludes only the two unexpressible trigger types plus the vendor
default, which is one predicate rather than a name-prefix carve-out:

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

### The 27, with every attribute the translation needs

`trig` = trigger group logic type as live (see §4 — the provider will pin it to `any-short`);
`af` = `action_filters[0].logic_type`; `#af` = its condition count; `freq` = `config.frequency`
-> `frequency_minutes`; `fall` = `fallthrough_type`.

| name (byte-for-byte) | id | trig | trigger conditions | af | #af | freq | fall |
|---|---|---|---|---|---|---|---|
| `action-required-sla-veto-bypass` | 715628 | all | first_seen_event | all | 3 | 5 | ActiveMembers |
| `auth-callback-no-code-burst` | 566683 | all | event_frequency_count(value=3,interval=15m) | all | 2 | 62 | ActiveMembers |
| `auth-exchange-code-burst` | 566682 | all | event_frequency_count(value=5,interval=15m) | all | 2 | 61 | ActiveMembers |
| `auth-signout-burst` | 566672 | all | event_frequency_count(value=5,interval=15m) | all | 2 | 60 | ActiveMembers |
| `byok-art-33-breach` | 600195 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 5 | ActiveMembers |
| `byok-cap-exceeded` | 600196 | all | first_seen_event | all | 2 | 15 | **NoOne** |
| `chat-message-save-failure` | 607768 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 10 | ActiveMembers |
| `container-restart-burst` | 638577 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 17 | ActiveMembers |
| `cron-egress-blocked` | 624623 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 30 | ActiveMembers |
| `disk-io-wal-concentration` | 666233 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 21 | ActiveMembers |
| `gh-pages-cert-reissue-failed` | 705074 | all | event_frequency_count(value=0,interval=1h) | all | 1 | 63 | ActiveMembers |
| `git-data-boot-fatal` | 728266 | all | event_frequency_count(value=0,interval=1h) | **any-short** | 9 | 24 | ActiveMembers |
| `github-webhook-founder-ambiguous` | 671178 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 19 | ActiveMembers |
| `inbox-action-required-notify-failure` | 675790 | all | first_seen_event | all | 2 | 15 | ActiveMembers |
| `kb-db-error` | 611582 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 13 | ActiveMembers |
| `kb-sync-protected-fallback-failed` | 638698 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 18 | ActiveMembers |
| `kb-sync-silent-failure` | 636637 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 12 | ActiveMembers |
| `local-cache-reload-rate` | 703994 | all | event_frequency_count(value=0,interval=1h) | all | 1 | 26 | ActiveMembers |
| `outbound-email-send-failure` | 636539 | any-short | first_seen_event + reappeared_event + regression_event | all | 1 | 16 | ActiveMembers |
| `repo-resolver-divergence` | 643978 | any-short | first_seen_event + reappeared_event + regression_event | all | 1 | 20 | ActiveMembers |
| `seccomp-remediation-failed` | 703995 | all | event_frequency_count(value=0,interval=1h) | all | 1 | 27 | ActiveMembers |
| `stale-bot-pr` | 630477 | any-short | first_seen_event + reappeared_event + regression_event | all | 2 | 14 | ActiveMembers |
| `web-host-private-nic-boot-gate` | 707232 | all | event_frequency_count(value=1,interval=1h) | **any-short** | 2 | 24 | ActiveMembers |
| `web-host-terminal-boot-fatal` | 695939 | all | event_frequency_count(value=1,interval=1h) | **any-short** | 5 | 24 | ActiveMembers |
| `workspace-sync-health` | 609710 | any-short | first_seen_event + reappeared_event + regression_event | all | 1 | 11 | ActiveMembers |
| `workspaces-luks-drift` | 703574 | all | event_frequency_count(value=0,interval=1h) | all | 2 | 25 | ActiveMembers |
| `zot-mirror-fallback-rate` | 685990 | all | event_frequency_count(value=0,interval=1h) | **any-short** | 5 | 23 | ActiveMembers |

Bolded cells are the per-rule values that a uniform mapping would get wrong. The earlier
mapping asserted `logic_type = any-short` for lifecycle and said nothing about the action
filter; in fact **4 of 27 action filters are `any-short`** and the rest are `all`, and the
distinction is load-bearing — `git-data-boot-fatal` ORs nine boot-stage tags and would match
nothing under `all`.

Uniform across all 27, verified rather than assumed:

- `detectorIds == ["1213799"]` for all 30 workflows -> `monitor_ids` binds the issue-stream
  monitor uniformly. Prefer the vendor's own data source over the literal:
  `data.sentry_project_issue_stream_monitor` exists at v0.15.7
  (`docs/data-sources/project_issue_stream_monitor.md`), takes `organization` + `project`,
  exposes `id`, and its documented purpose is verbatim "You can then map these IDs into
  `sentry_alert.monitor_ids`".
- `enabled == true`, `environment == null`, `owner == null`, exactly one action filter,
  exactly one `email` action, and every action-filter condition is `tagged_event`
  (65/65 across the org).
- Action shape is `target_type = "issue_owners"` + `fallthrough_type = "ActiveMembers"` for
  26 of 27; `byok-cap-exceeded` alone is `NoOne`, deliberately (the C4 model records this at
  `model.c4:619`).

---

## 7. What did NOT change

- `state rm` remains refresh-free and therefore survives a brownout.

> **SUPERSEDED 2026-09-04 (#7650 Phase 2).** This bullet used to continue:
> *"`removed {}` remains unusable, because a plan/apply refresh of the removed
> resource hits the 410."* **That is false and was never measured.** Measured on
> Terraform v1.10.5: a `removed {}` carrying `lifecycle { destroy = false }`
> plans as `actions: ["forget"]` and emits ZERO `Refreshing state...` lines,
> against one for the same resource with its block present. A forget is
> state-only — there is no `after` object to compute — so it never issues a
> read, and it is therefore the ONE construct guaranteed not to touch the
> deprecated `rules/` endpoint. See HashiCorp PR 35458
> (`node_resource_plan_orphan.go`: `if !n.skipRefresh && !forget`), the plan's
> §R1 two-arm measurement, and `phase2-measurements-2026-09-04.md` §2.
>
> This retraction matters beyond tidiness: `phase2-measurements-2026-09-04.md`
> names THIS document as authoritative for the provider-schema sections, so an
> operator following that pointer mid-brownout would have read an unretracted
> claim that the adopted mechanism is unusable, and reached for `state rm` +
> `import` — the path the plan rejects as not implementable against `main` and
> whose worst case is 27 duplicate live paging rules created ungated.
- `terraform state mv` between the two types remains impossible — the schemas share only
  name/organization/id (`apps/web-platform/infra/sentry/issue-alerts.tf:28-31`).
- Import ID format, from the provider's own example
  (`examples/resources/sentry_alert/import.sh:1-6 @ v0.15.7`):

  ```sh
  terraform import sentry_alert.default https://{organization}.sentry.io/monitors/alerts/{id}/
  terraform import sentry_alert.default organization/id
  ```

  e.g. `jikigai-eu/728266`.
- The workflow ids are a **disjoint identifier space** from the deprecated `rules/` ids
  (`apps/web-platform/infra/sentry/README.md:60-84`). The ids in §6 come from `workflows/`
  and are the ones import takes.
