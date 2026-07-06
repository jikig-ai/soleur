---
title: "fix(infra): probe web-1 uptime over a single-level hostname (Universal SSL depth)"
type: fix
date: 2026-07-06
branch: feat-one-shot-web1-uptime-single-level-hostname
lane: cross-domain # no spec.md for this branch (direct one-shot plan) → fail-closed default per plan skill
brand_survival_threshold: none
---

# 🐛 fix(infra): probe web-1 uptime over a single-level hostname (Universal SSL depth)

## Overview

Better Stack auto-paused the uptime monitor **"soleur uptime web-1"** for sustained
downtime. The host is **not** down — the probe URL was never certificate-servable.

`betteruptime_monitor.web_host` (`apps/web-platform/infra/uptime-alerts.tf:87-110`)
probes `https://web-1.app.soleur.ai/health` with `verify_ssl = true`. Its CF-proxied
probe record `cloudflare_record.web_host` (`apps/web-platform/infra/dns.tf:32-41`)
is named `"${each.key}.app"` → `web-1.app.soleur.ai` — a **two-level** subdomain.

Cloudflare's **Universal SSL** edge certificate covers only `soleur.ai` and the
**one-level** wildcard `*.soleur.ai` (verified live: `openssl s_client -connect app.soleur.ai:443`
→ SAN = `soleur.ai, *.soleur.ai`). A wildcard matches exactly one label, so the CF
edge has **no certificate** for the two-level `web-1.app.soleur.ai`; every HTTPS probe
fails the TLS handshake at the edge (SSL alert 40 / `handshake_failure`) before it ever
reaches the origin. Confirmed live: `app.soleur.ai/health` → 200 (app healthy), but
`web-1.app.soleur.ai/health` fails the handshake. The monitor could never have gone green.

There is no Advanced Certificate Manager / Total TLS resource anywhere in the repo
(Universal SSL only), so the two-level hostname is uncoverable without a paid cert.

**Fix (free, minimal):** rename the probe hostname down one level to `web-1.soleur.ai`
— a single-label subdomain the existing `*.soleur.ai` wildcard already covers. Applying
the changed `betteruptime_monitor.web_host` in the same Terraform run reconciles Better
Stack's auto-pause and re-enables the monitor (`paused = false` is unchanged). The
`each.key` generalization is preserved, so web-2 gets `web-2.soleur.ai` automatically
when the #5274 cutover flips its `monitored` flag to true.

## User-Brand Impact

**If this lands broken, the user experiences:** the "soleur uptime web-1" monitor stays
red/auto-paused — the operator (non-technical founder) keeps getting a false-down page (or,
worse, silence), and per-host absence detection for web-1 remains dark. No customer-facing
surface is affected; the apex + Sentry monitors still prove overall reachability.

**If this leaks, the user's data is exposed via:** N/A — this changes a monitoring probe
hostname and a DNS record name. No user data, secrets, auth, or PII are touched. The record
stays proxied, preserving the CF-IP-only origin firewall (no origin-IP exposure).

**Brand-survival threshold:** none — internal observability restoration on an already-provisioned
surface. `reason: probe-hostname rename + monitor unpause; no user-data, auth, schema, or API
surface touched; diff is confined to two .tf files (DNS record name + monitor URL string).`

## Research Reconciliation — Premise Validation (verified live against repo)

| Claim in task | Reality (verified) | Plan response |
|---|---|---|
| `cloudflare_record.web_host` uses `name = "${each.key}.app"` | Confirmed `dns.tf:36` | Rename to `name = each.key` |
| `betteruptime_monitor.web_host` probes `https://${each.key}.app.soleur.ai/health` | Confirmed `uptime-alerts.tf:91` | Change to `https://${each.key}.soleur.ai/health` |
| Both resources are in the auto-apply `-target` set | Confirmed `apply-web-platform-infra.yml:361` (`cloudflare_record.web_host`) + `:362` (`betteruptime_monitor.web_host`), the main `-target` plan, NOT the SSH set | Merge auto-applies both |
| `paused = false` already set | Confirmed `uptime-alerts.tf:109` | Leave as-is — apply reconciles Better Stack's auto-pause |
| No paid ACM / Total TLS resource in repo | Confirmed — no `cloudflare_certificate_pack` / `total_tls` anywhere | Single-level rename is the free fix; do NOT add a paid cert |
| `for_each` gates on `if v.monitored` | Confirmed identical filter on both resources (`dns.tf:33`, `uptime-alerts.tf:88`); only web-1 has `monitored = true` (`variables.tf:85-86`) | Filter UNCHANGED → web-2's server is not dragged into the apply; no premature provisioning |
| Renaming `cloudflare_record.name` is in-place | The resource address `cloudflare_record.web_host["web-1"]` is unchanged (only the `name` attribute changes) → in-place UPDATE, not destroy/recreate; no `moved` block, no maintenance window | Apply on merge, no window |
| Test assertions on the two-level probe hostname | grep of `apps/web-platform/infra/**/*.{tf,tftest.hcl,test.sh,sh}` for `.app.soleur.ai/health`, `web-1.app`, `${each.key}.app` → **zero** probe-hostname assertions (all `web_host`/`WEB_HOST` hits are `WEB_HOST_PRIVATE_IPS` / `var.web_hosts` private-IP parity, unrelated) | No test file needs editing; guard grep documented below |

