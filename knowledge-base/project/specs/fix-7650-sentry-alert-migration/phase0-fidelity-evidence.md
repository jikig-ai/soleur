# Phase 0 fidelity evidence — #7650 `sentry_issue_alert` → `sentry_alert`

Measured 2026-08-26 against **live** Sentry (org `jikigai-eu`), read-only, using
`SENTRY_IAC_AUTH_TOKEN` from Doppler `soleur/prd`. No object was created, mutated, or
deleted; every call below is a GET.

> **SCOPE RETRACTED 2026-09-02.** The PASS below holds for the 16 **lifecycle-triggered**
> rules and NOT for the 13 frequency-triggered ones. This file measured how Sentry's **API**
> represents our rules; it never checked whether the **provider** can express that
> representation, and it cannot. A frequency trigger round-trips through
> `legacy_trigger_conditions` (a List of String) which discards the `comparison` payload,
> and the write path reconstructs it as the boolean `true` — destroying the threshold and
> interval on a live paging rule. The mapping "correction" below is also wrong for the
> provider, whose frequency conditions live under `action_filters[].conditions`.
> See `phase2-provider-cannot-express-frequency-triggers.md`.

## Verdict: PASS for lifecycle rules only, and the plan's translation mapping was wrong

Phase 0 asked whether a **pure-frequency** rule (`event_frequency`, no lifecycle trigger)
fires faithfully once bound to a default monitor, since binding one to an issue-stream
monitor could change *when* it fires. That was the risk gating the whole migration.

It does not change. The question turned out to be answerable by reading rather than by
constructing a scratch experiment, because **Sentry has already migrated all 29 of our
rules server-side**: `projects/{org}/{proj}/rules/` and `organizations/{org}/workflows/`
are two views of the same objects. The faithful translation already exists, authored by
the vendor, and can simply be read.

## What was measured

`GET /api/0/organizations/jikigai-eu/workflows/?per_page=100` → **30 workflows**: our 29
plus Sentry's own default "Send a notification for high priority issues".

### 1. Monitor binding is uniform — it is not a semantic differentiator

```
detectorIds distribution across all 30 workflows:
     30  1213799
```

Every workflow — lifecycle-triggered, pure-frequency, and Sentry's own default alike —
binds to the **same** detector, `1213799` (`type=issue_stream`, name `Issue Stream`). The
org exposes exactly two default monitors for the project:

```
1213798  type=error         name=Error Monitor
1213799  type=issue_stream  name=Issue Stream
```

So `monitor_ids` does not distinguish a frequency rule from a lifecycle rule, and binding
a pure-frequency rule to the issue-stream monitor is precisely what Sentry itself does.
**The Phase 0 risk does not materialise.**

### 2. Frequency is a first-class TRIGGER type — the plan put it in the wrong place

```
trigger-condition vocabulary, all 30 workflows:
     16  first_seen_event
     13  reappeared_event
     13  regression_event
     11  event_frequency_count
      2  event_unique_user_frequency_count
      1  new_high_priority_issue
      1  existing_high_priority_issue

actionFilters condition vocabulary, all 30 workflows:
     65  tagged_event      <- and nothing else
```

Frequency conditions live in `triggers.conditions` as `event_frequency_count` /
`event_unique_user_frequency_count`. `actionFilters` carry **only** `tagged_event`.

The migration plan's Phase 2.1 said: *"frequency conditions + `tagged_event`/`level`
filters → `action_filters[].conditions`"*. That is measured false for the frequency half.
Following it would have placed frequency conditions where Sentry never puts them.
Corrected in the plan.

`logicType` also tracks the shape faithfully: pure-frequency rules use `all` (one
condition), lifecycle rules use `any-short` (fire on any of first-seen / reappeared /
regression).

### 3. The four `auth-*` rules' live definitions are now readable

Terraform declares `conditions_v2 = []` for these four under a wide `ignore_changes`, so
their real configuration has only ever existed inside `configure-sentry-alerts.sh`. The
workflows API exposes what is actually live:

```
auth-exchange-code-burst      all  event_frequency_count
auth-callback-no-code-burst   all  event_frequency_count
auth-signout-burst            all  event_frequency_count
auth-per-user-loop            all  event_unique_user_frequency_count
```

This does not unblock #7634 — that is about the WRITE shape, and nothing here was
written — but it removes the need to reverse-engineer the intended state from the script
in order to verify a future migration. It also independently corroborates the
disjoint-sets finding: these four are frequency rules whose Terraform blocks are empty
shells.

## Consequences for the migration

- ~~**Phase 0 passes.** All 25 non-`auth-*` rules, including the 9 pure-frequency ones, are
  faithfully expressible. No rule needs to stay on `sentry_issue_alert` for fidelity.~~
  **RETRACTED 2026-09-02:** true for the 16 lifecycle rules, false for the 9 pure-frequency
  ones. Measuring the API's representation is not the same as measuring the provider's, and
  only the first was done here.
- **The work is closer to an import than a re-creation.** The target objects already
  exist server-side with correct semantics; the task is getting Terraform to manage them,
  not to author them. That is materially lower risk than the plan assumed.
- **Phase 2.1's mapping is corrected** to put frequency in `trigger_conditions`.
- Phase 1 (destroy-guard extension) is unchanged and still must land first.

## Reproduce

```sh
doppler run -p soleur -c prd -- bash -c '
  curl -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
    "https://$SENTRY_API_HOST/api/0/organizations/$SENTRY_ORG/workflows/?per_page=100" \
  | jq -r ".[] | \"\(.name)|\(.detectorIds|join(\",\"))|\(.triggers.logicType)|\([.triggers.conditions[]?.type]|join(\"+\"))\""'
```

## Token boundary observed

`GET /organizations/{org}/projects/{proj}/detectors/` returns **403** with this token;
the org-scoped `GET /organizations/{org}/detectors/` returns 200. Anything needing the
project-scoped path will need a scope widen. Token scopes as reported by the org
endpoint: `project:read org:read project:admin project:write alerts:read alerts:write`.

## Brownout note

The deprecated `rules/` endpoint returned **200** throughout this session, i.e. this ran
outside a brownout window. Consistent with a scheduled brownout, and — per the retracted
2026-07-17 finding — **not** evidence that the deprecation has been lifted.
