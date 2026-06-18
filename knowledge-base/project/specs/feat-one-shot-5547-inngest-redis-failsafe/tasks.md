---
title: "fix(inngest): durable image delivers Redis assets + SQLite fail-safe"
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-18-fix-inngest-durable-redis-delivery-and-failsafe-plan.md
issue: 5547
date: 2026-06-18
---

# Tasks — #5547 Inngest durable Redis delivery + SQLite fail-safe

> Derived from the finalized (post-deepen) plan. Phase order is load-bearing:
> Gap 1 (delivery) before Gap 2 (precondition); env-file before Redis before
> server-unit heredoc. Brand-survival threshold: single-user incident.
> Issue link: use `Ref #5547` in the PR body, NOT `Closes` (ops-remediation:
> full fix proven only by the post-merge live deploy).

## Phase 0 — Preconditions (read-before-edit)

- [ ] 0.1 Re-read at HEAD: `ci-deploy.sh` `case "inngest")` + `verify_inngest_health`;
  `cloud-init.yml` Redis docker-cp lines (the form to mirror); `inngest-bootstrap.sh`
  durable-Redis block + env-file materialization block + server-unit heredoc.
- [ ] 0.2 Record the current line ranges of (a) env-file materialization,
  (b) durable-Redis install block, (c) server-unit `cat >` in `inngest-bootstrap.sh`.
  Target Phase-2 order: env-file → Redis install + `REDIS_READY` → server heredoc.
- [ ] 0.3 Confirm Gap-1 docker-cp lines run as `deploy` (no sudoers change needed);
  staging target is `/tmp/inngest-redis.*`.
- [ ] 0.4 Run `bash apps/web-platform/infra/inngest.test.sh` — confirm it passes at
  HEAD before adding asserts (it will be newly CI-wired; surface latent drift now).

## Phase 1 — Gap 1: deliver Redis assets (existing-host path)

- [ ] 1.1 In `ci-deploy.sh` `case "inngest")`, after the `/vector.toml` docker-cp and
  before `docker rm "$INNGEST_EXTRACT_CONTAINER"`, add `rm -f` + three `docker cp`
  (`2>/dev/null || true`) for `inngest-redis.conf`, `inngest-redis.service`,
  `inngest-redis-bootstrap.sh` to `/tmp/inngest-redis.*`, + `chmod +x` the bootstrap.
  Mirror the cloud-init form; comment the WHY (existing-host bypasses the ENTRYPOINT
  that stages these; `|| true` keeps pre-#5450 rollback functional).

## Phase 2 — Gap 2: precondition inversion + SQLite fail-safe (`inngest-bootstrap.sh`)

- [ ] 2.1 Re-order: ensure `/etc/default/inngest-server` env-file materialization
  precedes the durable-Redis install block (the Redis unit reads it for the
  Doppler password).
- [ ] 2.2 Move the durable-Redis install block before the server-unit heredoc;
  set `REDIS_READY` from the bootstrap exit code ALONE
  (`if /usr/local/bin/inngest-redis-bootstrap.sh; then REDIS_READY=1; else REDIS_READY=0; ...; fi`).
  Comment cites `inngest-redis-bootstrap.sh` step 6 (exit-0 ⟹ unit active). On
  not-ready, `log` the `INNGEST_DURABLE_DEGRADED` token.
- [ ] 2.3 Branch the ExecStart via a single-quoted heredoc + `@@BACKEND_FLAGS@@`
  sentinel + non-`sed` substitution. Fragment: durable (`--postgres-uri … --redis-uri … --postgres-max-open-conns 25`)
  when `REDIS_READY=1`, empty when `0`. `--sqlite-dir` + signing-key strip +
  event-key + `--poll-interval`/`--sdk-url` stay in the SHARED prefix. Preserve
  literal `$${INNGEST_*}` tokens; no surviving sentinel.

## Phase 3 — verify_inngest_health reconcile + degraded reason (`ci-deploy.sh`)

- [ ] 3.1 Add a degraded ADVISORY via `logger -t "$LOG_TAG"` (ci-deploy tag → Vector
  → Better Stack) when ExecStart lacks `--postgres-uri`. Keep the `INNGEST_DURABLE`
  FAIL branch for postgres-without-redis. Authoritative no-SSH carrier.
- [ ] 3.2 In `case "inngest")`, on a 0-exit degraded bootstrap (SQLite ExecStart),
  `final_write_state 0 "success_degraded_durability"` instead of plain `success`,
  so `/hooks/deploy-status` `.reason` distinguishes degraded from healthy-durable.
- [ ] 3.3 Confirm the rollback path: pre-#5450 tag → `REDIS_READY=0` → SQLite
  ExecStart → /health passes → durable-gate skips → deploy succeeds.

## Phase 4 — Tests (RED → GREEN) wired into CI

- [ ] 4.1 `ci-deploy.test.sh` (CI-wired): per-asset line-start grep that the
  `case "inngest")` block docker-cp's all three Redis assets (AC1). RED first.
- [ ] 4.2 `ci-deploy.test.sh`: assert the degraded ADVISORY (not `return 1`) when
  ExecStart lacks `--postgres-uri`; FAIL branch intact (AC5); and
  `success_degraded_durability` reason on 0-exit degraded (AC5b).
- [ ] 4.3 `inngest.test.sh`: ordering (env-file < `REDIS_READY=` < server `cat >`),
  durable + SQLite fragments, `--sqlite-dir` in shared prefix, no surviving
  sentinel, literal `$${INNGEST_*}` tokens (AC2/AC3/AC4).
- [ ] 4.4 `inngest.test.sh`: reconcile existing `--postgres-uri`/`--redis-uri`
  asserts to the durable branch (AC8); reconcile the `inngest-redis-bootstrap.sh$`
  + `tail -1` ordering guard to select the invocation (not install) line.
- [ ] 4.5 `.github/workflows/infra-validation.yml`: add a step running
  `bash apps/web-platform/infra/inngest.test.sh` (AC6).
- [ ] 4.6 Run `bash apps/web-platform/infra/ci-deploy.test.sh` and
  `bash apps/web-platform/infra/inngest.test.sh` — both pass (AC7).

## Phase 5 — Post-merge (operator, automatable)

- [ ] 5.1 (AC9) After merge + `deploy inngest … vX.Y.Z`: read deploy-status webhook +
  inngest-inventory hook → confirm Redis unit active + durable ExecStart. Bake into
  `/soleur:ship` post-merge verification (authenticated GET, no SSH).
- [ ] 5.2 (AC10) Verify a rollback succeeds with `.reason=success_degraded_durability`
  + the `INNGEST_DURABLE: advisory` line (Better Stack query).
- [ ] 5.3 `gh issue close 5547` after AC9 confirms Redis installs on the live host.
