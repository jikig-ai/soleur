---
title: "Phase 2 in-session measurements — the drift source, and the live plan"
issue: 7650
date: 2026-09-04
tags: [sentry, terraform, migration, measurement]
---

# Phase 2 in-session measurements (2026-09-04)

Deliberately NOT a restatement of
[`phase2-v0157-frequency-trigger-landed-scope-is-27.md`](./phase2-v0157-frequency-trigger-landed-scope-is-27.md).
That document is authoritative for the provider schema at the pinned tag (§1, §3),
the boolean-comparison trap (§2), the hardcoded `any-short` (§4), and the 27 with
every attribute the translation needs (§6). All of it was independently
re-derived in this session and agreed; it is not repeated here.

What follows is only what that document does NOT contain.

## 1. The frequency trap runs the OTHER way — the script is the drift source

The resume brief stated that `issue-alerts.tf` carried `61`/`62` as
dedup-avoidance placeholders against a live value of `60`. Measured, that is
inverted:

| Source | auth-signout-burst | auth-exchange-code-burst | auth-callback-no-code-burst |
|---|---|---|---|
| Live (authoritative) | 60 | 61 | 62 |
| `issue-alerts.tf` | 60 | 61 | 62 |
| `configure-sentry-alerts.sh` | 60 | 60 | 60 |

The `.tf` matched live byte-for-byte. `configure-sentry-alerts.sh` wrote `60`
for all three, so **any run of it rewrote two live paging cadences** (61→60,
62→60) through the deprecated `/rules/` endpoint.

Retiring its ownership of those three (§2.2) therefore removes an ACTIVE drift
vector, not merely a redundant writer. `auth-per-user-loop` (frequency 30) stays
in the script, so the script is not deleted.

## 2. The live plan — the adoption is a no-op on every rule

Read-only `terraform plan` against live prod state, this branch:

    Plan: 27 to import, 0 to add, 0 to change, 0 to destroy.

Plan JSON, asserted directly rather than read off the summary line:

| Assertion | Measured |
|---|---|
| `["forget"]` rows | 27 |
| `.change.importing.id` keys (note the path) | 27 |
| actions containing `delete` | 0 |
| actions equal to `["create"]` | 0 |
| all other rows | 88 × `["no-op"]` |
| resolved `monitor_ids` across the imports | `["1213799"]` |

`0 to change` is the load-bearing one: it means the 27 authored blocks are
faithful to live, so no paging threshold, filter, cadence or recipient is
silently rewritten. The equal-length-attribute rewrite class (which produces
`deletes=0 / creates=0 / nested_deletes=0` and is invisible to the destroy
guard) is excluded by measurement, not by argument.

The last row also settles a design risk: `monitor_ids` resolves through
`data.sentry_project_issue_stream_monitor.web_platform` rather than a hardcoded
literal, and it resolved to exactly the captured detector.

**A clean plan is NOT evidence the deprecation lifted.** The two surviving
`sentry_issue_alert` rules still refresh through the deprecated endpoint; this
plan simply ran outside a brownout window. The retry stays.

## 3. Ack posture — measured on the real plan, not predicted

Running the repo's own `scripts/sentry-destroy-counts.sh` against the real plan
JSON:

    resource_deletes=0  resource_creates=0  nested_deletes=142  destroy_count=142

A `forget` carries `after == null`, and `destroy-guard-filter-sentry.jq` selects
`sentry_issue_alert` rows on `index("delete") | not` — true for `forget` — then
computes `before - after`. So all 27 rules' nested conditions, filters and
actions register as nested deletes.

Consequences, both of which the merge must honour:

- The merge commit **must** carry `[ack-destroy]` on its own line in the commit
  BODY, and that ack is **correct** — nothing is being destroyed.
- Because the ack is blanket and names no address set, it must be paired with an
  explicit **`resource_deletes == 0`** assertion. That is the discriminator
  proving no genuine delete rode along under it, and it held: 0.

## 4. Type-scope coverage

