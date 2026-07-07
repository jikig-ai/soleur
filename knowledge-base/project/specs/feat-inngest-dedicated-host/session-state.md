# Session state — feat-inngest-dedicated-host (#6178)

Last updated: 2026-07-07. Branch `feat-inngest-dedicated-host`; worktree
`.worktrees/feat-inngest-dedicated-host/`. PR #6180. Rebased onto origin/main at session start (was 4 behind).

## Done + committed this session

1. **Phase 0 — spikes + ADR-098 (commit c78bbf0bb).** All three load-bearing spikes resolved
   EMPIRICALLY against the pinned `inngest/inngest:v1.19.4` **server** (Docker harness, external
   Redis+Postgres). Evidence: `phase0-empirical-spike.md`. ADR-098 (`status: adopting`, amends
   ADR-030); C4 edits + regenerated `model.likec4.json` (all c4-*.test.sh green). Verdicts:
   - **Fan-out = ROUTE-ONCE** → single stable `--sdk-url` now (to web-1 private `10.0.1.10`), VIP at N>1 (Phase 4.2).
   - **Cron-run enum = `runs(RunsFilterV2, timeField:STARTED_AT, functionIDs)`**; invariant `(functionID, floor(startedAt/period))`; `scheduled_tick` nonexistent. AC13 soak probe demonstrably writable.
   - **Redis FLUSHALL+DBSIZE==0 before the Postgres flip = MANDATORY** (proven: stale Redis jobs + cron schedule + idempotency keys survive a Postgres swap). `inngest start` exposes BOTH `--redis-uri` and `--postgres-uri` (plan's "SQLite-only" assumption was wrong).
2. **Task 1.2.1 — shared-script templating (commit 59423f97d).** `inngest-bootstrap.sh` templates
   `--sdk-url` (`@@SDK_URL@@`), doppler project (`@@DOPPLER_PROJECT@@`), and arch (`INNGEST_CLI_ARCH`)
   for the **server** unit. ALL defaults preserve the co-located web host (regression guards green in `inngest.test.sh`).
3. **Phase-1 core IaC (commit ffe3153da).** `inngest-host.tf` (host/volume/network/firewall + fresh
   keys AC-KEYROTATE + separate `soleur-inngest` Doppler project AC3 + 3 core secrets + read token),
   `cloud-init-inngest.yml` (arm64 Doppler, GHCR bake, nftables SEC-H2, self-check, arm64 inngest-CLI
   SHA override), `variables.tf`/`network.tf` additions. `terraform validate` green; fmt clean; cloud-init 11420B < 32KB.

**Verified facts (re-use, don't re-derive):** inngest SERVER pin `v1.19.4` (npm SDK is 3.54.2 — different).
arm64 inngest-CLI SHA `30a3f01474cb2266c24545cdc83930baeae14232d629c87aeeb8f21118948199` (amd64 `d023...` matches inngest.tf; both from the signed v1.19.4 `checksums.txt`). Private IPs: web-1 `.10`, web-2 `.11`, git-data `.20`, registry `.30`, **inngest `.40`**.

## REMAINING — Phase 1 (before the apply-dispatch can safely run)

The core IaC is committed + terraform-valid + **inert on merge**, but two reconciliations are needed
before the host actually boots correctly at the (not-yet-authored) apply-dispatch. Neither affects merge safety.

### R1 — Doppler-project isolation cascade (the plan's AC3 completion)
The dedicated host's boot token is scoped to `soleur-inngest`, but 3 systemd units the host runs still
hardcode `doppler run --project soleur` and would FAIL with the isolated token (only the **server** unit
was templated). Complete the cascade (each default MUST preserve `soleur` for the web host — regression guards):
- `inngest-bootstrap.sh:190` heartbeat ExecStart (heredoc is **unquoted** `<<HEARTBEATEOF` → use `--project ${DOPPLER_PROJECT}` directly, add `DOPPLER_PROJECT="${DOPPLER_PROJECT:-soleur}"` already exists).
- `inngest-bootstrap.sh:533` Vector ExecStart (check heredoc quoting; template same way).
- `inngest-redis.service:23` — a STATIC file installed verbatim by `inngest-redis-bootstrap.sh` (`install -m 0644 /tmp/inngest-redis.service`). Needs a `@@DOPPLER_PROJECT@@` sentinel + a substitution step added to `inngest-redis-bootstrap.sh` before install (it has `DOPPLER_PROJECT` in env from the parent bootstrap).
- **Secret provisioning:** for full isolation the host reads ALL its secrets from `soleur-inngest`, so provision `INNGEST_HEARTBEAT_URL` (= the reused `betteruptime_heartbeat.inngest_prd` URL) + `BETTERSTACK_LOGS_TOKEN` (Vector) into the project. `BETTERSTACK_LOGS_TOKEN` is an operator/out-of-band secret in soleur/prd (not a TF resource) → decide: TF `data` copy vs. out-of-band operator set into soleur-inngest (mirror the `INNGEST_POSTGRES_URI` out-of-band doctrine). **Also Vector arm64:** `cloud-init-inngest.yml` still passes the image-env (amd64) `VECTOR_CLI_SHA256`; Vector is arch-coupled too → add a `vector_cli_sha256_arm64` local + override (same pattern as the inngest-CLI arm64 fix). Lower urgency (Vector failure = degraded observability, not a dead scheduler).
- **Tests:** `inngest.test.sh` heartbeat assertions (~line 127-131) assert `run --project soleur` → update to the sentinel/default-preserves shape (mirror the sdk-url/doppler-project asserts already added for the server unit at ~line 158+).
- **Design note (borderline CTO):** "isolate observability secrets too, or only the inngest-core secrets?" is a small design call — full isolation (chosen direction per AC3) means the BetterStack token lives in soleur-inngest. If the provisioning friction is judged not worth it, the alternative is a documented exception. Not a hard architecture fork; decide inline or route to `soleur:engineering:cto` if it grows.

### R2 — Apply-dispatch job + parity test (task 1.5)
- Add an `inngest_host` job to `.github/workflows/apply-web-platform-infra.yml` modeled on `web_2_recreate`/`warm_standby` (gated `inputs.apply_target == 'inngest-host'`; `-target`s the full inngest-host resource set; shared concurrency group `terraform-apply-web-platform-host`). Add `inngest-host` to the `apply_target` choice `options`.
- `plugins/soleur/test/terraform-target-parity.test.ts`: add ALL inngest-host resources to `OPERATOR_APPLIED_EXCLUSIONS` (NOT the per-merge `-target` list — AC2), the service token to `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`, and the new `inngest_host` job to `stripDispatchJobs` (else its `-target`s leak into the coverage set — latent parity weakening).
- Add an `inngest-host.test.sh` drift guard (mirror `inngest.test.sh`/`firewall-9000-deny.test.sh`): assert fresh-keys (no reuse), separate-project, nftables allowlist drops `.20`/`.30`, no `ignore_changes[user_data]`, arm64 SHA present. Register it in `.github/workflows/infra-validation.yml` (unregistered infra tests never gate — #5417).

## REMAINING — Phases 2-3 (post-merge; operator/soak — NOT a code-session unit)
- **Phase 2 (operator cutover, maintenance window):** author/adapt `cutover-inngest.yml op=execute` (capture-all-hosts incl weight-0 web-2 / quiesce-all / **Redis FLUSHALL + DBSIZE==0 gate (2.2b, proven mandatory)** / prod-Postgres flip / app-repoint at `ci-deploy.sh:1341`+`:1574` / rearm / verify per-(fn,tick) / rollback-stops-dedicated-first). This PR uses `Ref #6178`, not `Closes` (post-merge cutover + 7-day soak gate).
- **Phase 3 (SOAK-GATED, lands only after Phase-4.1 green):** web decommission (`cloud-init.yml` 79 sudoers / 245 ReadWritePaths / `ci-deploy.sh` 1341+1574 / `webhook.service:45` — all preconditions verified this session, in-range), `INNGEST_HOST_FALLBACK` (`cron-inngest-cron-watchdog.ts:73`) → `10.0.1.40`, observability extension. Keep co-located inngest stopped+disabled-but-present until soak-green.
- **Phase 4:** author soak probe `scripts/followthroughs/inngest-double-fire-6178.sh` using the R1 `runs()` query; Follow-Through Enrollment.

## Resume prompt
Continue #6178 Phase 1: complete R1 (doppler-project isolation cascade — template heartbeat/vector/redis units + provision observability secrets into soleur-inngest + Vector arm64 SHA + update inngest.test.sh) and R2 (apply-dispatch job + terraform-target-parity exclusions + inngest-host.test.sh drift guard). Then /review → /ship (Ref #6178, not Closes; PR carries Phase-1 IaC only — Phase 2 cutover + Phase 3 soak are post-merge operator/soak work). All Phase-0 spike verdicts + arm64 SHA + private IPs are recorded above — do not re-derive.
