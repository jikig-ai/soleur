---
adr: ADR-133
title: Pre-apply entrypoint-enumeration gate for whole-list Cloudflare rulesets
status: active
date: 2026-07-22
---

# ADR-133: Pre-apply entrypoint-enumeration gate for whole-list Cloudflare rulesets

## Context

A `kind = "zone"` / `kind = "root"` `cloudflare_ruleset` OWNS its phase entrypoint
as a WHOLE-LIST replacement. `terraform plan` reports "1 to add" for such a
resource purely because it is absent from *state* — that line is correct — but
`plan` never calls the Cloudflare API, so it cannot see that the LIVE entrypoint
is already populated with dashboard-created rules. A clean plan is therefore
fully compatible with a DESTRUCTIVE first apply: the create whole-list-PUTs the
config's rules over the live list, silently deleting rules a human made in the
dashboard. This is the #6746 outage class (the "Flexible SSL for web platform"
rule on `app.soleur.ai`).

The destroy-guard (`destroy-guard-filter-web-platform.jq`) CANNOT catch it: on a
create, `change.before` is null, so its `before.rules − after.rules` delta is
negative and filtered by `select(. > 0)`, and `resource_deletes` is 0 — no
`[ack-destroy]` fires. **A plan-derived guard inherits plan's blind spot.**
ADR-130 defined the entrypoint enumeration as a manual `/work`-time *probe* and
explicitly deferred making it a standing gate to #6767.

## Decision

Ship a standing, fail-closed, **live-API-querying** pre-apply gate
(`tests/scripts/lib/preapply-entrypoint-gate.sh`, wired as a separate
"Pre-apply entrypoint gate" step in `apply-web-platform-infra.yml`, after
"Terraform plan" and before the MAIN "Terraform apply", outside any
`[ack-destroy]` bypass). Plus a read-only retrospective `--audit` mode run via a
guarded `entrypoint-audit` dispatch that posts findings to #6767.

The gate asserts on plan **shape** and then queries the live API:

- **Discriminator (EXACT):** `.change.actions == ["create"] && .change.before ==
  null && .change.importing == null`. NOT `index("create")` — that also matches
  `-replace` `["delete","create"]` and create-before-destroy `["create","delete"]`,
  false-positiving a legitimate replace of an in-state ruleset. The hazard is a
  create-from-**absent-state** only. An imported/adopted resource (`importing`
  present, or steady-state `["no-op"]`/`["update"]`) is exempt in both phases.
- **Iterate the FULL `resource_changes[]` array**, never the `-target` list: a
  transitively pulled-in create must still be caught.
- **Control probe (once, if ≥1 matched row):** GET a known-populated phase
  (`http_request_dynamic_redirect`) and require HTTP 200 before trusting any
  target read. This makes a subsequent target 404 provably mean "empty phase",
  not "mis-constructed URL / bad token" — closing the fail-open 404 seam and
  disambiguating the byte-identical-403 problem. `curl --max-time` bounds a CF
  hang so it cannot hold the sole apply concurrency serializer.
- **DEFAULT-DENY HTTP handling:** PASS only on a **proven-empty** entrypoint
  (HTTP 200 with zero rules, or HTTP 404). EVERY other outcome — non-200 control
  probe, empty token, unparseable plan JSON, unclassified `kind`, a null
  URL-building field, and every non-200/404 code (000/400/401/403/429/5xx/
  non-numeric, curl failure) — routes to ONE fail-closed catch-all. On a clobber
  the `::error::` carries a copy-pasteable **singular** v4 import block
  (`zone/<zone_id>/<ruleset_id>`; the plural `zones/…` form fails as
  Authentication error 10000) plus the live rules to reproduce verbatim.

### Inclusion Principle (what the gate guards)

The #6746 hazard is precisely: *a create silently **adopts** and **whole-replaces**
a server-side singleton addressed by a **natural / composite key** that can
pre-exist outside Terraform (e.g. created directly in the CF dashboard).*
Adjudicating every `cloudflare_*` class declared in `apps/web-platform/infra/`
against that principle (cross-referenced to the destroy-guard class table at
`destroy-guard-filter-web-platform.jq:5-16` so the two cannot drift):

| Class | Key | Silent-adopt on create? | Verdict |
|---|---|---|---|
| `cloudflare_ruleset` (zone + account phase entrypoint) | `(zone\|account, phase)` — natural | **Yes** — whole-list PUT over a pre-existing entrypoint | **IN** (the one true member) |
| `cloudflare_zero_trust_tunnel_cloudflared_config` | `tunnel_id` (TF-created same apply) | No — attaches to a *fresh* tunnel | OUT (IN the day a tunnel is imported) |
| `cloudflare_bot_management` | zone singleton, TF-managed settings | No — settings overwrite, not a hidden whole-list adopt | OUT |
| `cloudflare_zone_settings_override` | zone singleton, TF-managed | No — a same-named dashboard object is a different object | OUT |
| `cloudflare_zone_dnssec` | zone singleton, TF-managed | No | OUT |
| `cloudflare_notification_policy` | TF-generated ID | No | OUT |
| `cloudflare_list` | TF-generated ID | No | OUT |
| `cloudflare_zero_trust_access_application` | TF-generated ID | No | OUT |
| `cloudflare_zero_trust_access_policy` | TF-generated ID | No | OUT |
| `cloudflare_zero_trust_access_service_token` | TF-generated ID | No | OUT |
| `cloudflare_zero_trust_tunnel_cloudflared` | TF-generated ID | No | OUT |
| `cloudflare_record` | name+type | No — errors/duplicates, never silent whole-replace | OUT |

The gate covers exactly `cloudflare_ruleset`. This is NOT a speculative
"extensible whole-list class registry" (exactly one class exists); it is a
**stated inclusion principle + a parity test** (a forcing function). The parity
test in `tests/scripts/test-preapply-entrypoint-gate.sh` FAILs if a dispatch
`-target` set gains a `cloudflare_ruleset` without a gate, or if a new
`cloudflare_*` type appears that is neither gate-covered nor adjudicated-OUT
here — making the coupling *tested*, not prose someone must remember to update.

### Dispatch-job / sibling-workflow boundary

The `workflow_dispatch` jobs and the sibling `apply-deploy-pipeline-fix.yml`
`-target` only `hcloud_*`/`doppler_*`/`random_*`/`terraform_data.*` resources.
Because `-target` transitivity flows toward *dependencies*, not dependents, none
can pull in a ruleset create. The parity test backs this as a tested invariant.

## Alternatives Considered

See the **Alternative Approaches Considered** table in the plan
`knowledge-base/project/plans/2026-07-22-feat-ruleset-entrypoint-preapply-gate-plan.md`
(extend-the-destroy-guard, plan-shape-only, `index("create")`, enumerate-the-fail-codes,
speculative-registry, recurring-cron, keep-as-prose). Not re-typed here per DHH thinness.

## Consequences

- A future whole-list `create` over a live entrypoint fails the apply loud with a
  copy-pasteable adoption remedy, instead of clobbering silently. A false positive
  fails the apply job *before* `apply` (dev friction, zero prod mutation) — the
  safe direction.
- Supersedes ADR-130's "manual probe" for the pre-apply case: ADR-130's manual
  enumeration remains the `/work`-time pre-*write* check when authoring a new
  phase; this ADR makes the pre-*apply* case a standing automated control.
- The retrospective audit confirms nothing already-lost and no current drift,
  posting once to #6767 as the system-of-record.
