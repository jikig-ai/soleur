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
- [ ] 0.2 `@@HOST_NAME@@` → TF-injected per-host server name (via templatefile, like `image_name`), NOT runtime `$(hostname)`. Verify web-1/web-2 resolve to DISTINCT `soleur-web-platform`/`soleur-web-2` (`server.tf:102`); inngest keeps `soleur-inngest-prd`. (all hosts share ONE Better Stack source 2457081 — host_name is the sole discriminator)
- [ ] 0.3 `git grep -n 'soleur-inngest-prd' apps/web-platform/infra/` — enumerate every host_name consumer before parameterizing (incl. `zot-registry.tf:66-72`).
- [ ] 0.4 Prove no force-replace of web-1: `terraform plan` (canonical `doppler run --name-transformer tf-var`) shows 0 change to `hcloud_server.web["web-1"]` for the `host_script_files`/image change. Non-zero ⇒ STOP.
- [ ] 0.5 Dry-run `bash scripts/regenerate-c4-model.sh` to confirm it runs here.

## Phase 1 — Vector config parameterization (contract-declaring)

- [ ] 1.1 `vector.toml:344,358` — replace `soleur-inngest-prd` literal with `@@HOST_NAME@@` sentinel; keep `host_metrics` scrape interval + device excludes at cost-tuned inngest values.
- [ ] 1.2 `inngest-bootstrap.sh` — render `@@HOST_NAME@@`→`soleur-inngest-prd` on the inngest path so its Better Stack `host_name` is byte-identical to today (mirror `@@DOPPLER_PROJECT@@` at `:648-650`).
- [ ] 1.3 Author a decoupled web-host `vector.service` unit **as an in-script heredoc** (no `After=inngest-server.service`; **`EnvironmentFile=/etc/default/webhook-deploy`** — the DOPPLER_TOKEN source; NOT `/etc/default/inngest-server`; `ExecStart=doppler run --project soleur --config prd -- /usr/local/bin/vector …`). **P0: without the EnvironmentFile, `doppler run` has no token → Vector never starts (fail-open silent).**
- [ ] 1.4 `server.tf:16-59` — add `vector.toml` to `local.host_script_files` **AND the matching `COPY` line in `apps/web-platform/Dockerfile:177-204` IN LOCKSTEP** (P1: else `host_scripts_content_hash` mismatch → `web2-recreate-preflight.sh:98` aborts before `-replace`).

## Phase 2 — Ungated Vector install (consumer of Phase 1)

- [ ] 2.1 `soleur-host-bootstrap.sh` — baked `/usr/local/bin/soleur-vector-install` helper (heredoc, 0 user_data): `curl --max-time` fetch + sha-verify, install config (render `@@HOST_NAME@@`), install unit, `enable`+`restart --no-block` (NOT `enable --now`). Fully fail-open AND fail-fast (non-blocking).
- [ ] 2.2 `cloud-init.yml` — NEW ungated runcmd item at the END of the chain, AFTER the terminal block's `cloud_init_complete` emit (`:777`) and after the `%{ if web_colocate_inngest }` block: `- timeout 60 sh -c 'soleur-vector-install' || true`. (The `:9000` gate is the webhook bind, not the app origin `:80/:3000` — end-of-chain is safest for serving latency; journald backfills.)

## Phase 3 — Terminal serving-block boot-emit trap (DC-2)

- [ ] 3.1 `cloud-init.yml` — arm the trap EARLY, right after `set -e` at `:731` (NOT after `TMPENV=`): `stage=terminal_preamble; trap 'rc=$?; rm -f "${TMPENV:-}"; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal' EXIT` (covers the `. /etc/default/webhook-deploy` source + `mktemp` region). Mutable `stage=`: `hostscripts_check`→`terminal_preamble`→`doppler_download` (before `:742`)→`docker_run` (before `:755`).
- [ ] 3.1b Add explicit `soleur-boot-emit hostscripts_incomplete fatal` BEFORE the `poweroff -f` at `:738` (it does NOT self-emit; poweroff bypasses the EXIT trap).
- [ ] 3.2 Disarm `trap - EXIT` after `rm -f "$TMPENV"` (`:768`), BEFORE the egress-enforce-probe (`:772-774`) — that path self-emits + poweroffs.

## Phase 4 — `host_id` on `pull_failure_event`

- [ ] 4.1 `ci-deploy.sh:536` — add `host_id: $h` to `tags`; `--arg h "${HOST_ID:-}"` (readonly global at `:137-157`, empty-safe).

## Phase 5 — C4 edge + ADR amendments