**No external premises to validate** (no cited GitHub issues/PRs to re-check as blockers).
The load-bearing probe record is `cloudflare_record.web_host`, NOT the app ingress
`cloudflare_record.app` (`dns.tf:13-20`) — the latter is untouched.

## Hypotheses (L3→L7 network-outage discipline — trigger: "handshake")

Root cause is definitively at **L7 (TLS/edge)**, verified live. The lower layers are
verified clean, ruling out an origin/firewall/service misdiagnosis:

- **L3 — DNS / routing:** `web-1.app.soleur.ai` resolves (the proxied A record exists in
  state and returns a CF edge IP). DNS is NOT the failure — the packet reaches the CF edge.
  *Verified:* the probe fails during TLS handshake, which only happens after DNS + TCP succeed.
- **L3 — Origin firewall:** origin 443 is gated to CF IPs (`firewall.tf`). Irrelevant here —
  the probe never reaches the origin; it dies at the CF edge handshake. Not the cause.
- **L7 — TLS / edge (ROOT CAUSE):** `openssl s_client -connect app.soleur.ai:443` shows the
  edge cert SAN = `soleur.ai, *.soleur.ai`. `*.soleur.ai` matches one label only, so
  `web-1.app.soleur.ai` (two labels) has no edge cert → handshake fails (SSL alert 40).
  `verify_ssl = true` + `monitor_type = status` → the monitor records a failure and, after
  sustained failures, Better Stack auto-paused it. **This is the bug.**
- **L7 — Application:** `app.soleur.ai/health` → 200 (app is healthy). The service layer is
  NOT the problem — a service-layer fix would be non-causal. Rules out "web-1 is down".

Fix acts at L7: move the probe hostname under the covered wildcard depth (`web-1.soleur.ai`),
so the edge presents `*.soleur.ai` and the handshake completes → CF proxies to origin → 200.

## Implementation Phases

### Phase 1 — Rename the CF-proxied probe record (dns.tf)

`apps/web-platform/infra/dns.tf`, resource `cloudflare_record.web_host`:

- Line 36: `name = "${each.key}.app"` → `name = each.key` (→ `web-1.soleur.ai`, one level).
- Update the block comment (lines 22-31) that says `web-<n>.app.soleur.ai` to the new
  single-level hostname AND state the reason: Universal SSL's `*.soleur.ai` wildcard covers
  one subdomain label only, so a two-level `web-<n>.app.soleur.ai` has no edge cert and every
  proxied HTTPS probe fails the edge TLS handshake.

### Phase 2 — Point the monitor at the single-level hostname (uptime-alerts.tf)

`apps/web-platform/infra/uptime-alerts.tf`, resource `betteruptime_monitor.web_host`:

- Line 91: `url = "https://${each.key}.app.soleur.ai/health"` → `url = "https://${each.key}.soleur.ai/health"`.
- Update the comment (line 80) referencing `web-<n>.app.soleur.ai/health` to the single-level form.
- Leave `paused = false` (line 109) as-is — applying it reconciles Better Stack's auto-pause and
  re-enables the monitor in the same apply.

### Phase 3 — Guard sweep (verification only, expected no-op)

Grep the infra tree for stale two-level probe assertions and confirm none remain:

```bash
grep -rniE '\.app\.soleur\.ai/health|web-[0-9]\.app|\$\{each\.key\}\.app' \
  apps/web-platform/infra --include='*.tf' --include='*.tftest.hcl' --include='*.test.sh' --include='*.sh'
```

