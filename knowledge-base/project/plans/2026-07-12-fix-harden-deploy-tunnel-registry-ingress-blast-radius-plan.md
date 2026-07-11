---
title: "fix(infra): harden shared deploy tunnel against registry-origin dial storms (#6357)"
issue: 6357
type: fix
classification: infra
lane: cross-domain   # spec.md absent for this branch — defaulted to cross-domain (fail-closed)
brand_survival_threshold: aggregate pattern
provider: cloudflare ~> 4.0
status: ready-for-work
date: 2026-07-12
---

# 🐛 fix(infra): harden shared deploy tunnel against registry-origin dial storms (#6357)

## Overview

On 2026-07-11 (~21:06–21:16 UTC) `POST deploy.soleur.ai/hooks/deploy` returned **HTTP 502 at the
Cloudflare tunnel layer** for ~10 minutes, blocking two prod deploy jobs
(`restart-inngest-server.yml`, `web-platform-release.yml#deploy`). It self-recovered by ~21:44 UTC;
a re-run deployed `v0.212.3` via the GHCR fallback path. Concurrently, `cloudflared` on web-1 was
logging continuous `dial tcp 10.0.1.30:5000: operation was canceled` for ingressRule=2
(`registry.soleur.ai`).

**Issue #6357 proposes removing (or repointing) the `registry.soleur.ai → tcp://10.0.1.30:5000`
ingress rule, on the premise that it is a "stale leftover" pointing at a "dead origin" from a
"registry migration nbg1→hel1 (#6288)."** Research falsifies that premise (see Research
Reconciliation). The correct #6357 deliverable is **not** a removal — it is:

1. **Correct the false "stale rule" premise in `tunnel.tf`** so no future agent/operator deletes the
   live registry-push path (the highest-leverage, lowest-risk change — it defuses a destructive
   mis-fix footgun).
2. **Reduce the blast radius** a down registry origin has on the *shared* tunnel daemon by adding a
   minimal fail-fast `origin_request { connect_timeout = 5; no_happy_eyeballs = true }` scoped to
   the registry ingress rule.
3. **Close the observability gap** that let the 502 go undetected except via CI failure, by adding an
   independent edge-side/synthetic monitor for the deploy tunnel path.

The true **root cause** (registry container instability during the #6288 OOM/region-migration window)
is tracked in **#6288**; the proper **architectural** fix (decouple the deploy webhook from
co-located/sibling tunnel traffic) is tracked in **#6178** ("pollutes the deploy tunnel"). This plan
deliberately does neither — it lands the cheap, durable edge-hardening + premise correction.

## Research Reconciliation — Spec vs. Codebase

| Issue #6357 claim | Reality (verified) | Plan response |
|---|---|---|
| The rule is a **"stale leftover"** | It was added deliberately in **#6122 / ADR-096** as the registry **PUSH** ingress, with a dedicated CF Access app + service token + Doppler secrets (`tunnel.tf:44-60,133-209`). `git log tunnel.tf` shows active work through #6202 (2026-07). | **Do NOT remove.** Correct the "stale" comment; keep the rule. |
| Origin `10.0.1.30:5000` is **"dead"** because the registry **"moved to a new host per #6288"** | #6288 (`registry-region-migrate`) moved the registry **region** nbg1→hel1 and recreated the store **volume**, but the **private IP stayed `10.0.1.30`** — the `10.0.1.0/24` net spans hel1 (`variables.tf:45`; `zot-registry.tf:40 registry_private_ip="10.0.1.30"`). The origin address is **unchanged and correct**. | **Do NOT repoint** — repointing is a no-op. |
| #6288 is a **"registry migration"** PR | #6288 is an **OPEN issue**: *"zot registry container restart-loops (~4/min) post-disk-fix — likely OOM."* `closedByPullRequestsReferences: []`. It is the registry-**stability** tracker, not a migration record. | Root cause = registry transiently **down** during the OOM/ForceNew window (empty hel1 volume re-filling from GHCR). Link #6288; do not re-fix here. |
| "Remove the rule to fix the deploy 502" | Removing it breaks the CI registry-**push** path (`cloudflared access tcp --hostname registry.<base>`; `dns.tf:52-66`). Deploys still work via the GHCR fallback (`ci-deploy.sh` `ZOT_GATE_DEGRADED`), but push CI would fail. | Fix the **coupling**, not the rule: fail-fast `origin_request` + an independent deploy-path monitor. |

