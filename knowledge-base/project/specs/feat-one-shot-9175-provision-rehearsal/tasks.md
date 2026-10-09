# Tasks: inngest provision forced-race rehearsal (#9175)

Plan: `knowledge-base/project/plans/2026-10-08-infra-inngest-provision-forced-race-rehearsal-plan.md`

Execution order: Phase 1 (parameterization + red-then-green suites), Phase 2 (rehearsal TF
root + guards), Phase 3 (workflow + capture + sweep), Phase 4 (docs/ADR/spec). The live
rehearsal dispatch is post-merge and operator-gated — it is NOT a work-skill task here.

## Phase 1: `DOPPLER_CONFIG` parameterization (Deliverable A)

- [x] 1.1 Grep-enumerate every `--config prd` / `--project soleur-inngest` literal on the
      inngest boot path (cloud-init-inngest.yml ~9 sites; inngest-bootstrap.sh ~8;
      inngest-cutover-flip.sh; inngest-luks-cutover.sh; inngest-cutover-flip.service;
      inngest-luks-cutover.service). Record the census in the commit message.
- [x] 1.2 Update the pinning suites RED first: `cloud-init-inngest-provision-unit.test.sh`,
      `cloud-init-inngest-bootstrap.test.sh`, `inngest-host.test.sh`,
      `inngest-cutover-flip.test.sh`, `inngest-luks-cutover.test.sh`,
      `inngest-server-flip-guard.test.sh`, `inngest-boot-emitter.test.sh` — each asserts the
      parameterized form AND that the prod default resolves `prd`.
- [x] 1.3 `inngest-bootstrap.sh`: `--config "${DOPPLER_CONFIG:-prd}"` (or `@@DOPPLER_CONFIG@@`
      render substitution where the unit text is emitted); pass `DOPPLER_CONFIG` into the
      bootstrap env the provision script sets.
- [x] 1.4 `inngest-cutover-flip.sh` / `inngest-luks-cutover.sh`: same env-defaulted contract
      for their internal `doppler secrets get/set/delete` calls.
- [x] 1.5 `inngest-cutover-flip.service` / `inngest-luks-cutover.service`: `EnvironmentFile=`
      + systemd `$DOPPLER_CONFIG` substitution (or render-time substitution if emitted by
      bootstrap.sh — pick per file).
- [x] 1.6 `cloud-init-inngest.yml`: add `inngest_doppler_config` template var; substitute at
      every template-side `--config prd` site (secrets staging :~370, bs-token restage :~635,
      isolation check :~935, DIAGNOSTIC_BOOT read :~1192 — re-grep); add `DOPPLER_CONFIG=` to
      `/etc/default/inngest-doppler`.
- [x] 1.7 `inngest-host.tf`: pass `inngest_doppler_config = "prd"` explicitly in the
      templatefile args.
- [x] 1.8 `bash apps/web-platform/infra/run-registered-suites.sh` — green (or the scoped
      suites first, then the full pass).
- [x] 1.9 Verify prod-render invariance: rendered units/scripts resolve `--config prd` /
      `--project soleur-inngest` byte-identically with defaults (Guard 3 census).

## Phase 2: Rehearsal Terraform root (Deliverable B, infra half)

- [x] 2.1 `apps/web-platform/infra/inngest-provision-rehearsal/main.tf` — R2 backend
      `web-platform/inngest-provision-rehearsal/terraform.tfstate`, `use_lockfile=false`,
      providers pinned to the parent root's versions.
- [x] 2.2 `variables.tf` — `hcloud_token`, `doppler_token_tf`, `sentry_dsn`,
      `betterstack_logs_token`, `zot_pull_token`, `rehearsal_run_id` (validation
      `^[0-9]+$`), `nic_attached` (bool), `location`/`server_type` defaults `hel1`/`cpx22`.
      No defaults on secret vars.