Expected: only the two edited `.tf` files (now single-level) — no test fixture asserts the
probe hostname, so no test expectation edits are required. If a hit surfaces outside the two
edited files, update it to the single-level hostname in this PR.

## Files to Edit

- `apps/web-platform/infra/dns.tf` — `cloudflare_record.web_host`: `name` attr + block comment.
- `apps/web-platform/infra/uptime-alerts.tf` — `betteruptime_monitor.web_host`: `url` attr + comment.

## Files to Create

- None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `dns.tf` `cloudflare_record.web_host.name` is `each.key` (no `.app` suffix); block comment
  updated to the single-level hostname + Universal-SSL-depth reason.
      Verify: `grep -nE 'name\s*=\s*each\.key' apps/web-platform/infra/dns.tf` returns the web_host line;
      `grep -c '${each.key}.app' apps/web-platform/infra/dns.tf` == 0.
- [ ] `uptime-alerts.tf` `betteruptime_monitor.web_host.url` is `https://${each.key}.soleur.ai/health`.
      Verify: `grep -c 'app.soleur.ai/health' apps/web-platform/infra/uptime-alerts.tf` == 0;
      `grep -c '${each.key}.soleur.ai/health' apps/web-platform/infra/uptime-alerts.tf` == 1.
- [ ] `paused = false` unchanged on `betteruptime_monitor.web_host`.
- [ ] `for_each` filter `if v.monitored` unchanged on BOTH resources (no premature web-2 provisioning).
- [ ] Guard grep (Phase 3) returns only the two edited `.tf` files at single-level; no stale two-level
      probe assertion anywhere in `apps/web-platform/infra/`.
- [ ] `cd apps/web-platform/infra && terraform fmt -check` passes on both files (or `terraform validate`
      if creds-free validation is available).
- [ ] Both resources remain in the main `-target` set of `apply-web-platform-infra.yml`
      (`cloudflare_record.web_host` + `betteruptime_monitor.web_host`) — NOT the SSH provisioner set.

### Post-merge (auto-applied, no operator action)

- [ ] Merge to `main` triggers `apply-web-platform-infra.yml`; the `-target` apply updates
      `cloudflare_record.web_host["web-1"]` in place (new `name`) and `betteruptime_monitor.web_host["web-1"]`
      (new `url` + unpause) in the same run. No destroy/recreate of the record.
- [ ] `curl -sS -o /dev/null -w '%{http_code}' https://web-1.soleur.ai/health` returns `200`
      (edge TLS handshake now succeeds under `*.soleur.ai`; CF proxies to origin).
- [ ] Better Stack "soleur uptime web-1" monitor flips from auto-paused → active and reports up.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/dns.tf` — `cloudflare_record.web_host` (cloudflare provider, declared `main.tf`).
- `apps/web-platform/infra/uptime-alerts.tf` — `betteruptime_monitor.web_host` (betterstackhq provider, `main.tf`).
- No new providers, variables, or secrets. No new Terraform root.

### Apply path
- **(c-adjacent) in-place `-target` update** via the merge-triggered `apply-web-platform-infra.yml`
  (`github.event_name == 'push'` → `manual-rerun`/default path). Renaming `cloudflare_record.name`
  is an in-place UPDATE (resource address `["web-1"]` unchanged), NOT a destroy/recreate — no `moved`
  block, no maintenance window, no blast radius on the load-bearing app ingress `cloudflare_record.app`.
  The Better Stack monitor URL change + auto-pause reconcile in the same apply. No bootstrap script needed.

### Distinctness / drift safeguards
- `for_each = { for k, v in var.web_hosts : k => v if v.monitored }` unchanged on both resources ⇒
  web-2 (`monitored = false`) stays excluded from the `-target` apply; `hcloud_server.web["web-2"]`
  is NOT transitively pulled. `terraform plan` must show **no create** of any web-2 resource.
- Record stays `proxied = true` ⇒ origin-IP-only firewall preserved; no raw-origin exposure.

### Vendor-tier reality check
- Better Stack free tier: monitor URL + unpause are free-tier operations. The paid-tier
  `betteruptime_policy.uptime` escalation stays `count`-gated on `var.betterstack_paid_tier` (untouched).
- Universal SSL (free) `*.soleur.ai` covers the new single-level hostname — no ACM/Total TLS spend.

## Observability

```yaml
liveness_signal:
  what: "betteruptime_monitor.web_host['web-1'] HTTPS status probe of https://web-1.soleur.ai/health"
  cadence: "check_frequency = 180s (3 min), 60s confirmation"
  alert_target: "email = true (ops@jikigai.com via Better Stack account recipient); paid-tier escalation policy gated on var.betterstack_paid_tier"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf:87-110"
