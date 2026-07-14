---
title: web-host Vector log-shipping + boot observability — tasks
issue: 6396
lane: single-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-14-feat-web-host-vector-log-shipping-boot-observability-plan.md
---

# Tasks — #6396 web-host Vector log-shipping + boot observability

Derived from the finalized plan. Contract-declaring edits (Phase 1 config parameterization)
precede their consumers (Phase 2 install). All host-side commands run inside Terraform-delivered
artifacts (`soleur-host-bootstrap.sh` OCI-baked, `cloud-init.yml` user_data) — no operator SSH.

## Phase 0 — Preconditions (verify, do not edit)

- [ ] 0.1 Confirm `BETTERSTACK_LOGS_TOKEN` readable in `soleur/prd` (read-only `doppler secrets get … --project soleur --config prd`). Absent ⇒ STOP.
- [ ] 0.2 Decide `@@HOST_NAME@@` substitution rule: is the inngest host's OS `hostname` == `soleur-inngest-prd`? Yes ⇒ uniform `$(hostname)`; No ⇒ path-specific value on the inngest render. (`inngest-bootstrap.sh:595-650`, `server.tf:102`)
- [ ] 0.3 `git grep -n 'soleur-inngest-prd' apps/web-platform/infra/` — enumerate every host_name consumer before parameterizing (incl. `zot-registry.tf:66-72`).
- [ ] 0.4 Prove no force-replace of web-1: `terraform plan` (canonical `doppler run --name-transformer tf-var`) shows 0 change to `hcloud_server.web["web-1"]` for the `host_script_files`/image change. Non-zero ⇒ STOP.
- [ ] 0.5 Dry-run `bash scripts/regenerate-c4-model.sh` to confirm it runs here.

## Phase 1 — Vector config parameterization (contract-declaring)

- [ ] 1.1 `vector.toml:344,358` — replace `soleur-inngest-prd` literal with `@@HOST_NAME@@` sentinel; keep `host_metrics` scrape interval + device excludes at cost-tuned inngest values.
- [ ] 1.2 `inngest-bootstrap.sh` — render `@@HOST_NAME@@` on the inngest path per the Phase 0 decision so its Better Stack `host_name` is byte-identical to today (mirror `@@DOPPLER_PROJECT@@` at `:648-650`).
- [ ] 1.3 Author a decoupled web-host `vector.service` unit (no `After=inngest-server.service`, no `EnvironmentFile=/etc/default/inngest-server`; `ExecStart=doppler run --project soleur --config prd -- /usr/local/bin/vector …`).
- [ ] 1.4 `server.tf:16-59` — add `vector.toml` (+ the web-host unit if a file) to `local.host_script_files` (OCI-baked, `host_scripts_content_hash`-covered).

## Phase 2 — Ungated Vector install (consumer of Phase 1)

- [ ] 2.1 `soleur-host-bootstrap.sh` — baked `/usr/local/bin/soleur-vector-install` helper (heredoc, 0 user_data): `curl --max-time` fetch + sha-verify, install config (render `@@HOST_NAME@@`), install unit, `enable`+`restart --no-block` (NOT `enable --now`). Fully fail-open AND fail-fast (non-blocking).
- [ ] 2.2 `cloud-init.yml` — NEW ungated runcmd item AFTER the `:609` `:9000` gate: `- timeout 60 sh -c 'soleur-vector-install' || true`.

## Phase 3 — Terminal serving-block boot-emit trap (DC-2)

- [ ] 3.1 `cloud-init.yml:730-778` — mutable `stage=` var (`doppler_download` before `:742`, `docker_run` before `:755`); arm `trap 'rc=$?; rm -f "$TMPENV"; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal' EXIT` after `TMPENV=` (`:740`).
- [ ] 3.2 Disarm `trap - EXIT` after `rm -f "$TMPENV"` (`:768`), BEFORE the egress-enforce-probe (`:772-774`) — that path self-emits + poweroffs (and `poweroff -f` bypasses EXIT traps anyway).

## Phase 4 — `host_id` on `pull_failure_event`

- [ ] 4.1 `ci-deploy.sh:536` — add `host_id: $h` to `tags`; `--arg h "${HOST_ID:-}"` (readonly global at `:137-157`, empty-safe).