- [x] 2.3 `rehearsal.tf` — `tls_private_key` + `hcloud_ssh_key.rehearsal`;
      `doppler_environment.rehearsal` (project `soleur-inngest`, slug `rehearsal_<runid>` —
      verify slug charset at work); five `doppler_secret`s (throwaway `random_*` for
      INNGEST_SIGNING_KEY/EVENT_KEY/REDIS_PASSWORD, `INNGEST_DIAGNOSTIC_BOOT="true"`,
      `BETTERSTACK_LOGS_TOKEN`); `doppler_service_token.rehearsal` (read scope); two
      `hcloud_volume`s; deny-all `hcloud_firewall`; `hcloud_server.rehearsal` with the
      byte-identical render call (identity args only: doppler_token, inngest_doppler_config,
      inngest_private_ip=10.0.1.60, sdk_url=loopback, web_host_private_ips=127.0.0.1, scratch
      volume ids); `hcloud_server_network.rehearsal` (`count = var.nic_attached ? 1 : 0`,
      `network_id = data.hcloud_network.private.id`, `ip = "10.0.1.60"` — verify arg shape
      against provider ~>1.49). Label everything `app=soleur-inngest-provision-rehearsal`;
      name the host `soleur-inngest-rehearsal-<run_id>`.
- [x] 2.4 `terraform init` → commit `.terraform.lock.hcl`; `terraform validate` clean.
- [x] 2.5 `scripts/inngest-provision-plan-shape.sh` — `additive` + `nic-attach` modes;
      `tests/scripts/test-inngest-provision-plan-shape.sh` with real plan-JSON fixtures.

## Phase 3: Workflow + capture + sweep (Deliverable B, CI half)

- [x] 3.1 `.github/workflows/inngest-provision-rehearsal.yml` — dispatch-only;
      `confirm=REHEARSE-INNGEST-PROVISION`; `dry_run` default true; `teardown_only`;
      `environment: web-platform-infra-apply`; `concurrency.group:
      terraform-apply-web-platform-host`; `permissions: contents: read`; every step
      `timeout-minutes`; phase-B apply gated on observed miss markers; reboot via
      `POST /v1/servers/<id>/actions/reboot`; evidence artifact; teardown `always()`.
      ADR-231: assemble section-at-a-time; prose goes to the runbook.
- [x] 3.2 `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` + colocated test —
      three-state 0/1/2; source-liveness anchor; iid-joined stage sequence;
      `inngest-provision-rehearsal-evidence.env`.
- [x] 3.3 `scripts/inngest-provision-rehearsal-probe.sh` — public API runs-read printing
      `last_run_conclusion=<…>`.
- [x] 3.4 `apps/web-platform/infra/inngest-provision-rehearsal.test.sh` — sentinel suite
      (Guards 1/4/5 arms; `.rehearsal` census; workflow invariants).
- [x] 3.5 `apply-web-platform-infra.yml` — add `!apps/web-platform/infra/inngest-provision-rehearsal/**`.
- [x] 3.6 `scheduled-terraform-drift.yml` — orphan sweep for the label/prefix +
      `rehearsal_*` environments in `soleur-inngest`.

## Phase 4: Docs / records

- [x] 4.1 `runbooks/inngest-provision-rehearsal.md` — dispatch invocation, artifacts table,
      outcome table, After-a-PASS (attach evidence to #9175).
- [x] 4.2 ADR-279 (PROVISIONAL — re-probe all `origin/*` refs immediately before writing;
      ADR-278 is claimed by `feat-open-web-egress`).
- [x] 4.3 `model.c4` `github -> hetzner` edge prose names this route; `views.c4`
      completeness check.
- [x] 4.4 `inngest-server.md` — Provision-unit paragraph names the rehearsal route.
- [ ] 4.5 PR body: `Ref #9175` (NEVER `Closes` — the issue closes on a real run's evidence);
      first line states the production effect (none until next `inngest-host-replace`).

## Post-merge (operator-gated — tracked by #9175, not this task list)

- [ ] The image pipeline mints `vinngest-v*` carrying the parameterized bootstrap; pin-bump
      PR lands (ADR-232 machinery).
- [ ] Dispatch `inngest-provision-rehearsal.yml -f dry_run=true`, then the real run;
      attach `inngest-provision-rehearsal-evidence.env` to #9175.
