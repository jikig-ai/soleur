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

- **Issue:** [#7884](https://github.com/jikig-ai/soleur/issues/7884). It stays open after PR #8216
  and closes with the import-block removal PR, which carries `Closes #7884` and follows the AC17
  read-back.
- **Incident:** [prd Supabase database unreachable, 2026-09-15](../../operations/post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md).

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

### Vendor probes (2026-09-15, before merge)

The keyword half rests on Better Stack matching a quoted compact-JSON substring in the raw body.
Its documentation says only "a specified keyword or phrase in the page response", so it was
measured with throwaway monitors on the real URL (`confirmation_period` 0, no alert channels).

**Probe 1: does the keyword match, and can it fail?**

| Step | Result |
|---|---|
| `POST /api/v2/monitors`, `monitor_type` keyword, `required_keyword` `"supabase":"connected"` | **201**, id `4934114` |
| Read with the real keyword | **`up`**, `last_checked_at` 2026-09-15T17:11:55Z |
| `PATCH` to a keyword that can never match | 200; **`down`**, `last_checked_at` 17:12:10Z |
| `DELETE`, then `GET` | **204**, then **404** |

The `down` reading is what makes the `up` reading mean anything: a monitor that cannot fail also
reads `up`. The workspace also accepted the `keyword` type, so the plan's `status` fallback branch
did not apply.

**Probe 2: does the vendor accept the in-place conversion the adoption apply sends?**

| Step | Result |
|---|---|
| `POST` a `status` monitor (the shape of `4226366`) | created, id `4934199`, 2026-09-15T17:52Z |
| One `PATCH` with the exact attribute set the apply converges: `monitor_type` status→keyword, `required_keyword`, `confirmation_period` 180, `recovery_period` 180, `request_timeout` 10, `pronounceable_name` | **200** |
| Read back | every attribute matched; reading after conversion **`up`** |
| `DELETE`, then `GET` | **204**, then **404** |

The provider updates `monitor_type` in place, and the vendor accepts that update with the rest of
the merge's attribute set, so the adoption apply is not expected to be refused.

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
  `required_keyword` or `paused` differs, and, where the declaration sets them, `email`, `call`,
  `sms`, `push`, `confirmation_period`, `check_frequency`, `request_timeout`, `recovery_period`,
  `verify_ssl` or `follow_redirects`, plus any live maintenance window. A vendor-side edit
  therefore cannot quietly disarm the alarm in decision 1 between infra merges. It emails on every
  run while it persists.
- A declaration file that fails to parse prints
  `SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=parse-error`; an override file or
  a `.tf.json` file reports `reason=unresolvable-declaration`. Both fail the run.
- Every `MISMATCH` row carries one `route=<reason>~<subject>` token, and escalation keys on it
  (ADR-117 amendment of 2026-09-15 owns the routing rule).
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
- **The gated import block is temporary, and harmful if kept (hypothesis H-F).** Terraform
  v1.10.5 skips an import while the address is in state. If `4226366` were deleted on the vendor
  side, the provider's read of the 404 clears the id (`SetId("")`), refresh drops the object from
  state, and the import is attempted again against a missing object ("Cannot import non-existent
  remote object"). Which plans that aborts was measured on Terraform 1.10.5 during review: an
  import whose `to` address is outside a plan's `-target` set is skipped silently, even with an
  unreadable id, while an untargeted plan or one that targets the address aborts. So after a
  deletion:
  - the per-merge `apply` job of `apply-web-platform-infra.yml`, which targets
    `betteruptime_monitor.app_health`, aborts on every infra merge and emails through its
    `notify-apply-failure` job;
  - the scheduled `drift-check` plan, which is untargeted, exits 1 on every run, sending
    `[ERROR] Terraform plan failed for web-platform` twice a day and a Sentry
    `scheduled-terraform-drift` error check-in;
  - targeted dispatch jobs whose `-target` set excludes the address, such as
    `apply-deploy-pipeline-fix.yml`, skip the import and keep working (that workflow sends no
    failure email of its own).

  The abort follows from Terraform core and provider source plus the targeting measurement; it was
  not reproduced against Better Stack. The reconcile reports the deletion as `absent-live` on its
  next run (06:00 or 18:00 UTC), so within 12 hours, not necessarily before the next merge: an
  infra merge inside that gap fails first and emails. The interim off-switch is setting
  `adopt_app_health_monitor` to `false` in a PR (runbook
  [app-database-readiness-alarm.md](../../operations/runbooks/app-database-readiness-alarm.md)).
  The block and the variable are removed by a follow-up PR after the AC17 read-back; #7884 stays
  open until that PR merges. Removing the variable also closes a Doppler `TF_VAR_*` override path
  around the reconcile's resolver (ADR-117 amendment of 2026-09-15).
- **Unmanaged objects surface within one drift cycle (12 h at most), with no SSH**, through the
  existing mismatch issue, the `infra-drift` label and email.
- **The first run after merge re-emails every existing mismatch row once**, because issue history
  carries no `route=` tokens yet (ADR-117 amendment).

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
- **The readiness check is one REST read, so some Supabase outages stay green.**
  `checkSupabase` is a single service-role `GET /rest/v1/users?select=id&limit=1`. Supabase Auth
  down while PostgREST serves, and a database that has gone read-only (reads succeed, writes
  fail), both keep `"supabase":"connected"` and do not page, although users cannot sign in or
  save.
- **A hand-made replacement of an untargeted heartbeat is read as managed.** Heartbeats join on
  name, and the reconcile has no tfstate access. The four heartbeats in the parity test's
  `OPERATOR_APPLIED_EXCLUSIONS` (`git_data_prd`, `workspaces_luks`, `registry_prd`,
  `registry_disk_prd`) have no per-merge `-target`. A vendor-side replacement of one of them that
  reuses the declared name matches its declaration and is not reported.
- **Only uptime monitors and heartbeats are inventoried.** Status pages, on-call calendars,
  escalation policies, webhooks and undeclared Logs alerts (such as the paused
  `Output utilization high`) are not read.
- **Modules are not expanded.** Declarations are read from the root's own `.tf` files; a monitor
  or heartbeat declared inside a module call would not be seen.

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
  asserted; H-F's reach is measured on Terraform and its trigger is labelled source-derived, not
  reproduced against Better Stack.
