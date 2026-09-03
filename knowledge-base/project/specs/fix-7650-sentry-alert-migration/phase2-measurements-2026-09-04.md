---
title: "Phase 2 measurements — scope, traps, and provider schema at v0.15.7"
issue: 7650
date: 2026-09-04
tags: [sentry, terraform, migration, measurement]
---

# Phase 2 measurements (2026-09-04)

Every number here was measured in-session against live prod or the pinned provider.
Nothing is quoted from the plan, the resume prompt, or a changelog.

## Scope: 27, derived not asserted

Source: `phase2-live-workflows-capture-2026-09-04.json`, captured `HTTP/2 200` from
`GET /api/0/organizations/jikigai-eu/workflows/?per_page=100`.

| Step | Count |
|---|---|
| Live workflows in the org | 30 |
| less `Send a notification for high priority issues` (566201, vendor default: `new_high_priority_issue` + `existing_high_priority_issue`) | -1 |
| less `auth-per-user-loop` (566671) and `sandbox-startup-failure` (669246), both `event_unique_user_frequency_count` | -2 |
| **In scope** | **27** |

Re-derived from the committed capture, not from the raw response.

## Trap 2 — comparison shape: CLEAR

11 `event_frequency_count` trigger conditions across the org; **0** carry a bare-boolean
comparison. All 11 are objects, so none falls into `legacy_trigger_conditions` and none
loses its threshold.

## Detector uniformity: CONFIRMED

`[.[] | .detectorIds] | flatten | unique` over all 30 returns exactly `["1213799"]`.
`monitor_ids` does not branch per rule class.

## Provider schema at the pinned tag (read from the provider, not the changelog)

`terraform providers schema -json` against `jianyuan/sentry 0.15.7` in a scratch root:

- `trigger_conditions` (list) offers `event_frequency_count{interval,value}`,
  `first_seen_event`, `reappeared_event`, `regression_event`, `issue_resolved_trigger`.
  Frequency triggers **are** expressible at 0.15.7 — the plan's v0.15.5-era
  "NOT MIGRATABLE" is stale, as recorded.
- `trigger_conditions` has **no** `event_unique_user_frequency_count`. This is upstream
  jianyuan/terraform-provider-sentry issue 950 confirmed *from the schema itself*, and it
  is why the two exclusions above are real rather than assumed.
- `trigger_conditions` has **no** `logic_type` attribute — the provider hardcodes
  `any-short`. See the semantics check below.
- `action_filters` is REQUIRED, with REQUIRED `actions` and REQUIRED `logic_type`
  (`any` | `any-short` | `all` | `none`).
- `action_filters[].conditions` **does** offer `event_unique_user_frequency_count` — it is
  available as a filter condition and merely absent as a *trigger*, which is precisely the
  shape upstream 950 describes.
- There is **no** `project` attribute; `organization` is REQUIRED.

## The hardcoded `any-short` is semantics-preserving — proven, not assumed

14 of the 27 in-scope rules report `triggers.logicType = "all"` rather than `any-short`.
Every one of those 14 has **exactly one** trigger condition, where `all` and `any-short`
are semantically identical. Rules with multiple trigger conditions all already report
`any-short`.

    count of (logicType != "any-short" AND n_conditions > 1) = 0

So authoring under the provider's hardcoded `any-short` changes no paging semantics.
Had any multi-condition trigger used `all`, adoption would have silently widened it.

## `action_filters[].logic_type`: 4 of 27 are `any-short`

`git-data-boot-fatal`, `web-host-private-nic-boot-gate`, `web-host-terminal-boot-fatal`,
`zot-mirror-fallback-rate`. The other 23 are `all`. Must be authored per rule.

## `fallthrough_type`: `NoOne` on `byok-cap-exceeded` alone

The other 26 are `ActiveMembers`. Note this is `ActiveMembers`, not `AllMembers`.

## Frequency: the trap runs the OTHER way

The resume prompt stated the `.tf` carried 61/62 as dedup placeholders against a live
value of 60. Measured, that is inverted:

| Source | auth-signout-burst | auth-exchange-code-burst | auth-callback-no-code-burst |
|---|---|---|---|
| Live (authoritative) | 60 | 61 | 62 |
| `issue-alerts.tf` | 60 | 61 | 62 |
| `configure-sentry-alerts.sh` | 60 | 60 | 60 |

The `.tf` matches live byte-for-byte. **`configure-sentry-alerts.sh` is the drift source:**
any run of it today rewrites two live paging cadences (61 to 60, 62 to 60) through the
deprecated `/rules/` endpoint. Retiring its ownership of the three burst rules therefore
removes an active drift vector, not merely a redundant writer — which strengthens the
operator's decision to fold the auth-three into this pass.

`auth-per-user-loop` (frequency 30) stays in the script, so the script is not deleted.

## Environment and enabled

All 27 are `enabled: true` with `environment: null`.
