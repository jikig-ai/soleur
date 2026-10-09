---
title: The inngest provision unit gets an on-demand forced-race rehearsal route (two-phase NIC apply) in a separate Terraform root
status: accepted
date: 2026-10-08
supersedes: none
issue: 9175
related: [8539, 6180, 7228, 7025, 6178]
related_adrs: [ADR-149, ADR-231, ADR-115, ADR-100, ADR-232]
tags: [infrastructure, inngest, rehearsal, terraform, doppler]
brand_survival_threshold: none
---

# ADR-279: The inngest provision unit gets an on-demand forced-race rehearsal route (two-phase NIC apply) in a separate Terraform root

## Status

**Accepted at merge (implementation ships unfired; #9175 closes only on a post-merge run's
evidence, per ADR-084).** The harness merged behind `Ref #9175`; the ordinal was re-probed
across all `origin/*` refs immediately before this file was created (ADR-278 was already
claimed by `feat-open-web-egress`).

## Context

The 2026-09-22 incident (#8539): a freshly replaced inngest host booted before its private
NIC attached; the provision unit's zot pull failed unreachable, and the operator-visible
failure arrived late and ambiguous. The fix (ADR-115 amendment: the
`99-soleur-private-fallback.network` converge primitive + bounded NIC wait + retryable
provision unit) shipped and is live. What is not live is a way to know it still works: the
next `inngest-host-replace` is the next time the code path runs for real, and it would run
unrehearsed.

The rung-2 rehearsal route (#7025, ADR-149) already proved the shape — separate Terraform
root, dispatch-only workflow, plan-shape guard, off-box evidence — for the git-data birth.
This decision applies the same route doctrine to the provision path, with two deliberate
divergences listed under Considered Options.

## Decision

**A separate Terraform root** (`apps/web-platform/infra/inngest-provision-rehearsal/`,
state key `web-platform/inngest-provision-rehearsal/terraform.tfstate`) renders the
production `cloud-init-inngest.yml` through the same `base64gzip(replace(templatefile(…),
strip, ""))` pipeline and boots one throwaway `hcloud_server.rehearsal`. To make that
possible, the Inngest boot path's Doppler config name is parameterized end-to-end:
`inngest_doppler_config` (template var) → `DOPPLER_CONFIG` (env file + provision-unit env)
→ `--config ${DOPPLER_CONFIG:-prd}` / `@@DOPPLER_CONFIG@@` at all 19 boot-path sites;
production passes `"prd"` explicitly at the call site. The committed `.service` files use
plain systemd `${DOPPLER_CONFIG}` substitution — systemd does not support `:-` defaults in
`ExecStart`, so `inngest-bootstrap.sh` backstops `DOPPLER_CONFIG` into
`/etc/default/inngest-server` for preserved env files.

**The forced race is a two-phase apply.** `var.nic_attached` gates exactly
`hcloud_server_network.rehearsal` (`network_id` + `ip` — hcloud has no subnet data source).
Phase A births NIC-less and the workflow's evidence gate refuses Phase B until the expected
failure is observed; Phase B creates exactly the attachment (asserted by
`scripts/inngest-provision-plan-shape.sh nic-attach` — the delta is exactly
`hcloud_server_network.rehearsal[0]`, and absence fails). A Hetzner-API reboot then proves
the latch refuses re-provisioning.

**The scratch config is a `doppler_environment`, not a `doppler_config` branch.** A branch
config under `prd` resolves the environment's root as its base, which would hand the
throwaway host a token that reads every prod `soleur-inngest` secret. An environment's root
config inherits nothing, so the read-scoped `doppler_service_token.rehearsal` sees exactly
the five secrets staged for it (three throwaway randoms, `INNGEST_DIAGNOSTIC_BOOT=true`,
and the write-only `BETTERSTACK_LOGS_TOKEN`).

**Diagnostic boot is the durable-state answer.** `INNGEST_DIAGNOSTIC_BOOT=true` (#7228)
runs the real pipeline SQLite-only against a loopback `--sdk-url`, so the rehearsal host
cannot adopt a registry or double-fire prod crons even if every other guard failed — and
it cannot emit a false positive pass, because the isolation self-check, zot pull, and
bootstrap all still run for real.

**Evidence is an artifact, never a commit** (`permissions: contents: read`); the operator
attaches it to #9175 per the runbook.

## Consequences

- The #8539 recovery path is exercised end-to-end on demand: NIC-absent failure observed,
  attach heals, `bootstrap-done`, reboot leaves the latch holding.
- Prod behaviour is unchanged: every call site resolves `prd` today (render-pinned in the
  provision-unit suite; `inngest.test.sh` carries a 19-site census that REDs an
  unparameterized boot-path `--config`).
- The parameterization cannot reach a host until the next `vinngest-v*` mint + pin bump
  (ADR-232 pipeline) — a dispatch before that lands rehearses the pre-parameterization
  bytes and fails named at Phase A's Doppler reads. The runbook gates on this.
- Cost is one cpx22 host-hour per real run plus ~90 min wall clock, worst case.

## Considered Options

| Option | Rejected/accepted because |
|---|---|
| **`count=0` rehearsal inside the parent root** | Rejected — `-target` is transitive on dependencies; a rehearsal address referencing a prod resource could pull `hcloud_server.inngest` into a rehearsal apply's plan closure. A separate state file makes that structural rather than grep-enforced (same argument as ADR-149). |
| **`doppler_config` branch under `prd` (rung2's shape)** | Rejected here — branch configs inherit their environment's root secrets; a rehearsal token would read all of prod `soleur-inngest`. `doppler_environment` root configs inherit nothing. **Named follow-up:** rung2's `prd_git_data_rehearsal_*` branch DOES inherit `soleur/prd` — its "reads NOTHING of production's" claim merits re-audit. |
| **systemd `${DOPPLER_CONFIG:-prd}` in committed units** | Rejected — systemd `EnvironmentFile=` interpolation supports `${FOO}`/`$FOO` only; a `:-` token resolves empty and breaks `doppler run`. Plain `${DOPPLER_CONFIG}` + the env file carries the value. |
| **Scratch private network for Phase B** | Rejected — the subnet IS the subject; the attach event on the real `10.0.1.0/24` (and zot reachability over it) is what is being rehearsed. |
| **Scratch docker Postgres arm (full non-diagnostic durable state)** | Deferred — the plan names it a follow-up; diagnostic boot is the #9175 scope. |
