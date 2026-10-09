---
title: "infra(inngest): forced-race rehearsal of the provision unit on a throwaway host"
date: 2026-10-08
slug: infra-inngest-provision-forced-race-rehearsal
branch: feat-one-shot-9175-provision-rehearsal
issue: 9175
closes: []
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-10-08
**Sections enhanced:** Proposed Solution (marker-level evidence chain), Alternative
Approaches (branch-config inheritance verified against live Doppler docs), Risks (API-shape
preconditions), new `## Network-Outage Deep-Dive` and `## Downtime & Cutover` sections per
deepen-plan §4.5/§4.55.
**Research agents used:** none spawnable in this harness (no Task tool) — the per-section
passes were executed inline: verify-the-negative greps against `cloud-init-inngest.yml`,
mechanical gates (`lint-guard-contract.py`, PAT-regex, scope-check structure), live `gh`
state checks on every load-bearing issue/PR citation, a fresh `git fetch origin main` +
all-refs ordinal probe (ADR-278 was already claimed by `feat-open-web-egress`; this plan
carries provisional **ADR-279**), and a live Doppler-docs check of branch-config inheritance.

### Key Improvements

1. The `--config prd` literal pins (~20 sites, template + image) were identified as the
   hard blocker for any scratch-config rehearsal — the plan now carries the
   `DOPPLER_CONFIG`/`inngest_doppler_config` parameterization as Deliverable A with a
   prod-render-invariance guard.
2. `INNGEST_DIAGNOSTIC_BOOT` verified end-to-end as the rehearsal's durable-state stand-in
   (cloud-init-inngest.yml:1309–1318 exempts a REQUESTED diagnostic boot from the
   degraded/latch check; the flip guard allows diagnostic+non-durable).
3. The latch ordering verified at source: latch write (`: > "$LATCH"`,
   cloud-init-inngest.yml:1331) precedes the `bootstrap-done` emit (:1336); the timer's
   `OnBootSec=90s` re-entry is refused by `ConditionPathExists=!…/done` (:1411).

### New Considerations Discovered

- Branch configs under `prd` DO inherit the root's secrets (docs.doppler.com/docs/root-configs:
  "When a root config secret is updated, it will automatically update the secret in any Branch
  Configs stemming from that root config") — confirming the scratch-config-in-prod-project
  must be an ENVIRONMENT root config, not a branch. This also casts doubt on rung2's
  `prd_git_data_rehearsal_*` isolation claim ("reads NOTHING of production's") — a
  work-time verification + possible follow-up, noted in Alternatives.
- A post-reboot phone-home marker requires `inngest-bs-token-restage.service` to succeed on
  the scratch config — the parameterization must reach that unit too (it reads the config
  pin at cloud-init-inngest.yml:635).
- Every failed attempt emits `provision_attempt_failed` (Sentry warning) — the alert shipped
  by #9176 will fire during the rehearsal's forced misses; bounded and disclosed.

## Overview

GitHub issue #9175 asks for a throwaway, Terraform-managed rehearsal root that exercises the
dedicated inngest host's real boot path under a deliberately late private-NIC attach: the zot
bootstrap pull misses on first boot, `soleur-inngest-provision.service` retries against a real
zot mirror and a real Doppler config, the latch is written only after `bootstrap-done`, and a
reboot does not re-run the unit. PR #9159's Tier B rehearsal (systemd 255 as PID 1 in a
container) already covers systemd semantics offline; this plan adds the real-network half,
modeled on the git-data rung-2 rehearsal route (`apps/web-platform/infra/rung2-rehearsal/` +
`.github/workflows/git-data-rung2-rehearsal.yml`).

<!-- iac-routing-ack: plan-phase-2-8-reviewed — every mutation below is a Terraform resource,
     a GitHub Actions step, or a Hetzner control-plane API call; quoted `doppler secrets …`
     strings in Research Insights describe EXISTING code, not prescribed operator steps. -->

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9175` — OPEN, title "infra(inngest): forced-race rehearsal of the provision unit
  on a throwaway host", labels `priority/p3-low`, `type/chore`, `domain/engineering`,
  `meta/machinery`. Deferred from merged PR #9159 (`Ref #8562`).
- `gh pr view 9159` — MERGED 2026-09-28 ("fix(infra): move inngest host provisioning into a
  latched retrying systemd unit (delivered dark)"). Tier B (systemd 255 as PID 1 in docker)
  covered systemd semantics offline; it filed three follow-ups: #9175 (this), #9176 (CLOSED by
  PR #9292 — `sentry_alert` for `provision_attempt_failed` exists at
  `apps/web-platform/infra/sentry/issue-alerts.tf`), #9177 (CLOSED by PR #9681 — `op=resume`
  G4 refusing without `bootstrap-done` for the new iid exists in `scripts/cutover-inngest.sh`).
- Cited artifacts all exist on this branch: `apps/web-platform/infra/rung2-rehearsal/`
  (`main.tf`, `variables.tf`, `rehearsal.tf`, `seed-dirty-journal.sh`, `.terraform.lock.hcl`),
  the `soleur-inngest-provision` script+`.service`+`.timer` in
  `apps/web-platform/infra/cloud-init-inngest.yml`, and the
  `/var/lib/soleur-inngest-provision/done` latch + `bootstrap-done`/`bootstrap-done-DEGRADED`
  phone-home stages.
- ADR corpus check (mechanism keywords: rehearsal root, late NIC attach, retrying unit): ADR-149
  DC-6 (rung-2 rehearsal route doctrine), ADR-231 (workflow byte-budget → runbook relocation),
  ADR-115 §Amendment 2026-09-22 (#8539 — the `99-soleur-private-fallback.network` converge
  primitive + `soleur-inngest-nic-wait`), ADR-257 (#8562 latched retrying unit — status
  `adopting` until `scripts/followthroughs/inngest-provision-unit-8562.sh` reads PASS on a real
  host life), ADR-100 (single-writer inngest; two servers on prod Postgres double-fire crons),
  ADR-241 (Tier-B credential loading via `.github/actions/infra-credentials`, environments
  `infra-privileged`/`web-platform-infra-apply`), ADR-232 (bootstrap pin bumps are authored by
  the publish workflow). No rejected alternative collides with the proposed mechanism.

### Property List (Phase 0.6b)

The asks restated as observable properties:

1. A throwaway Terraform-managed root exists that can boot a host running the real inngest
   cloud-init render without touching production state it must not touch.
2. A forced late-NIC-attach: the host provably boots with no private NIC (stage evidence),
   the NIC is then attached, and the `soleur-inngest-provision` unit's next retry succeeds —
   exercising the #8539 fallback (`private_nic_timeout`, `private_nic_ok by=…`, and the in-unit
   `provision-nic-ABSENT` early-fail) against a real subnet and a real zot pull.
3. The unit restarts on real failures (multiple `provision-attempt-start`/`provision-attempt-exit-*`
   rows for one `iid`).
4. The latch is written only after `bootstrap-done` for that `iid` (no latch after failed
   attempts — proven by the attempt counter still incrementing after the NIC attach).
5. A reboot does not re-run the unit (post-reboot liveness anchor + zero new
   `provision-attempt-start` for the same `iid`).
6. Everything the rehearsal owns is reclaimed (teardown job `if: always()` + orphan sweep
   coverage), and nothing it does can reach production secrets or the production scheduler.

### Cut List (Phase 0.6b)

- Mechanism "rehearse inside the existing root with `count=0`" → rejected by the rung-2 analysis:
  `-target` is transitive on dependencies; a separate root is the safety argument
  (`rung2-rehearsal/main.tf` header). Covered by property 1.
- Mechanism "scratch private network + scratch zot mirror" → rejected: prod zot serves only on
  `10.0.1.0/24` (deny-all public ingress, plain HTTP); a second zot host doubles the rehearsal's
  cost and machinery for no added fidelity — the thing under test is Hetzner's late attach on
  the REAL subnet. The rehearsal attaches to `hcloud_network.private` read-only via data
  sources; see Risks for the bounded prod-net exposure.
