---
title: "fix(infra): web-1 private-net probe units fail to start — doppler-auth (HOME/token) + vector Source 4 delivery"
date: 2026-07-18
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: [6438, 6548]
issue_ref_style: "Ref (NOT Closes — both are soak-gated; auto-close via scripts/followthroughs/l3-probe-armed-6438.sh earliest 2026-07-25)"
related_adrs: [ADR-123, ADR-117, ADR-115]
related_learnings:
  - 2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md
  - 2026-05-20 (root systemd doppler unit failed — "$HOME is not defined")
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: every `systemctl` in this plan is inside a terraform_data remote-exec
     provisioner (the established `*_install` IaC pattern in server.tf, e.g. server.tf:502-511 which
     already runs `systemctl daemon-reload` / `enable --now`). No manual/operator SSH step is
     prescribed. The `## Infrastructure (IaC)` section below routes the vector delivery through a
     terraform_data resource. -->

# fix(infra): web-1 private-net probe units FAIL TO START — doppler-auth + observability delivery

🐛 **Fix.** The off-host L3 probe PR (14075d1b, #6654) delivered the three web-host private-net
probe systemd units to web-1 (`soleur-web-platform`), but they **FAIL TO START at runtime** — the
`ExecStart` exits non-zero on every timer fire, so no heartbeat is ever pinged and the arm gate
fail-loud'd (monitors rolled back to PAUSED). Continues delivery of the L3 probe work for #6438 §1
(zot consumer), #6548 (git-data), #6438 §3 (NIC guard). **Ref #6438 #6548 — do NOT `Closes`**: both
are soak-gated and auto-close via `scripts/followthroughs/l3-probe-armed-6438.sh` (earliest
2026-07-25) once three heartbeats hold. This plan touches neither the followthrough nor the
already-provisioned GH secrets/ADRs (all done — see Non-Goals).

## Enhancement Summary

**Deepened on:** 2026-07-18. **Reviewers:** architecture-strategist, spec-flow-analyzer,
observability-coverage-reviewer, code-simplicity-reviewer, verify-the-negative pass, + a fable
scoped advisor. All 6 negative/premise claims independently CONFIRMED against live infra.

### Key revisions applied
1. **Token delivery folded into the existing `*_install` provisioners** (append `DOPPLER_TOKEN=` to
   each `/etc/default/web-<probe>` write) instead of a new `/etc/default/web-probes` file + new
   `EnvironmentFile=`. Removes a new-file surface, a cross-resource ordering race, an SRP smell, and a
   `-target` gap — 4 reviewers converged. Units now add only `Environment=HOME=/root`.
2. **Token is a dedicated Terraform-minted read-scoped `doppler_service_token.web_probes`**
   (`access=read`), matching the fleet's explicit security convention (4 precedents; "NOT the full-prd
   `var.doppler_token`") — committed as the single path (no reuse-vs-mint ambiguity).
3. **Phase model corrected:** the "measure still-broken units' stderr BEFORE fixing" checkpoint is
   structurally unreachable in one auto-applied PR (merge = one apply job + arm in the same job) —
   demoted to best-effort; the true probe-first split is recorded in decision-challenges §1.
4. **Positive-control canary added** (luks-#6604 pattern): the probes are silent-on-success, so
   Source-4 liveness was only fault-observable — a recurrence of this exact gap would have been silent.
   The canary makes it a steady-state detectable signal; `discoverability_test` + failure_mode 3
   rewired onto it (the l3-probe-armed soak checks `status==up` only and CANNOT see a Source-4 death).
5. **Vector delivery folded into `terraform_data.journald_persistent`** (already SSHes web-1 + reloads
   a daemon + is `-target`ed) to avoid a new resource + new `-target` entry; `-target` membership made
   a HARD pre-merge AC.

## Overview

Two coupled defects, both delivery/runtime-only (no design change to ADR-123's probe architecture):

1. **The unit-start bug (why the beats never land).** All three units — `web-zot-consumer-probe`,
   `web-git-data-probe`, `web-private-nic-guard` — run
   `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- …'` as **root** (no `User=`)
   but set **no `Environment=HOME=/root`** and source **no `DOPPLER_TOKEN`**. The doppler CLI calls
   `os.UserHomeDir()`; a root systemd service gets no `$HOME`, so doppler dies with
   `Doppler Error: $HOME is not defined` **before it can exec the probe script** — a *documented*
   fleet failure (the 2026-05-20 heartbeat-unit failure; the rule is stated verbatim in
   `cron-egress-firewall.service:14-16`). Compounding it: `/etc/default/inngest-server` — the token
   source every sibling root-doppler unit reads — **is absent on web-1** (`web_colocate_inngest`
   defaults false), so there is **no existing systemd unit on web-1 that successfully authenticates
   doppler as root**. The only populated prd-scoped token file on web-1 is
   `/etc/default/webhook-deploy` (deploy-owned, 600, `DOPPLER_TOKEN` + `DOPPLER_CONFIG_DIR=/tmp/.doppler`).

2. **The observability gap (why the FATAL reason is invisible — fix in the SAME PR).** The units
   correctly set `SyslogIdentifier=web-{zot-consumer-probe,git-data-probe,nic-guard}` and
   `vector.toml` Source 4 (`host_scripts_journald`) lists all three tags
   (`vector.toml:191-193`) — **but no `server.tf` provisioner delivers `vector.toml` or reloads the
   vector agent on the running, unrebuildable web-1**. web-1's vector installs *only* at cloud-init
   boot (`soleur-vector-install`, `cloud-init.yml:806`); web-1 is cx33-unrebuildable and never re-runs
   cloud-init. So Source 4's probe tags are **file-only, never live on web-1**. Measured
   (self-pulled, per `hr-no-dashboard-eyeball-pull-data-yourself`): in the failing window web-1
   shipped **59 systemd supervisor lines and ZERO probe-tagged lines** to Better Stack.

**Fix, probe-first (load-bearing ordering, per learning 2026-07-16 §2).** Deliver the observability
fix so the probe's own stderr reaches Better Stack **first**, use the now-visible reading to
**confirm** the doppler-auth diagnosis on the failing host, **then** fix the units, then re-run the
arm workflow. The soak follow-through closes #6438/#6548 on its own.

## Premise Validation

- **#6438 OPEN**, **#6548 OPEN** (`gh issue view` — both). Neither has a closing PR. `Ref`, not
  `Closes`, is correct: they are soak-gated (`l3-probe-armed-6438.sh`, earliest 2026-07-25).
- **Commit 14075d1b exists** (PR #6654, merged 2026-07-18) — the L3 probe delivery this fix continues.
- All cited artifacts exist on disk: `apps/web-platform/infra/{server.tf, web-probe.tf,
  vector.tf, vector.toml, web-*-probe.{service,timer,sh}}`, `scripts/followthroughs/l3-probe-armed-6438.sh`,
  `ADR-123-web-host-private-nic-self-report-no-self-converge.md`.
- **Own capability claims verified, not asserted:** the doppler-auth diagnosis is a **unit diff**
  against the fleet's working root-doppler units (`container-restart-monitor.service`,
  `cron-egress-*.service`) — the method learning 2026-07-16 §1 endorses ("diff the units before
  theorising"). `triggers_replace` on each `*_install` provisioner **hashes the `.service` file**
  (`server.tf:476` and siblings), so editing a unit re-fires delivery (verified, not assumed).
- No stale premise found.

## Research Reconciliation — Diagnosis vs. Codebase

| Hypothesis (issue framing) | Codebase reality (verified) | Plan response |
|---|---|---|
| (a) `doppler run --config prd` has no auth in the unit env | **Confirmed as source-level gap.** Units set no `HOME` and source no token; `/etc/default/inngest-server` (sibling token source) is absent on web-1; only `/etc/default/webhook-deploy` carries a prd token (deploy-owned). No root-doppler-auth systemd precedent exists on web-1. | **Fix (deepen-plan-revised):** add `Environment=HOME=/root` to all 3 units; **fold `DOPPLER_TOKEN=` into each unit's EXISTING `/etc/default/web-<probe>` file** (the `*_install` provisioners already `printf` these — server.tf:463/506/549), so the token is co-located + ordered with the unit that consumes it (no new file, no new `EnvironmentFile=`, no cross-resource race). The token value is a **dedicated Terraform-minted read-scoped `doppler_service_token.web_probes`** (`config=prd, access=read`) — the fleet convention (`inngest-host.tf:197`, `zot-registry.tf:235`, `git-data.tf:176`, `web-arm-write-token.tf:29` all mint read tokens, "NOT the full-prd `var.doppler_token`, per security review"). Do NOT source `webhook-deploy` (deploy-owned; imports `DOPPLER_CONFIG_DIR=/tmp/.doppler`). With `HOME=/root` + a token-only env value (no `DOPPLER_CONFIG_DIR`), doppler uses `/root/.doppler` — **permanently eliminating hypothesis (d)**. NB the fleet's root-doppler precedent (inngest-cutover-flip etc.) uses `HOME=/root` + a `/tmp/.doppler` redirect *because* those units are `User=deploy`+`ProtectHome=read-only`; the root, no-ProtectHome probes correctly diverge and need no redirect. |
| (b) EnvironmentFile missing/incomplete → per-probe FATAL exit 1 | **Less likely.** The `/etc/default/web-*` files ARE written (server.tf:463/506/549) with the probe keys; and the *fail-soft* git-data probe (defaults its endpoint, only WARNs on a missing URL) fails **identically** — a per-probe FATAL would differ across the three. The identical failure localises upstream to the shared `doppler run` wrapper. | Not the live cause; **confirm/exclude via the Phase-1-shipped stderr** (do not mark refuted). |
| (c) ZOT_PULL_USER/TOKEN absent from prd doppler | **Excluded.** Both are in `soleur/prd` (`zot-registry.tf:257-271`) and consumed identically by cloud-init `docker login`. Also would explain only the zot probe, not all 3. But the probe never *reaches* the cred check (doppler dies first). | Not the cause; noted UNKNOWN-but-excluded until stderr confirms. |
| (d, new) `/tmp/.doppler` ownership clash (the #6536 mechanism) | **Not the current cause** (units run root-vs-root: `/tmp/.doppler` is root-owned from boot, a root unit reads it fine). **But a forward hazard:** if the fix switches any unit to `User=deploy` WITHOUT `PrivateTmp=true`, it WILL hit `open /tmp/.doppler/…: permission denied`. | **Constraint on the fix:** keep the units root-run; if ever deploy-run, add `PrivateTmp=true`. |
| Observability: Source 4 not live on web-1 | **Confirmed (measured).** Source 4 lists all 3 tags but no provisioner delivers/reloads `vector.toml` on the running web-1; 0 probe-tagged rows in Better Stack for the window. | **Phase 1 deliverable:** a new SSH provisioner delivers `vector.toml` + reloads the vector agent on web-1. |

## Hypotheses (diagnosis discipline — learning 2026-07-16)

**The deciding datum is currently invisible.** The probe/doppler stderr is NOT shipped (Source 4 not
live on web-1 — measured: 0 probe-tagged rows). Per learning 2026-07-16 §1, **no root-cause verdict
may read CONFIRMED purely from reasoning while its discriminator is invisible.** What IS confirmed
comes from *visible* evidence, not inference:

- **CONFIRMED (self-pulled telemetry):** all 3 units fail (`Failed with result 'exit-code'`), web-1,
  2026-07-18 09:14–09:30 UTC; and the probe's own stderr does NOT reach Better Stack (0 probe-tagged
  rows vs 59 systemd rows).
- **CONFIRMED (unit diff — visible source, the endorsed method):** all 3 units lack `HOME=/root`
  (which every working root-doppler unit on the fleet sets) and any token source; web-1 has no
  working root-doppler-auth precedent. This is a two-fold structural gap on the failing host's own
  units — materially stronger than #6536's dev-box `curl` evidence, but still a **prediction of the
  runtime error** (`$HOME is not defined` fires first and may mask a downstream token error).
- **LEADING (to be measured):** `$HOME is not defined` + missing token is the live cause. **The
  Phase-1 observability delivery exists to turn this prediction into a measurement** — the next
  timer fire self-reports the actual doppler error, off-box, no SSH.
- **Network-outage checklist (plan Phase 1.4, L3→L7 order):** the L3 layer is **cleared** — the SSH
  `terraform_data` provisioner reached web-1 successfully (units were delivered), the firewall/egress
  path to web-1 is proven, and `SOLEUR_PRIVATE_NIC nic_ok=true` emits healthily (from the *registry*
  host guard — `reboot_count=1`, the web guard emits the constant `reboot_count=0`, so web-1's own
  guard produced no telemetry, consistent with the unit failing before its emit step). This is a
  **probe-UNIT startup bug, not a network outage** — no sshd/fail2ban/firewall change is proposed.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing *new* immediately (web-1 serves normally;
the monitors are safely paused), but the operator's private-net degradation detection stays
**dark** — a web host silently losing its private-NIC path to zot/git-data falls back to
GHCR/degraded, every health signal stays green, and deploys/data-access rot for days undetected
(the #6400 shape). A **half-armed probe that reads as coverage while providing none is worse than
none** (ADR-117).

**If this leaks, the user's data/workflow/money is exposed via:** minimal new surface — a dedicated
Terraform-minted **read-scoped** prd token (`doppler_service_token.web_probes`, `access=read`) written
into the existing per-probe `/etc/default/web-<probe>` files (600). Least-privilege by construction
(read-only, not the full-prd `var.doppler_token`); no PII in the beats; no new operator secret.

**The one live-prod mutation — the vector-agent reload on web-1 (folded into the IaC
`terraform_data.journald_persistent` remote-exec) — cannot reach serving traffic:** vector is a
journald→Better Stack log-shipper sidecar, not in the request path (the app is served behind the
cloudflared tunnel); its journald sources resume from their `sd_journal` cursor after the sub-second
reload with no gap (persistent journal), so no user-facing disruption. A botched render fails the apply
(render-sanity gate) BEFORE the running agent is touched, so vector never goes down on a bad config.

**Brand-survival threshold:** **single-user incident.** CPO sign-off required at plan time (carried
forward from the brainstorm framing); `user-impact-reviewer` runs at review time.

## Implementation Phases

**Delivery intent is probe-first** (learning 2026-07-16 §2), but deepen-plan review (spec-flow +
architecture) established that in ONE auto-applied PR the merge runs a single apply job that delivers
vector + the unit fix together and arms in the same job — so the "measure the *still-broken* units'
stderr before fixing" checkpoint is **structurally unreachable** as a single-PR AC (see decision-
challenges §1 for the two-PR alternative). The essential #6536 value survives: once Source 4 is live
(same merge), ANY residual failure is self-diagnosable off-box. The root cause is already **confirmed
from the unit diff** (visible source), so the broken-state beat is confirmatory, not load-bearing.

### Phase 1 — Observability + token delivery (co-located, ordered)
1. **Token, folded into the existing probe installers (NOT a new file).** In each of the 3
   `terraform_data.*_install` remote-execs (server.tf:463/506/549), append `DOPPLER_TOKEN=<token>` to
   the existing `printf … > /etc/default/web-<probe>` line. The token value is a **dedicated
   Terraform-minted `doppler_service_token.web_probes`** (`config=prd, access=read` — the
   `web-arm-write-token.tf` pattern; self-provisioning, no operator mint). Extend each installer's
   `triggers_replace` to hash `doppler_service_token.web_probes.key` so a rotation re-fires delivery.
   This co-locates the token with the unit that `enable --now`s the timer — no cross-resource ordering
   race, no new `-target` entry, no new file surface.
2. **Vector delivery to running web-1 — fold into `terraform_data.journald_persistent`**
   (server.tf:668; it already SSHes web-1 + reloads a host observability daemon AND is on the SSH
   `-target` list, so no new resource / no new `-target` entry — /work to confirm it is targeted; else
   add a new resource AND append it to the workflow `-target` list + Files to Edit). Deliver the
   rendered `vector.toml` → `/etc/vector/vector.toml` and reload the vector agent (re-invoke
   `/usr/local/bin/soleur-vector-install`, which already renders host_name; reload mechanics in the
   IaC section). Extend its `triggers_replace` to hash `file(vector.toml)`.
3. **Positive-control canary (observability review P1 — close the recurrence blind spot).** The probes
   are silent-on-success, so Source-4 liveness is only observable during a fault → a future
   vector-delivery regression would be silent AND heartbeats (pinged by direct curl, independent of
   Source 4) would stay green. Adopt the luks-monitor (#6604) pattern the `vector.toml` comment
   documents: emit a periodic benign tagged row on HEALTHY runs so Source-4 liveness is a steady-state
   canary. /work to pick the cadence-appropriate mechanism (a low-frequency `[probe] ok` line vs
   `SOLEUR_PROBE_VERBOSE=1` — weigh the 60s-cadence quota cost the scripts deliberately gate off).

### Phase 2 — Unit-start fix
4. Edit the three unit files — add, in `[Service]`, ONLY `Environment=HOME=/root` (doppler then uses
   `/root/.doppler`; the token now arrives via each unit's EXISTING `EnvironmentFile=/etc/default/web-<probe>`
   — no new `EnvironmentFile=` directive). Keep units **root-run** (no `User=`; never `User=deploy`
   without `PrivateTmp=true`). **Fail loud, no degrade guard** (advisor + `cq-silent-fallback-must-mirror-to-sentry`):
   a token regression must surface as a `failed` unit + visible stderr + heartbeat lapse. Units are
   delivered byte-identical by the SSH provisioner (web-1) AND the cloud-init bake (future hosts,
   #6459), so one edit fixes both routes.
5. The `.service` edits change each `*_install` provisioner's `triggers_replace` hash → force
   re-delivery + `daemon-reload` + `enable --now` (verified: server.tf:476 hashes the `.service`).

### Phase 3 — Arm the heartbeats
6. **On merge**, `apply-web-platform-infra.yml` (push trigger) applies everything AND runs the "Arm
   web-host probe heartbeats" step (apply-web-platform-infra.yml:719-794) in the SAME job — it does
   NOT wait for a separate dispatch. So the merge itself attempts the arm right after re-delivering the
   fixed units; if the units are already beating it arms GREEN, else it fail-loud rolls back (safe).
   The `workflow_dispatch` re-run (`gh workflow run apply-web-platform-infra.yml --ref main -f
   reason='arm L3 probes after unit-start fix (#6438/#6548)'`) is the deliberate RETRY once
   self-pulled telemetry confirms the units beat. The arm unpauses → polls `status==up` within
   deadline (web-zot-consumer 230s, web-nic-guard 470s, git-data-prd 230s). **Cadence caveat:** the
   60s-cadence probes land a beat well inside their deadline; the nic-guard's 5-min cadence gives ~one
   post-unpause fire inside 470s — reconcile the Observability period figures with the live deadlines
   at /work so the GREEN is not marginal.

### Phase 4 — Soak handoff (do NOT touch)
6. `scripts/followthroughs/l3-probe-armed-6438.sh` (already enrolled: directive + `follow-through`
   label on #6438; `BETTERSTACK_API_TOKEN` already wired) soaks and, once all three monitors hold
   `up`, closes #6438/#6548 on its own (earliest 2026-07-25). **This plan does not close them.**

## Files to Edit

- `apps/web-platform/infra/web-zot-consumer-probe.service` — add `Environment=HOME=/root` (token arrives via the existing `EnvironmentFile=/etc/default/web-zot-consumer-probe`).
- `apps/web-platform/infra/web-git-data-probe.service` — same (existing `/etc/default/web-git-data-probe`).
- `apps/web-platform/infra/web-private-nic-guard.service` — same (existing `/etc/default/web-private-nic-guard`).
- `apps/web-platform/infra/server.tf` — (1) in each of the 3 `*_install` remote-execs, append `DOPPLER_TOKEN=<token>` to the existing `printf … > /etc/default/web-<probe>` line + hash `doppler_service_token.web_probes.key` in `triggers_replace`; (2) fold the `vector.toml` delivery + reload into `terraform_data.journald_persistent` (server.tf:668) and hash `file(vector.toml)` in its `triggers_replace` (or a new resource + `-target` entry if journald_persistent is not targeted).
- `apps/web-platform/infra/web-arm-write-token.tf` (or a new `web-probe-read-token.tf`) — add `doppler_service_token.web_probes` (`config=prd, access=read`) + a `doppler_secret`/local wiring for the token value.
- `.github/workflows/apply-web-platform-infra.yml` — **only if** vector delivery is a NEW resource: append it to the SSH `-target` list (~:681-694). If folded into `journald_persistent` (already targeted), no workflow edit. (HARD requirement, not a footnote — a new untargeted `terraform_data` is silently skipped on merge-apply.)
- `apps/web-platform/test/` — extend the infra drift-guard: assert each probe `.service` carries `Environment=HOME=/root`; each `/etc/default/web-<probe>` write includes `DOPPLER_TOKEN`; no probe unit sets `User=deploy` w/o `PrivateTmp=true` or references `/tmp/.doppler`; a `vector.toml` delivery/reload path to web-1 exists with `triggers_replace` hashing `vector.toml`. Shell tests `.test.sh` in `test/` (constitution); register in `infra-validation.yml`.
- `knowledge-base/engineering/architecture/decisions/ADR-123-*.md` — **light amendment note** (web-1 root-doppler-unit auth contract). See ADR/C4 section.

## Files to Create

- `knowledge-base/project/learnings/…/2026-07-18-web-1-has-no-root-doppler-auth-systemd-precedent-and-vector-toml-has-no-running-host-delivery.md` — the compound learning (created at write-time by /work; directory + topic only, date at write-time).
- (Token IaC) a new `web-probe-read-token.tf` if `doppler_service_token.web_probes` is not co-located in an existing token `.tf`.

(No new `apps/web-platform/test/web-probe-doppler-auth.test.sh` — the assertions are a few greps; fold into the existing infra drift-guard, per simplicity review.)

## Observability

```yaml
liveness_signal:
  what: three Better Stack heartbeats (soleur-web-zot-consumer-web-1, soleur-web-nic-guard-web-1, soleur-git-data-prd) pinged by the web-1 systemd timers (60s cadence)
  cadence: period 180/360/180s, grace 60/120/180s
  alert_target: email (fleet baseline; betterstack_paid_tier=false — escalation is #6549, out of scope)
  configured_in: apps/web-platform/infra/web-probe.tf + git-data.tf; armed by apply-web-platform-infra.yml:719-794
error_reporting:
  destination: Better Stack Logs source 2457081 (soleur-inngest-vector-prd), host_name=soleur-web-platform, via vector Source 4 (host_scripts_journald) — NEWLY LIVE on web-1 after Phase 1
  fail_loud: yes — probe FATAL/classification stderr (SyslogIdentifier=web-{zot-consumer-probe,git-data-probe,nic-guard}) ships off-box; the doppler-auth error will self-report once Phase 1 applies (Source 4 goes live on web-1 on the merge-apply — not before)
failure_modes:
  - mode: doppler run fails (no HOME/token) — the current bug
    detection: SYSLOG_IDENTIFIER=web-*-probe stderr in Better Stack (Source 4) shows "Doppler Error: $HOME is not defined" / auth error
    alert_route: heartbeat absence → email alarm (after arm)
  - mode: private-NIC path to zot/git-data broken (consumer-perspective)
    detection: probe SUPPRESS-ping stderr (000 UNREACHABLE / 404 / 401) + heartbeat absence; NIC guard emits discriminating SOLEUR_PRIVATE_NIC {nic_ok,converged_by,imds_rc,imds_nets,imds_has_expected}
    alert_route: heartbeat absence → email alarm
  - mode: vector on web-1 not shipping Source 4 (this observability gap recurring)
    detection: absence of the HEALTHY positive-control canary row (Phase 1 step 3, luks-#6604 pattern) — NOT "monitor not up" (heartbeats ship by direct curl, independent of Source 4, so a Source-4 death leaves them green)
    alert_route: the recurring canary-read (drift-guard asserts the delivery/reload path statically; a runtime read of the canary row is the live signal). NOTE: l3-probe-armed-6438.sh (status==up only) CANNOT detect this mode — do not rely on it here.
logs:
  where: Better Stack Logs (ClickHouse warehouse, table t520508_soleur_inngest_vector_prd_3_logs)
  retention: hot ~40min + s3 archive (queried via scripts/betterstack-query.sh with the UNION-ALL archive arm)
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep web-zot-consumer-probe --grep web-nic-guard --grep web-git-data-probe"
  expected_output: the HEALTHY positive-control canary row (Phase 1 step 3) tagged with a probe SyslogIdentifier from host soleur-web-platform — present in steady state (NO ssh). Its ABSENCE = Source 4 dark (the exact recurrence). (Without the canary the probes are silent-on-success, so 0 rows is ambiguous — healthy vs Source-4-dead.)
```

**Affected-surface note (plan 2.9.2):** the probe oneshot units are a blind execution surface — the
fix's whole Phase 1 IS the in-surface probe (their own stderr, now shipped), and the NIC guard's
`SOLEUR_PRIVATE_NIC` event already discriminates every competing NIC-fault hypothesis in one event.

## Infrastructure (IaC)

### Terraform changes
- **Token:** new `doppler_service_token.web_probes` (`config=prd, access=read` — Terraform-minted,
  self-provisioning, no operator mint; the fleet least-privilege convention, NOT `var.doppler_token`).
  Its value is appended as `DOPPLER_TOKEN=` inside each existing `*_install` remote-exec's
  `/etc/default/web-<probe>` write (server.tf:463/506/549), and hashed into each installer's
  `triggers_replace`. No new file, no new resource-ordering dependency (co-located with the unit).
- **Vector:** fold `vector.toml` delivery + reload into `terraform_data.journald_persistent`
  (server.tf:668; already SSHes web-1 + reloads a host daemon + is on the SSH `-target` list) — hash
  `file(vector.toml)` into its `triggers_replace`. The reload runs inside the terraform_data
  remote-exec, an IaC-owned step. If journald_persistent is not `-target`ed, use a new resource AND
  append it to the workflow `-target` list.
- The 3 `.service` edits require no new `.tf` — they re-fire the `*_install` provisioners via
  `triggers_replace`. Reuses `var.ci_ssh_private_key`.

### Apply path
- (b) cloud-init + idempotent re-delivery: the `.service` fixes reach web-1 via the existing SSH
  provisioners (idempotent `daemon-reload` + `enable --now`); the new vector provisioner is idempotent
  (`soleur-vector-install` is designed to be re-run). No host replace. Blast-radius: web-1 only;
  the vector reload is non-disruptive to serving traffic.

### Distinctness / drift safeguards
- Single live host (web-2 retired #6538). `ignore_changes=[paused]` on the heartbeats keeps source
  paused=true; the arm gate PATCHes live. No `dev`/`prd` collision (infra is prd-only). A new
  `terraform_data` resource must be added to the arm workflow's `-target` list or applied via a full
  plan — /work to confirm.

### Vendor-tier reality check
- Better Stack free-tier: heartbeats are unconditionally creatable; escalation stays email-only
  (`betterstack_paid_tier=false`). No tier gate needed.

## Architecture Decision (ADR/C4)

No **new** architectural decision — ADR-123 already records the web-host probe design (detect+emit+
alarm, no reboot). This fixes the **delivery/auth** of the units that implement it.

### ADR
- **Amend ADR-123** with a short implementation-contract note: *"web-1 root-run doppler systemd units
  MUST set `Environment=HOME=/root` and receive a prd-scoped `DOPPLER_TOKEN` from a dedicated
  read-scoped `doppler_service_token` written into the unit's own `/etc/default/web-<probe>` file
  (600) — NOT `webhook-deploy` (deploy-owned; imports `DOPPLER_CONFIG_DIR=/tmp/.doppler`), and NOT
  `var.doppler_token` (full-prd). `/etc/default/inngest-server` is absent when
  `web_colocate_inngest=false`. With `HOME=/root` doppler uses `/root/.doppler`; never touch
  `/tmp/.doppler`; never `User=deploy` without `PrivateTmp=true`."* Records the invariant so #6459
  (future-host bake) inherits it — the token file must also be baked for fresh hosts (see Sharp Edges).

### C4 views
- **No C4 impact.** Enumerated against the change: external human actors — none added; external systems
  — zot (10.0.1.30), git-data (10.0.1.20), Better Stack are all already modeled (the merged PR added
  the consumer-probe edges to `model.c4`); containers/data-stores — none new; actor↔surface access
  relationships — none changed (the probe units, their targets, and the BetterStack sink edge already
  exist). /work to confirm by reading `diagrams/{model.c4,views.c4,spec.c4}` that no new element/edge is
  introduced; a delivery/auth bug fix on already-modeled elements adds none.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Each of the 3 probe `.service` files contains `Environment=HOME=/root` (grep-guard test); no
      probe `.service` sources `/etc/default/webhook-deploy` or sets a `DOPPLER_CONFIG_DIR`.
- [ ] Each `*_install` remote-exec writes `DOPPLER_TOKEN=` (from `doppler_service_token.web_probes`)
      into its `/etc/default/web-<probe>` file; `doppler_service_token.web_probes` has `access="read"`.
- [ ] No probe `.service` sets `User=deploy` without `PrivateTmp=true`; no probe unit references
      `/tmp/.doppler` (grep-guard test).
- [ ] A `vector.toml` delivery+reload path to web-1 exists (in `journald_persistent` or a new resource)
      with `triggers_replace` hashing `file(vector.toml)`; **if a NEW resource, it is in the workflow
      SSH `-target` list** (grep the workflow — hard gate, not a footnote).
- [ ] A positive-control healthy canary row is emitted to Source 4 (Phase 1 step 3) and the
      `discoverability_test`/failure_mode-3 detection keys on it.
- [ ] Drift-guard test registered in `infra-validation.yml`; `tsc`/shell tests green.
- [ ] PR body uses **`Ref #6438 #6548`** (NOT `Closes`).
- [ ] SpecFlow analysis run on the infra change (constitution: infra changes require SpecFlow).
- [ ] ADR-123 amendment note present.

### Post-merge (operator/automated — sequenced, all automatable)
- [ ] **Merge-apply verified:** after the merge apply, self-pulled telemetry shows (a) the probe units
      start cleanly (no `Failed with result exit-code` in Better Stack) and (b) the positive-control
      canary + probe classification rows reach Source 4 (Source 4 now live on web-1). *Automation:*
      `scripts/betterstack-query.sh`. (The pre-fix "measure the still-broken units first" reading is
      best-effort only — structurally unreachable in one PR; see decision-challenges §1.)
- [ ] **Arm GREEN:** `apply-web-platform-infra.yml` arm step reports all 3 heartbeats `status=up` —
      either on the merge-apply (if units already beating) or on the deliberate `workflow_dispatch`
      re-run (`gh workflow run … -f reason=…`) once telemetry confirms beats. *Automation:*
      `gh workflow run` + `gh run watch`.
- [ ] **Soak:** l3-probe-armed-6438.sh (earliest 2026-07-25) closes #6438/#6548 — verified by the
      sweeper, not this PR.

## Test Scenarios (Given/When/Then)

- **Given** a probe `.service` + its `*_install` env-file write, **When** the drift-guard runs,
  **Then** it asserts `Environment=HOME=/root` and `DOPPLER_TOKEN=` in the env-file write (fails RED
  on the current, unfixed files).
- **Given** the fix applied on merge, **When** a timer fires, **Then** the probe classifies
  (200/reachable/nic_ok), pings its heartbeat, AND the positive-control canary row reaches Source 4;
  `betterstack-query.sh` shows the beat + the canary (NO ssh).
- **Given** Source 4 later regresses on web-1, **When** the discoverability_test runs, **Then** the
  canary row is ABSENT — the recurrence is detectable (it was not before this fix).
- **Given** the units beating, **When** the arm step runs (merge-apply or dispatch), **Then** each
  monitor transitions to `up` within its deadline and stays armed.
- *(Best-effort, not a gate):* if the vector delivery could be applied strictly before the unit fix
  (two-PR path, decision-challenges §1), a `web-*-probe`-tagged `Doppler Error: $HOME is not defined`
  row would confirm the root cause on the still-broken units.

## Domain Review

**Domains relevant:** engineering (infra). Product/UX — **NONE** (no UI surface; no `page.tsx`/
`layout.tsx`/component; the mechanical UI-surface override does not fire). Legal/finance/etc. — none
(internal telemetry, existing sub-processor Better Stack, no PII, no new vendor).

### Engineering (carry-forward + fix-specific)
**Status:** reviewed (brainstorm carry-forward + plan-time analysis).
**Assessment:** The parent feature's `## Domain Assessments` (CTO, platform-strategist, CPO, CLO —
brainstorm 2026-07-18) are carried forward. The **new decision** this fix introduces — the web-1
root-doppler-unit auth pattern (HOME/token from `webhook-deploy`) + the vector-delivery provisioner —
is a delivery-correctness change within the reviewed ADR-123 design. Sent to the plan-time **scoped
strong-model advisor** (Phase 4.5) on the riskiest phase; the eng plan-review panel (DHH/Kieran/
simplicity) + `architecture-strategist` (single-user threshold) + deepen-plan run downstream.

**Brainstorm-recommended specialists:** none beyond the carried-forward leaders.

## Open Code-Review Overlap

None. Open `code-review` issues (#3191 GitHub callback probes, #2349 qa port-probe) touch none of the
files this plan edits.

## Non-Goals (do NOT touch — already done)

- The merged L3 probe PR 14075d1b (ADR-123, vector.toml Source 4 wiring, lint-bot-statuses regions,
  validate-vector-config SyslogIdentifier, the 2 review P2s).
- GH secrets `DOPPLER_TOKEN_WEB_ARM` / `BETTERSTACK_API_TOKEN` (provisioned); the sweeper's
  `BETTERSTACK_API_TOKEN` wiring.
- `scripts/followthroughs/l3-probe-armed-6438.sh` and its enrollment directive.
- Closing #6438/#6548 (soak-gated — `Ref`, not `Closes`).
- The A5 deferral decision-challenge issue (#6656) and future-host cloud-init bake (#6459).
- Escalation / paid-tier (#6549). NIC-guard reboot semantics (ADR-123 — unchanged).

## Sharp Edges

- **Diagnosis discipline (learning 2026-07-16):** the doppler-auth root cause is established by a
  **unit diff** (visible source), not a dev-box probe. In ONE auto-applied PR the merge applies vector
  + unit fix together and arms in the same job, so the "measure the still-broken units first"
  checkpoint is structurally unreachable (spec-flow + architecture review) — it is DEMOTED to
  best-effort, and the true probe-first measurement requires the two-PR split (decision-challenges §1).
  The essential value survives: once Source 4 is live (same merge), any residual failure is
  self-diagnosable.
- **Silent-on-success blind spot (observability review):** without the positive-control canary
  (Phase 1 step 3), the probes emit nothing to Source 4 when healthy, so a future vector-delivery
  regression is INVISIBLE (heartbeats ship by direct curl, stay green). The canary is what makes the
  recurrence detectable — do NOT drop it as "extra scope"; it is the honesty the feature exists for.
- **`-target` membership is load-bearing (spec-flow CRITICAL):** a NEW untargeted `terraform_data`
  vector resource is SILENTLY SKIPPED on merge-apply while the `.service`-triggered installs ship —
  leaving units that now require the token but never got vector. Fold vector into `journald_persistent`
  (already targeted) OR add the new resource to the workflow `-target` list AND Files to Edit.
- **Token co-location removes the ordering race:** deliver the token inside each `*_install` (which
  `enable --now`s the timer) — NOT a separate resource — so the token file always exists before the
  timer fires. A separate resource without `depends_on` races the enable (nic-guard's ~1 post-unpause
  fire makes a first-fire race a false rollback).
- **The arm runs on the merge PUSH, not only workflow_dispatch:** the merge itself attempts the arm
  right after re-delivering units; plan for a fail-loud-safe rollback if timing misses, and use the
  dispatch re-run as the deliberate retry once beats are confirmed.
- **#6459 fresh-host bake:** the token is delivered only by the web-1 SSH provisioner; a future baked
  host would get units requiring `DOPPLER_TOKEN` with nothing writing it. Out of scope here, but record
  it as an explicit #6459 blocker (the ADR note alone won't prevent it).
- **`$HOME` masks the token error:** doppler checks `$HOME` before auth, so the first shipped error
  will be `$HOME is not defined`; the fix must add BOTH `HOME=/root` AND the token source — fixing only
  one leaves the other latent.
- **`User=deploy` + missing `PrivateTmp=true` = the #6536 clash.** The dedicated `HOME=/root` +
  token-only file means doppler uses `/root/.doppler` and NEVER `/tmp/.doppler`, so the fix eliminates
  this surface. Keep the units root-run; if ever deploy-run, add `PrivateTmp=true`. Do NOT "fix" auth
  by sourcing `webhook-deploy` — its `DOPPLER_CONFIG_DIR=/tmp/.doppler` re-opens the exact surface.
- **`triggers_replace` is load-bearing for re-delivery** — verified it hashes the `.service` content
  (server.tf:476), so the edits re-provision. The NEW vector provisioner must likewise hash
  `vector.toml`, else the reload never reaches web-1 (the "plan unchanged defers the real test to prod"
  trap, constitution line 182).
- **`-target` scope:** a new `terraform_data` resource must be in the arm workflow's `-target` list (or
  applied via full plan) or the merge-apply silently skips it.
- **PIR consideration:** this is a post-merge delivery defect caught by the fail-loud arm gate (working
  as designed), monitors safely paused, **no user impact** — the sibling #6536 produced a *learning*,
  not a PIR. Primary artifact = the compound learning; if `/ship` Phase 5.5's Incident-PIR gate fires,
  a short PIR under `post-mortems/` is the deliverable.
- **A plan whose `## User-Brand Impact` is empty/TODO fails deepen-plan Phase 4.6** — it is filled above.

## Rollback plan

Revert the PR. The `.service` + env-file edits revert to the prior (broken-but-inert) units; the vector
fold is additive (reverting stops shipping Source 4 but breaks nothing). The heartbeats stay paused
(source `paused=true`, `ignore_changes=[paused]`), so a revert cannot fire a false alarm. **Note:** the
revert push itself re-runs the arm step, which fail-loud rolls the monitors back to paused once more —
harmless to users (monitors stay paused), but not a silent no-op. No data migration, no user-facing
surface.
