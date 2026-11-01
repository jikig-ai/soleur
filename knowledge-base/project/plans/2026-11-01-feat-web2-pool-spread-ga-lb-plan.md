---
title: "feat: Pool web-2 into the GA load balancer (drained) + repair the health monitor's dead signal"
type: feat
date: 2026-11-01
slug: feat-web2-pool-spread-ga-lb
branch: feat-one-shot-6027-web2-pool-spread
issue: 6027
lane: cross-domain
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All production mutation in this plan routes through existing Terraform + gated
     dispatch arms (cf-lb-overlay.yml / apply-web-platform-infra.yml). References to
     "operator" below are descriptive: the workflow's own steer text, the `manual-rerun`
     input literal, email alert targets, and the #9358-recorded token prerequisite — no
     manual provisioning step is prescribed. -->

# feat: Pool web-2 into the GA load balancer (drained) + repair the health monitor's dead signal

## Overview

Continuation of clustering epic #6027 after the #11181 non-cutover track completed
2026-11-01: the Cloudflare GA load balancer is live on app.soleur.ai (monitor + web-1
pool + LB, applied via `cf-lb-overlay.yml` ga-overlay). A live read-only check run during
planning confirmed the resume brief's hypothesis: the monitor is `type=https` probing
origin :443 while the origin publishes only HTTP :80 and :3000 (never :443), so CF reports the web-1 origin
permanently **down** (`failure_reason: "TCP connection failed"`) and the LB routes solely
through `fallback_pool_id` — which points at the same pool, making the dead health signal
invisible. This plan repairs the monitor to probe the path traffic actually takes
(HTTP :80, matching the Flexible-SSL config rule), lands web-2 in the pool as a **drained
(weight-0) origin** — the ADR-068 §(b) shape, which the anti-pooling gate's standby branch
already passes — declares the steering shape, extends the `cf-lb-overlay` arm/gate pair so
these updates are applicable through the sanctioned dispatch path, and rewrites the
committed-config anti-pooling assertion to the drained-shape invariant. The weight 0→1
flip and the web-1 `placement_group_id` attach reboot are #6027 window acts encoded as
gated follow-through, not in-PR implementation; all Cloudflare/Hetzner mutation is
post-merge and dispatch-gated.

## Problem Statement

Three independent defects/forks land in one PR:

1. **Dead health signal (live-verified).** `cloudflare_load_balancer_monitor.web` is
   `type = "https"` with no `port` → CF probes origin :443 over TLS. web-1's container
   publishes `0.0.0.0:80:3000` and `0.0.0.0:3000:3000` (cloud-init.yml:808-809); nothing
   listens on :443. Live CF
   API read (2026-11-01): pool `web-1` origin `135.181.45.178` → `healthy:false`,
   `failure_reason:"TCP connection failed"`. The B1 self-fallback masks it — traffic flows,
   steering evidence does not. The committed comment's premise ("origin firewall permits
   CF IPs on 443") conflates *permitted* with *listened*.
2. **web-2 is not a pool member.** ADR-068 §(b) prescribes "web-2 sits in the pool at
   weight 0 (drained) until GA"; the F3 implementation kept it structurally absent (B2).
   Drained membership is the correct pre-flip shape: it gives web-2 a health signal AND
   keeps it out of rotation — the `lb-weight-gate.sh` top-guard passes it by design.
3. **The apply machinery only creates.** `cf_lb_gate_ga` accepts `create`-only plans with
   origins ⊆ {web-1}; the monitor fix and the drained origin are `update` actions on
   existing resources — currently inapplicable through any sanctioned path.

## Proposed Solution

