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
| (a) `doppler run --config prd` has no auth in the unit env | **Confirmed as source-level gap.** Units set no `HOME` and source no token; `/etc/default/inngest-server` (sibling token source) is absent on web-1; only `/etc/default/webhook-deploy` carries a prd token (deploy-owned). No root-doppler-auth systemd precedent exists on web-1. | **Leading fix:** add `Environment=HOME=/root` + `EnvironmentFile=/etc/default/web-probes` to all 3 units, where `/etc/default/web-probes` is a NEW `root:root 600` file (only `DOPPLER_TOKEN`, a prd-read token value) delivered by the new provisioner. Do NOT source `webhook-deploy` (advisor Phase 4.5): it is deploy-owned and imports `DOPPLER_CONFIG_DIR=/tmp/.doppler` — coupling the probe lifecycle to a deploy-rotated file and dragging in the `/tmp/.doppler` surface. With `HOME=/root` + a token-only file, doppler uses `/root/.doppler` and never touches `/tmp/.doppler` — **permanently eliminating hypothesis (d)**. |
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

**If this leaks, the user's data/workflow/money is exposed via:** no new exposure vector. No PII in
the beats; the fix sources an existing prd-scoped token (`webhook-deploy`) already present on web-1 —
no new secret, no new surface.

**Brand-survival threshold:** **single-user incident.** CPO sign-off required at plan time (carried
forward from the brainstorm framing); `user-impact-reviewer` runs at review time.

## Implementation Phases