- Mechanism "any manual provisioning or SSH step" → forbidden
  (`hr-all-infrastructure-provisioning-servers`, `hr-no-ssh-fallback-in-runbooks`); every
  mutation is Terraform or the Hetzner control-plane API (`POST /servers/{id}/actions/reboot`,
  same shape `web-host-reboot.yml` uses since #9372).
- Mechanism "mock/stubbed zot or Doppler" → rejected; that is exactly what Tier B already was
  and the issue exists because it was insufficient.

### Key findings

- **The load-bearing discovery:** every Doppler call on the inngest boot path pins
  `--project soleur-inngest --config prd` as literals — in `cloud-init-inngest.yml` (isolation
  check, `BETTERSTACK_LOGS_TOKEN` re-stage, `DIAGNOSTIC_BOOT` read, env-file staging) AND inside
  the bootstrap image (`inngest-bootstrap.sh` heartbeat/server/flip-guard/vector ExecStarts,
  `inngest-cutover-flip.sh`, `inngest-luks-cutover.sh`). A scratch Doppler config can never be
  named `prd` (config names are unique per project), so a faithful rehearsal REQUIRES
  parameterizing the config name (`${DOPPLER_CONFIG:-prd}`, mirroring `DOPPLER_PROJECT`'s
  existing env pattern and git-data's `doppler_config_name` template var). The image-shipped
  files need a new `vinngest-v*` image mint + pin bump — both delivered dark, both by the
  existing publish machinery (ADR-232).
- `INNGEST_DIAGNOSTIC_BOOT` is purpose-built for this rehearsal (`inngest-bootstrap.sh`: the
  diagnostic branch points `--sdk-url` at a closed loopback port so the host "adopts NO registry
  and cannot double-fire prod crons"; the flip guard explicitly allows diagnostic + non-durable):
  SQLite-only server, prod Postgres unreachable, still emits `bootstrap-done` and still writes
  the latch (exempt from the durable-shape check). It removes any need for a rehearsal Postgres.
- The throwaway-Doppler story mirrors git-data: a NEW `doppler_environment` in project
  `soleur-inngest` (slug `rehearsal_<runid>` — Doppler slugs take underscores, not hyphens) creates a non-inheriting root config holding only
  the five allowlisted names (`INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`, `INNGEST_REDIS_PASSWORD`
  throwaway `random_*`, `INNGEST_DIAGNOSTIC_BOOT="true"`, `BETTERSTACK_LOGS_TOKEN` = prod's
  write-only ingest token) — n_total = n_inngest = 5, the isolation check passes; a
  `doppler_service_token` scoped to it is the boot credential.
- Post-reboot evidence needs the phone-home channel re-armed:
  `inngest-bs-token-restage.service` re-stages `/run/inngest-bs-logs-token` every boot and emits
  `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` — the natural post-reboot liveness anchor.
- Alert hygiene: #9176's `provision_attempt_failed` issue alert will fire for the rehearsal's
  deliberately-failed attempts (bounded: NIC-absent attempts exit BEFORE the zot pull, so no
  `inngest_pull_fatal` pages; a handful of `provision_attempt_failed` warnings in the window —
  acceptable and disclosed).
- Naming collision trap (documented at rung2): `soleur-inngest` is a prefix of
  `soleur-inngest-rehearsal-*`; every sweep/capture must anchor on the full
  `soleur-inngest-rehearsal-` prefix with trailing hyphen.
- Presence under `apps/web-platform/infra/` IS CI registration (run-registered-suites.sh
  glob-derives; the sentinel suite must live at the infra root, not inside the subdir).
- `hr-every-new-terraform-root-must-include-an`: R2 backend, distinct key
  `web-platform/inngest-provision-rehearsal/terraform.tfstate`, providers pinned to the parent
  root's versions.
- `apply-web-platform-infra.yml` needs the same negated `paths:` glob
  (`!apps/web-platform/infra/inngest-provision-rehearsal/**`) the rung2 dir carries.

### Open Code-Review Overlap (Phase 1.7.5)

`gh issue list --label code-review --state open` scanned against the planned file set:
`scripts/followthroughs` matches #8800, #8659, #8496, #8435 — none touches the new capture
script; #8659 (test-helper EXIT-trap hygiene) is **acknowledged** and informs how the new
suite is written, not what it tests. No rework or double-counting risk.

## Problem Statement / Motivation

PR #9159 shipped `soleur-inngest-provision.service` — a latched, retrying oneshot that pulls
the bootstrap image from zot, runs `inngest-bootstrap.sh`, writes
`/var/lib/soleur-inngest-provision/done` only after a durable `bootstrap-done`, and unpauses
the cutover FSM timers it quiesced — but every property of it was verified OFFLINE (systemd
255 as PID 1 in docker). None of the production-specific behavior has been exercised on a real
host: Hetzner's late `hcloud_server_network` attach (#8539), a real zot pull over the real
private subnet, a real scoped Doppler token, the real retry timer, or a real reboot.

The next `inngest-host-replace` will be the first time any of this runs for real, and its only
feedback is production telemetry. #9175 asks for a paid rehearsal — a throwaway
Terraform-managed host that rides the SAME render against a REAL zot mirror and REAL Doppler
while the private NIC is deliberately held back, so the forced miss exercises both the #8539
fallback (`private_nic_timeout` → `provision-nic-ABSENT` → `private_nic_ok
by=99-soleur-private-fallback`) and the unit's recovery contract end to end.

The enabler this plan must carry (discovered in research, not visible from the issue): the
inngest boot surface pins `--config prd` as literals in ~20 places across
`cloud-init-inngest.yml`, `inngest-bootstrap.sh`, `inngest-cutover-flip.sh`,
`inngest-luks-cutover.sh`, and two committed `.service` files. A scratch Doppler config can
never be named `prd` — config names are unique per project, `prd` is taken, and a branch
config under `prd` would inherit prod's values (including `INNGEST_POSTGRES_URI`, which a
throwaway host must never hold — a second scheduler against prod Postgres double-fires crons,
ADR-100). So the config name must become parameterizable (`${DOPPLER_CONFIG:-prd}`,
behavior-identical on prod) before a faithful rehearsal is possible, and that change rides the
bootstrap image — requiring a new `vinngest-v*` mint + pin bump through the existing publish
machinery, all delivered dark.

## Proposed Solution

Two coupled deliverables in one PR (the second is inert without the first; see Split
Assessment):

**Deliverable A — make the inngest host's Doppler config name addressable.**
`cloud-init-inngest.yml` gains template var `inngest_doppler_config` (prod passes `"prd"`
explicitly in `inngest-host.tf`, mirroring git-data's `doppler_config_name`); every
`--config prd` literal on the boot path becomes `${inngest_doppler_config}` (template sites) or
`${DOPPLER_CONFIG:-prd}` (scripts and unit files, resolved from the unit's own environment —
`doppler run` exports `DOPPLER_CONFIG`/`DOPPLER_PROJECT` as reserved secrets to its children,
and `/etc/default/inngest-doppler` gains the `DOPPLER_CONFIG=` line for units that are not
launched under a `doppler run` wrapper). `--project soleur-inngest` stays literal everywhere —
the scratch config lives in the same project. Prod render is byte-behavior-identical; the
image-side change ships via the normal mint → build → mirror → pin-bump pipeline (ADR-232)
and reaches a host only at the next `inngest-host-replace`.

**Deliverable B — the rehearsal route** (`inngest-provision-rehearsal`, mirroring rung2):
a separate Terraform root, a dispatch-only workflow, a plan-shape guard, an evidence-capture
script, a sentinel test suite, and an orphan-sweep arm.

- **Rehearsal host:** `hcloud_server.rehearsal` in `hel1` on `cpx22`, `ubuntu-24.04`, deny-all
  firewall attached at create, throwaway `tls_private_key`+`hcloud_ssh_key`, two scratch
  `hcloud_volume`s (redis store + LUKS-partner, both ext4 — `inngest_expect_luks="false"` =
  prod parity), label `app=soleur-inngest-provision-rehearsal`, name
  `soleur-inngest-rehearsal-<run_id>` (trailing-hyphen prefix is load-bearing: `soleur-inngest`
  alone matches prod).
- **user_data = the SAME render call as prod**, `base64gzip(replace(templatefile(
  cloud-init-inngest.yml, {…}), local strip, ""))` — byte-fidelity is the evidence. The ONLY
  argument divergences are identity-class: `doppler_token` = the scratch service token,
  `inngest_doppler_config` = `rehearsal_<runid>`, `inngest_private_ip` = `10.0.1.60`,
  `sdk_url` = `http://127.0.0.1:3000/api/inngest` (loopback; `INNGEST_DIAGNOSTIC_BOOT` also
  overrides it inside the image), `web_host_private_ips` = `127.0.0.1` (nobody may reach the
  rehearsal's :8288), `inngest_volume_id`/`inngest_luks_volume_id` = the scratch volumes.
  Everything else — `betterstack_logs_token`, `zot_registry_endpoint`, `zot_pull_user`,
  `zot_pull_token`, arch/sha256 derivations — is prod's own value, because the
  telemetry/pull channels are part of what is being rehearsed. **EXCEPTION `sentry_dsn =
  ""`** (changed at review time): the shared Sentry issue-alerts filter on stage only — the
  rehearsal's intentional `private_nic_timeout` would page `web_private_nic_boot_gate` as
  prod-attributed, and `soleur-boot-emit` hardcodes `host_name='soleur-inngest'`, which
  would also pollute the zot-soak denominator. An empty DSN sends every Sentry emit down
  the baddsn path (it still phones home `sentry-emit-FAILED` to Better Stack, so the emit
  path itself is still exercised).
- **The forced race is a two-phase apply**, not a timing hope: `hcloud_server_network.rehearsal`
  (`network_id = data.hcloud_network.private.id`, `ip = "10.0.1.60"` — the hcloud provider's
  data-source set has no `hcloud_network_subnet` lookup, so the attach binds by
  network_id+ip; work-time verify against provider `~>1.49`) is
  `count`-gated on `var.nic_attached`. Phase A (`nic_attached=false`) boots the host NIC-less;
  the workflow's evidence gate refuses to start phase B until Better Stack shows
  `private_nic_timeout` + `provision-unit-armed` + ≥2 `provision-attempt-start` rows all
  provision-family markers iid-joined to this boot's cloud-init instance-id once it resolves — the miss is *observed*, then healed. Phase B (`nic_attached=true`)
  adds the one attachment; the `99-soleur-private-fallback.network` file converges it via DHCP
  (the ADR-115 #8539 amendment mechanism) and the unit's next retry runs the full
  zot-login → pull → Doppler-isolation → bootstrap chain.
- **Scratch Doppler footprint:** `doppler_environment.rehearsal` on the EXISTING project
  `soleur-inngest` (slug `rehearsal_<runid>` — a non-inheriting root config), five
  `doppler_secret`s (throwaway `random_id`/`random_password` values for
  `INNGEST_SIGNING_KEY`/`INNGEST_EVENT_KEY`/`INNGEST_REDIS_PASSWORD`,
  `INNGEST_DIAGNOSTIC_BOOT="true"`, `BETTERSTACK_LOGS_TOKEN`=var), and one read-scoped
  `doppler_service_token.rehearsal`. The boot isolation check sees n_total = n_inngest = 5 and
  passes; `INNGEST_POSTGRES_URI`/`INNGEST_HEARTBEAT_URL`/`INNGEST_CUTOVER_FLIP` are absent
  (diagnostic boot needs none of them; absent `HEARTBEAT_URL` suppresses the pusher; absent
  `CUTOVER_FLIP` makes the flip FSM a no-op).
- **Diagnostic boot is the rehearsal's durable-state answer:** `INNGEST_DIAGNOSTIC_BOOT=true`
  runs the real pipeline with a SQLite-only server against loopback sdk — no rehearsal
  Postgres, no risk of a second prod scheduler, and the provision unit still emits
  `bootstrap-done` + writes the latch (requested-diagnostic exemption). The non-diagnostic
  durable arm (scratch docker Postgres + `inngest-pg-*`/`inngest-redis` markers) is a named
  follow-up, not this plan.
- **Reboot arm:** after `bootstrap-done` for the host's `iid`, the workflow issues
  `POST /v1/servers/<id>/actions/reboot` via the Hetzner API (control plane, never SSH — same
  shape as `web-host-reboot.yml`'s #9372 job). Post-reboot evidence = the
  `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` liveness row (emitted every boot, and itself a
  successful scratch-Doppler read) PLUS zero `provision-attempt-start`/`bootstrap-*` rows for
  the `iid` after the reboot boundary — the latch held, the timer's `OnBootSec` re-entry was
  refused by `ConditionPathExists`.
- **Evidence:** `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` queries Better
  Stack's query API (same credentials and three-state 0/1/2 contract as
  `git-data-rung2-evidence-capture.sh`, with a source-liveness anchor so an instrument outage
  reads TRANSIENT, never FAIL) and emits `inngest-provision-rehearsal-evidence.env` as a
  workflow artifact. The workflow runs with `permissions: contents: read`; evidence is never
  committed by CI — the operator attaches it to #9175 per the runbook.
- **Teardown:** `terraform destroy` in a teardown job gated `always()` (plus `teardown_only`
  recovery dispatch), plus a `scheduled-terraform-drift.yml` orphan sweep for the
  `soleur-inngest-rehearsal-*` label/prefix and `rehearsal_*` Doppler environments in project
  `soleur-inngest` — bounded sweep window, loud listing, manual destroy (rung2 doctrine:
  visibility is the point, not auto-reclaim).

**Precedent diff vs `rung2-rehearsal/`** (the canonical shape this borrows — §4.4):

| Element | rung2 | this rehearsal | Why the diff |
|---|---|---|---|
| Private network | no `hcloud_server_network` (host stays off prod net) | phase-B `hcloud_server_network.rehearsal` into `data.hcloud_network.private` | The subnet IS the subject — the #8539 race is a prod-network attach event; a scratch net can't reach the IP-bound zot |
| Scratch config shape | `doppler_config` branch `prd_git_data_rehearsal_*` under `soleur/prd` | `doppler_environment` root config `rehearsal_<runid>` under `soleur-inngest` | Branch configs inherit root secrets (verified: Doppler root-configs doc) — under prd that resolves prod values to the token. An environment root is non-inheriting. NOTE: rung2's "reads NOTHING of production's" claim is likely false under branch inheritance — tracked as #9817 |
| Config reachability | `GIT_DATA_DOPPLER_CONFIG` was already env-parameterized | `--config prd` was literal everywhere → Deliverable A parameterizes | The inngest boot surface never needed a second config before |
| Backend exercised | redis/LUKS provision, reset arm | diagnostic SQLite boot (`INNGEST_DIAGNOSTIC_BOOT=true`) | No scratch Postgres; the latch contract is identical on both arms |
| Evidence consumer | releases `git_data_rung2_rehearsal_gate` (birth interlock) | no interlock — artifact + issue attachment closes #9175 | The provision unit already shipped; this is post-hoc assurance, not a gate dependency |
| NIC race injection | n/a (seed/payload phases exercise volume state) | two-phase `nic_attached` gate observed-before-heal | The race must be forced, not re-won |

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| `count=0` resources inside the existing `apps/web-platform/infra` root | `-target` is transitive on dependencies; rehearsal resources would drag production resources into the planning/apply closure. The separate root IS the safety argument (rung2 `main.tf` header; #7025, ADR-149 DC-6). |
| Scratch `hcloud_network` + scratch zot registry host | Zero added fidelity at ~2× cost: prod zot is only reachable on `10.0.1.0/24`, so a scratch net could never reach it anyway; the thing under test is Hetzner's attach behavior on the REAL subnet. A second zot would also need its own image mirror. |
| Branch config `prd_rehearsal_*` under `soleur-inngest/prd` | A branch config inherits the root's values → the rehearsal token would resolve prod's `INNGEST_POSTGRES_URI` and signing keys. Disqualified on blast radius, independent of the name-pin problem. (Also surfaces a question for work: whether rung2's `prd_git_data_rehearsal_*` branch tokens resolved soleur/prd's inherited secrets — the rehearsal.tf comment claims not; verify and record.) |
| Token scoped to prod `soleur-inngest/prd` | Puts real production secrets on a throwaway host, including the URI that could let it join the prod scheduler set. Disqualified. |
| `doppler` CLI shim/divert at `/usr/bin/doppler` on the rehearsal host | Ordering is racy vs. the template's own doppler install inside runcmd; a shim that silently rewrites `--config` makes the evidence unverifiable (the bytes under test diverge from prod's mechanism). |
| Host-side `sed` patch of the extracted `inngest-bootstrap.sh` pre-run | Same objection: a runtime mutation the evidence cannot hash; weaker than shipping the parameterization honestly. |
| Single apply + `time_sleep` before the NIC attachment | The attach must be gated on the *observed* miss (stage markers), not on a clock — otherwise a slow boot lets the NIC arrive before attempt 1 and the rehearsal proves nothing. Two-phase apply is the deterministic version. |
| Non-diagnostic arm now (docker Postgres on the rehearsal host) | Real option, deliberately deferred: diagnostic boot is the purpose-built substrate (#7228), the unit's latch/quit/retry contract is identical on both arms, and a scratch-pg arm doubles the plan. Named follow-up below. |
| `INNGEST_POSTGRES_URI` → the prod Supabase project | Disqualified (ADR-100 single-writer; a diagnostic-free rehearsal host armed with the prod URI is exactly the double-scheduler shape the flip guard exists to block). |

## Network-Outage Deep-Dive

(§4.5 fired: the plan's Overview contains `timeout`/`unreachable`. This plan does not
*diagnose* an outage — it *stages* one — but the L3→L7 ordering discipline still binds
the evidence chain, so each layer is answered with its verification artifact.)

1. **L3 — firewall allow-list.** The rehearsal host carries a deny-all `hcloud_firewall`
   attached inside `ServerCreate` (prod parity: `hcloud_firewall.inngest` binds at create,
   inngest-host.tf ~:470). No inbound path exists, and no SSH surface exists anywhere in
   the rehearsal — `hr-no-ssh-fallback-in-runbooks` is enforced by construction, not by
   omission of a step. [verified: resource declared in `rehearsal.tf`; the sentinel suite
   pins firewall attachment at create]
2. **L3 — DNS/routing.** The private-NIC leg IS the object under test: `private_nic_timeout`
   → `provision-nic-ABSENT` rows prove absence, `private_nic_ok
   by=99-soleur-private-fallback` proves the DHCP converge after the phase-B attach. The
   zot pull is the L3-liveness proof for `10.0.1.30:5000`. No `dig`/`traceroute` claim is
   needed — the markers are the artifact. [verified by the rehearsal itself]
3. **L7 — TLS/proxy.** zot is plain HTTP on the private subnet (ADR-096 Phase-0 posture,
   no TLS — declared in Encryption Posture). The vendor HTTPS legs (Doppler API, Sentry
   ingest, Better Stack ingest) are exercised live: phone-home markers landing *are* the
   TLS verification. [verified by marker presence/absence in evidence]
4. **L7 — application.** The provision unit's own journald→Vector→Better Stack stream plus
   the `inngest-boot-phone-home.sh` curl-direct channel give two independent app-layer
   records; `post-boot-health` (svc states + loopback :8288 + journal tail) rides the same
   emit. [verified]

No hypothesis in this plan proposes an sshd/firewall/service fix — there is nothing to
diagnose; the checklist's purpose (never mistake an L3 drop for an L7 failure) is instead
inverted: the rehearsal *proves* the L3 event is handled correctly by the L7 machinery.

## Downtime & Cutover

(§4.55 fired: editing `cloud-init-inngest.yml` changes `local.inngest_user_data_*`, and
`hcloud_server.inngest` has **no** `ignore_changes=[user_data]` — the edit pends a
force-replace of the sole scheduler.)

- **The offline-inducing operation:** the next `apply_target=inngest-host-replace` dispatch
  (a separately gated, already-existing route — this PR does not dispatch it, and the
  merge-triggered apply never reaches `hcloud_server.inngest` because it is excluded from
  the per-merge `-target` set, apply-web-platform-infra.yml §OPERATOR_APPLIED_EXCLUSIONS).
- **Zero-downtime path, evaluated:** the dedicated host is *by design* replace-based — the
  replace boots a fresh host that self-provisions via this very unit while the old host
  still serves; `cutover-inngest.yml -f op=resume` then flips traffic only after the new
  host's `bootstrap-done` (the G4 gate landed by #9177). There is no in-place edit path for
  a cloud-init change — this *is* the zero-downtime shape, and the rehearsal this plan
  builds exists precisely to de-risk that window. **Merging this PR induces zero downtime**
  — the user_data delta is inert until a human approves the replace dispatch.
- **Residual downtime:** none introduced by this plan; the replace route's own runbook
  (inngest-server.md) already owns that operation's drain/cutover semantics.

## Files to Create

- `apps/web-platform/infra/inngest-provision-rehearsal/main.tf` — R2 backend
  (`bucket=soleur-terraform-state`, `key=web-platform/inngest-provision-rehearsal/terraform.tfstate`,
  `use_lockfile=false`, same endpoint/region caveat comments as rung2), `required_version >= 1.7`,
  providers pinned to the parent's declared versions (hcloud `~> 1.49`, random `~> 3.0`,
  doppler `~> 1.21`, tls `~> 4.0`, cloudflare `~> 4.0` for the backend's S3 ops).
- `apps/web-platform/infra/inngest-provision-rehearsal/variables.tf` — `hcloud_token`,
  `doppler_token_tf`, `betterstack_logs_token`, `zot_pull_token`,
  `rehearsal_run_id` (validation `^[0-9]+$`), `nic_attached` (bool), `location`/`server_type`
  (defaults = prod's). No operator-minted secret defaults
  (`hr-tf-variable-no-operator-mint-default`).
- `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` — all resources named
  `.rehearsal` / labeled `app=soleur-inngest-provision-rehearsal`: `tls_private_key`,
  `hcloud_ssh_key`, `doppler_environment.rehearsal` + five `doppler_secret`s +
  `doppler_service_token.rehearsal` (read scope), two `hcloud_volume`s, deny-all
  `hcloud_firewall`, `hcloud_server.rehearsal` (user_data = the same render call),
  `hcloud_server_network.rehearsal` (`count = var.nic_attached ? 1 : 0`,
  `data "hcloud_network" "private"` lookup — the ONLY permitted prod-named references, and
  read-only).
- `apps/web-platform/infra/inngest-provision-rehearsal/.terraform.lock.hcl` — generated by
  `terraform init` at work time, committed; workflow runs `-lockfile=readonly`.
- `.github/workflows/inngest-provision-rehearsal.yml` — `workflow_dispatch` only; inputs
  `confirm` (`REHEARSE-INNGEST-PROVISION`), `dry_run` (default `true`), `teardown_only`;
  `environment: web-platform-infra-apply`; `concurrency.group: terraform-apply-web-platform-host`
  (the widest apply serializer — this root mutates prod-adjacent objects: the prod private
  network's member set and the prod `soleur-inngest` project structure); `permissions:
  contents: read`; every step `timeout-minutes`-bounded; the same `base32`/`head -c` credential
  discipline for the baked-token upload leg.
- `scripts/inngest-provision-plan-shape.sh` — JSON plan guard, two modes: `additive` (phase A:
  only `<type>.rehearsal*` addresses, create-only) and `nic-attach` (phase B: exactly one
  create — `hcloud_server_network.rehearsal` — plus permitted reads/no-ops). Unclassified
  address → fail (census, not name-pin).
- `tests/scripts/test-inngest-provision-plan-shape.sh` — fixtures per the mutation matrix below
  (real `terraform plan -json` shapes from a dry-run plan, not hand-authored XML/JSON
  approximations).
- `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` + colocated
  `inngest-provision-rehearsal-capture.test.sh` — three-state verdict + evidence env writer;
  CLI `--host-name/--evidence-url/--since/--divergence/--out` mirroring the rung2 capture.
- `scripts/inngest-provision-rehearsal-probe.sh` — the Observability discoverability probe
  (public `api.github.com` runs read; no credentials).
- `apps/web-platform/infra/inngest-provision-rehearsal.test.sh` — the sentinel suite (infra-root
  placement = CI registration by glob).
- `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md` — dispatch
  invocation, three-artifact table, outcome table, token/After-PASS procedure (ADR-231: prose
  belongs here, not in the workflow).
- `knowledge-base/engineering/architecture/decisions/ADR-279-inngest-provision-forced-race-rehearsal.md`
  — **ordinal provisional**; re-run the cross-branch probe (all `origin/*` refs, not
  `origin/main`) immediately before creating the file and again before merge.
- `knowledge-base/project/specs/feat-one-shot-9175-provision-rehearsal/tasks.md` — work's task list.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` — `inngest_doppler_config` template var;
  replace the `--config prd` literals in the inngest surface (~9 sites measured 2026-10-08:
  secrets-download staging, bs-token restage, isolation check, DIAGNOSTIC_BOOT read — re-grep
  at work); write `DOPPLER_CONFIG` into `/etc/default/inngest-doppler` (0600, additive key —
  the isolation self-check operates on Doppler *secret names*, not env-file keys); pass
  `DOPPLER_CONFIG` through the provision unit's env when invoking `inngest-bootstrap.sh`.
- `apps/web-platform/infra/inngest-host.tf` — pass `inngest_doppler_config = "prd"` in the
  templatefile args (explicit, not defaulted, so prod's resolution is visible at the call
  site).
- `apps/web-platform/infra/inngest-bootstrap.sh` — its `--config prd` literals (~8 sites:
  heartbeat ExecStart, server ExecStart, flip-guard ExecStartPre, vector ExecStart,
  `cutover_flag` read, etc.) become `${DOPPLER_CONFIG:-prd}`/`@@DOPPLER_CONFIG@@`-substituted,
  consistent with how `DOPPLER_PROJECT`/`SDK_URL` are already threaded.
- `apps/web-platform/infra/inngest-cutover-flip.sh`, `inngest-luks-cutover.sh`,
  `inngest-cutover-flip.service`, `inngest-luks-cutover.service` — internal `doppler secrets
  get/set/delete --config prd` and the `.service` ExecStart wrappers adopt the same
  `${DOPPLER_CONFIG:-prd}` contract (for the committed unit files: `EnvironmentFile=` +
  systemd `$VAR` substitution, or render-time substitution where the unit is emitted by
  `inngest-bootstrap.sh` — pick per file at work; `--project soleur-inngest` stays literal
  everywhere).
- The suites that pin the literals — at minimum `cloud-init-inngest-bootstrap.test.sh`,
  `cloud-init-inngest-provision-unit.test.sh`, `inngest-host.test.sh`,
  `inngest-cutover-flip.test.sh`, `inngest-luks-cutover.test.sh`,
  `inngest-server-flip-guard.test.sh`, `inngest-boot-emitter.test.sh` — re-grep for
  `--config prd`/`--project soleur-inngest` at work; every pin keeps asserting the prod
  default while admitting the parameterized form.
- `.github/workflows/apply-web-platform-infra.yml` — add
  `!apps/web-platform/infra/inngest-provision-rehearsal/**` to the same `paths:` list that
  carries `!apps/web-platform/infra/rung2-rehearsal/**`.
- `.github/workflows/scheduled-terraform-drift.yml` — extend the rung2-style orphan sweep with
  the `soleur-inngest-rehearsal-` prefix/`soleur-inngest-provision-rehearsal` label and a
  `rehearsal_*`-environment enumeration in project `soleur-inngest` (bounded to same-week).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — one paragraph naming
  the rehearsal route in the Provision-unit section.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — extend the `github -> hetzner`
  edge prose, which already enumerates CI callers by name ("the git-data rung-2 rehearsal
  (including a server reset)"), to name this route; no new element (a rehearsal host is an
  ephemeral instance of `platform.infra.inngest`, not a modeled system). Check `views.c4`
  element enumeration for completeness at the same time.

## Implementation Phases

**Phase 1 — parameterization + pinning-test updates (Files to Edit, infra scripts).**
Grep-complete enumeration of every `--config prd` literal on the inngest boot path; adopt the
`${DOPPLER_CONFIG:-prd}` contract (with `@@DOPPLER_CONFIG@@`/`EnvironmentFile=` per site);
add `inngest_doppler_config` to the template + prod call site; update the red suites to pin
the parameterized form AND the prod default. Suites:
`bash apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`,
`bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`,
`bash apps/web-platform/infra/inngest-host.test.sh`,
`bash apps/web-platform/infra/inngest-cutover-flip.test.sh`,
`bash apps/web-platform/infra/run-registered-suites.sh` (full pass before commit — measure;
the runner is glob-derived so nothing new registers itself there).

**Phase 2 — rehearsal Terraform root + shape guard + sentinel suite.** New dir per Files to
Create; `terraform init` produces the lockfile; the plan-shape script + its fixtures; the
sentinel `inngest-provision-rehearsal.test.sh`. Verification is `terraform validate` +
`terraform plan` in dry mode INSIDE the workflow (never a local `apply` — the plan is
planning-only; `soleur:work` writes code but the live run stays behind the dispatch).

**Phase 3 — workflow + capture script + drift-sweep arm + apply-workflow path exclusion.**
`inngest-provision-rehearsal.yml` assembled section-at-a-time under ADR-231; capture script +
test; the negated `paths:` glob; the orphan-sweep block.

**Phase 4 — docs.** Runbook, ADR-279 (provisional), `model.c4`/`views.c4` prose accuracy,
`inngest-server.md` paragraph, spec `tasks.md`.

**Post-merge (operator-gated, out of this plan's execution):** the normal image pipeline mints
`vinngest-v*` carrying the parameterized bootstrap; the pin-bump PR lands; only then does a
real `REHEARSE-INNGEST-PROVISION` dispatch produce a valid rehearsal. #9175 stays OPEN until a
real run's evidence is attached — the PR body must say `Ref #9175`, never `Closes #9175`
(ADR-084 single-shot closure).

## User-Brand Impact

- **If this lands broken, the user experiences:** for the harness half — nothing user-visible
  (a failed rehearsal burns a ~€0.05 host-hour (cpx22 is ~€0.03/hr; ~90 min) and reports FAIL). For the parameterization
  half — if the `${DOPPLER_CONFIG:-prd}` contract resolved wrong on prod, the NEXT
  `inngest-host-replace` boots a scheduler that cannot read Doppler: provisioning retries to
  exhaustion, the scheduler stays dark, and every user's scheduled jobs/cron reminders stall
  until rollback — the same blast shape as #8539's original incident.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the strongest
  residual is a throwaway host holding a token scoped to an *empty-of-prod-values* config —
  the only prod values on it are narrowly-scoped credentials (`BETTERSTACK_LOGS_TOKEN` and
  `sentry_dsn` are write-only ingest; `zot_pull_token` is a registry **read** credential —
  pull-only, no user data behind it). A leak's worst
  product-facing outcome is forged telemetry, not user data.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** a botched parameterization doesn't hurt one user on
  one request — it darkens the sole scheduler for the whole fleet until the next replace, so
  it clears `single-user incident`; it does not approach `none` because the harness half alone
  would have been `none`-adjacent tooling.

## Observability

```yaml
liveness_signal:
  what:            # soleur-inngest-provision unit stage markers in Better Stack
                   # (provision-unit-armed / provision-attempt-start / bootstrap-done), each
                   # carrying attempt= and iid=; post-reboot the anchor is the
                   # SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1 row (re-armed every boot)
  cadence:         # per attempt (~120s backoff) during the rehearsal window; per boot for
                   # the restage anchor
  alert_target:    # the capture script's verdict (PASS/FAIL/TRANSIENT) in the workflow log;
                   # TRANSIENT means the instrument, not the host, is suspect
  configured_in:   # apps/web-platform/infra/cloud-init-inngest.yml
                   # (inngest-boot-phone-home.sh + soleur-boot-emit); evidence assembly:
                   # scripts/followthroughs/inngest-provision-rehearsal-capture.sh

error_reporting:
  destination:     # Sentry SUPPRESSED on the rehearsal (sentry_dsn="" — stage-only alert
                   # filters would page the intentional nic-timeout as prod; the emit path
                   # still runs and phones home sentry-emit-FAILED)
  fail_loud:       # provision-attempt-exit-* (Better Stack) per failed attempt +
                   # sentry-emit-FAILED (Better Stack) marking each suppressed Sentry emit;
                   # bootstrap-exit-nonzero / bootstrap-done-DEGRADED / inngest_pull_fatal
                   # on the fatal legs

failure_modes:
  - mode:          # NIC attach never converges after phase-B apply
    detection:     # bounded capture poll sees no private_nic_ok for the iid within the
                   # attach window → workflow prints the HALT table and teardown still runs
    alert_route:   # workflow failure + artifact; no page (rehearsal scope)
  - mode:          # instrument (Better Stack/Sentry) dead — zero rows even for the anchor
    detection:     # source-liveness query: ANY row from the source in the window; zero rows
                   # → TRANSIENT, never FAIL (the git-data-rung2-evidence-capture contract)
    alert_route:   # workflow TRANSIENT verdict; operator re-dispatches
  - mode:          # latch written before bootstrap-done (the property under test, failing)
    detection:     # provision-attempt-start count stops increasing while bootstrap-done is
                   # absent for the iid → FAIL verdict, evidence artifact carries the stage
                   # table
    alert_route:   # workflow failure + issue comment per runbook
  - mode:          # reboot re-runs provisioning (latch not honored)
    detection:     # any provision-attempt-start/bootstrap-* row for the iid timestamped
                   # after the reboot boundary → FAIL
    alert_route:   # workflow failure + issue comment per runbook
  - mode:          # rehearsal resources left behind after destroy
    detection:     # scheduled-terraform-drift.yml orphan sweep (soleur-inngest-rehearsal-
                   # prefix / app=soleur-inngest-provision-rehearsal label / rehearsal_*
                   # environments in soleur-inngest)
    alert_route:   # the drift workflow's existing reporting path

logs:
  where:           # journald → Vector → Better Stack on the host (host-pinned: host_name=
                   # soleur-inngest-rehearsal-<run_id>); workflow step logs for the
                   # orchestration half
  retention:       # Better Stack ~3-day telemetry retention → the evidence artifact is the
                   # durable record; workflow run logs retained by GitHub

discoverability_test:
  command:         bash scripts/inngest-provision-rehearsal-probe.sh
  expected_output: last_run_conclusion=
  # The probe curls the public GitHub runs API for this repo (no credentials on a public
  # repo) and prints `last_run_conclusion=<success|failure|null>` for the newest
  # inngest-provision-rehearsal.yml run — the operator-readable state of the shipped route.
```

## Encryption Posture

```yaml
at_rest:
  - store:            # hcloud_volume.rehearsal_store + hcloud_volume.rehearsal_luks
    mechanism:        # plaintext-exception
    evidence:         # ext4 scratch volumes holding a throwaway Redis AOF + SQLite state only;
                      # prod parity: inngest_expect_luks="false" is prod's live posture today
                      # (the LUKS recut arms later, #7695 series)
    defends_against:  # nothing beyond provider isolation — declared, not implied
    does_not_defend:  # a seized/RMA'd disk; a raw volume snapshot; anyone attaching the volume
                      # pre-destroy — defensible because every value on it is synthesized
                      # per-run throwaway material with zero user data
    disclosed_as:     # not-publicly-claimed
    live_verification: # available — `terraform state show` size/format fields
  - store:            # the rehearsal root's own terraform.tfstate (R2, soleur-terraform-state)
    mechanism:        # provider-managed: Cloudflare R2 object store (same posture the parent
                      # and rung2 roots already carry)
    evidence:         # inngest-provision-rehearsal/main.tf backend block; matches
                      # rung2-rehearsal/main.tf's shape
    defends_against:  # accidental local state; cross-root state collision (distinct key)
    does_not_defend:  # a reader of the bucket sees the baked scratch Doppler token, the prod
                      # Better Stack ingest token, and the prod zot pull token in plaintext —
                      # same sensitivity class as the parent root's state, which already holds
                      # the equivalent values
    disclosed_as:     # not-publicly-claimed
    live_verification: # available — object presence in R2
in_transit:
  - connection:        # rehearsal host -> zot (10.0.1.30:5000) over the private subnet
    enforced_at:       # apps/web-platform/infra/cloud-init-inngest.yml (zot login + pull arm)
    tls:               # none — plain HTTP inside 10.0.1.0/24, the ADR-096 Phase-0 accepted
                       # posture this host already inherits (digest pin protects the payload,
                       # not the credential — inngest-host.tf's own trust-boundary note)
    cert_verification: # off
    does_not_defend:   # a private-net sniffer sees the pull token + image bytes — same exposure
                       # prod's inngest host has today; the rehearsal adds one more transitorily
                       # attached member for ~the rehearsal window
    disclosed_as:      # ADR-096 Phase-0 posture (insecure-registry allowlist)
  - connection:        # rehearsal host -> api.doppler.com / Sentry ingest / Better Stack ingest
    enforced_at:       # host egress over the public NIC (deny-all ingress; egress-only)
    tls:               # https, vendor-managed endpoints
    cert_verification: # on (OS trust store)
    does_not_defend:   # endpoint compromise; DNS/egress tampering on a bootstrapping host
    disclosed_as:      # not-publicly-claimed
exception:
  justification:      # the private-net HTTP zot path is the existing production posture the
                      # rehearsal exists to exercise — weakening it in rehearsal would falsify
                      # the evidence
  tracking_issue:     # #9175
  reevaluate_when:    # the registry's private-net TLS work (ADR-096 follow-ons) lands, or the
                      # rehearsal is promoted from throwaway to standing
  expires_on:         # 2027-01-05
```

## Infrastructure (IaC)

All provisioning for this feature is Terraform (`hr-all-infrastructure-provisioning-servers`;
the IaC Routing Gate fired on `new Terraform root` + `hcloud_server` + `doppler_environment`):

- **Apply/destroy mechanism:** `terraform apply`/`destroy` run ONLY inside
  `.github/workflows/inngest-provision-rehearsal.yml` behind `environment:
  web-platform-infra-apply` (reviewer-gated), a `confirm` token, and `dry_run` defaulting
  true. The plan/apply artifacts are never executed locally.
- **No provisioners:** zero `remote-exec`, `local-exec`, `file`, or `null_resource`; host
  mutation is exclusively first-boot `user_data` (cloud-init). The one non-Terraform mutation
  is `POST /servers/{id}/actions/reboot` — control-plane API, mirroring #9372's
  web-host-reboot precedent.
- **Secrets:** every secret-bearing input is a `sensitive`, no-default variable fed from
  `TF_VAR_*` loaded via the Tier-B loader (`.github/actions/infra-credentials`,
  DOPPLER_TOKEN_INFRA_PRIVILEGED for provider ops; ZOT_PULL_TOKEN read out of `soleur/prd` at
  dispatch time — never committed, never a default). Throwaway values are `random_*`
  resources, not operator-typed strings.
- **Backend:** Cloudflare R2, `use_lockfile = false` (R2 lacks conditional writes), distinct
  key `web-platform/inngest-provision-rehearsal/terraform.tfstate` —
  `hr-every-new-terraform-root-must-include-an`.
- **Parallel-state discipline:** the root joins `concurrency.group:
  terraform-apply-web-platform-host` because it writes into objects the parent applies touch
  (the private network's member set; project `soleur-inngest`'s environment list).
- **No new API-surface blind spot:** every resource class used is already exercised by the
  parent root or rung2 under the same tokens (hcloud server/volume/firewall/ssh_key/
  server_network; doppler environment/secret/service_token). The one first-use-in-this-root
  shape — `hcloud_server_network` against a data-sourced network — gets a known-granted
  control probe in the workflow's phase-A precondition (`GET /networks/<id>` on the same
  token) before any write, per the ADR-130 probe discipline.

## Architecture Decision (ADR/C4)

ADR required — provisional **ADR-279** (re-probe ordinals across all `origin/*` before
writing; the ordinal is provisional until merge). The decision it records:

1. An in-scope rehearsal may attach to the production private network *through read-only data
   sources* — the divergence from rung2's detached posture is justified because the subnet is
   the subject under test — bounded by: data-source-only reference, a dedicated free IP
   (`10.0.1.60`), deny-all firewall, diagnostic boot (no prod scheduler/datastore contact),
   and a fenced attach window.
2. The inngest boot surface's Doppler config name becomes an env/template parameter with a
   `prd` default — converging on git-data's existing `doppler_config_name` pattern and making
   scratch-config rehearsals possible at all.
3. `INNGEST_DIAGNOSTIC_BOOT` is the rehearsal's durable-state stand-in; the non-diagnostic
   arm is explicitly deferred.
4. Evidence is an off-host Better Stack stage sequence joined on `iid`, assembled by a
   three-state capture script — never an operator looking at a dashboard
   (`hr-no-dashboard-eyeball-pull-data-yourself`).

C4: no new model element (an ephemeral rehearsal instance of `platform.infra.inngest`); a
prose-accuracy edit to the `github -> hetzner` edge enumeration in `model.c4` (it already
names sibling rehearsal routes) + a `views.c4` completeness check. No external actor or vendor
is added — Hetzner, Doppler, Better Stack, Sentry, GHCR are all already modeled.

## Guard Contract

### Guard 1 — rehearsal-root production-reference census

**Property.** No `resource`, `module`, or `terraform_remote_state` block inside
`apps/web-platform/infra/inngest-provision-rehearsal/` may reference a production address; the
only prod-named references permitted anywhere in the root is the single read-only `data`
block (`hcloud_network.private`).

**Assembly.** Every `resource`/`module`/`data`/`terraform_remote_state` declaration in every
`*.tf` file in the root, plus every attribute expression in those files that could carry an
address (`hcloud_*`, `doppler_*`, `terraform_remote_state`, `data.` references). Chokepoint:
the comment-stripped grep step in the workflow AND the sentinel suite arm — both enumerate
the full file set, never a named list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add `resource "hcloud_server" "x"` referencing `hcloud_server.inngest.id` | RED |
| 2 | Make the census script a no-op (`: >`-equivalent / greps a fixed empty path) | RED |
| 3 | Add a second prod-referencing `data` block beyond the two allowed (e.g. `data "hcloud_server" "inngest"`) | RED |
| 4 | Rename a rehearsal resource to a name without `rehearsal` | RED |

### Guard 2 — plan-shape guard (`scripts/inngest-provision-plan-shape.sh`)

**Property.** In `additive` mode the plan may only create `.rehearsal`-addressed resources; in
`nic-attach` mode it may create exactly `hcloud_server_network.rehearsal` (plus no-ops/reads);
every other action class or address fails closed.

**Assembly.** The `resource_changes[]` array of `terraform show -json` output for every
apply the workflow performs. Chokepoint: the single guard script invoked by both phase steps.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Fixture where phase-A plan includes an `update` to a `.rehearsal` resource | RED |
| 2 | Guard exits 0 on an empty/missing plan JSON (vacuous pass) | RED |
| 3 | Fixture where phase-B plan creates TWO resources (the NIC + a straggler) | RED |
| 4 | Fixture where a create names a non-`.rehearsal` address | RED |

### Guard 3 — prod-render invariance under parameterization

**Property.** With `inngest_doppler_config = "prd"` and `DOPPLER_CONFIG` unset, every rendered
`--config`/`--project` on the inngest boot path resolves to exactly the pre-change literals
(`prd`, `soleur-inngest`).

**Assembly.** Every site in `cloud-init-inngest.yml` + `inngest-bootstrap.sh` +
`inngest-cutover-flip*` + `inngest-luks-cutover*` that emits a `--config`/`--project` flag;
enumerated by grep census in the updated pinning suites (an unclassified new site → RED).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Change one site's default to `${DOPPLER_CONFIG:-dev}` | RED |
| 2 | The census asserts a named-site list and a new `--config` site is added unlisted | RED |
| 3 | Parameterize a `--project soleur-inngest` site (project must stay literal) | RED |
| 4 | Add a second parameterized site while the sentinel's floor stays stale | RED |

### Guard 4 — naming-prefix discipline

**Property.** Every sweep, capture, and label rule anchors on `soleur-inngest-rehearsal-` /
`app=soleur-inngest-provision-rehearsal` — never on the bare prefix `soleur-inngest`, which
matches the production host.

**Assembly.** Every name/label/prefix literal in `rehearsal.tf`, the workflow, the capture
script, and the drift-sweep block. Chokepoint: the sentinel suite's prefix arms.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Shorten the sweep prefix to `soleur-inngest` (drops the hyphen + qualifier) | RED |
| 2 | Guard greps only `rehearsal.tf` and the prefix literal moves to `main.tf` | RED |
| 3 | A second distinct prefix is introduced (e.g. `soleur-inngest-rehearsal2-`) unlisted | RED |

### Guard 5 — workflow hygiene sentinel

**Property.** The dispatch workflow carries the rung2-derived invariants verbatim in shape:
`dry_run` default true, `confirm` typo-token required, `environment: web-platform-infra-apply`,
the apply-serializing concurrency literal, `permissions: contents: read`, every step
`timeout-minutes`-bounded, teardown `if: always()`, evidence written to an artifact — never
committed.

**Assembly.** The whole `inngest-provision-rehearsal.yml` file (comment-stripped greps +
`yq`-parsed fields where a field's absence is the failure class).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Flip `dry_run` default to `false` | RED |
| 2 | Remove `environment:` from the apply job | RED |
| 3 | Add a step without `timeout-minutes` | RED |
| 4 | Add `contents: write` / a `git commit` step | RED |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Rehearse, on a throwaway Terraform-managed root, the late-NIC-attach / missed-first-pull race against a real zot mirror and real Doppler." | Files-to-Create: `inngest-provision-rehearsal/` root, `inngest-provision-rehearsal.yml` (two-phase `nic_attached` gate), Proposed Solution "forced race" bullet | mapped |
| 2 | "The rehearsal should cover both the #8539 fallback" | Evidence arm: `private_nic_timeout`/`provision-nic-ABSENT`/`private_nic_ok by=99-soleur-private-fallback` stage assertions in the capture script + workflow gating | mapped |
| 3 | "the new `soleur-inngest-provision` unit's recovery: the unit restarts" | ≥2 observed `provision-attempt-start`/`provision-attempt-exit-*` pairs for one `iid` before phase B | mapped |
| 4 | "the latch is written only after `bootstrap-done`" | Latch-ordering evidence: attempt counter increments post-attach (no latch on failures) + `bootstrap-done` precedes latch-proven silence | mapped |
| 5 | "a reboot does not re-run the unit" | Reboot arm: Hetzner-API reboot → `SOLEUR_INNGEST_BS_TOKEN_RESTAGED` anchor + zero post-reboot `provision-attempt-start` for the `iid` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `inngest-provision-rehearsal/` TF root (main/variables/rehearsal/lockfile) | "a throwaway Terraform-managed root" | asked |
| `inngest-provision-rehearsal.yml` two-phase workflow | "the late-NIC-attach / missed-first-pull race" | asked |
| `inngest-provision-rehearsal-capture.sh` + evidence env | "the unit restarts, the latch is written only after `bootstrap-done`, and a reboot does not re-run the unit" (evidence arms 3–5) | asked |
| `DOPPLER_CONFIG`/`inngest_doppler_config` parameterization edits (cloud-init, bootstrap, cutover scripts) | — | inferred — justification: every boot-path Doppler call pins `--config prd` literally; a scratch config can never be named `prd`, so without this the rehearsal's host can never pass the isolation check or reach `bootstrap-done` — the ask's own success criteria require it |
| New `vinngest-v*` image mint + pin bump (via existing publish machinery, post-merge) | — | inferred — justification: the parameterized `inngest-bootstrap.sh` ships inside the image; the rehearsal pulls the pinned image, so the enabler is unreachable without a mint. Delivered dark via ADR-232 machinery |
| `inngest-provision-plan-shape.sh` + fixtures | — | inferred — justification: the rehearsal writes into prod-adjacent surfaces (network membership, soleur-inngest project); an unguarded apply is the precise failure class the rung2 shape gate exists for |
| Sentinel test `inngest-provision-rehearsal.test.sh` | — | inferred — justification: Guards 1/4/5 are assertions about file content; without a pinning suite they decay silently (`hr-*` discipline + rung2's own test-file convention) |
| Drift-sweep extension in `scheduled-terraform-drift.yml` | — | inferred — justification: ask 6-adjacent ("throwaway" implies reclaimable); forgotten-resource visibility is the rung2 doctrine |
| `!apps/web-platform/infra/inngest-provision-rehearsal/**` path exclusion in apply-web-platform-infra.yml | — | inferred — justification: without it a merge touching the rehearsal dir fires the production apply workflow |
| Runbook `inngest-provision-rehearsal.md` | — | inferred — justification: ADR-231 byte-budget requires operator prose to live in a runbook, not the workflow |
| ADR-279 (provisional) | — | inferred — justification: attaching a throwaway host to the production private network is a trust-boundary decision differing from rung2's detached posture; it must be recorded to survive later review |
| `model.c4` edge prose update | — | inferred — justification: the `github -> hetzner` edge enumerates CI callers by name; leaving this caller unlisted makes the model false |
| `inngest-provision-rehearsal-probe.sh` | — | inferred — justification: the Observability `discoverability_test` requires a committed probe on an allowlisted verb |
| `inngest-server.md` paragraph | — | inferred — justification: the runbook is the operator surface for the provision unit; an unnamed rehearsal route is undiscoverable |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform` (infra subtree), `.github`, `scripts`, `tests`,
  `knowledge-base`
- Planned files: ~22 created+edited | Estimated changed lines: ~1,900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **split — PR-A = the `DOPPLER_CONFIG` parameterization + suite updates
  (small, prod-behavior-identical, independently reviewable); PR-B = the rehearsal harness
  (new files only, zero prod risk, inert until the parameterized image is minted).** The
  one-shot pipeline will land both on this branch unless the reviewer elects the split at
  review time; the commit stream should still be split along that seam.

## Domain Review

- **Domains relevant:** Engineering only (CTO-domain: Terraform roots, dispatch workflows,
  systemd units, secrets topology). No product, marketing, legal, finance, sales, support, or
  operations surface — the GDPR gate's four triggers do not fire (no schema/migration, no
  auth surface, no cron reading personal-data stores, no distribution surface carrying user
  data; the rehearsal host holds synthesized throwaway values only).
- **Fan-out note (pipeline mode):** domain-leader Task spawns are not available in this
  harness; the assessment above is an inline reading of `brainstorm-domain-config.md`'s domain
  boundaries. Engineering-criticality is self-evident (prod-adjacent infra), and the plan's
  Guard Contract + Observability sections carry the engineering-review load.

## Acceptance Criteria

- [ ] `terraform init` + `terraform validate` succeed in
      `apps/web-platform/infra/inngest-provision-rehearsal/` against the committed lockfile;
      `-lockfile=readonly` is clean.
- [ ] A dry-run `terraform plan` (phase A) shows only `*.rehearsal`-addressed creates and the
      two allowed `data` reads; phase-B plan shows exactly one create
      (`hcloud_server_network.rehearsal`). Both enforced by
      `scripts/inngest-provision-plan-shape.sh`.
- [ ] With `inngest_doppler_config="prd"` and `DOPPLER_CONFIG` unset, the rendered prod
      cloud-init and every emitted unit resolve `--config prd` / `--project soleur-inngest`
      byte-identically to pre-change (Guard 3 arms green in the updated suites).
- [ ] `inngest-provision-rehearsal.yml` dispatches only on `confirm=REHEARSE-INNGEST-PROVISION`,
      defaults `dry_run=true`, requires `environment: web-platform-infra-apply`, serializes on
      `terraform-apply-web-platform-host`, bounds every step, and tears down under `always()`.
- [ ] `apps/web-platform/infra/inngest-provision-rehearsal.test.sh` is discovered by
      `run-registered-suites.sh` and green, covering Guards 1/4/5 and the sentinel arms.
- [ ] `scheduled-terraform-drift.yml` sweeps the rehearsal label/prefix and `rehearsal_*`
      environments in `soleur-inngest`.
- [ ] `apply-web-platform-infra.yml` carries the negated `paths:` glob for the rehearsal dir.
- [ ] When dispatched for real (post-merge, post image-mint): the evidence artifact shows, for
      one `iid` — `private_nic_timeout`, ≥2 `provision-attempt-start`/`exit-*` pairs,
      `private_nic_ok`, `zot-login-ok`, `inngest_zot`, `isolation-check-passed`,
      `bootstrap-exit-0`, `bootstrap-done`, then post-reboot `SOLEUR_INNGEST_BS_TOKEN_RESTAGED`
      with zero subsequent `provision-attempt-start`. (This AC gates the ISSUE's closure, not
      the PR's merge — the harness ships unfired, rung2-style.)
- [ ] The diff is limited to the named Files to Create/Edit plus pipeline-generated
      `knowledge-base/INDEX.md` and `specs/<branch>/` artifacts.

## Test Scenarios

- Given the rehearsal root checked out, when `terraform plan -var nic_attached=false` runs,
  then the plan creates the server/volumes/firewall/doppler set and NO `hcloud_server_network`.
- Given phase B planned after phase A applied, when `nic_attached=true`, then the plan adds
  exactly `hcloud_server_network.rehearsal` and nothing else mutates.
- Given a `DOPPLER_CONFIG` parameterization regression (e.g. a site rendered `--config dev`),
  when `inngest-host.test.sh`/the sentinel census runs, then RED.
- Given the prod render, when `inngest_doppler_config="prd"`, then every `--config`/`--project`
  site matches the pre-change literals (render-diff test on the extracted unit text).
- Given a Better Stack fixture stream, when the capture script reads a stream missing the
  post-reboot anchor, then verdict is TRANSIENT/FAIL per its contract — never PASS.
- Given a workflow missing `environment:` or `timeout-minutes`, when the sentinel suite runs,
  then RED.

Verification commands (operator route, all read-only or dispatch):

- `gh workflow run inngest-provision-rehearsal.yml -f confirm=REHEARSE-INNGEST-PROVISION -f
  dry_run=true` — dry-run plans only.
- `gh workflow view inngest-provision-rehearsal.yml` — surface shape.
- Cleanup is the workflow's own teardown arm (`-f teardown_only=true`), never operator-side
  deletes.

## Dependencies & Risks

| Risk | P | I | Mitigation |
|---|---|---|---|
| Rehearsal host attached to the prod private network | M | M | Diagnostic boot (no prod datastore contact, loopback sdk-url), deny-all ingress, `web_host_private_ips=127.0.0.1`, ~30–60 min fenced window, teardown `always()`, ADR-279 records the posture |
| `--config` parameterization regresses prod | L | H | Every site defaults to `prd`; Guard 3 render-invariance census; delivered dark — reaches a host only via `inngest-host-replace`, which the rehearsal itself now precedes |
| Image mint/pin-bump ordering | M | L | The rehearsal is inert until the publish pipeline lands the new tag+pin; the runbook names the ordering (`Ref`, not `Closes`, on #9175) |
| Rehearsal token can read prod values | L | H | Environment-root config (non-inheriting) + read-scoped token + exact-set isolation check verified at boot |
| `provision_attempt_failed` paging during forced misses | H | L | Bounded: NIC-absent attempts exit pre-pull (no `inngest_pull_fatal`); ~a handful of warning-level events in the window; disclosed here and in the runbook |
| `hcloud_server_network` arg shape (`network_id`+`ip` vs `subnet_id`) or `doppler_environment` slug charset differs from assumed | M | L | Work-time verification against provider `~>1.49`/`~>1.21` docs + `terraform plan` in the dry-run arm before any apply |
| Precondition probes (doppler env create, network attach) hit an untested permission | L | M | ADR-130 control-probe discipline: phase A reads the network + project on the same token before writing |
| Evidence joins on `iid` mis-keyed | L | M | `iid` is emitted by the same phone-home call sites prod uses; capture keys on host_name + iid both |

## Deferrals

- **The live rehearsal run itself** — dispatch is environment-gated and requires the merged
  harness + the minted bootstrap image. Tracked by: #9175 stays open until a real run's
  evidence artifact is attached; the PR body must say `Ref #9175`, never `Closes`.
- **Non-diagnostic durable arm** (scratch docker Postgres on the rehearsal host covering the
  `inngest-pg-*`/`inngest-redis` markers + durable-ExecStart latch check) — candidate
  follow-up issue; re-evaluate if the diagnostic arm's evidence leaves a gap reviewers care
  about.
- **Extending the forced-race harness to git-data/registry hosts** — out of scope; the route
  is reusable but each host's own deferral owns that decision.

## Sharp Edges

- `inngest-provision-rehearsal.yml` — dispatching this mints real billed infrastructure on the
  production Hetzner project and attaches a foreign host to `soleur-private` for the duration;
  always `dry_run=true` first. Recovery after a mid-run failure: re-dispatch with
  `-f teardown_only=true`; if that fails, the sweep (next-daily) names the stragglers for
  Terraform-targeted destroy — never console clicks.
- `inngest_doppler_config`/`DOPPLER_CONFIG` — every site must keep `prd` as its default; a
  site that hard-codes a scratch name, or reads the env without a default, silently changes
  what prod's next `inngest-host-replace` boots into.
- `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` — a TRANSIENT verdict means
  the instrument (Better Stack query credentials/table) is suspect; do not read it as a host
  failure, and do not "fix" it by re-running until the anchor query itself returns rows.
- `inngest-provision-rehearsal/rehearsal.tf` — `nic_attached` is the load-bearing phase gate;
  planning phase B before phase A has produced miss evidence defeats the rehearsal's purpose
  (the NIC attaches while the unit might still succeed on attempt 1 — the race is then merely
  re-won, not exercised).

## References & Research

- Issue: #9175 (this), #9159 (merged PR; Tier-B rehearsal, filed the deferral), #8562 (unit
  design), #8539 (the incident being rehearsed), #7025 (rung-2 precedent), #8036 (zot-only
  pull), #9176/#9177 (landed siblings: alert + resume gate).
- Precedent files: `apps/web-platform/infra/rung2-rehearsal/{main,variables,rehearsal}.tf`,
  `.github/workflows/git-data-rung2-rehearsal.yml`,
  `scripts/git-data-rung2-plan-shape.sh`,
  `scripts/followthroughs/git-data-rung2-evidence-capture.sh`,
  `tests/scripts/test-git-data-rung2-plan-shape.sh`.
- Subject under test: `apps/web-platform/infra/cloud-init-inngest.yml`
  (`soleur-inngest-provision` script/service/timer, `inngest-boot-phone-home.sh`,
  `inngest-bs-token-restage.service`, `99-soleur-private-fallback.network`,
  `soleur-inngest-nic-wait`), `apps/web-platform/infra/inngest-bootstrap.sh`
  (DIAGNOSTIC_BOOT branch, ExecStart emission), `inngest-server-flip-guard.sh` (diagnostic +
  non-durable → allow).
- ADRs: ADR-096 (zot-only pull + insecure-registry posture), ADR-100 (single-writer inngest),
  ADR-115 §2026-09-22 (NIC-fallback mechanism + falsification criterion `private_nic_ok
  by=99-soleur-private-fallback`), ADR-149 DC-6 (rehearsal route doctrine), ADR-231
  (workflow byte-budget), ADR-232 (pin-bump machinery), ADR-241 (Tier-B credential loading),
  ADR-257 (latched retrying unit — the contract being proven).
- Learnings: `2026-09-28-a-retrying-unit-must-latch-only-full-success-and-undo-what-it-paused.md`,
  `2026-09-22` post-mortem `inngest-host-replace-private-nic-race-postmortem.md`,
  `2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md`.
