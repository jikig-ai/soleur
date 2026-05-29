# Learning: Sentry `/detectors/` PUT takes a bare partial body — never echo the GET response back

## Problem

PR #4603 (#4596) added pause/resume of the `soleur_www` Sentry uptime detector
to `deploy-docs.yml`. The plan's Research-Reconciliation table asserted (citing
the `jianyuan/terraform-provider-sentry` OpenAPI `requestBody.required: true`)
that `PUT /api/0/organizations/{org}/detectors/{id}/` requires the **full**
`ProjectMonitorRequest` body, so a bare `{"enabled": false}` PUT would 400 —
and prescribed a GET-then-PUT round-trip (fetch full object, mutate `.enabled`,
PUT it back).

In production both PUTs returned **400**:

```
{"dataSources":{"assertion":{"error":"serialization_error",
  "details":"Failed to deserialize the JSON body into the target type:
   url: invalid type: null, expected a string ..."}}}
```

The pause PUT 400'd (monitor never paused → no alerting gap, since it stayed
enabled), but the resume step's non-200 path `exit 1` reddened **every** docs
deploy. The feature was non-functional and the workflow was broken.

## Solution

The plan's reconciliation was **backwards**. Against the live API
(`jikigai-eu.sentry.io`, detector `1221117`):

- `PUT {"enabled": false}` / `PUT {"enabled": true}` (bare partial) → **HTTP 200** ✓
- `PATCH {"enabled": true}` → **HTTP 403** (method not permitted for this token)
- Echoing the full GET response back as the PUT body → **HTTP 400**

The GET **response** (`ProjectMonitor`) and the PUT **request** schemas differ:
the GET response embeds nested `dataSources[].queryObj.url`-class fields that
serialize as `null` on read, but the request schema requires a non-null string.
Echoing GET→PUT therefore fails deserialization. A bare partial body sidesteps
the entire class.

Fix: replace the GET-then-PUT with a single bare `PUT {"enabled": <bool>}` in
both pause and resume steps. (Full pause→`false`→resume→`true` cycle
live-validated, monitor restored to `enabled: true`.)

## Key Insight

**For a REST resource where you only need to toggle one field, try the bare
partial `PUT {"field": value}` FIRST — do not assume "full-body required" from
an OpenAPI `requestBody.required: true` and echo the GET response back.** A GET
response routinely carries read-only/computed/null-on-read fields (`id`,
`dateCreated`, nested `*.url`) that the request schema rejects; response and
request schemas are NOT interchangeable. When a plan prescribes a specific API
body shape, treat it as an **unverified open question** until a live probe
confirms it (the plan even flagged the partial-PUT question but resolved it the
wrong way). A 5-minute `curl` against the live endpoint at /work time would have
caught this before it shipped — the same "plan-prescribed runtime shapes must be
grepped/probed against the live API, not assumed" discipline that applies to CLI
flags and installed library versions. See
[[2026-05-29-plan-mandated-compound-selector-must-be-implemented-fully]].

## Session Errors

1. **Shipped a P1 that broke deploy-docs (resume PUT 400 → exit 1 on every
   run).** Root cause: the plan's API-contract reconciliation was wrong
   (assumed full-body PUT required; reality is bare partial works, full echo
   400s), and no live probe ran at /work or QA time because the change had no
   `## Test Scenarios` and the discoverability probe only checked the www→apex
   301, not the Sentry PUT. — Recovery: hotfix to bare partial PUT, live-
   validated full cycle. — Prevention: the Key Insight above — when a workflow
   makes a vendor-API write whose body shape is plan-asserted-but-unverified,
   run one live `curl` against the real endpoint before shipping (QA Test
   Scenario or a /work live-probe), especially when the plan itself flags the
   shape as an open question.

## Tags
category: integration-issues
module: ci/sentry-iac
issue: 4596
pr: 4603
