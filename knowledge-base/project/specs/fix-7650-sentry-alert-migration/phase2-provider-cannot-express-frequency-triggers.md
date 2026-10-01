# Phase 2 blocker — the provider cannot express a frequency TRIGGER, and round-trips it destructively

> ## SUPERSEDED 2026-09-04 — the blocker below is version-scoped and has LIFTED
>
> **Do not act on the scope in this document.** It says Phase 2 covers **16** rules and that
> frequency triggers are unmigratable. Both were **true at `v0.15.5`** and are **false at
> `v0.15.7`**, which is what `apps/web-platform/infra/sentry/versions.tf` and
> `.terraform.lock.hcl` now pin.
>
> Upstream PR 943 merged 2026-09-01, one day before the `v0.15.7` tag was cut
> (`364da964`, 2026-09-02 23:43:17 +0100). `trigger_conditions` now expresses **five** types
> including `event_frequency_count` with its `{value, interval}` comparison —
> `internal/provider/resource_alert_gen.go:135-162 @ v0.15.7`.
>
> **Current scope is 27**, derived in
> [`phase2-v0157-frequency-trigger-landed-scope-is-27.md`](./phase2-v0157-frequency-trigger-landed-scope-is-27.md).
>
> This file is **kept, not deleted**. It is the dated record of a correct measurement, and two
> of its findings are still live and still load-bearing:
>
> - **§"The destructive round-trip" still applies to a BARE-BOOLEAN comparison.** The
>   `default:` fallthrough and the hardcoded `true` on write are unchanged at `v0.15.7`
>   (`resource_alert_impl.go:896-898` and `:740`). Only the *object*-comparison case was fixed.
> - **§"Can the 13 be RESTRUCTURED instead? No" is unaffected** and remains the reason
>   `event_unique_user_frequency_count` rules are not restructured as action filters.
>
> Superseded by #7650 Phase 2. See the plan's `## Retractions — 2026-09-04`.

Measured 2026-09-02, from the provider source at `v0.15.5` and live org state. Read-only.
**This retracts the scope of the Phase 0 "PASS".**

## What Phase 0 got wrong

Phase 0 measured how **Sentry's API** represents our rules and concluded all 25 non-`auth-*`
rules were faithfully expressible. It never checked whether the **provider** can express
that representation. Those are different questions, and they diverge here.

- The **API** puts frequency conditions in `triggers.conditions`
  (`event_frequency_count`, `event_unique_user_frequency_count`) — measured, still true.
- The **provider** models frequency only under `action_filters[].conditions`.
  `trigger_conditions` accepts exactly four types: `first_seen_event`,
  `issue_resolved_trigger`, `reappeared_event`, `regression_event`.

So the mapping correction I made to the plan on 2026-08-26 — moving frequency into
`trigger_conditions` — was right about the API and **wrong about the provider**. The plan's
*original* mapping (frequency → `action_filters[].conditions`) was correct for authoring
new alerts. Both are now stated explicitly, because the two shapes genuinely differ.

## The destructive round-trip

`internal/provider/resource_alert_impl.go` at `v0.15.5`.

**Read** — any trigger type outside the four falls through to a default that keeps only the
type string:

```go
default:
    legacyTriggerConditions = append(legacyTriggerConditions, triggerCondition.Type)
```

`legacy_trigger_conditions` is a `List of String`. The `comparison` payload —
`{"value": 3, "interval": "5m"}` — has nowhere to go and is discarded.

**Write** — the comparison is reconstructed as a hardcoded boolean:

```go
comp.FromOrganizationWorkflowTriggerConditionComparison0(true)
...
Type:            inLegacyTriggerCondition,
Comparison:      comp,          // literally `true`
```

So an import followed by any apply rewrites the live trigger from
`{"value": 3, "interval": "5m"}` to `true`. The threshold and the interval are destroyed
on a live paging rule.

## Blast radius: 14 of 30 workflows