**Phase ordering is load-bearing** (learning 2026-07-16 §2: "the probe ships before the fix so the
next fire self-reports which defect was live"). The apply is `-target`-scoped and dispatch-gated, so
these apply steps are sequenced within the one PR.

### Phase 1 — Observability delivery + token file (probe ships FIRST)
1. Add a new `terraform_data` provisioner in `server.tf` (sibling to `journald_persistent` /
   `zot_consumer_probe_install`) that SSH-connects to web-1 and does TWO deliveries via its
   remote-exec (the established IaC pattern — see the `## Infrastructure (IaC)` section for the
   vector-reload mechanics):
   - **(a) vector.toml:** deliver the updated `vector.toml`, render `@@HOST_NAME@@` (mirror
     `soleur-host-bootstrap.sh:342` — or re-invoke `/usr/local/bin/soleur-vector-install`), install it
     to `/etc/vector/vector.toml`, and reload the vector agent (same IaC pattern as the existing
     `*_install` provisioners' daemon-reload; the reload verb is documented in the IaC section).
   - **(b) doppler token file:** write `/etc/default/web-probes` as `root:root`, `chmod 600`, content
     `DOPPLER_TOKEN=<prd-read token>`. Reuse the existing web-1 prd-read token value (the same
     `doppler_token`/write-token already on the host in `webhook-deploy` — no new operator mint,
     `hr-tf-variable-no-operator-mint-default`); OR mint a dedicated read-scoped
     `doppler_service_token` (least-privilege, the `web-arm-write-token.tf` pattern with `access="read"`)
     — /work + deepen-plan to pick, defaulting to reuse (minimal, no new secret to provision).
   `triggers_replace = sha256(join(",", [file(".../vector.toml"), host_name render input, token ref]))`
   so a vector.toml edit OR token change re-fires it. Idempotent.
2. **Apply Phase 1 first** (`-target` the new provisioner via `apply-web-platform-infra.yml`), then
   **self-pull telemetry** (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
   --grep web-zot-consumer-probe --grep 'Doppler Error'`). **Evidence checkpoint:** confirm the probe
   stderr now ships AND reads the predicted `$HOME is not defined` / auth error on the still-broken
   units. This is the measured confirmation of the root cause.

### Phase 2 — Unit-start fix (verified against the Phase-1 reading)
3. Edit the three unit files — add, in `[Service]`:
   - `Environment=HOME=/root` (doppler needs `$HOME`; with it, doppler uses `/root/.doppler` — no
     `/tmp/.doppler`).
   - `EnvironmentFile=/etc/default/web-probes` (the NEW `root:root 600` token file from Phase 1(b),
     `DOPPLER_TOKEN` only). Do NOT source `webhook-deploy` (advisor Phase 4.5 — deploy-owned, and its
     `DOPPLER_CONFIG_DIR=/tmp/.doppler` reintroduces the surface we are eliminating).
   - Keep the units **root-run** (no `User=`) — do NOT introduce `User=deploy` without
     `PrivateTmp=true` (hypothesis d). Keep the existing `EnvironmentFile=/etc/default/web-*`
     (probe keys) — no key overlap with the token file.
   - **Fail loud, no degrade guard** (advisor Phase 4.5 + `cq-silent-fallback-must-mirror-to-sentry`):
     do NOT wrap the doppler call in a `[ -n "$DOPPLER_TOKEN" ]` exit-0 degrade. A token regression
     must surface as a `failed` unit + visible stderr (now shipped) + heartbeat lapse — three signals,
     not a systemd-green silent lapse. On web-1 the token is present, so the units succeed.
   Because these units are delivered **byte-identical** by both the SSH provisioner (web-1) and the
   cloud-init bake (future hosts, #6459), one edit fixes both routes.
4. **Apply Phase 2** — the `.service` edits change each `*_install` provisioner's `triggers_replace`
   hash → force re-delivery + `daemon-reload` + `enable --now` (verified: `server.tf:476` hashes the
   `.service` content). Self-pull telemetry: confirm probe classification/success stderr ships and a
   real beat lands.

### Phase 3 — Arm the heartbeats
5. Re-run `apply-web-platform-infra.yml` via `workflow_dispatch` with a `reason` input
   (`gh workflow run apply-web-platform-infra.yml --ref main -f reason='arm L3 probes after unit-start fix (#6438/#6548)'`).
   The "Arm web-host probe heartbeats" step (apply-web-platform-infra.yml:719-794) unpauses →
   polls `status==up` within period+grace → leaves armed (deadlines: web-zot-consumer 230s,
   web-nic-guard 470s, git-data-prd 230s). Timer cadence 60s ⇒ a beat lands well inside every deadline.

### Phase 4 — Soak handoff (do NOT touch)
6. `scripts/followthroughs/l3-probe-armed-6438.sh` (already enrolled: directive + `follow-through`
   label on #6438; `BETTERSTACK_API_TOKEN` already wired) soaks and, once all three monitors hold
   `up`, closes #6438/#6548 on its own (earliest 2026-07-25). **This plan does not close them.**

## Files to Edit

- `apps/web-platform/infra/web-zot-consumer-probe.service` — add `Environment=HOME=/root` + `EnvironmentFile=/etc/default/web-probes`.
- `apps/web-platform/infra/web-git-data-probe.service` — same.
- `apps/web-platform/infra/web-private-nic-guard.service` — same.
- `apps/web-platform/infra/server.tf` — add `terraform_data.web_vector_reload_install` (deliver `vector.toml` + reload the vector agent on web-1 AND write `/etc/default/web-probes` root:root 600 with the prd-read `DOPPLER_TOKEN`). Optionally add a read-scoped `doppler_service_token` resource if not reusing the existing token. (The 3 probe `*_install` provisioners already re-fire on the `.service` edits via `triggers_replace` — no change to them needed for re-delivery.)
- `apps/web-platform/test/` (or the infra validation surface) — extend the drift-guard: assert each probe `.service` carries `Environment=HOME=/root` AND an `EnvironmentFile` supplying `DOPPLER_TOKEN`; assert a delivery/reload path exists for `vector.toml` on web-1. Shell tests are `.test.sh` in the `test/` sibling (constitution); register in `infra-validation.yml`.
- `knowledge-base/engineering/architecture/decisions/ADR-123-*.md` — **light amendment note** recording the web-1 root-doppler-unit auth contract (HOME=/root + prd token from `webhook-deploy`; never `User=deploy` without `PrivateTmp=true`). See ADR/C4 section.

## Files to Create

- `knowledge-base/project/learnings/…/2026-07-18-web-1-has-no-root-doppler-auth-systemd-precedent-and-vector-toml-has-no-running-host-delivery.md` — the compound learning (created at write-time by /work; directory + topic only, date at write-time).
- (Possibly) `apps/web-platform/test/web-probe-doppler-auth.test.sh` — the drift-guard, if a new file is the right home.

## Observability

```yaml
liveness_signal:
  what: three Better Stack heartbeats (soleur-web-zot-consumer-web-1, soleur-web-nic-guard-web-1, soleur-git-data-prd) pinged by the web-1 systemd timers (60s cadence)
  cadence: period 180/360/180s, grace 60/120/180s
  alert_target: email (fleet baseline; betterstack_paid_tier=false — escalation is #6549, out of scope)
  configured_in: apps/web-platform/infra/web-probe.tf + git-data.tf; armed by apply-web-platform-infra.yml:719-794
error_reporting:
  destination: Better Stack Logs source 2457081 (soleur-inngest-vector-prd), host_name=soleur-web-platform, via vector Source 4 (host_scripts_journald) — NEWLY LIVE on web-1 after Phase 1
  fail_loud: yes — probe FATAL/classification stderr (SyslogIdentifier=web-{zot-consumer-probe,git-data-probe,nic-guard}) ships off-box; the doppler-auth error is now self-reporting
failure_modes:
  - mode: doppler run fails (no HOME/token) — the current bug
    detection: SYSLOG_IDENTIFIER=web-*-probe stderr in Better Stack (Source 4) shows "Doppler Error: $HOME is not defined" / auth error
    alert_route: heartbeat absence → email alarm (after arm)
  - mode: private-NIC path to zot/git-data broken (consumer-perspective)
    detection: probe SUPPRESS-ping stderr (000 UNREACHABLE / 404 / 401) + heartbeat absence; NIC guard emits discriminating SOLEUR_PRIVATE_NIC {nic_ok,converged_by,imds_rc,imds_nets,imds_has_expected}
    alert_route: heartbeat absence → email alarm
  - mode: vector on web-1 not shipping Source 4 (this observability gap recurring)
    detection: 0 probe-tagged rows in Better Stack while units fire — the drift-guard test + the l3-probe-armed soak surface it
    alert_route: l3-probe-armed-6438.sh FAIL (monitor not up)
logs:
  where: Better Stack Logs (ClickHouse warehouse, table t520508_soleur_inngest_vector_prd_3_logs)
  retention: hot ~40min + s3 archive (queried via scripts/betterstack-query.sh with the UNION-ALL archive arm)
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep web-zot-consumer-probe --grep web-nic-guard --grep web-git-data-probe"
  expected_output: probe classification/success rows tagged with the probe SyslogIdentifiers from host soleur-web-platform (NO ssh)
```

**Affected-surface note (plan 2.9.2):** the probe oneshot units are a blind execution surface — the
fix's whole Phase 1 IS the in-surface probe (their own stderr, now shipped), and the NIC guard's
`SOLEUR_PRIVATE_NIC` event already discriminates every competing NIC-fault hypothesis in one event.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/server.tf`: new `terraform_data.web_vector_reload_install` (SSH to web-1,
  deliver `vector.toml`, render host_name, reload the vector agent, AND write `/etc/default/web-probes`
  root:root 600 with the prd-read `DOPPLER_TOKEN`). Reuses `var.ci_ssh_private_key`; reuses the
  existing prd-read token value by default (**no new secret**), or optionally adds a read-scoped
  `doppler_service_token` (the `web-arm-write-token.tf` pattern) for least-privilege. The vector reload
  runs inside this terraform_data remote-exec, exactly like the existing `*_install` provisioners'
  daemon-reload — an IaC-owned step, not a manual one.
- The 3 probe `.service` edits require no new `.tf` — they re-fire the existing `*_install`
  provisioners via `triggers_replace`.

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
  MUST set `Environment=HOME=/root` and source a prd-scoped `DOPPLER_TOKEN` from a dedicated
  `root:root 600` file (`/etc/default/web-probes`) — NOT `/etc/default/webhook-deploy` (deploy-owned;
  imports `DOPPLER_CONFIG_DIR=/tmp/.doppler`), and `/etc/default/inngest-server` is absent when
  `web_colocate_inngest=false`. With `HOME=/root` doppler uses `/root/.doppler`; never touch
  `/tmp/.doppler`; never switch to `User=deploy` without `PrivateTmp=true`."* Records the invariant so
  #6459 (future-host bake) inherits it.

### C4 views
- **No C4 impact.** Enumerated against the change: external human actors — none added; external systems
  — zot (10.0.1.30), git-data (10.0.1.20), Better Stack are all already modeled (the merged PR added
  the consumer-probe edges to `model.c4`); containers/data-stores — none new; actor↔surface access
  relationships — none changed (the probe units, their targets, and the BetterStack sink edge already
  exist). /work to confirm by reading `diagrams/{model.c4,views.c4,spec.c4}` that no new element/edge is
  introduced; a delivery/auth bug fix on already-modeled elements adds none.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Each of the 3 probe `.service` files contains `Environment=HOME=/root` AND
      `EnvironmentFile=/etc/default/web-probes` (grep-guard test, green); no probe `.service` sources
      `/etc/default/webhook-deploy`.
- [ ] The new provisioner writes `/etc/default/web-probes` as `root:root` `chmod 600` with `DOPPLER_TOKEN`.
- [ ] No probe `.service` sets `User=deploy` without `PrivateTmp=true`; no probe unit references
      `/tmp/.doppler` (grep-guard test).
- [ ] `server.tf` contains a `terraform_data` resource that delivers `vector.toml` to web-1 and reloads
      the vector agent, with `triggers_replace` hashing `vector.toml`.
- [ ] Drift-guard test registered in `infra-validation.yml`; `tsc`/shell tests green.
- [ ] PR body uses **`Ref #6438 #6548`** (NOT `Closes`).
- [ ] SpecFlow analysis run on the infra change (constitution: infra changes require SpecFlow).
- [ ] ADR-123 amendment note present.

### Post-merge (operator/automated — sequenced, all automatable)
- [ ] **Phase 1 applied + verified:** after the vector provisioner applies, self-pulled telemetry
      shows probe-tagged stderr from host soleur-web-platform reaching Better Stack (0→N probe rows).
      *Automation:* `apply-web-platform-infra.yml` + `scripts/betterstack-query.sh`.
- [ ] **Phase 2 applied + verified:** all 3 probe units start cleanly (no `Failed with result
      exit-code` in Better Stack) and a real measured beat lands. *Automation:* same.
- [ ] **Phase 3:** `apply-web-platform-infra.yml` (workflow_dispatch, `reason=…`) arm step reports
      all 3 heartbeats `status=up` (GREEN). *Automation:* `gh workflow run` + `gh run watch`.
- [ ] **Phase 4:** l3-probe-armed-6438.sh soak (earliest 2026-07-25) closes #6438/#6548 — verified
      by the sweeper, not this PR.

## Test Scenarios (Given/When/Then)

- **Given** a probe `.service` file, **When** the drift-guard runs, **Then** it asserts
  `Environment=HOME=/root` and a `DOPPLER_TOKEN`-supplying `EnvironmentFile` are present (fails RED
  on the current, unfixed files).
- **Given** the vector provisioner applied to web-1, **When** a probe timer fires with the units still
  unfixed, **Then** Better Stack shows a `web-*-probe`-tagged `Doppler Error: $HOME is not defined`
  row (the measured root-cause confirmation).
- **Given** the unit fix applied, **When** a timer fires, **Then** the probe classifies (200/reachable/
  nic_ok) and pings its heartbeat; `betterstack-query.sh` shows the classification stderr and the beat.
- **Given** all 3 beats holding, **When** the arm workflow runs, **Then** each monitor transitions to
  `up` within its deadline and stays armed.

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
  **unit diff** (visible source), not a dev-box probe — but the *runtime error* is still a prediction
  until Phase 1 ships the stderr. Do NOT collapse Phase 1 into Phase 2 ("they ride one PR so ordering
  is meaningless" is the argument to reject). Phase 1 must produce a real reading; if applied together,
  Source 4 still makes any residual failure self-diagnosable.
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

Revert the PR. The `.service` edits revert to the prior (broken-but-inert) units; the vector provisioner
is additive (removing it stops shipping Source 4 but breaks nothing). The heartbeats stay paused
(source `paused=true`, `ignore_changes=[paused]`), so a revert cannot fire a false alarm. No data
migration, no user-facing surface.
