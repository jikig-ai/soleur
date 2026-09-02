# Phase 2 blocker — the provider cannot express a frequency TRIGGER, and round-trips it destructively

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
