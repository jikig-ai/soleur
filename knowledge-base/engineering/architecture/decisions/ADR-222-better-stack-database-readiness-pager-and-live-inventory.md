---
title: "ADR-222: Better Stack is the database-readiness pager, reading the /health body; every live Better Stack uptime object is Terraform-declared or reported"
status: active
date: 2026-09-15
issue: 7884
amends:
  - ADR-117
  - ADR-149
  - ADR-204
tags: [observability, uptime-monitoring, better-stack, terraform, supabase, health, drift, reconcile]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/app-database-readiness-alarm.md
---

# ADR-222: Better Stack is the database-readiness pager, reading the `/health` body; every live Better Stack uptime object is Terraform-declared or reported

## Status

`active`. Both decisions ship in PR #8216. The paging half is live from the first per-merge
apply that imports and converges `betteruptime_monitor.app_health`; that apply and the read-back
after it are post-merge facts, checked by the plan's AC17/AC18 and not asserted here.

- **Issue:** [#7884](https://github.com/jikig-ai/soleur/issues/7884) (stays open until the
  post-merge read-back).
- **Incident:** [prd Supabase database unreachable, 2026-09-15](../../operations/post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md).
- **Ordinal note:** ADR-221 was the highest ordinal across all `origin/*` refs on 2026-09-15
  (it exists only on a pushed branch). Re-derive at ship.

## Context

On 2026-09-15 the prd Supabase Postgres stopped serving from 14:16:06Z to 15:45:16Z (~89 min).
Nothing paged. The outage was found by accident, about 60 minutes in, by a deploy job.

`https://app.soleur.ai/health` did carry the signal. `apps/web-platform/server/index.ts` answers
the `/health` branch with `res.writeHead(200, …)` and `JSON.stringify(health)` in every state, and
`buildHealthResponse()` in `server/health.ts` sets `supabase: supabaseOk ? "connected" : "error"`,
where `checkSupabase` is a service-role REST read with `AbortSignal.timeout(2000)`. During the
outage `/health` returned `status: ok` with `supabase: error` (post-mortem timeline, 15:33Z).

The only uptime monitor on that URL was Better Stack monitor `4226366`. It was created by hand on
2026-03-28, declared in no Terraform root, and typed `status`, so it read the HTTP 200 and stayed
green. ADR-204 found it while measuring the free-tier quota and recorded it as unmanaged.

Two further facts shaped the second decision:

- **The object-cap question had two contradicting readings.** ADR-149 reason (c) read "a single
  shared pool of ten" monitors and heartbeats off the vendor page; the `uptime-alerts.tf` header
  said heartbeats are not pooled. Live on 2026-09-15 the workspace held **4 monitors + 9
  heartbeats = 13 objects**, which contradicts the first reading and settles nothing about the
  second.
- **A hand-made object is invisible to every existing check.** The drift plan reports only
  resources in state; the twice-daily `heartbeat-live-reconcile` job compared declared heartbeats
  against live ones and never listed monitors or looked for undeclared objects.

### Vendor probe (2026-09-15, before any code)

The keyword half rests on Better Stack matching a quoted compact-JSON substring in the raw body.
Its documentation says only "a specified keyword or phrase in the page response", so it was
measured with a throwaway monitor on the real URL (`confirmation_period` 0, no alert channels):

| Step | Result |
|---|---|
| `POST /api/v2/monitors`, `monitor_type` keyword, `required_keyword` `"supabase":"connected"` | **201**, id `4934114` |
| Read with the real keyword | **`up`**, `last_checked_at` 2026-09-15T17:11:55Z |
| `PATCH` to a keyword that can never match | 200; **`down`**, `last_checked_at` 17:12:10Z |
| `DELETE`, then `GET` | **204**, then **404** |

The `down` reading is what makes the `up` reading mean anything: a monitor that cannot fail also
reads `up`. The workspace also accepted the `keyword` type, so the plan's `status` fallback branch
did not apply.

## Considered Options