## Phase 5 — C4 edge + ADR-082 amendment

- [ ] 5.1 `model.c4` — add `hetzner -> betterstack` edge after `:376`, tech `"Vector → Better Stack Logs (HTTPS)"`. NO `views.c4` change (both endpoints already in `containers` include).
- [ ] 5.2 `bash scripts/regenerate-c4-model.sh`; commit regenerated `model.likec4.json`.
- [ ] 5.3 Amend `ADR-082-fresh-web2-boot-observability.md` (Decision + Alternatives + cross-ref ADR-100/ADR-068).

## Phase 6 — Tests

- [ ] 6.1 `soleur-host-bootstrap-observability.test.sh` — NEW AC: terminal-block trap + `trap - EXIT` disarm + terminal stage names (AC6b's `cleanup;` regex won't match a `rm -f "$TMPENV"` trap — add a dedicated assertion). NEW AC: ungated `soleur-vector-install` call site after `:9000` + installer authored once in `$BOOT`.
- [ ] 6.2 `cloud-init-inngest-bootstrap.test.sh` — update AC7: a fresh ungated host now installs Vector (no longer `web_colocate_inngest`-gated).
- [ ] 6.3 `journald-config.test.sh`, `inngest.test.sh` — reconcile Vector-config expectations with `@@HOST_NAME@@`.
- [ ] 6.4 `.github/workflows/validate-vector-config.yml` + VRL fixture — validate sentinel-rendered per-host config parses.
- [ ] 6.5 `ci-deploy.test.sh` — NET-NEW assertion capturing the `pull_failure_event` Sentry `-d` payload, asserting `tags.host_id` via `SOLEUR_HOST_ID_OVERRIDE` (pattern at `:1576`).
- [ ] 6.6 Run `c4-code-syntax.test.ts`, `c4-render.test.ts`, `c4-model-freshness.test.sh` (orphan — full-suite exit gate).

## Phase 7 — Verification (no-SSH)

- [ ] 7.1 Post-merge: `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6396 vector+trap verify'`; `deploy-status-fanout-verify.sh` → `reason==ok` off-host; Sentry breadcrumb trail shows `cloud_init_complete` for the host_id; Better Stack shows a non-zero `soleur-web-2` source.
- [ ] 7.2 web-1: verification deferred to its next natural recreate (documented, NOT force-replaced).

## Acceptance Criteria (post-condition gates)

### Pre-merge (PR)
- [ ] AC1 Fresh ungated web host installs Vector: `cloud-init-inngest-bootstrap.test.sh` proves the install is reachable with `web_colocate_inngest=false`.
- [ ] AC2 Vector install is fail-open + fail-fast: cloud-init call site is `timeout … sh -c 'soleur-vector-install' || true` after the `:9000` gate (assertion in observability test).
- [ ] AC3 `vector.toml` carries `@@HOST_NAME@@` (no bare `soleur-inngest-prd` literal at `:344,:358`); inngest render keeps its host_name unchanged.
- [ ] AC4 Terminal-block composite trap present with mutable stage + disarmed before the egress probe (dedicated observability-test AC).
- [ ] AC5 `pull_failure_event` payload includes `tags.host_id` (`ci-deploy.test.sh` payload-capture assertion, deterministic via `SOLEUR_HOST_ID_OVERRIDE`).
- [ ] AC6 `model.c4` has `hetzner -> betterstack`; `model.likec4.json` regenerated + committed; c4 tests green.
- [ ] AC7 ADR-082 amended (not a follow-up issue).
- [ ] AC8 `terraform plan` shows 0 change to `hcloud_server.web["web-1"]` (no force-replace of the live origin).
- [ ] AC9 No new `doppler_secret`/TF var (BETTERSTACK_LOGS_TOKEN reused from `soleur/prd`).

### Post-merge (operator — menu-ack dispatch, no SSH)
- [ ] AC10 `web-2-recreate` dispatch reports `reason==ok`; Sentry breadcrumb trail shows `cloud_init_complete` for web-2's host_id; Better Stack `soleur-web-2` source non-zero.