Faithfully importable (trigger types all within the provider's four): **16**.
Threshold destroyed on round-trip: **14**.

```
auth-per-user-loop              event_unique_user_frequency_count {"value":3,"interval":"5m"}
auth-signout-burst              event_frequency_count
auth-exchange-code-burst        event_frequency_count
auth-callback-no-code-burst     event_frequency_count
sandbox-startup-failure         event_unique_user_frequency_count
zot-mirror-fallback-rate        event_frequency_count {"value":0,"interval":"1h"}
web-host-terminal-boot-fatal    event_frequency_count
web-host-private-nic-boot-gate  event_frequency_count
workspaces-luks-drift           event_frequency_count
local-cache-reload-rate         event_frequency_count
seccomp-remediation-failed      event_frequency_count
gh-pages-cert-reissue-failed    event_frequency_count
git-data-boot-fatal             event_frequency_count {"value":0,"interval":"1h"}
"Send a notification for high priority issues"   (Sentry's own default — do not import)
```

`byok-art-33-breach` is lifecycle-triggered and therefore **not** affected: the GDPR
Art. 33 paging path is safe either way.

## Why no guard catches this, including the one shipped in Phase 1

Phase 1's destroy guard counts `legacy_trigger_conditions` **shrink**. This hazard is not a
shrink: the list keeps its length and its type string. What changes is a value that exists
only server-side and is never present in the `.tf` at all — so `terraform plan` shows no
diff to count. It is invisible to the destroy gate **by construction**, not by omission.

That makes this a hard blocker for the affected 14 rather than something to guard and
proceed through. The Phase 1 guard remains correct and worth having; it simply cannot see
this failure mode, and the plan should not imply that it can.

## Re-scope

- **Phase 2 covers 16 rules, not 25.** Those are exactly the lifecycle-triggered ones,
  whose trigger conditions carry `comparison: true` already and round-trip losslessly.
- The 13 frequency-triggered rules of ours stay on `sentry_issue_alert` until the provider
  can express a frequency trigger with its comparison. That keeps them on the deprecated
  read path, so the brownout retry stays load-bearing for them — Phase 3.4's condition
  ("remove the retry when zero `sentry_issue_alert` remain") is unchanged but is now much
  further away.
- Sentry's own default workflow must never be imported, for the same reason plus the
  `new_high_priority_issue` / `existing_high_priority_issue` types it carries.
- The `auth-*` four are now blocked twice over: by #7634's write shape and by this.

## Can the 13 be RESTRUCTURED instead of blocked? No.

The obvious workaround is to move frequency from the trigger to an action filter, which the
provider *does* support (`action_filters[].conditions[].event_frequency_count`) and the API
permits (`OrganizationWorkflow_ActionFilter_Condition_EventFrequencyCount`). It does not
work, for a structural reason rather than a fiddly one.

A workflow evaluates as: **detector produces an issue event → trigger decides whether the
workflow runs → action filters gate whether the action fires.** So an action filter can only
narrow something a trigger already started.

The provider's entire trigger vocabulary is four types — `first_seen_event`,
`issue_resolved_trigger`, `reappeared_event`, `regression_event`. **None of them means
"every event".** So there is no trigger to pair a frequency filter with that reproduces
"fire whenever this issue exceeds N in `interval`". Any available trigger narrows evaluation
to a lifecycle moment, which is a different rule: `zot-mirror-fallback-rate` would stop
firing on a sustained fallback rate on an *existing* issue and only fire if the threshold
happened to be crossed at first-seen.

That is a semantic change to live paging, which is precisely what Phase 0 existed to
prevent. Restructuring is therefore rejected, not deferred.

## Where the actual fix is

The API is not the constraint. `OrganizationWorkflow_Trigger_Condition.comparison` is
declared `oneOf: [boolean, object]` in the provider's own vendored `api.yaml` — carrying
`{"value": 3, "interval": "5m"}` on a trigger is already legal, and the generated client
can hold it. The loss happens one layer up, in the resource model: `trigger_conditions`
exposes only the four lifecycle types, so everything else is funnelled into the
string-only `legacy_trigger_conditions`.

The unblock is provider-side: `trigger_conditions` variants for `event_frequency_count`,
`event_unique_user_frequency_count`, and `event_frequency_percent` that carry the comparison
object. Upstream appears aware the shape is unsettled — the vendored spec annotates that
`oneOf` with `# TODO: Legacy?`.

## Recommendation: do not migrate the 16 now

Migrating the 16 lifecycle rules is possible but **buys nothing operationally and costs
risk.** `apply-sentry-infra.yml` plans the FULL ROOT, so all 13 remaining
`sentry_issue_alert` resources still refresh through the deprecated endpoint on every run.
The gate would keep wedging on exactly the same brownout, and the retry would stay
load-bearing. Meanwhile the change would be `state rm` + `import` against 16 live paging
rules, and would split one concern across two resource types for an unknown wait.

So Phase 2 is parked until the provider can express a frequency trigger. What is already
shipped — the scoped retry, the frequency meter, the destroy guard — is what carries the
operational load in the meantime, and the meter FAILs if the brownout ever outgrows the
retry budget.

## Reproduce

```sh
# which rules survive a provider round-trip
jq -r '.[] | . as $w
  | ([$w.triggers.conditions[].type]
     | map(select(. == "first_seen_event" or . == "reappeared_event"
                  or . == "regression_event" or . == "issue_resolved_trigger"))
     | length) as $ok
  | ([$w.triggers.conditions[]] | length) as $tot
  | "\($w.name)|\($ok)|\($tot)"' wf-all.json
```

Provider source: `internal/provider/resource_alert_impl.go` at tag `v0.15.5`, the `default:`
branch of the trigger read switch and the `LegacyTriggerConditions` write loop.