The plan's four resource types — `sentry_alert` (27), `sentry_issue_alert` (29:
27 forgets + 2 no-ops), `sentry_cron_monitor` (55), `sentry_uptime_monitor` (4) —
match the types declared in `*.tf` exactly, and all four are in
`COVERED_TYPES` in `tests/scripts/test-destroy-guard-sentry-scope-guard.sh`
(the Phase 1 extension, already on main).

## 5. Generator parity

`phase2-generate-alert-blocks.py` re-run against the committed capture
reproduces the committed `resource` / `removed` / `import` runs byte-for-byte.
It derives resource labels mechanically with a three-entry override table for
the historical aliases (`cron-egress-blocked` → `egress_blocked`,
`web-host-private-nic-boot-gate` → `web_private_nic_boot_gate`,
`web-host-terminal-boot-fatal` → `web_terminal_boot_fatal`) and reads nothing
from `issue-alerts.tf`, so deleting the legacy blocks cannot break it.

## 6. Sentry token `workflows/` WRITE scope — present (task 1.6)

The adoption itself writes nothing to Sentry: 27 imports and `0 to change` is a
read-only plan. The first WRITE happens on the first later apply that changes an
adopted rule, so a missing write scope would not surface here — it would surface
mid-apply, months from now, in a half-applied state. Hence the preflight.

Probed 2026-09-04 with `SENTRY_IAC_AUTH_TOKEN` (Doppler `soleur/prd_terraform`),
against `jikigai-eu.sentry.io`:

| Request | Status | Reading |
|---|---|---|
| `GET  /api/0/organizations/jikigai-eu/workflows/?per_page=1` | **200** | read scope present (control) |
| `PUT  /api/0/organizations/jikigai-eu/workflows/999999999/` with `{}` | **404** | **write scope present** — the request was authorised and failed only on the id |

**404, not 403, is the whole result.** Sentry rejects an unauthorised write with
403 before it looks the resource up; a 404 means authorisation passed and the
lookup failed. So the token can write this endpoint family.

**Why the probe is safe to have run against production.** The id `999999999` does
not exist, so no mutation was reachable on any code path — a PUT to a missing
resource cannot partially apply. That is deliberately the ONLY shape of write
probe used here: sending `{}` to a REAL workflow id would have distinguished the
same two cases while risking a live paging rule.

**What this does NOT establish.** Nothing about the write ENVELOPE. Whether
`workflows/` accepts a PUT/POST body that Terraform or
`configure-sentry-alerts.sh` could construct is still unknown and is exactly
what #7634 tracks. Scope and schema are different questions; this answers only
the first.

## 7. `plan_pr` runtime against the adoption-shaped plan (task 1.7)

`apply-sentry-infra.yml`'s `plan_pr` carries `timeout-minutes: 15`, set before this
plan shape existed. A timeout is a `failure`, and the aggregator fails closed on
it with **no brownout annotation** — so an under-set budget would present as an
unexplained red on the one PR that moves 27 live paging rules.

Measured 2026-09-04, full root, warm provider cache, this branch:

```
terraform plan -no-color -input=false -out=/tmp/tfplan.sentry
  rc=0   elapsed=12s
  Plan: 27 to import, 0 to add, 0 to change, 0 to destroy.
  410 responses: 0
```

The 27 live import reads cost seconds, not minutes: Terraform issues them during
the same refresh walk it already performs.

**Budget arithmetic, worst case.** 12 s of plan + the brownout retry's full
ceiling (3 attempts, 5 s then 10 s backoff, plus two further plan attempts) is
under 4 minutes even if every attempt runs to completion. `timeout-minutes: 15`
has roughly 4x headroom and does **not** need raising for this shape.

**What this measurement does not cover.** A GitHub-hosted runner adds cold
`terraform init` (provider download, ~20-40 s observed on sibling roots) and has
no warm cache, and a real brownout adds the 210 s of sleep this arithmetic
already budgets. Both are inside the headroom above. The number to re-derive if
that stops being true is the plan itself, not the retry count.