- [ ] 5.1 `model.c4` — add `hetzner -> betterstack` edge after `:376`; correct/remove the stale per-host-probe edge at `:380` (retired #5933). NO `views.c4` change (both endpoints already in `containers` include).
- [ ] 5.2 `bash scripts/regenerate-c4-model.sh`; commit regenerated `model.likec4.json`.
- [ ] 5.3 Amend `ADR-082` (Decision + Alternatives + cross-refs) AND add a one-line Consequences back-ref in `ADR-100` (its default-false `web_colocate_inngest` dropped the co-located Vector path).

## Phase 5b — Sentry paging for the terminal-block fatal (P1)

- [ ] 5b.1 `sentry/issue-alerts.tf` — NEW `sentry_issue_alert`, `filters_v2` `tagged_event` `key="stage"` over `{terminal_preamble, hostscripts_incomplete, doppler_download, docker_run}` → operator (mirror `zot_mirror_fallback_rate:1368`). Wire into the sentry-infra apply scope.
- [ ] 5b.2 NEW op-contract test (`test/sentry-*-alert-op-contract.test.ts`) asserting the alert matches the terminal stage tags. (web-2 standby has no standing uptime coverage — this is the sole page for a dead standby.)

## Phase 6 — Tests

- [ ] 6.1 `soleur-host-bootstrap-observability.test.sh` — NEW AC: terminal-block trap + `trap - EXIT` disarm + terminal stage names (AC6b's `cleanup;` regex won't match a `rm -f "$TMPENV"` trap — add a dedicated assertion). NEW AC: ungated `soleur-vector-install` call site after `:9000` + installer authored once in `$BOOT`.
- [ ] 6.2 `cloud-init-inngest-bootstrap.test.sh` — update AC7: a fresh ungated host now installs Vector (no longer `web_colocate_inngest`-gated).
- [ ] 6.3 `journald-config.test.sh`, `inngest.test.sh` — reconcile Vector-config expectations with `@@HOST_NAME@@`.
- [ ] 6.4 `.github/workflows/validate-vector-config.yml` + VRL fixture — validate sentinel-rendered per-host config parses.
- [ ] 6.5 `ci-deploy.test.sh` — NET-NEW assertion capturing the `pull_failure_event` Sentry `-d` payload, asserting `tags.host_id` via `SOLEUR_HOST_ID_OVERRIDE` (pattern at `:1576`).
- [ ] 6.6 Run `c4-code-syntax.test.ts`, `c4-render.test.ts`, `c4-model-freshness.test.sh` (orphan — full-suite exit gate).

## Phase 7 — Verification + web-1 gap closure (no-SSH)

- [ ] 7.0 **Coherence ordering (P1):** merge → build/publish new `soleur-web-platform` image → normal deploy to web-1 → THEN dispatch `web-2-recreate`. (Else `web2-recreate-preflight.sh:98` COHERENCE MISMATCH abort.)
- [ ] 7.1 web-2 verify: `web-2-recreate` dispatch → `deploy-status-fanout-verify.sh` `reason==ok` off-host; Sentry breadcrumb trail shows `cloud_init_complete` for web-2 host_id; Better Stack source 2457081 non-zero for `host_name='soleur-web-2'`.
- [ ] 7.2 **web-1 blind-origin gap (HIGH — close, don't silently defer):** schedule ADR-068 blue-green promote-web-2 + recreate-web-1-as-standby (zero live poweroff) so web-1 ships logs. Deliverable 1 is half-met at ship (web-2 only) until this runs.
- [ ] 7.3 File a `follow-through`-labelled tracking issue: fires the `host_name='soleur-web-1'` Better Stack source check after web-1 recreate + folds it into the host-recreate runbook.

## Acceptance Criteria (post-condition gates)

### Pre-merge (PR)
- [ ] AC1 Fresh ungated web host installs Vector: `cloud-init-inngest-bootstrap.test.sh` proves the install is reachable with `web_colocate_inngest=false`.
- [ ] AC2 Vector install is fail-open + fail-fast: cloud-init call site is `timeout … sh -c 'soleur-vector-install' || true` placed at end-of-chain (after `cloud_init_complete`); assertion in observability test.
- [ ] AC3 `vector.toml` carries `@@HOST_NAME@@` (no bare `soleur-inngest-prd` literal at `:344,:358`); rendered from the TF-injected per-host server name; inngest render keeps its host_name unchanged.
- [ ] AC4 Terminal-block composite trap: armed at `:731` (stage=terminal_preamble), mutable stage, explicit `hostscripts_incomplete` emit before the `:738` poweroff, disarmed before the egress probe (dedicated observability-test AC).
- [ ] AC5 `pull_failure_event` payload includes `tags.host_id` (`ci-deploy.test.sh` payload-capture assertion, deterministic via `SOLEUR_HOST_ID_OVERRIDE`).
- [ ] AC6 `model.c4` has `hetzner -> betterstack` AND the stale `:380` per-host-probe edge corrected/removed; `model.likec4.json` regenerated + committed; c4 tests green.
- [ ] AC7 ADR-082 amended + ADR-100 Consequences back-ref added (not a follow-up issue).
- [ ] AC8 `terraform plan` shows 0 change to `hcloud_server.web["web-1"]` (no force-replace of the live origin).
- [ ] AC9 No new `doppler_secret`/TF var (BETTERSTACK_LOGS_TOKEN reused from `soleur/prd`).
- [ ] AC10 **web `vector.service` carries `EnvironmentFile=/etc/default/webhook-deploy`** (DOPPLER_TOKEN source) — dedicated unit-shape test.
- [ ] AC11 **`apps/web-platform/Dockerfile` COPY list includes `vector.toml` in lockstep with `local.host_script_files`** — lockstep membership test (mirror `cron-egress-enforce-probe.test.sh:140`).
- [ ] AC12 **NEW `sentry_issue_alert` matches the terminal stage tags** (`filters_v2` `key=stage`) — op-contract test.

### Post-merge (operator — menu-ack dispatch, no SSH)
- [ ] AC13 Ordering: new image built + deployed to web-1 BEFORE the `web-2-recreate` dispatch (else preflight coherence abort).
- [ ] AC14 `web-2-recreate` dispatch reports `reason==ok`; Sentry breadcrumb trail shows `cloud_init_complete` for web-2's host_id; Better Stack source 2457081 non-zero for `host_name='soleur-web-2'`.
- [ ] AC15 web-1 gap: `follow-through` tracking issue filed for the ADR-068 blue-green promote-web-2/recreate-web-1 closure + the `host_name='soleur-web-1'` source check.