| Option | Why not |
|---|---|
| Return 503 from `/health` when Supabase fails, keep a `status` monitor | `/health` is the load-balancer and deploy liveness probe. A database outage would then also read as "app down" to every consumer that only needs the process alive. |
| A separate `/ready` endpoint with a `status` monitor | A new app route and deploy to expose a property the existing body already carries. |
| A Sentry uptime assertion on the body | Not rejected on capability: `/health` does not redirect, so the terminal-response limit ADR-204 recorded does not bite, though a body assertion was not measured on Sentry. Rejected because the incident's app-side symptoms already went to Sentry and were lost as background noise, so the readiness page belongs on the independent exit, and because the Better Stack object on this URL existed and needed adoption either way. The Sentry app monitor is itself unmanaged (#6606). A Sentry-side second assertion stays a candidate for the Better Stack outage residual below. |
| Delete `4226366` and create a fresh keyword monitor | Loses about 5.5 months of check history for no gain; the provider updates `monitor_type` in place. |
| `terraform import` CLI from a dispatch job | Imperative and state-only, so the adoption would be invisible in review. |
| Match live objects to declarations by tfstate id | The reconcile job has no state access; it would need a second credential surface. Literal URL (monitors) and resolved name (heartbeats) are stable join keys. |
| Assert a cap (10, or 10 per kind) | The measured 13 contradicts one reading, and neither is needed: a measured count answers the question every run. |

## Decision

### 1. Better Stack pages on database readiness by reading the `/health` body

`betteruptime_monitor.app_health` in `apps/web-platform/infra/uptime-alerts.tf` adopts monitor
`4226366` and converges it in the same per-merge apply:

- `monitor_type = "keyword"`, `required_keyword = "\"supabase\":\"connected\""`, the exact compact
  JSON `index.ts` serializes.
- `check_frequency = 180`, `confirmation_period = 180` (was 0), `recovery_period = 180`,
  `request_timeout = 10` (was 30, the sibling convention; `/health` is bounded by the 2 s REST
  timeout).
- `pronounceable_name = "soleur app database readiness"`, so the email subject names the failure.
- Email only, like every sibling monitor (`call`, `sms`, `push` false).
- Adopted through a declarative `import {}` block gated by `var.adopt_app_health_monitor`
  (default `true`, set `false` in `tests/web-hosts-eu-pin.tftest.hcl` because `mock_provider`
  does not mock imports), with a `-target=betteruptime_monitor.app_health` line in the per-merge
  apply. This is the `seo-config-rules.tf` precedent.

`/health` keeps answering HTTP 200 in every database state. A body without the keyword pages: a
database failure, a service-role key the REST check rejects, a REST read slower than 2 s, and
also a Cloudflare 52x page, a timeout or a TLS failure, none of which carry the phrase.

### 2. Every live Better Stack uptime object is Terraform-declared or reported

The existing twice-daily reconcile (`plugins/soleur/scripts/reconcile-live-heartbeats.ts`, job
`heartbeat-live-reconcile` in `scheduled-terraform-drift.yml`) now covers monitors as well as
heartbeats, against the declarations in `apps/web-platform/infra`:

- Monitors join on the declared literal `url`; heartbeats on the declared `name`, with
  `for_each`/`count` resolved exactly from literal variable defaults. A declaration it cannot
  resolve fails the run (rc 1) rather than being skipped.
- `reason=unmanaged-live` reports a live monitor or heartbeat no declaration accounts for, and
  every object sharing a URL or name with another (`dup=url` / `dup=name`). The issue gains the
  `infra-drift` label and the email says so.
- `reason=monitor-config-drift` reports a declared monitor whose live `monitor_type`,
  `required_keyword` or `paused` differs, so a vendor-side edit cannot quietly disarm the alarm in
  decision 1 between infra merges.
- Every run in which both uptime reads succeed prints
  `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=<n> heartbeats=<n> total=<n>`. This measured
  count replaces any asserted cap, in `uptime-alerts.tf` and in ADR-149 reason (c).