**Premise Validation note:** Cited refs checked — #6357 (target, OPEN), #6288 (OPEN issue, not a
migration PR), #6178 (OPEN, architectural tunnel-decoupling), #6122 (feat), ADR-096 (in-repo). The
central "stale/migrated origin" premise is **stale/misattributed**; the plan re-scopes from *remove*
to *harden + correct*. In a headless one-shot this challenge is also recorded in
`decision-challenges.md` for `ship` to surface.

## User-Brand Impact

**If this lands broken, the user experiences:** the operator (Soleur's non-technical founder) cannot
ship — a too-tight `connect_timeout` on the registry rule would fail-close the CI registry-**push**
(deploys degrade to the GHCR fallback, non-fatal), and a malformed tunnel-config apply could 502 the
deploy webhook itself, blocking all prod releases until reverted.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this change moves no user
data; it tunes an edge→origin timeout and adds a synthetic monitor. No new secret surface (the CF
Access deploy service token already exists in TF state).

**Brand-survival threshold:** aggregate pattern — the blast radius is prod-**deploy-pipeline
availability** (fleet-wide shipping capability), not any single user's data. No `single-user incident`
→ no CPO plan-time sign-off required; section present for the ship-time gate. `tunnel.tf` is a
sensitive path, so this threshold line is load-bearing for preflight Check 6.

## Hypotheses (L3→L7 — network-outage checklist)

The incident evidence was **self-pulled and captured in the issue** (no operator action); it is the
verification artifact for the lower layers. Ordering per
`plan-network-outage-checklist.md` (triggered by `502` / `timeout` / dial-`canceled`).

1. **L3 — firewall / private-net reachability to the origin.** `10.0.1.30:5000` is deny-all-public;
   web-1's `cloudflared` reaches it as a `10.0.1.0/24` member (`dns.tf:57-58`, `network.tf:55-60`).
   During #6288's ForceNew region-migrate the registry host/volume was **recreated** → the origin was
   transiently **absent**, producing `dial … operation was canceled`. **[verified via issue journal
   evidence: repeated dial-canceled for `registry.soleur.ai` only]**
2. **L3 — DNS / routing.** `deploy`, `ssh`, and `registry` all CNAME to the **same** tunnel
   `${tunnel.web.id}.cfargotunnel.com` (`dns.tf:31-66`) → they share **one** `cloudflared` daemon.
   Routing itself was healthy. **[verified: single shared tunnel confirmed in dns.tf/tunnel.tf]**
3. **L7 — TLS / edge (proxy) layer.** The 502 originated at the **CF tunnel edge**, i.e. the edge
   could not get a healthy origin stream from the web-1 daemon. **Primary hypothesis:** the registry
   dial storm (CI push retries + probes) piled up concurrent goroutines each holding an edge HA-stream
   slot for the full ~30s default `connect_timeout`, saturating the shared stream budget /
   CPU on the small cx host → no slot for the deploy-webhook stream → sibling 502. Self-recovery when
   the storm drained fits this. **[UNVERIFIED mechanism — cloudflared `--metrics` were not captured;
   this is the observability gap this plan closes. Alternative co-mechanisms: host CPU/mem starvation;
   edge-side origin-health marking. `connect_timeout` reduction mitigates all three.]**
4. **L7 — application (webhook binary).** RULED OUT as the drop point: on-host evidence showed
   `webhook`/`cloudflared`/`inngest-server` all `active`, and `localhost:9000` processed POST/GET
   (403/500 on bad sig). A request that **reaches** the binary returns 403/500, **not** 502 → the 502
   packets never reached the app. **[verified: absence of an app-layer signal is itself the signal —
   the drop is above L7-app, at the edge/daemon layer]**

**Opt-out (L7-app deeper trace):** justified — the binary was proven healthy in-window by the issue's
self-pulled evidence; no service-layer hypothesis is warranted.

## Implementation Phases

### Phase 1 — Correct the false "stale rule" premise in `tunnel.tf` (highest leverage)

Edit the comment block above the `registry.${var.app_domain_base}` ingress rule
(`apps/web-platform/infra/tunnel.tf:44-60`) to state, in-line, that this rule is the **live** ADR-096
/ #6122 registry-**push** path and is **NOT** stale:

- The `10.0.1.30:5000` origin is the current zot registry; #6288 moved the registry **region**
  nbg1→hel1 but the **private IP is unchanged** (10.0.1.0/24 spans hel1).
- **Do NOT remove or repoint** this rule — removal breaks CI registry push (`cloudflared access tcp
  --hostname registry.<base>`); repointing is a no-op.
- `dial … operation was canceled` here means the **origin is transiently down** (registry stability =
  #6288), not that the config is wrong.

**Purpose:** permanently defuse the "delete the stale rule" mis-fix the next reader would otherwise
attempt (the exact class of destructive change #6357 requested).

### Phase 2 — Fail-fast `origin_request` on the registry ingress rule (blast-radius reduction)

In the same `ingress_rule` block (`tunnel.tf:57-60`), add a **minimal** nested block (verified v4
schema — `cloudflare/cloudflare ~> 4.0`, per-ingress overrides config-level):

```hcl
ingress_rule {
  hostname = "registry.${var.app_domain_base}"
  service  = "tcp://${local.registry_endpoint}"
  origin_request {
    # Fail-fast so a DOWN registry origin (see #6288) does not pile up ~30s-held
    # dials that saturate the shared tunnel daemon's HA-stream budget and degrade
    # the sibling deploy-webhook route (the 2026-07-11 502; #6357). Mitigation,
    # not cure — root cause is registry stability (#6288); decoupling is #6178.
    connect_timeout   = 5        # INTEGER seconds (NOT "5s") — bounds the TCP dial only
    no_happy_eyeballs = true     # origin is a v4 literal → removes the v4/v6 parallel-dial fan-out
  }
}
```

Constraints (from CTO + framework-docs research + Kieran plan-review):
- **`connect_timeout` is an INTEGER (seconds) in the CF provider schema, not a Go-duration string.**
  Use `connect_timeout = 5`, NOT `"5s"` — the string form fails `terraform validate` (number
  conversion) and is the wrong grep literal. Kieran verified against the v4 provider docs; framework
  research initially reported a duration-string form, so **Phase 3 `terraform validate` is the
  arbiter** — if v4 unexpectedly rejects the integer, fall back to the duration string, but the
  integer is the verified form.
- `connect_timeout` bounds the **TCP handshake only** — a cold zot still `accept()`s immediately, and
  large-layer pushes are unaffected (no total-duration bound introduced). **Do NOT go below 5**
  (seconds) — host accept-queue backpressure could false-fail a valid push.
- **Do NOT** add `keep_alive_*` / `tcp_keep_alive` / `proxy_type` / `http_host_header` — HTTP/pool
  semantics that are no-ops (best case) or schema friction (worst) for a raw `tcp://` bridge.

### Phase 3 — Pre-apply validation

Run `terraform fmt -check` + `terraform validate` (v4 provider) against the edited root **before**
merge — this is the arbiter for the `connect_timeout` integer-vs-string question and catches any
`origin_request` schema mismatch at config-phase (the v4-vs-v5 resource-name learning applies).
Capture the `terraform plan` diff to confirm the **only** change is a single **in-place update** to
`cloudflare_zero_trust_tunnel_cloudflared_config.web`, **0 to destroy**.

### Deferred (NOT in this PR) — independent deploy-tunnel monitor → #6178

The deploy webhook path has no independent monitor today (the 502 was noticed only via CI failure).
Plan-review converged that adding one here is **out of scope**:
- The cheap Terraform-native option (`cloudflare_notification_policy` for tunnel-health) is
  **structurally unlikely to detect this failure mode** — a sibling-route 502 while the daemon stays
  *up* (Kieran) — so it would ship green-but-blind.
- The option that *does* detect it (a CF-Access-authed synthetic 502 monitor) requires wiring the
  deploy service-token secret into a third party (Better Stack), a real secret-surface cost (DHH +
  simplicity: over-scope for a transient, self-recovered, already-CI-detected incident).

So the monitor + the richer cloudflared `--metrics` export are **deferred to #6178** (which already
owns deploy-tunnel decoupling + telemetry). This plan keeps the `## Observability` section (existing
signals + the no-SSH `deploy-status` discoverability probe) but adds **no** new monitor resource —
hence Phases 1–2 touch only the already-`-target`ed tunnel config resource and need **no** workflow
edit.

## Files to Edit

- `apps/web-platform/infra/tunnel.tf` — Phase 1 comment correction + Phase 2 `origin_request` block on
  the registry ingress rule (existing resource `cloudflare_zero_trust_tunnel_cloudflared_config.web`,
  already in the apply `-target=` allow-list at `apply-web-platform-infra.yml:313`).

## Files to Create

None. (The deploy-tunnel monitor and cloudflared metrics export are deferred to #6178; no drift-test
file — its two greps live in Acceptance Criteria, and testing a comment string is brittle prose-testing
per plan-review.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/tunnel.tf` registry `ingress_rule` block contains
      `origin_request { connect_timeout = 5 ... no_happy_eyeballs = true }` (integer, not `"5s"`) and
      **no** `keep_alive_*` / `proxy_type` / `http_host_header` field. Verify:
      `awk '/hostname = "registry/,/^    }/' apps/web-platform/infra/tunnel.tf | grep -c connect_timeout`
      ≥ 1 and `... | grep -c keep_alive` = 0.
- [ ] Removal-guard (the one behavioral guard, kept per Kieran): the registry ingress rule still routes
      to the endpoint — `grep -c 'tcp://\${local.registry_endpoint}' apps/web-platform/infra/tunnel.tf`
      ≥ 1. (Loosened from `= 1` so a Phase-1 comment that names the same interpolated token does not
      false-fail.)
- [ ] `terraform fmt -check` passes and `terraform validate` passes against the v4-pinned root (this is
      the arbiter for the `connect_timeout` type).
- [ ] `terraform plan` (captured in PR) shows a single **in-place update** to
      `cloudflare_zero_trust_tunnel_cloudflared_config.web` and **0 to destroy** (no net-new resource,
      no `-target=` workflow edit).
- [ ] PR body uses **`Ref #6357`** (not `Closes`) — this is an ops-remediation whose real close
      happens post-apply (see below). Also `Ref #6288`, `Ref #6178`.

### Post-merge (operator / automated)

- [ ] Merge to `main` auto-applies via `apply-web-platform-infra.yml` (tunnel config resource is in the
      `-target=` set). **Automation: feasible** — no operator SSH; the workflow applies the remote
      tunnel config. Confirm the workflow run is green.
- [ ] No-SSH deploy-path health probe returns healthy: `GET deploy.soleur.ai/hooks/deploy-status`
      (HMAC via `X-Signature-256`, handler `cat-deploy-state.sh`) returns the last deploy state, and a
      bad-sig `POST deploy.soleur.ai/hooks/deploy` returns the webhook's **403/500** (not 502) —
      proving the tunnel→webhook path is healthy. **Automation: feasible** (curl + HMAC; no SSH).
- [ ] Close #6357 via `gh issue close 6357` only **after** the apply is green and the probe passes
      (ops-remediation close pattern).

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/tunnel.tf`: **single** in-place `origin_request` block on
  `cloudflare_zero_trust_tunnel_cloudflared_config.web` (existing resource) + a comment correction. No
  net-new resource.
- Providers/pins: `cloudflare/cloudflare ~> 4.0` (existing). **No new provider, no new no-default
  `TF_VAR_*`, no new secret.** (The registry-push CF Access token is already provisioned.)

### Apply path
(b) cloud-init + idempotent bootstrap → **N/A**; this is a **Cloudflare-managed remote tunnel config**
(`config_src = "cloudflare"`) pushed by Terraform. Chosen path: **merge-triggered auto-apply**
(`apply-web-platform-infra.yml`, `-target`-scoped; the tunnel config resource is already targeted at
line 313, so **no workflow edit is needed**). Expected blast-radius: an in-place edge-config update —
no host reboot, no container restart, no downtime.

### Distinctness / drift safeguards
- No `dev`/`prd` split concern (single prod tunnel). `lifecycle.ignore_changes = [secret, config_src]`
  on the tunnel resource (`tunnel.tf:21-23`) is unaffected — we edit the **config** resource, not the
  tunnel resource. State holds no new secret. Re-run `terraform plan` immediately pre-merge to confirm
  no accumulated unrelated drift rides along (drift-runbook learning).

### Vendor-tier reality check
- N/A — no net-new monitored resource (the deploy-tunnel monitor is deferred to #6178). No tier gate.

## Observability

```yaml
liveness_signal:
  what: post-apply confirmation the deploy tunnel→webhook path is healthy (no-SSH probe)
  cadence: post-merge (apply green) + on-demand; independent deploy-tunnel monitor deferred to #6178
  alert_target: ops@jikigai.com (existing Better Stack team member / CF notification email)
  configured_in: apps/web-platform/infra/hooks.json.tmpl (deploy-status endpoint, existing); monitor → #6178
error_reporting:
  destination: GitHub Actions run status (deploy jobs) today; independent page deferred → #6178
  fail_loud: yes — a failed deploy job goes red; the #6178 monitor will add an independent page
failure_modes:
  - mode: registry origin down → dial-storm degrades sibling deploy route (the #6357 incident)
    detection: no-SSH deploy-status probe (below) returns 502; deploy jobs go red; independent monitor → #6178
    alert_route: GitHub Actions run status; ops@jikigai.com (post-#6178 monitor)
  - mode: registry origin down (root cause) — registry container OOM/restart-loop
    detection: betteruptime_heartbeat.registry_prd (exists; currently PAUSED — un-pause tracked in #6288)
    alert_route: ops@jikigai.com
  - mode: registry-PUSH broken by too-tight connect_timeout
    detection: CI release push step fails / falls back to GHCR (ZOT_GATE_DEGRADED in workflow logs)
    alert_route: GitHub Actions run status (release workflow)
logs:
  where: Cloudflare tunnel edge (GraphQL/Logpush, edge-side); cloudflared --metrics on host (deferred → #6178)
  retention: Cloudflare default; GitHub Actions run logs (90d)
discoverability_test:
  command: 'curl -s -H "X-Signature-256: <hmac>" https://deploy.soleur.ai/hooks/deploy-status  # returns last deploy state; bad-sig POST /hooks/deploy → 403/500 not 502'
  expected_output: last deploy state JSON (healthy) / 403 on bad sig — proves tunnel→webhook path alive without SSH
```

**Affected-surface note:** the true diagnostic signal for the L7-edge saturation hypothesis is
cloudflared `--metrics` (`concurrent_requests_per_tunnel`, `ha_connections`, origin-dial errors). That
export **and** the independent deploy-tunnel monitor are a larger lift (metrics-port reachability;
CF-Access-authed synthetic) and are scoped to **#6178**. This plan closes the diagnosis (root cause =
#6288) and lands the cheap edge-hardening; the no-SSH `deploy-status` probe is the interim
discoverability path.

## Architecture Decision (ADR / C4)

**No new ADR; no C4 change.** This is parameter hardening + a comment correction **within** the
existing architecture governed by **ADR-008** (Cloudflare Tunnel deployment) and **ADR-096** (self-hosted
zot over the tunnel bridge). Neither ADR constrains per-ingress `origin_request`; neither is reversed or
extended. The architectural decision to **decouple** the deploy webhook from sibling tunnel traffic is a
genuine ADR-shaped question — it is **owned by #6178**, not this plan.

**### C4 views — no impact (enumeration cited).** All three model files were read
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Checked, and each is
already modeled or unchanged:
- External **human actors**: none added (operator/founder + contributor already modeled; no new
  correspondent/recipient).
- External **systems / vendors**: none added — Cloudflare Tunnel (`model.c4:176-179`) and zot registry
  (`model.c4:258-261`) already exist; no new vendor edge.
- **Containers / data stores**: none added.
- **Access relationships**: unchanged — the edge→origin routing (tunnel→zot, tunnel→webhook) already
  exists; `origin_request` tunes an **existing** edge, adds no new relationship, and shares no data
  differently. Adding a monitor is an observability edge, not a system-boundary change.

## Domain Review

**Domains relevant:** Engineering (infra) only.

### Engineering (CTO / platform-strategist)
**Status:** reviewed
**Assessment:** Reject the literal remove/repoint (rule is live, not stale). Highest leverage = the
`tunnel.tf` premise correction (defuses the destructive mis-fix footgun); add a **narrow**
`origin_request` (`connect_timeout` + `no_happy_eyeballs` only — skip keep-alive/pool tuning,
meaningless for raw `tcp://`). `connect_timeout` bounds the TCP dial only → safe for cold zot +
large-layer pushes at ≥5s; do not drop below 5s. The sibling-degradation mechanism (shared-daemon
HA-stream saturation from ~30s-held dials) is a **reasoned hypothesis, not proven** — cloudflared
metrics were never captured; `connect_timeout` mitigates all candidate mechanisms regardless.
**Plan-review refinement (DHH + Kieran + simplicity):** the independent deploy-tunnel monitor CTO
raised is deferred to #6178 — the cheap `cloudflare_notification_policy` is structurally blind to a
sibling-route 502 while the daemon stays up, and the real detector (CF-Access synthetic) is over-scope
for a transient self-recovered incident. Defer real tunnel decoupling + metrics + monitor to #6178.

**Product/UX Gate:** NONE — no UI-surface file in Files to Edit (single infra `.tf` change). No
mechanical UI-surface override fired.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open scope-out touching
`tunnel.tf`, `apply-web-platform-infra.yml`, `uptime-alerts.tf`, or `origin_request`.

## Risks & Sharp Edges

- **Empty/placeholder `## User-Brand Impact`** fails `deepen-plan` Phase 4.6 — the section is filled
  (threshold `aggregate pattern`).
- **`connect_timeout` is an INTEGER, not `"5s"`** (Kieran, verified vs v4 provider docs). Use
  `connect_timeout = 5`; the string form fails `terraform validate`. `terraform validate` (Phase 3) is
  the arbiter — if v4 unexpectedly rejects the integer, the duration string is the fallback.
- **`connect_timeout` too tight** could false-fail a cold/loaded zot push. Mitigation: pin **5** (CTO
  floor); do not go to 1–2. `connect_timeout` bounds the **TCP dial**, not push/layer-upload duration,
  so large pushes are safe.
- **v4-vs-v5 provider naming** — this root is pinned `~> 4.0` and uses `ingress_rule {}` (v4); v5 renames
  to `ingress {}`. `origin_request` field names are stable across v4/v5, but keep all edits in the v4
  form and gate on `terraform validate` (Phase 3). Do not `-upgrade` the provider in this PR.
- **A cheap tunnel-health monitor would be green-but-blind** (Kieran): CF tunnel-level alert types fire
  on daemon degradation, not on a single ingress route returning 502 while the daemon is up — so the
  #6357 failure mode would not be caught. The real detector (CF-Access-authed synthetic 502) carries a
  secret-surface cost. Both deferred to **#6178** rather than shipping blind detection.
- **`Closes #6357` at merge would false-resolve** — the real fix lands at **post-merge apply**; use
  `Ref #6357` + a post-apply `gh issue close` (ops-remediation close pattern).
- **Deferred work has trackers already:** registry stability → **#6288** (open); tunnel decoupling +
  cloudflared metrics export → **#6178** (open). No new deferral issue required.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Remove the `registry.soleur.ai` ingress rule (issue's literal ask) | **Rejected** — rule is live (ADR-096/#6122 push path); removal breaks CI push. |
| Repoint the rule at a "current registry host" | **Rejected** — no-op; the private IP `10.0.1.30:5000` is unchanged post-#6288. |
| Give the registry its own dedicated `cloudflared` tunnel/daemon | **Deferred → #6178** — the correct architectural decoupling, but YAGNI for a transient self-recovered incident; over-scoped for #6357. |
| Add an independent deploy-tunnel monitor now (notification policy or CF-Access synthetic) | **Deferred → #6178** — the cheap notification policy is blind to a daemon-up sibling 502 (Kieran); the real synthetic detector needs a service-token secret in a 3rd party — over-scope for a transient, CI-detected, self-recovered incident (DHH + simplicity). |
| Export cloudflared `--metrics` → Better Stack | **Deferred → #6178** — the richest diagnostic signal, but a larger lift (metrics-port reachability). |
| Fix the registry OOM / un-pause the registry heartbeat | **Deferred → #6288** — the true root cause; out of scope here. |
| Ship a drift-guard `*.test.sh` asserting the comment/timeout persist | **Rejected** — testing a comment string is brittle prose-testing (DHH + simplicity); the one behavioral guard lives as an AC grep. |
| Config-wide (`config { origin_request }`) fail-fast instead of per-ingress | **Rejected** — broader than needed; per-ingress override is exact and leaves the localhost deploy/ssh origins untouched. |

## Non-Goals

- Fixing the registry container's OOM/restart-loop instability (**#6288**).
- Architecturally decoupling the deploy webhook from sibling tunnel traffic (**#6178**).
- cloudflared `--metrics` export / host-side tunnel telemetry (**#6178**).
- Un-pausing the registry liveness heartbeat (**#6288**).
- Any change to the CF Access apps, service tokens, or Doppler secrets around the tunnel.