- **Monitor fix (in-PR):** `type = "http"`, `port = 80` — the Flexible-SSL data path is
  HTTP to origin :80 (dns.tf `seo_config_rules` `ssl = "flexible"`; firewall.tf permits CF
  IPs on :80). Reachability-only on `/health` per ADR-068 §(b) — `expected_codes = "200"`
  retained (tighter than the ADR's `2xx`, same reachability-only semantics).
- **Drained pooling (in-PR):** second `origins{}` block on `cloudflare_load_balancer_pool.web_1`:
  `name="web-2"`, `address=hcloud_server.web["web-2"].ipv4_address`, `enabled=true`,
  **`weight=0`** — NOT the brief's `weight=1`. The 0→1 flip is the #6027 window act.
- **Steering (in-PR):** `steering_policy` on the LB stays `"off"` (pool-level knob; one
  default pool). Declare `origin_steering { policy = "random" }` on the pool — pending
  technical ruling; provider default made explicit. See `## Alternative Approaches`.
- **Apply machinery (in-PR):** two new dispatch arms on `cf-lb-overlay.yml` +
  matching graders in `cf-lb-overlay-gate.sh`, each carrying the repo's per-arm
  confirm-literal + `environment:` conventions; `cf_lb_gate_ga` origins pin widened to
  {web-1, web-2} so a create-path recreate cannot silently drop web-2.
- **Committed-config guard rewrite (in-PR):** `lb-weight-gate.test.sh` Condition C
  asserts the drained-shape invariant instead of structural absence.
- **Observability (in-PR):** `cloudflare_notification_policy` with
  `alert_type = "load_balancing_health_alert"` (verified in the account's
  `available_alerts` 2026-11-01 — unlike the Enterprise-gated `http_alert_*` family),
  filtered to the web pool, so the next dead-origin state pages instead of hiding.
- **Gated follow-through (not in-PR):** ga-monitor-fix dispatch → health green; then when
  flip preconditions hold (`GIT_DATA_STORE_ENABLED=true`, `GIT_DATA_LUKS_CUTOVER_AT`+soak,
  owner-side relay bound, `WORKSPACES_LUKS_CUTOVER_AT`+soak — today: workspaces marker
  present 2026-10-29, the rest **not met**), the #6027 orchestrator runs
  `lb-weight-gate-with-marker.sh` + the on-host runtime-bind probe → weight 0→1 window
  diff → drain web-1 → `ignore_changes` removal → placement-group attach reboot →
  restore → AC4/AC11 soak → ADR-068 `adopting`→`accepted`.

## Technical Approach

### Architecture

The serving path becomes `client → CF edge → LB (app.soleur.ai) → pool web_1 →
origins {web-1@w1, web-2@w0}`. The drained origin is health-monitored but receives no
traffic — CF never routes to a weight-0 origin. The monitor probes each origin on its
real listener (:80/HTTP), giving per-origin health truth before the flip rather than
discovering it mid-window. `default_pool_ids` and `fallback_pool_id` are unchanged
(B1 preserved: disabled LB still degrades to web-1 via the retained A record +
fallback pool).

### Implementation Phases

#### Phase 1 — cloudflare-lb.tf config changes

- `cloudflare_load_balancer_monitor.web`: `type` → `"http"`, add `port = 80`; rewrite the
  firewall comment (the permit is :80; :443 has no listener).
- `cloudflare_load_balancer_pool.web_1`: append second `origins{}` block (web-2,
  enabled, weight 0); add `origin_steering { policy = "random" }` (pending ruling).
- Rewrite the B2 comments (cloudflare-lb.tf:10-11, 35, 52, 62, 70) from "structurally
  absent" to "drained member — weight 0 until the #6027 window flip".
- Add `cloudflare_notification_policy.web_lb_health` (`load_balancing_health_alert`,
  filters: pool_id + event_source + new_health; email_integration id
  `var.cf_notification_email`).
- Success criterion: `terraform plan` (routine -target set) shows only the new
  notification policy; the GA trio stay out of the routine apply's scope by design.

#### Phase 2 — cf-lb-overlay arm + gate extension

- `.github/workflows/cf-lb-overlay.yml`: two new `arm` choices —
  `ga-monitor-fix` (confirm `FIX-GA-LB-MONITOR`; applies `update` on
  `cloudflare_load_balancer_monitor.web` only) and `ga-pool-update` (confirm
  `UPDATE-GA-LB-POOL`; applies `update` on `cloudflare_load_balancer_pool.web_1` and, if
  the steering diff lands there, `cloudflare_load_balancer.app`). Both reuse the existing
  job skeleton: `environment: web-platform-infra-apply`, R2 backend, saved-plan grading.
  `ga-pool-update` carries a `mode` dispatch input (`drain`/`serve`); `serve` mode runs
  `lb-weight-gate-with-marker.sh` fail-closed before plan (env: `prd` +
  `prd_workspaces_luks_marker` via dedicated tokens — the wrapper needs a read token on
  the marker config; provisioning one is the #9358-recorded prerequisite).
- `tests/scripts/lib/cf-lb-overlay-gate.sh`: add `cf_lb_gate_ga_monitor_update` and
  `cf_lb_gate_ga_pool_update <plan> <mode>`; extend `cf_lb_gate_ga`'s origins pin to the
  set {web-1_ip, web-2_ip} read from the plan's no-op `hcloud_server.web` entries.
- `tests/scripts/test-cf-lb-overlay-gate.sh`: fixtures + assertions for the new graders
  and the widened origins pin.
- Success criterion: both graders refuse non-update verbs, out-of-set addresses,
  repointed origins, and `serve`-mode plans that pool above weight 0 in `drain` mode.

#### Phase 3 — committed-config guard + parity/docs updates

- `apps/web-platform/infra/lb-weight-gate.test.sh` Condition C: C.3-sweep becomes the
  **drained-shape invariant** — an LB .tf may reference web-2 ONLY inside an `origins`
  block carrying `weight = 0`; retains C.1b (exactly one `name = "app"` record), C.1c,
  C.2, and a new refusal on `default_pool_ids` referencing a web-2 pool or on
  `weight = 1`/`>0` paired with the web-2 origin (the flip PR re-tightens this).
  **Lexing note (sharp-edge):** the weight pairing must be block-scoped (awk-range over
  the `origins {}` block containing `name = "web-2"`), never a bare line-grep for
  `weight = 0` — a line-scanner cannot bind the weight term to the web-2 block and
  passes on a dropped term (Guard 3 mutation row 2).
- `knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md`:
  document the two new arms + verdict semantics.
- ADR-068: add dated amendment — monitor transport corrected to the Flexible data path;
  web-2 pooled at weight 0 (the §(b) drained shape) replacing F3's structural absence.
- C4 `model.c4`: `cloudflare` system description gains the LB role (LB fronts
  app.soleur.ai, origin pool {web-1, web-2-drained}, fallback to A record); the
  LB-fronted serving edge prose covers the two-origin set. `views.c4` checked — the
  `cloudflare` element is already included in the context view.
- The notification policy rides the **`ga-pool-update` arm's `-target` set** (pool + LB +
  `cloudflare_notification_policy.web_lb_health`), NOT the routine apply: if
  `filters.pool_id` referenced `cloudflare_load_balancer_pool.web_1.id`, a routine-apply
  `-target` on the policy would transitively pull the pool — and the web-2 origin update —
  into an unattended apply (the #8705 second-apply-workflow class). Inside the arm the
  transitivity is inert (the pool is already targeted), so the resource reference is safe
  there; the literal-id alternative was rejected (drift on recreate).
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: bump
  `BASELINE_DECLARED_PROBES` 89 → 90 (this plan declares a non-placeholder
  `credentials_required`; required by preflight's corpus count, #8651).
- Success criterion: `lb-weight-gate.test.sh`, `test-cf-lb-overlay-gate.sh`,
  `terraform-target-parity.test.ts` green; `cloud-init-user-data-size.test.ts`
  unaffected (no cloud-init change).

#### Phase 4 — follow-through enrollment

- `scripts/followthroughs/ga-lb-pool-soak-6027.sh`: probes (a) CF pool-health API shows
  every pool origin `healthy:true`, (b) `app.soleur.ai/health` serves 200, (c) zero new
  Better Stack incidents in the soak window. Exits 0 only while all hold inside
  `[deploy_ts, deploy_ts+7d]`; `earliest=` pinned to flip+7d by the window session's
  tracker directive.
- `knowledge-base/project/specs/<branch>/decision-challenges.md`: persist ruling rows
  (already written this session).
- Success criterion: ship Phase 5.5's Soak-Gated Follow-Through Enrollment Gate sees the
  script + directive shape.

## Research Insights

### Premise Validation (Phase 0.6)

Checked live + on the worktree HEAD:

- **Cited anchors — all verified:** `placement_group_id` location-scoped expression at
  `server.tf:368`; `web_tunnel_connector = each.key == "web-2"` at `server.tf:458`; pool
  `origins{}` at `cloudflare-lb.tf:43-48`; soak-marker comments at `cloudflare-lb.tf:52`
  and `:70`; `hcloud_placement_group.web_spread` at `placement-group.tf:7`.
- **Issues:** #6027 OPEN (deferred cutover orchestrator — re-evaluation criteria include
  `GIT_DATA_LUKS_CUTOVER_AT` + soak; body orders the window sequence
  weight-flip → drain → ignore_changes removal → drained-host reboot). #11181 OPEN
  (non-cutover epic; its spec keeps AC4 + AC11 with the cutover track). #11749 OPEN
  (probe-calibration tail). #11592 OPEN (docs PR, draft). #11766 OPEN (this draft PR).
- **Live CF state (read-only, `prd_terraform` token):** pool `web-1`
  `fb2b0492d5a8f5e4bd7ec1e2667fe610`, origin `135.181.45.178` → `healthy:false`,
  `failure_reason:"TCP connection failed"`. Monitor `855cd0c4725e7b459d5538f439688815`:
  `type=https, port=null` → confirmed dead-on-arrival probe semantics.
- **Live Doppler gate state (`soleur/prd` etc.):** `GIT_DATA_STORE_ENABLED=false`;
  `GIT_DATA_LUKS_CUTOVER_AT` absent in prd/prd_git_data/prd_workspaces_luks{,_web};
  `WORKSPACES_LUKS_CUTOVER_AT=2026-10-29T10:09:06Z` present in `prd_workspaces_luks_marker`
  (soak elapsed); `SOLEUR_PROXY_BIND` absent everywhere checked (relay NOT bound);
  `SOLEUR_HOST_ROSTER` + `SOLEUR_PROXY_PEER_ALLOWLIST` present. **The weight flip is NOT
  authorized today** — pooling lands drained, and the flip stays orchestrator-gated.
- **STALE BRIEF CLAIM (corrected):** "web-2 moved hel1→fsn1 (2026-07-13)" refers to the
  retired warm-standby web-2 (#6538). The CURRENT web-2 was born hel1 2026-07-24
  (ADR-143/#6459), `var.web_hosts` default confirms `location = "hel1"`, and it was born
  INTO `web_spread`. Brief open-question 2 dissolves; the `server.tf:362-366` comment
  citing the fsn1 move is stale/defensive and is corrected in the window PR's comment
  sweep, not here (server.tf is out of this PR's file scope).
- **ADR check (Phase 0.6 item 4):** ADR-068 §(b) prescribes the weight-0 drained pool
  membership — the brief's `weight=1` is corrected to the ADR shape. `expected_codes`
  tension: ADR prescribes `"2xx"`, committed value is `"200"` — retained (stricter, still
  reachability-only; no `/health` body parse either way).

### Property List (Phase 0.6b)

1. CF reports truthful per-origin health for BOTH pool members (today: web-1 reads
   permanently down; web-2 would read identically dead if pooled).
2. web-2 is a monitored, drained pool member per ADR-068 §(b) — health-checked, zero
   serving weight until the authorized flip.
3. Every committed GA-trio change remains applicable ONLY through a fail-closed gated
   dispatch (create AND update shapes).
4. The committed-config anti-pooling tripwire keeps working under the new shape — it
   asserts the drained invariant rather than structural absence.
5. A silent origin-down state pages someone (today it cannot).
6. The 0→1 flip + placement-group attach remain orchestrator-gated window acts (AC4/AC11
   stay with the cutover track per the #11181 spec).

### Cut List (Phase 0.6b)

- Brief's `weight=1` immediate pooling → buys property 2 falsely (pre-flip weight is a
  workspace-gone incident class; `GIT_DATA_LUKS_CUTOVER_AT` absent today). Covered instead
  by weight-0 drained membership + the window flip.
- Brief's `steering_policy` change ("off"→"random"/"geo") → wrong layer; `steering_policy`
  steers BETWEEN pools (one pool here — `"off"` is correct). The origin-level knob is
  `origin_steering` on the pool → carried as a pending ruling row.
- Reusing `ga-overlay` for updates → its gate's create-only semantics are the guard; a
  relaxation would blur "create the live LB" authorization. Rejected in favour of
  purpose-scoped update arms (repo's per-arm confirm-literal pattern).
- `lifecycle.ignore_changes` removal (server.tf) → explicitly routed to the window PR
  (#6027 sequencing: flip → drain → attach on drained host). Not this PR's mechanism.

### Local research (sequential fallback — no Task tool on this harness)

- `repo-research-analyst` (inlined): `cloudflare-lb.tf` (74 lines, GA trio + B1-B3
  comments); `server.tf:360-368` (location-scoped `placement_group_id`), `:607-640`
  (ignore_changes GA-deferral + HARD GATE note), `:458` (connector predicate);
  `variables.tf:187-188` (`web_hosts` map — both hel1); `firewall.tf` (:80/:443 CF-IP
  rules); `cloud-init.yml:808` (`-p 0.0.0.0:80:3000`); `cf-lb-overlay-gate.sh` (four arm
  graders, negative-action filter, identity pins); `cf-lb-overlay.yml` (four arms,
  confirm literals, environment gates, saved-plan grading, continuity probe);
  `lb-weight-gate{,-with-marker}.sh` (top-guard standby PASS, Conditions A+B, marker
  seam); `lb-weight-gate.test.sh` §C (committed-HCL assertions incl. C.3-sweep);
  `terraform-target-parity.test.ts:1338-1341` (GA trio -target exclusion) + `:2647`
  (ignore_changes pin — window PR scope); `apply-web-platform-infra.yml:854-899`
  (reboot_updates destroy-guard + `[skip-web-platform-apply]` steer); `tunnel.tf:325`
  (notification_policy precedent); `uptime-alerts.tf:642` (CF notification entitlement
  note — `http_alert_*` unavailable, `load_balancing_health_alert` IS available per live
  `available_alerts` read).
- `learnings-researcher` (inlined): plan globs verified against repo structure;
  `2026-04-15-gh-jq-does-not-forward-arg-to-jq` (two-stage piping used in the overlap
  check); the #4003/#4015/#4018 CF-notification entitlement history (verified the LB
  alert type live rather than trusting it).
- Related issues/PRs: #6027, #11181, #11592, #11749, #11766, #5887, #6459, #6538,
  #6575, #6969, #9358, ADR-068/114/143/263.

### Conventions honored

- `hr-all-infrastructure-provisioning-servers` — every mutation is Terraform via the
  existing gated workflows; zero out-of-band steps prescribed.
- `hr-no-ssh-fallback-in-runbooks` — verification is CF API / Doppler / workflow logs.
- Follow-through convention — soak script under `scripts/followthroughs/` + directive.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief/spec) | Reality (verified) | Plan response |
|---|---|---|
| "web-2 moved hel1→fsn1 (2026-07-13)… cannot join web_spread" | Current web-2 born hel1 2026-07-24 inside `web_spread`; fsn1 was the retired standby (#6538) | Fork 2 dissolved — no DC decision; correct stale server.tf comment in the window PR |
| "weight=1 origin" for step 4 | ADR-068 §(b): weight 0 (drained) until GA; flip preconditions unmet today | In-PR `weight=0`; flip encoded as gated follow-through |
| "`steering_policy` 'off' → 'random'/geo" | `steering_policy` is pool-level; one default pool; origin-level knob is `origin_steering` | `origin_steering.policy` pending-ruling (assumed `random`); LB `steering_policy` stays `"off"` |
| "probe calibration tail (#11749)" | Continuity verdict floor unreachable — real defect in the step the new arms will reuse | New arms reuse the probe step; #11749 stays open — Acknowledge, do not fold |
| "monitor may be down" | CONFIRMED live: `healthy:false / TCP connection failed` on :443 | Monitor fix is in-PR Phase 1 + immediate `ga-monitor-fix` follow-through |

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| `type="https"` + `port=443` + real origin TLS listener | Rejected — no :443 listener exists; adding TLS-at-origin is a separate architecture change (origin-cert issuance, renewal, firewall semantics). The Flexible-SSL path is today's sanctioned data path (with #10479 tracking its hardening). |
| `type="http"`, `port=80` | **Chosen** — mirrors the actual CF→origin path; `expected_codes="200"` on `/health`; ADR-068 §(b) reachability-only preserved. |
| `type="tcp"`, `port=80` | Rejected — TCP-connect liveness can't distinguish app-up from host-up; HTTP `/health` is the documented contract. |
| web-2 weight=1 in this PR | Rejected — flip preconditions unmet (`GIT_DATA_STORE_ENABLED=false`, no `GIT_DATA_LUKS_CUTOVER_AT`, `SOLEUR_PROXY_BIND` absent); violates ADR-068 §(c) and the #11181 spec FR1. |
| One combined `ga-update` arm | Rejected (assumed, pending ruling row) — the monitor fix must deploy NOW without inheriting the pooling arm's authorization tier; per-arm confirm literals are the repo convention. |
| `origin_steering.policy`: `random` vs `hash` vs `least_*` | `random` assumed pending ruling — `session_affinity="none"` and user-bound serving is lease-routed by the relay, so stickiness buys nothing; `hash` would silently introduce affinity semantics. |
| Extend routine apply `-target` to cover the GA trio | Rejected — the trio stays excluded by design (sequenced human-watched acts, terraform-target-parity:1338-1341). |

## User-Brand Impact

- **If this lands broken, the user experiences:** `app.soleur.ai` ingress outage (LB
  misroute) or the documented **workspace-gone incident** — a request routed to web-2
  before the flip hits an empty `/workspaces` (ADR-143 D2/D3: the sole live copy is
  web-1's volume).
- **If this leaks, the user's [data / workflow / money] is exposed via:** a user session
  landing on a host whose `/workspaces` is not the user's volume (workflow data
  isolation), or a misconfigured monitor masking a real origin outage (availability
  blindness, not data exposure).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the documented incident class is a single
  user's workspace appearing empty — per-user blast radius, already named the
  "single-user (workspace-gone) incident" in ADR-068 §(c) and `lb-weight-gate.sh`'s
  header.

`requires_cpo_signoff: true` — carried forward from the #11181 spec's
`brand_survival_threshold: single-user incident`. `soleur:engineering:review:user-impact-reviewer`
runs at review time per the review skill's conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: CF LB monitor probing GET /health on origin :80 (post-fix); CF pool-health API read (`GET /accounts/{id}/load_balancers/pools/{pool_id}/health` — `healthy:true` per origin); Better Stack `app_health` keyword monitor on https://app.soleur.ai/health (supabase:connected, 180s)
  cadence: CF monitor 60s interval / WEU region; Better Stack 180s; pool-health read on demand + post-apply per arm
  alert_target: alert email via var.cf_notification_email (new `cloudflare_notification_policy.web_lb_health`, alert_type load_balancing_health_alert, verified in available_alerts 2026-11-01); Better Stack → Slack + push + email (existing)
  configured_in: apps/web-platform/infra/cloudflare-lb.tf (monitor block + new notification policy) + apps/web-platform/infra/uptime-alerts.tf (existing monitors)

error_reporting:
  destination: Sentry web-platform (SENTRY_DSN, baked) + Better Stack incidents mirrored to GitHub issues (#10390 mirror)
  fail_loud: cf-lb-overlay.yml arm run failure (::error:: + job red); `healthy:false` / `failure_reason` in the pool-health JSON; `load_balancing_health_alert` notification email on origin health transitions

failure_modes:
  - mode: monitor misconfiguration marks a healthy origin down (this incident's shape)
    detection: `load_balancing_health_alert` notification + post-apply pool-health assertion step in each new arm (GET pool health, require origins healthy:true)
    alert_route: alert email + run failure
  - mode: drained web-2 origin actually unhealthy (would fail the flip later)
    detection: same pool-health read — web-2 origin healthy:false after pooling apply
    alert_route: alert email + run failure
  - mode: CF health probe flaps a live origin out of rotation (consecutive_down=2 @60s)
    detection: `consecutive_down`/`consecutive_up` pins in the monitor block + notification transitions
    alert_route: alert email
logs:
  where: cf-lb-overlay.yml run logs (gate verdicts, plan summary); CF audit log for applied changes; Better Stack incidents for edge-visible 5xx
  retention: GHA run retention (default) + CF audit retention (account-default); the pool-health JSON is point-in-time (no history) — the notification policy is the standing record of transitions

discoverability_test:
  command: bash scripts/followthroughs/ga-lb-pool-soak-6027.sh
  expected_output: "[PASS] pool %s all origins healthy; edge 200; %d incidents in window"
  credentials_required: "CF_API_TOKEN (Zone.Account Load Balancing read) + BETTERSTACK_API_TOKEN — pool origin health and incident counts have no unauthenticated substitute (preflight Check 10 SKIP-DECLARED)"
```

**Affected-surface note (Phase 2.9.2):** not a blind execution surface — the plan touches
no agent sandbox, container dispatch, or cron worker; detection rides existing in-surface
signals (CF API, workflow logs).

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces["web-2"] (web-2 /workspaces LUKS volume — not created here, newly REACHED by serving once the flip lands)
    mechanism: luks
    evidence: apps/web-platform/infra/workspaces-luks.tf (for_each LUKS volume, #9372); WORKSPACES_LUKS_CUTOVER_AT marker (prd_workspaces_luks_marker, verified present 2026-10-29)
    defends_against: seized/RMA'd disk; raw volume snapshot reads
    does_not_defend: runtime read via the mounted path on a booted host; a request routed pre-flip (routing — not an at_rest property — stays gated by lb-weight-gate.sh)
    disclosed_as: not-publicly-claimed
    live_verification: available (workspaces-luks-verify.yml web2_marker daily probe)
in_transit:
  - connection: CF edge -> origin :80 (app.soleur.ai serving, both origins post-flip)
    enforced_at: apps/web-platform/infra/seo-config-rules.tf:273 (config rule `ssl = "flexible"`)
    tls: none (HTTP to origin — Flexible SSL; pre-existing posture, NOT introduced by this diff — web-2 inherits the same path web-1 already serves on)
    cert_verification: off
    does_not_defend: on-path reading of CF->origin traffic between the edge and Hetzner
    disclosed_as: not-publicly-claimed
exception:
  justification: Flexible-SSL origin path is the existing sanctioned data path for app.soleur.ai; this plan extends it to a second origin rather than introducing it — remediation (full/strict + origin cert) is tracked separately
  tracking_issue: '#10479'
  reevaluate_when: origin TLS termination lands (origin cert + ssl=full/strict flip) or the monitor path diverges from the data path
  expires_on: 2026-12-31
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/cloudflare-lb.tf` — monitor type/port; pool `origins{}` +
  `origin_steering`; comment rewrites; new `cloudflare_notification_policy.web_lb_health`.
- `apps/web-platform/infra/lb-weight-gate.test.sh` — Condition C rewrite (test file,
  not provisioned infra).
- Providers: `cloudflare ~> 4.0` (locked 4.52.7) — `origin_steering` and
  `load_balancing_health_alert` both supported at this pin (alert type verified live in
  `available_alerts`).
- Sensitive variables: none new. `var.cf_notification_email` already declared
  (tunnel.tf:325 precedent). Runtime secrets unchanged.

### Apply path

**(d) dedicated gated dispatch arms** — the GA trio are deliberately `-target`-excluded
from `apply-web-platform-infra.yml` (terraform-target-parity.test.ts:1338-1341 pins this).
New arms on `cf-lb-overlay.yml` carry the updates: `ga-monitor-fix` then
`ga-pool-update` (mode=drain for this PR's shape). The notification policy rides the
`ga-pool-update` arm's `-target` set (NOT the routine apply — the filters.pool_id
transitivity trap, same as task 3.2). Blast radius: monitor update is
probe-semantics-only (no traffic change); pool update adds a weight-0 origin (no traffic
change); both take the continuity-probe step post-apply.

### Host fan-out

No `terraform_data` SSH provisioner added or edited — `web-host-provisioner-parity.test.sh`
unaffected. The web-1 `placement_group_id` attach (in-place reboot) is the window PR's
diff per `server.tf:607-614` ("REMOVE this entry in the GA maintenance-window PR as its
FIRST diff") and #6027's ordered sequence.

### Distinctness / drift safeguards

- One state backend per root; ga arms join the shared terraform-apply serializer group.
- The drained origin is idempotent — a re-dispatch of `ga-pool-update` on a converged
  plan yields zero changes and the grader refuses zero-change plans (same posture as
  `ga_creates==0` refusal).
- `lifecycle.ignore_changes` on `hcloud_server.web` unchanged in this PR — no
  reboot_updates component enters any routine plan (the `reboot_updates=0` destroy-guard
  stays green; `[skip-web-platform-apply]` is NOT needed for this merge).

### Vendor-tier reality check

`load_balancing_health_alert` confirmed in the account's `available_alerts`
(GET /accounts/{id}/alerting/v3/available_alerts, 2026-11-01) — contrast `http_alert_*`
types which are Enterprise-gated and absent (uptime-alerts.tf:642 note). LB subscription
(Basic, ~$5/mo, already approved) carries the alert type.

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` (same
document, dated amendment — the file's established convention): record (a) the monitor
transport correction to the Flexible data path (type http / :80) replacing the 443
premise; (b) the drained-origin pooling shape replacing F3's "structurally absent"
reading of §(b); (c) `origin_steering` declaration per the ruling row. No NEW ADR — the
change executes ADR-068's recorded Phase-3 design; status stays `adopting` (the
`adopting`→`accepted` flip is AC11's soak-gated act, not this PR).

### C4 views

Completeness enumeration (all three files read — model.c4, views.c4, spec.c4): external
human actors — none new (founder/users unchanged). External systems — Cloudflare already
modeled (`cloudflare` system element, model.c4:426) but its description predates the
2026-11-01 LB landing; the `betterstack -> hetzner` edge already says "LB-fronted"
(model.c4:885). Containers/stores — `hetzner` Compute already describes the two-host
cluster and the weight-0 standby. Access relationships — the user→app serving edge gains
the two-origin pool membership (drained). **In-scope task:** update the `cloudflare`
description (LB role, pool {web-1, web-2-drained}, A-record fallback) and the serving
edge prose; `views.c4` include list verified — `cloudflare` already renders in the
context view, no `include` change needed. Validation:
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` green.

### Sequencing

The committed weight-0 shape is true at merge; the weight-1 target state is recorded in
the ADR amendment as pending the flip window (the "adopting" note convention), not
postponed to a follow-up issue.

## Guard Contract

### Guard 1 — `cf_lb_gate_ga_monitor_update` (new grader, cf-lb-overlay-gate.sh)

**Property.** A `ga-monitor-fix` plan may ONLY `update`
`cloudflare_load_balancer_monitor.web` and its after-state must be exactly
{`type:"http"`, `port:80`, `path:"/health"`, `expected_codes:"200"`} — no other change,
no other address, no other monitor semantics.

**Assembly.** `cf-lb-overlay.yml`'s `ga-monitor-fix` job (the only caller) →
`terraform show -json tfplan` → grader. The negative-action filter
(`!= ["no-op"] and != ["read"]`) is the chokepoint every change row flows through —
same floor the four existing graders stand on.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Plan updates monitor with `type:"https"` retained (no transport fix) | RED |
| 2 | Plan's change set is empty (grader's own dispatch vacuity — zero updates approved) | RED |
| 3 | Plan additionally updates `cloudflare_load_balancer_pool.web_1` (second member smuggled beside a compliant first) | RED |
| 4 | Plan DELETES/recreates the monitor (non-update verb) | RED |
| 5 | Fixture: monitor after={type:http, port:443} (right type, wrong port) | RED |
| 6 | Fixture: compliant monitor update + unrelated `["read"]` data-source row | PASS |
| 7 | Suite mutation: grader invoked without the plan file (assert_readable path) | RED |

### Guard 2 — `cf_lb_gate_ga_pool_update` (new grader, mode-switched)

**Property.** A `ga-pool-update` plan may ONLY `update`
{`cloudflare_load_balancer_pool.web_1`, `cloudflare_load_balancer.app`}; every pool
origin address must resolve to a declared `hcloud_server.web[*].ipv4_address` in the
plan's no-op entries; in `drain` mode web-2's after-weight must be `0`; in `serve` mode
the plan may carry `weight > 0` ONLY when the job's gate-chain step ran green first.

**Assembly.** Same chokepoint (the `_CF_LB_CHANGES` filter + IN() address allow-set),
plus the origins set resolved from the plan's `hcloud_server.web["web-1"]` /
`["web-2"]` no-op entries — never a literal IP.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `drain`-mode plan with web-2 `weight=1` (the flip smuggled into the drain arm) | RED |
| 2 | `serve`-mode plan where `hcloud_server.web["web-2"]` has no no-op entry (web-2 IP unresolvable — the origins set can't be proven) | RED |
| 3 | Plan with an origin `address` set to a third IP (hostile repoint after a compliant web-1 origin) | RED |
| 4 | Plan updating an out-of-set address (e.g. `cloudflare_record.app`) beside the pool | RED |
| 5 | Fixture: `drain` mode, origins = {web-1@1, web-2@0}, LB steering diff within pins | PASS |
| 6 | Fixture: empty change set | RED |
| 7 | `serve`-mode plan at weight>0 where the workflow's gate-chain step was skipped (workflow-level row — the arm's `run:` ordering assertion) | RED |

### Guard 3 — lb-weight-gate.test.sh Condition C (rewrite)

**Property.** Committed HCL pools web-2 ONLY as a drained member: any `origins` block
naming web-2 carries `weight = 0`; no `default_pool_ids` references a web-2 pool; no
second `name = "app"` record; the connector predicate stays `each.key == "web-2"`.

**Assembly.** The `for f in "$SCRIPT_DIR"/*.tf` sweep — every .tf file in
`apps/web-platform/infra/` flows through it (file-level chokepoint; the per-file inner
grep is member-scoped by construction).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | web-2 `origins` block with `weight = 1` committed | RED |
| 2 | `origins` block for web-2 with `weight` line absent (shape-only check must not pass on a dropped term) | RED |
| 3 | Second `name = "app"` record added to dns.tf beside the compliant one (pre-existing C.1b case — regression floor) | RED |
| 4 | `.tf` sweep sees zero files (dir moved — fail-closed on dispatch, not a silent 0-hit GREEN) | RED |
| 5 | web-2 `origins` block at `weight = 0` + enabled | PASS |
| 6 | Suite mutation: C.3's grep anchored on a renamed resource label (`cloudflare_load_balancer_pool.web_2`) — assertions must still count, not vacuously pass | RED |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "VERIFY monitor health first… Check pool health via CF dashboard or GET /accounts/{id}/load_balancers/pools/{pool_id}/health. If the monitor is indeed down, fix the monitor's port/SSL semantics for BOTH origins BEFORE adding web-2" [brief] | FR1 / Phase 1 / cloudflare-lb.tf monitor block + `ga-monitor-fix` arm + Guard 1 | mapped — hypothesis CONFIRMED live during planning |
| 2 | "web-1 placement-group attach: server.tf:368 already assigns hcloud_placement_group.web_spread… pending the in-place REBOOT… route through it [#6027]" [brief] | Gated follow-through (window PR per server.tf:614 + #6027 ordering) — NOT in-PR | mapped (follow-through) |
| 3 | "web-2 placement decision — LOCATION-SCOPED constraint… flag to operator" [brief] | Premise-corrected: web-2 is hel1, already in web_spread | mapped (decision-challenges row, resolved) |
| 4 | "Pool origin add: cloudflare-lb.tf:43-48 — append a second origins{} block… Update the 'until soak marker' comments… grep apps/web-platform/test/ + cf-lb-overlay-gate.sh for pool-origin pins BEFORE editing" [brief] | FR2 / Phase 1 + Phase 2/3 gate + test updates | mapped — weight corrected to 0 per ADR-068 §(b) + live gate state |
| 5 | "steering_policy = 'off' → two origins argues for 'random' or geo — decision point" [brief] | `origin_steering { policy = "random" }` pending ruling; LB `steering_policy` stays "off" | mapped (decision-challenges row) |
| 6 | "Soak AC4 + AC11 per #6027 + verify app.soleur.ai serves via BOTH origins" [brief] | Follow-through enrollment (Phase 4 script + directive); the both-origins serving evidence belongs to the flip window | mapped (follow-through; AC11 = 7-day GA soak per #11181 spec) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| monitor `type="http"`, `port=80` | "fix the monitor's port/SSL semantics for BOTH origins BEFORE adding web-2" | asked |
| web-2 `origins{}` at weight 0 | "append a second origins{} block: name=\"web-2\", address=hcloud_server.web[\"web-2\"].ipv4_address, enabled=true" — weight corrected 1→0 (ADR-068 §(b) + unmet preconditions) | asked (amended) |
| `origin_steering` block | "steering_policy = \"off\" → two origins argues for \"random\" or geo — decision point" | asked (layer corrected) |
| `ga-monitor-fix` + `ga-pool-update` arms | — | inferred — the GA trio's ONLY apply path is cf-lb-overlay arms whose gate permits creates; without update arms the commits are unappliable through the sanctioned path |
| `cf_lb_gate_ga` origins pin widened to {web-1,web-2} | "the ga-overlay gate's GA-pool-origin pin needs a deliberate update if the pool is re-dispatched later" | asked |
| Condition C rewrite | "deliberately update any pinning tests that count origins — grep apps/web-platform/test/ + cf-lb-overlay-gate.sh for pool-origin pins BEFORE editing" | asked |
| `cloudflare_notification_policy.web_lb_health` | — | inferred — `hr-observability-as-plan-quality-gate`: the incident just demonstrated is a silent origin-down; `load_balancing_health_alert` verified provisionable |
| notification policy on the `ga-pool-update` arm's `-target` set | — | inferred — the alert rides the same watched dispatch as the pool it alerts on; the routine-apply route would transitively pull the pool (transitivity trap) |
| follow-through soak script | "Soak AC4 + AC11 per #6027" | asked |
| ADR-068 amendment + C4 description update | — | inferred — `wg-architecture-decision-is-a-plan-deliverable` (serving-path relationship changes) |
| runbook update | — | inferred — new arms are undocumented without it; the runbook is the dispatch surface's doc |

### Split Assessment

- Subsystems touched: 5 — `apps`, `.github`, `tests`, `knowledge-base`, `scripts`
- Planned files: 12 | Estimated changed lines: ~400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **split — boundary by authorization tier, not file count.** THIS PR
  = drained-shape config + machinery (appliable now); the window PR = weight flip +
  `ignore_changes` removal + drained-host reboot (#6027 orchestrator). Merging the
  reboot diff now would halt every routine apply until the window — the split keeps the
  monitor repair deployable immediately.

## Domain Review

**Domains relevant:** Engineering, Product (brand-survival carry-forward only)

### Engineering

**Status:** reviewed (sequential fallback — no Task tool; CTO lens applied inline)
**Assessment:** The architectural blast radius is the documented workspace-gone
single-user incident; the drained-shape design keeps the diff inside the ADR-068 §(b)+(c)
envelope. Correctness hinges on the two gate layers agreeing: static (Condition C
rewrite) asserts the drained SHAPE while runtime (lb-weight-gate + window orchestrator)
asserts the AUTHORIZATION. The stale-comment class is real (server.tf:362-366 cites the
retired fsn1 host) — corrected in the window PR where server.tf is in scope.

### Product/UX Gate

**Tier:** none — mechanical UI-surface scan of Files to Edit/Create: no match
(.tf/.sh/.yml/.md only; `ui-surface-terms.md` glob superset returns zero).
**Decision:** N/A (no UI surface) — `requires_cpo_signoff` still applies via the
brand-survival threshold (carried from the #11181 spec); the CPO lens is inlined here:
the user-visible delta is availability honesty (a real outage now reports as down), not
a surface change.

### Legal (assessed — not relevant)

No regulated-data surface (no schema/auth/API-route/.sql), no new processing activity —
the GDPR-gate trigger (b) fires only because the threshold is `single-user incident`.
Advisory note (soleur:gdpr-gate sequential fallback): post-flip, user workspaces are
served from web-2's LUKS-attested volume under the same processing purpose; the PA-36
lawful-basis gates are the cutover track's (`GIT_DATA_STORE_ENABLED` activation),
unchanged by this diff. No compliance filing needed.

**Brainstorm-recommended specialists:** none (no brainstorm carried into this run).
**Skipped specialists:** none required — `soleur:product:design:ux-design-lead` N/A (no
UI surface); `Pencil available: N/A (no UI surface)`.

## Open Code-Review Overlap

| Issue | File(s) | Disposition |
|---|---|---|
| #2197 (rate-limiter single-instance assumption cross-ref) | `apps/web-platform/infra/server.tf` | **Acknowledge** — touches a different concern (count/for_each semantics we don't edit); server.tf is out of this PR's file scope entirely. |
| #11749 (continuity-probe calibration; not code-review-labeled but a named tail) | `.github/workflows/cf-lb-overlay.yml` | **Acknowledge** — the new arms reuse the probe step; the calibration defect stays tracked on its own issue (re-dispatching ga-overlay already refuses at `ga_creates==0`, so the tail does not block these arms). |

## Acceptance Criteria

- [ ] **AC1** `cloudflare_load_balancer_monitor.web` is committed as `type = "http"`,
  `port = 80`, `path = "/health"`, `expected_codes = "200"`, `check_regions`-agnostic
  unchanged; the :443 firewall comment is corrected to name :80 as the listener.
- [ ] **AC2** `cloudflare_load_balancer_pool.web_1` carries a second `origins{}` block:
  `name = "web-2"`, `address = hcloud_server.web["web-2"].ipv4_address`,
  `enabled = true`, `weight = 0`; all B2/"structurally absent"/"soak marker" comments
  rewritten to drained-member semantics.
- [ ] **AC3** `origin_steering { policy = "random" }` declared on the pool (or the
  ruled alternative); `steering_policy` on `cloudflare_load_balancer.app` stays `"off"`
  with its comment updated to name the pool-level semantics.
- [ ] **AC4** `cloudflare_notification_policy.web_lb_health` declared
  (`alert_type = "load_balancing_health_alert"`, filters pinning the web pool,
  `email_integration { id = var.cf_notification_email }`) and added to the
  `ga-pool-update` arm's `-target` set (NOT the routine apply — the pool-reference
  transitivity would smuggle the origin update into an unattended apply).
- [ ] **AC5** `cf-lb-overlay.yml` gains `ga-monitor-fix` and `ga-pool-update` arms:
  per-arm confirm literals (`FIX-GA-LB-MONITOR`, `UPDATE-GA-LB-POOL`),
  `environment: web-platform-infra-apply`, saved-plan grading, and `ga-pool-update`'s
  `serve` mode invoking `lb-weight-gate-with-marker.sh` fail-closed before plan. The
  four existing arms are byte-identical.
- [ ] **AC6** `cf-lb-overlay-gate.sh` gains `cf_lb_gate_ga_monitor_update` +
  `cf_lb_gate_ga_pool_update <plan> <mode>` implementing Guards 1-2; `cf_lb_gate_ga`'s
  origins pin widened to the {web-1, web-2} IP set read from the plan.
- [ ] **AC7** `test-cf-lb-overlay-gate.sh` covers the new graders incl. all
  mutation-matrix rows that are fixture-expressible.
- [ ] **AC8** `lb-weight-gate.test.sh` Condition C asserts the drained-shape invariant
  (Guard 3) and the suite stays ≥ `MIN_CASES` with all-green output.
- [ ] **AC9** ADR-068 amendment + `model.c4`/`views.c4` update landed;
  `c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- [ ] **AC10** `scripts/followthroughs/ga-lb-pool-soak-6027.sh` committed (exit 0 iff
  all origins healthy + edge 200 + zero incidents in-window) and the tracker directive
  shape (`earliest` / `secrets`) documented for the window session.
- [ ] **AC11** `decision-challenges.md` carries rows for: steering ruling, arm
  partitioning, weight correction, dissolved DC fork, CPO sign-off, and no BLOCKED rows.
- [ ] **AC12** Gate suites green locally: `lb-weight-gate.test.sh`,
  `test-cf-lb-overlay-gate.sh`, `terraform-target-parity.test.ts`,
  `web-host-provisioner-parity.test.sh`; `precommit-guard.sh` clean; actionlint
  clean on the edited workflow.
- [ ] **AC13** `git diff origin/main -- apps/web-platform/infra/server.tf` is empty
  (no `ignore_changes` edit — window PR scope) and `terraform plan` under the routine
  target set shows `reboot_updates = 0`.
- [ ] **AC14** No `terraform apply`, `gh workflow run`, or Cloudflare/Hetzner mutation
  performed by this PR; all dispatch acts are listed under `## Gated Follow-Through`.

## Test Scenarios

- Given a fixture plan updating the monitor to `{type:"http", port:80, path:"/health",
  expected_codes:"200"}`, when `cf_lb_gate_ga_monitor_update` runs, then it exits 0
  (`unit`).
- Given a fixture plan with the monitor at `port:443` or `type:"https"`, when the
  monitor grader runs, then it exits 1 (`unit`).
- Given a `drain`-mode fixture with origins `{web-1@1, web-2@0}`, when
  `cf_lb_gate_ga_pool_update` runs, then it exits 0; with web-2 `weight=1` it exits 1
  (`unit`).
- Given committed HCL where web-2's origins block carries `weight = 1`, when
  `lb-weight-gate.test.sh` §C runs, then C.3 fails (`unit`/static).
- Given committed HCL where web-2's origins block carries `weight = 0`, when
  `lb-weight-gate.test.sh` §C runs, then C.3 passes (`unit`/static).
- **API verify (post-merge, gated):** `doppler run -p soleur -c prd_terraform -- curl -s
  -H "Authorization: Bearer $CF_API_TOKEN" https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/load_balancers/pools/$POOL_ID/health
  | jq '.result.pop_health'` — expects each origin `healthy:true` after the
  `ga-monitor-fix` arm runs (`e2e`, `pyramid-justified: live vendor state — no unit
  substitute exists for monitor probe semantics`).

## Downtime & Cutover

**Offline-inducing operations in this change's blast radius, and the zero-downtime
default for each:**

1. **Monitor `type`/`port` update (in-PR, `ga-monitor-fix` arm).** A monitor update
   changes probe semantics only — no traffic reroute. Zero-downtime by construction;
   residual risk is a wrongly-green monitor, mitigated by the arm's post-apply
   pool-health assertion (healthy:true or the run fails).
2. **Drained origin add (in-PR, `ga-pool-update mode=drain`).** weight-0 origins receive
   no traffic — CF routes only to weight>0 origins (ADR-068 §(b) drain semantics).
   Zero-downtime by construction; the continuity probe rides the arm.
3. **web-1 `placement_group_id` attach (window PR — reboot class, the 4.55 trigger).**
   An in-place power-off reboot of the sole live origin is NOT zero-downtime — the
   zero-downtime path is the #6027 blue-green sequence ALREADY recorded in the epic:
   weight 0→1 to web-2 FIRST (post-gate), drain web-1, then reboot the **drained** host
   and restore. Residual downtime is bounded to the drain window with automatic
   rollback (epic step 4). The alternative accepted-and-rejected shape — attaching while
   live — is exactly the "reboot the sole origin" incident the deferral exists to
   prevent (server.tf:607-614, #5887).
4. **Per-stage verification/rollback:** gate chain green → weight flip verified serving →
   drain verified by rotation set → attach verified `0 to destroy` in the graded plan →
   reboot → restore weight + health re-verified; rollback = weight 1→0 to web-2 +
   restore web-1 (the LB's drain primitive is the same knob).

## Enhancement Summary

`soleur:deepen-plan` ran sequentially on this harness (no Task/MCP spawn capability —
`Reviewed-Coverage: sequential-fallback`; per-section research agents, Context7,
skills/learnings/review fan-outs were inlined, not independently spawned).

### Gate verdicts

- **4.6 User-Brand Impact:** PASS — `single-user incident` + `requires_cpo_signoff`.
- **4.7 Observability:** PASS — 5-field block; `discoverability_test.command` =
  `bash scripts/followthroughs/ga-lb-pool-soak-6027.sh` (allowlisted verb; repo-relative
  script committed in this PR); `credentials_required` non-placeholder → SKIP-DECLARED.
- **4.8 PAT-shaped variables:** PASS — no new token-shaped inputs.
- **4.9 UI wireframe:** N/A — no UI-surface file.
- **4.10 Encryption Posture:** PASS — LUKS store + Flexible exception w/ #10479, 60-day expiry.
- **4.11 Guard Contract:** PASS — 3 guards, Property/Assembly/≥3-row matrices incl.
  own-dispatch + second-member + must-PASS rows.
- **4.12 Scope Check:** PASS — all 6 asks mapped, no BLOCKED.
- **4.13 Task Design:** assessed — no new autonomous surface (existing workflow +
  sweeper-enrolled probe under the followthrough convention).
- **4.5 Network-Outage Deep-Dive:** FIRED (server.tf provisioner blocks) — L3 firewall
  (:80/:443 permits vs :80 listener), L3 DNS/routing (edge serving), L7 TLS (TCP-fail on
  :443), L7 app (/health contract) — all verified with live artifacts in `## Hypotheses`.
- **4.55 Downtime & Cutover:** FIRED (reboot-class attach) — section added above;
  blue-green drain-first sequence is the recorded default.

### Round-1 realism passes (sequential)

- **Verify-the-negative:** "CF never routes to weight-0" — ADR-068 §(b) drain semantics
  + lb-weight-gate standby branch confirm; "GA trio -target-excluded" —
  terraform-target-parity.test.ts:1338-1341 confirm; "notification transitivity inert in
  arm" — arm -targets the pool already (confirms).
- **Precedent-diff (4.4):** new arms mirror the `ga-overlay` skeleton verbatim —
  checkout → infra-credentials → confirm literal → R2 creds → init → -targeted plan →
  saved-plan grading → apply → continuity; the deliberate DIFF is update-typed graders +
  the `mode` input + the `serve`-mode gate-chain step. No precedent for a mode-switched
  arm — novel, flagged for review scrutiny.
- **Post-edit self-audit:** no dropped/renamed symbols; `steering_policy` comment edit is
  additive (`origin_steering` is a new block, not a rename).

### Key improvements applied this pass

- `## Downtime & Cutover` section (4.55 halt).
- Notification policy re-routed from routine apply to the `ga-pool-update` arm's
  `-target` set — a `filters.pool_id` resource reference would transitively pull the
  pool into an unattended routine apply (#8705 class, sharp-edges:228).
- `BASELINE_DECLARED_PROBES` bump recorded (sharp-edges:215).
- Condition-C weight pairing specified as block-scoped awk-range, not line-grep
  (sharp-edges:222 line-scanner class).

### New considerations discovered

- `load_balancing_health_alert` is provisionable on the Basic LB tier (verified live in
  `available_alerts`) — closes the silent-origin-down gap as in-PR Terraform, not a
  deferred alert wish.
- `prd_workspaces_luks_marker` has no read-only token today (#9358) — the `serve` arm's
  gate-chain step records it as an orchestrator prerequisite, not an in-PR blocker.
- **Sequential fallback disclosure:** Eng/CTO/domain-leader/review agents could not be
  spawned; the lenses were applied inline in this session. Findings marked
  `pending - assumed` in decision-challenges.md await the parent's real CTO spawn.

## Hypotheses

Network-outage checklist fired (the window apply path touches `hcloud_server.web`, whose
definition carries `provisioner "file"` / `provisioner "remote-exec"` / `connection`
blocks):

1. **L3 firewall allow-list.** `firewall.tf` permits CF edge IPs on :80 AND :443; the
   failing probe hits :443 where no listener exists. [verified: firewall.tf:21,54 +
   cloud-init.yml:808-809 — the origin publishes `0.0.0.0:80:3000` AND
   `0.0.0.0:3000:3000`; :443 remains the port with no listener]
2. **L3 DNS/routing.** `app.soleur.ai` resolves and serves 200 through the CF edge
   today (the LB + retained A record both route to web-1). [verified: ga-overlay
   post-apply continuity green 2026-11-01 per the brief + live pool read]
3. **L7 TLS/proxy.** CF monitor probes origin:443/TLS → `TCP connection failed`
   (origin never completes a TCP handshake on :443, let alone TLS). [verified: live
   pool-health API `failure_reason:"TCP connection failed"` + monitor `type=https,
   port=null`]
4. **L7 application.** `/health` on :80 answers 200 (the Better Stack `app_health`
   keyword monitor rides the edge path continuously). [verified: monitor contract —
   `health-keyword-monitor-contract.test.ts` pins the body]
5. **Conclusion:** monitor transport mismatch — fix is `type=http`/`port=80`; not an
   sshd/fail2ban/service-layer fault. The `terraform_data` SSH provisioners are
   irrelevant to this diff (they run at create, not update).

## Gated Follow-Through (post-merge acts — NOT in-PR)

1. **Immediate:** dispatch `arm=ga-monitor-fix` (confirm `FIX-GA-LB-MONITOR`) →
   post-apply pool health shows web-1 `healthy:true`. Then dispatch
   `arm=ga-pool-update -f mode=drain` (confirm `UPDATE-GA-LB-POOL`) → pool health shows
   BOTH origins; web-2 receives zero traffic (weight 0 — verify by absence of origin
   distribution + `SOLEUR_SERVING_ROTATION` unchanged).
2. **Window (blocked on cutover preconditions — today unmet):** the #6027 orchestrator
   runs `lb-weight-gate-with-marker.sh` (env: `SOLEUR_WEB2_SERVING_WEIGHT=1`,
   `SOLEUR_SERVING_ROTATION=web-1,web-2`, relay/roster/soak env) AND the on-host
   runtime-bind probe (`docker exec soleur-web-platform curl 127.0.0.1:3000/internal/readyz`,
   N≥2 consecutive ready reads) → window PR flips `weight 0→1` + removes
   `placement_group_id` from `ignore_changes` (FIRST diffs; merge carries
   `[skip-web-platform-apply]` + the vector-redeliver allow-set update per
   `vector-redeliver.md:231`) → drain web-1 → dispatch `ga-pool-update -f mode=serve` →
   placement-group attach reboot on the drained host → restore → both-origins serving
   verification.
3. **Soak:** AC4 (drained-host reboot evidence) + AC11 (7-day GA soak) — tracker issue
   carries `<!-- soleur:followthrough script=scripts/followthroughs/ga-lb-pool-soak-6027.sh
   earliest=<flip+7d> secrets=GH_TOKEN,CF_API_TOKEN,BETTERSTACK_API_TOKEN -->` +
   `follow-through` label; ADR-068 `adopting`→`accepted` only after the soak holds.
4. **Prerequisite flagged for the orchestrator:** provision a read-only Doppler token for
   `prd_workspaces_luks_marker` (recorded on #9358 — the wrapper requires DOPPLER_TOKEN
   and no read-only token exists today).

## Files to Edit

- `apps/web-platform/infra/cloudflare-lb.tf` — monitor transport, web-2 drained origin,
  `origin_steering`, notification policy, comment rewrites.
- `apps/web-platform/infra/lb-weight-gate.test.sh` — Condition C rewrite (Guard 3).
- `tests/scripts/lib/cf-lb-overlay-gate.sh` — two new graders + origins-pin widening.
- `tests/scripts/test-cf-lb-overlay-gate.sh` — fixtures/assertions for the graders.
- `.github/workflows/cf-lb-overlay.yml` — two new arms + `mode` input.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` —
  `BASELINE_DECLARED_PROBES` bump (declared-probe corpus count).
- `knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md` —
  new arms + verdict semantics.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — dated amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — cloudflare LB role +
  serving-edge prose.
- `knowledge-base/project/specs/feat-one-shot-6027-web2-pool-spread/decision-challenges.md` — ruling rows.

## Files to Create

- `scripts/followthroughs/ga-lb-pool-soak-6027.sh` — soak probe (pool health + edge 200
  + incident window).
- `knowledge-base/project/specs/feat-one-shot-6027-web2-pool-spread/tasks.md` — task
  breakdown.

## Success Metrics

- CF pool-health API reports `healthy:true` for web-1 post-monitor-fix (today: false).
- Both origins health-monitored post-pool-update; web-2 weight-0 (zero traffic).
- `load_balancing_health_alert` notification exists for the web pool (the silent-down
  gap closes).
- Merge → routine apply unaffected (`reboot_updates=0`, no `[skip-web-platform-apply]`
  needed).
- The window sequence (flip → drain → attach → restore) is executable purely through
  gated dispatch arms — no out-of-band CF/Hetzner mutation.

## Dependencies & Risks

- **#6027 orchestrator is unbuilt** — this plan pre-stages config + machinery; the window
  acts depend on the epic's own sequencing and the unmet flip preconditions
  (`GIT_DATA_STORE_ENABLED=false`, `GIT_DATA_LUKS_CUTOVER_AT` absent, `SOLEUR_PROXY_BIND`
  absent).
- **#11749 probe calibration** — the reused continuity step emits a false NO-GO
  signature; recorded as Acknowledge.
- **Marker-config read token** (#9358) is a recorded orchestrator prerequisite for the
  `serve` arm path.
- **Steering/arm-partition rulings** pending the parent's technical-ruling gate —
  defaults assumed (`random` / two arms); a different ruling rewrites Phase 2's arm set
  and Guard 2's matrix minimally.
- **CF `consecutive_down=2` @60s** means an origin can flap out in ~2min; the monitor
  pins stand unchanged — flap behavior is a CF-managed constant, not tuned here.

## References & Research

- Plan-time live evidence: CF pool-health `healthy:false`/`TCP connection failed`
  (2026-11-01); `available_alerts` contains `load_balancing_health_alert`;
  Doppler `prd`/`prd_workspaces_luks_marker` gate-state read.
- `apps/web-platform/infra/cloudflare-lb.tf:19-33,36-55,59-71`; `server.tf:368,458,607-640`;
  `variables.tf:187-188`; `firewall.tf:21,54`; `cloud-init.yml:808`;
  `seo-config-rules.tf:273`.
- `tests/scripts/lib/cf-lb-overlay-gate.sh` (full); `.github/workflows/cf-lb-overlay.yml`;
  `apply-web-platform-infra.yml:460-540,700-899`.
- `apps/web-platform/infra/lb-weight-gate.sh`, `lb-weight-gate-with-marker.sh`,
  `lb-weight-gate.test.sh` §C.
- ADR-068 (multi-host; §(b) weight-0 drained, §(c) hard invariant, monitor
  reachability-only), ADR-114 (I1/I2), ADR-143 (D2/D3), ADR-263 (marker provenance),
  ADR-241 (tiered creds).
- Runbooks: `cf-lb-a-record-gaplessness-verify.md`, `vector-redeliver.md:231` (allow-set
  same-PR clause), `followthrough-convention.md` §Soak trigger shape.
- Issues/PRs: #6027, #11181, #11592, #11749, #11766, #10479, #5887, #6459, #6538,
  #6575, #6969, #9358, #10390.