Scope limit: Better Stack Logs (telemetry) alerts are outside this rule. ADR-218's `logs_alert`
arm checks declared alerts only and does not report undeclared ones.

## Consequences

- **The keyword literal is coupled to serialization.** A change to how `/health` is serialized
  (pretty-printing, a renamed field, a changed value) is a change to the paging contract.
  `apps/web-platform/test/server/health-keyword-monitor-contract.test.ts` reads the keyword from
  the declaration, builds the connected and failed bodies through `buildHealthResponse()`, and
  fails the PR if the keyword stops matching exactly the connected body. It also pins the monitor
  type to a committed constant, so downgrading the alarm needs a visible test edit.
- **Worst-case detection is about 6 minutes plus inbox latency.** Up to 180 s to observe the first
  failing check, plus the 180 s confirmation window. Paging is email only, so the time until a
  human acts includes reading the inbox; nothing escalates on the current configuration. The
  confirmation window absorbs single-check flaps such as the 15:44:44Z one in the post-mortem.
- **The gated import block is temporary, and most likely harmful if kept.** Terraform v1.10.5
  skips an import only while the address is in state. If `4226366` were deleted on the vendor
  side, refresh would drop it from state, the import would be attempted again, and the
  passthrough importer's read of a missing id would most likely abort every plan in the root.
  This is derived from Terraform and provider source (hypothesis H-F in the plan), not measured.
  Before any merge, the reconcile reports the deletion as `absent-live`; the off-switch is setting
  `adopt_app_health_monitor` to `false` in a PR (runbook
  [app-database-readiness-alarm.md](../../operations/runbooks/app-database-readiness-alarm.md));
  and a tracked follow-up removes the block and the variable once the post-merge read-back passes.
  Removing the variable also closes a Doppler `TF_VAR_*` override path around the reconcile's
  resolver (ADR-117 amendment of 2026-09-15).
- **Unmanaged objects surface within one drift cycle (12 h at most), with no SSH**, through the
  existing mismatch issue, the `infra-drift` label and email.
- **The first run after merge re-emails every existing mismatch row once**, because issue history
  carries no `resource=` routing tokens yet (ADR-117 amendment).

### Residual gaps, recorded rather than implied closed

- **A Better Stack outage leaves database readiness with no second alarm.** No Sentry assertion
  reads the body today.
- **Only web-1's view of Supabase is probed.** `cloudflare_record.app` in `dns.tf` points
  `app.soleur.ai` at web-1 alone, and web-2 is a serving-weight-0 standby. Once more than one host
  serves the name, a single host losing Supabase while its sibling is healthy would alternate
  checks and might never fill the confirmation window. Supabase is shared by both hosts, so this
  would be rare.
- **Checks oscillating near the 2 s REST timeout can open and close incidents repeatedly**, since
  `recovery_period` equals one cadence.
- **A persistent Better Stack 5xx or 429 on the reconcile never pages.** It prints
  `SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE` and a workflow warning (the existing contract), and it
  silently suspends unmanaged and disarm detection for as long as it lasts. The only trace is the
  missing `INVENTORY` line.

## Cost Impacts

None. The monitor already existed and keeps its id, so the object count does not change. The probe
monitor was created and deleted. No new vendor, plan or line item.

## NFR Impacts

- NFR-003 (Service-Level Monitoring): the Supabase dependency gains an externally paged readiness
  signal as seen from the app. The register row is not edited here.
- NFR-013 (Synthetic Monitoring): a synthetic probe now asserts response content on
  `app.soleur.ai/health`, not only the status code.

## Principle Alignment

- AP-001 (Terraform-only infrastructure provisioning): Aligned. A hand-made monitor is brought
  under Terraform, and live objects no declaration accounts for are now reported.
- AP-002 (No SSH state mutation): Aligned. Detection, diagnosis and the H-F remedy need no SSH.
- AP-005 (Email for ops): Aligned. Both the alarm and the reconcile page by email.
- AP-021 (Diagnostic honesty): Aligned. The object cap is measured by a marker and never
  asserted; H-F is labelled source-derived, not measured.