error_reporting:
  destination: "Better Stack incident (this monitor); apex reachability also covered by betteruptime_monitor.soleur_apex + 4 Sentry uptime monitors"
  fail_loud: "monitor pages on non-200 / handshake failure; this fix RESTORES the signal that was dark (auto-paused)"
failure_modes:
  - mode: "web-1 origin dead / never-booted"
    detection: "CF 522 / non-200 from https://web-1.soleur.ai/health → monitor fails"
    alert_route: "Better Stack incident + email"
  - mode: "edge cert regression (hostname pushed back to >1 label)"
    detection: "TLS handshake failure at edge → monitor fails; guard grep (Phase 3) blocks reintroduction in CI"
    alert_route: "Better Stack incident; pre-merge grep AC"
logs:
  where: "Better Stack monitor history (vendor dashboard) + incident emails"
  retention: "Better Stack free-tier retention"
discoverability_test:
  command: "curl -sS -o /dev/null -w '%{http_code}' https://web-1.soleur.ai/health"
  expected_output: "200"
```

## Open Code-Review Overlap

None — no open `code-review` issue references `dns.tf` or `uptime-alerts.tf` web_host.

## Domain Review

**Domains relevant:** none

Infrastructure/observability change (DNS record name + uptime-monitor URL). No user-facing
UI surface (no `components/**/*.tsx`, no `app/**/page.tsx`), no product/legal/finance implications.
Product/UX Gate: NONE (no UI-surface file in Files to Edit).

## Architecture Decision (ADR/C4)

Skipped — bug fix on an already-provisioned surface. No ownership/tenancy boundary move, no new
substrate, no resolver/trust-boundary change, no ADR reversal. The monitoring topology (Better
Stack as external vendor-isolated uptime probe of the web hosts) is unchanged; only the probe
hostname's subdomain depth changes. A competent engineer reading the existing ADRs + C4 would
not be misled about the system after this ships.

## Test Scenarios

- **Static (pre-merge):** grep ACs above confirm the `name`/`url` attrs and comment updates;
  `terraform fmt -check` on both files.
- **Guard:** Phase 3 grep proves no stale two-level probe assertion remains in the infra tree.
- **Post-apply (behavioral):** `curl https://web-1.soleur.ai/health` → 200; Better Stack monitor
  flips active. `terraform plan` on the `-target` set shows in-place update of the two resources
  and **no create** of any web-2 resource.

## PR Body Notes

- **Deploy path:** merging to `main` fires `apply-web-platform-infra.yml`; its main `-target`
  plan (the "~80 non-SSH resources" set) already includes `cloudflare_record.web_host` (line 361)
  and `betteruptime_monitor.web_host` (line 362), so the apply performs the Cloudflare record
  rename (in-place) and the Better Stack URL change + auto-pause reconcile in one run. No SSH,
  no operator step, no maintenance window.
- **Out of scope (no repo change):** the operator changed the Better Stack alert recipient from
  jean.deruelle@jikigai.com → ops@jikigai.com — that is a Better Stack UI account setting
  (Terraform only exposes `email = true`), already done by the operator. The infra alert shell
  scripts already send to ops@jikigai.com. Sentry uptime monitors are all single-level
  (`soleur.ai` / `www.soleur.ai`) and unaffected by this depth fix.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 —
  this one is filled (threshold `none` with a reason bullet).
- **Do NOT convert `cloudflare_record.web_host` to add/remove `for_each` keys or change the
  resource address** — a name-attribute change is in-place, but an address change (singleton↔keyed,
  or dropping the `if v.monitored` filter) would destroy/recreate and could drag `hcloud_server.web["web-2"]`
  into a routine apply. Keep the filter and address exactly as-is; only the `name` string changes.
- **The origin app must answer `/health` for Host `web-1.soleur.ai`.** It already had to answer for the
  previous non-primary Host `web-1.app.soleur.ai`, and `/health` is Host-agnostic (process-liveness), so
  this holds — but the post-apply `curl https://web-1.soleur.ai/health` == 200 check is the load-bearing
  confirmation, not the code diff.
- **Universal SSL depth is one label.** If a future change ever pushes any probe hostname back to two
  levels (`x.y.soleur.ai`), the edge handshake breaks again with no cert. The Phase 3 guard grep is the
  cheap regression brake; keep it.
