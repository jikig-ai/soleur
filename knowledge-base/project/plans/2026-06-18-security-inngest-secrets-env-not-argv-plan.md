---
title: "security(inngest): deliver durable secrets via environment, not argv + rotate exposed creds"
type: security
date: 2026-06-18
ref: 5560
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: ops-remediation
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: systemctl references describe the EXISTING inngest-bootstrap.sh IaC-driven behavior (image-baked, applied via cloud-init), not new manual steps. Rotation is routed through Terraform (terraform taint / apply -replace) + the Supabase Management API (AC10 marked automation-status: UNVERIFIED for /work to attempt). No new manual provisioning is introduced. -->

# security(inngest): deliver durable secrets via environment, not argv (+ rotate exposed creds)

> Ref #5560. **Post-merge operator/IaC rotation required** — use `Ref #5560` (NOT `Closes`) in the PR body; the issue is closed by a post-deploy `gh issue close 5560` after rotation verifies (ops-remediation class: the fix is only complete after the post-merge rotation runs, so auto-close-at-merge would false-resolve).

## Overview

The inngest-server systemd unit expands four Doppler-injected secrets into the `inngest start` **argv** via the `ExecStart` line written by `apps/web-platform/infra/inngest-bootstrap.sh`:

```
# inngest-bootstrap.sh:320 (shared prefix) + :354 (durable BACKEND_FLAGS)
ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/bin/bash -c '/usr/local/bin/inngest start … @@BACKEND_FLAGS@@ --signing-key "$${INNGEST_SIGNING_KEY#signkey-prod-}" --event-key "$${INNGEST_EVENT_KEY}" …'
# where (REDIS_READY=1):
BACKEND_FLAGS='--postgres-uri "$${INNGEST_POSTGRES_URI}" --redis-uri "redis://:$${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379" --postgres-max-open-conns 10'
```

`doppler run … bash -c '…'` expands `$INNGEST_POSTGRES_URI`, `$INNGEST_REDIS_PASSWORD`, `$INNGEST_SIGNING_KEY`, `$INNGEST_EVENT_KEY` and passes the **resolved values as argv elements** to the `inngest` child process. They are therefore visible in `/proc/<inngest-pid>/cmdline` — mode `0444`, **world-readable** to any user/process on the host (`ps -eo args | grep inngest`). Surfaced during #5558 debugging.

**The fix is two-part (mirrors the issue):**

1. **Stop passing secrets via argv.** `inngest start` reads all four secrets from environment variables (`INNGEST_POSTGRES_URI`, `INNGEST_REDIS_URI`, `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`) — verified against the official self-hosting docs (see Research Reconciliation). Doppler already injects three of them by name into the `doppler run` scope; only `INNGEST_REDIS_URI` must be constructed from `INNGEST_REDIS_PASSWORD`. Rewrite the ExecStart so secrets reach inngest via the inherited environment (`/proc/<pid>/environ`, mode `0400`, owner-only) instead of argv.
2. **Rotate the exposed credentials** (they were surfaced in a debugging-session transcript): `INNGEST_REDIS_PASSWORD` via `terraform taint` + apply, and the Supabase inngest-project Postgres password via the Management API → re-set `INNGEST_POSTGRES_URI` in Doppler prd → redeploy. **Rotation runs AFTER the argv→env fix is deployed and verified secret-free** — rotating first while still on argv re-leaks the new creds to `/proc/cmdline` immediately.

This hardens the #5450 durable-backend amendment to ADR-030 without changing the backend itself.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / approach) | Reality (verified) | Plan response |
|---|---|---|
| inngest reads `--postgres-uri`/`--redis-uri` from env | ✅ Official self-hosting docs (Context7 `/inngest/website` `pages/docs/self-hosting.mdx`, Docker-compose example): `INNGEST_POSTGRES_URI`, `INNGEST_REDIS_URI`, `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY` are all env-var inputs to `inngest start`. `<!-- verified: 2026-06-18 source: Context7 /inngest/website self-hosting.mdx -->` | Drop all four secret flags; rely on env. |
| Only postgres + redis URIs are in argv | ❌ `--signing-key` and `--event-key` are **also** secrets in the same ExecStart argv (`inngest-bootstrap.sh:320`). | Fix moves **all four** secrets out of argv (a partial fix would be flagged by security-sentinel). |
| Redis secret = full URI | ❌ Doppler holds `INNGEST_REDIS_PASSWORD` (password only); inngest wants `INNGEST_REDIS_URI` (full URI). | Construct + `export INNGEST_REDIS_URI="redis://:${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379"` inside the `bash -c` (env, not argv). |
| Env-config is unconditional | ❌ `INNGEST_POSTGRES_URI` is a Doppler prd secret → present in **both** the durable and the SQLite-only fail-safe `doppler run` scope. Relying on env unconditionally would make inngest connect to Postgres even in the fail-safe branch, defeating it. | In the REDIS_READY=0 branch, `unset INNGEST_POSTGRES_URI` (and do not set `INNGEST_REDIS_URI`) so the SQLite-only fail-safe is preserved. |
| Durability is detected via `--postgres-uri`/`--redis-uri` argv substring | ✅ 7 consumers grep the ExecStart/cmdline for these flags (see Files to Edit). Removing the flags **breaks every durability check** (they would read "SQLite-only" on a durable host). | Swap the detection substring to the **non-secret** `--postgres-max-open-conns` flag (kept on argv in the durable branch only — present iff durable). Sweep all 7 sites. |
| `INNGEST_POSTGRES_URI` rotation = TF resource | ❌ It is provisioned **out-of-band** (`inngest.tf:162`), NOT a `doppler_secret`. | Rotation = Supabase Management API password reset → re-set `INNGEST_POSTGRES_URI` in Doppler prd (stdin). `INNGEST_REDIS_PASSWORD` IS a `random_password` → `terraform taint`. |
| Changing the bootstrap deploys immediately | ❌ `inngest-bootstrap.sh` is baked into a version-pinned OCI image (`build-inngest-bootstrap-image.yml`, pin in `cloud-init.yml`; cf. commit `bcdf54fd4` "bump inngest-bootstrap pin v1.1.15→v1.1.16"). | Apply path: merge → tagged image build → bump pin (follow-up per `hr-tagged-build-workflow-needs-initial-tag-push`) → deploy → host re-runs bootstrap → new ExecStart. |

## User-Brand Impact

**If this lands broken, the user experiences:** inngest-server fails to start or silently runs non-durable — every cron + armed reminder (the inngest postmortem of 2026-06-18 documents a 3.5h crash-loop where 4 armed reminders never fired). A botched durable-detection sentinel swap could also let `inngest-wiped-volume-verify.sh` wipe a *durable* volume, destroying real run-state.

**If this leaks, the user's workflow/data is exposed via:** the durable Postgres URI grants read/write to the inngest project DB (all users' run-state + armed reminders); the Redis password grants the durable queue. Soleur runs autonomous agents that execute user-influenced code on infrastructure — a local process reading `/proc/<inngest-pid>/cmdline` could harvest these creds. Local-only (no remote exposure), single-tenant alpha — bounded, but real.

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true`. CPO ack on the approach is required at plan time (no UI; server/infra only). `user-impact-reviewer` runs at PR-review time against the diff. `security-sentinel` + `data-integrity-guardian` (wiped-volume guard) run at review.

## Files to Edit

- `apps/web-platform/infra/inngest-bootstrap.sh`
  - `:320` — rewrite the shared-prefix ExecStart: remove `--signing-key`/`--event-key` flags; add `export INNGEST_SIGNING_KEY="$${INNGEST_SIGNING_KEY#signkey-prod-}";` and a new `@@BACKEND_ENV@@` sentinel before **`exec`** `/usr/local/bin/inngest start …`. `INNGEST_EVENT_KEY` is read from the doppler env unchanged. **The `exec` is LOAD-BEARING (Kieran 1b / Architecture):** today inngest is the sole `bash -c` command so bash tail-execs it (inngest inherits the PID — `Type=simple`, `Restart=on-failure`, `TimeoutStopSec=180`, and the `inngest pause`/`resume` upgrade-drain all depend on it). Adding `export …; …; inngest start …` makes inngest a bash *child* unless `exec` is used → SIGTERM on stop/restart would hit bash not inngest, breaking drain + the PID `inngest pause` targets. Preserve the load-bearing `signkey-prod-` strip rationale comment (currently `:272-280`) — move, don't delete.
  - `:300-302` — **add a "DETECTION SENTINEL — do not remove or move to env" note** to the `--postgres-max-open-conns` pool-sizing comment (Architecture P2). After this change the flag is no longer purely pool-tuning: it is the non-secret durable-detection sentinel consumed by `ci-deploy.sh` (×2) + `inngest-wiped-volume-verify.sh` (the data-safety wipe guard). A future "tune the pool / drop the flag / move to env like the URIs" edit would silently break all three durable detectors.
  - `:353-359` — branch BOTH a new `BACKEND_ENV` var and the existing `BACKEND_FLAGS`:
    - durable (REDIS_READY=1): `BACKEND_ENV='export INNGEST_REDIS_URI="redis://:$${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379";'` and `BACKEND_FLAGS='--postgres-max-open-conns 10'` (non-secret durable sentinel; `INNGEST_POSTGRES_URI` is read from the doppler env).
    - fail-safe (REDIS_READY=0): `BACKEND_ENV='unset INNGEST_POSTGRES_URI;'` and `BACKEND_FLAGS=''`.
  - `:360-362` — add the parallel `@@BACKEND_ENV@@` substitution alongside the existing `@@BACKEND_FLAGS@@` substitution (bash parameter expansion, NOT sed — same rationale as the existing comment).
  - Update the explanatory comments (`:293-310`, `:342-352`) to describe env-delivery + the unset-in-fail-safe invariant.
- `apps/web-platform/infra/ci-deploy.sh`
  - `:269-289` (`verify_inngest_health` + its rationale comment) — change the durable-detection substring from `--postgres-uri` to `--postgres-max-open-conns`, and **DROP the now-dead `*'--redis-uri'*` argv sub-check** (`:279`): redis-uri is env-only after the fix, so an argv test for it can never be satisfied (Architecture P2). Re-express the invariant as: durable (sentinel present) ⇒ `inngest-redis.service` active + `/health` 200. Update the `:269-272` comment block + the FAIL/ok log strings (`:280`, `:287`).
  - `:1000-1001` — ExecStart re-derivation: change the `*'--postgres-uri'*` test to `*'--postgres-max-open-conns'*`.
- `apps/web-platform/infra/inngest-wiped-volume-verify.sh:98` — change the data-safety guard substring `*"--postgres-uri"*` → `*"--postgres-max-open-conns"*` (durable ⇒ SQLite is throwaway ⇒ safe to wipe). **Highest-risk consumer** — a wrong swap here can wipe durable state.
- `apps/web-platform/infra/inngest.test.sh:211-215` — rewrite the durable-fragment assertion: assert `BACKEND_FLAGS` contains `--postgres-max-open-conns` (no `--postgres-uri`/`--redis-uri`), assert `BACKEND_ENV` exports `INNGEST_REDIS_URI` from `INNGEST_REDIS_PASSWORD`, assert the fail-safe branch `unset INNGEST_POSTGRES_URI`.
- `apps/web-platform/infra/ci-deploy.test.sh:2214` — update the `--redis-uri absent` FAIL-message grep to match the new log string.
- `apps/web-platform/infra/inngest-wiped-volume-verify.test.sh` — update fixtures/assertions to the new sentinel.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
  - `:264-296`, `:278`, `:382-386` — update "cmdline contains `--postgres-uri` AND `--redis-uri`" → "cmdline contains `--postgres-max-open-conns` (durable sentinel); secrets are delivered via the doppler-run **environment**, never argv". Add a `## Secret delivery` note + the rotation procedure ordering (deploy-fix-first, then rotate).
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — amendment (see Architecture Decision section).
- **Regression guard — fold into `inngest.test.sh`, do NOT create a new file** (DHH + Simplicity): an assertion block on the assembled durable + fail-safe unit content. **Negative** (security invariant): the ExecStart contains none of `--signing-key`, `--event-key`, `--postgres-uri`, `--redis-uri`, and only `$${…}` env references — never expanded secret values. **Positive** (Kieran 3 / Architecture P1 — guards the inverse failure where secrets reach neither argv nor env): the durable body uses `exec`, exports `INNGEST_REDIS_URI` (constructed from `INNGEST_REDIS_PASSWORD`) + the stripped `INNGEST_SIGNING_KEY`, references `$${INNGEST_POSTGRES_URI}`/`$${INNGEST_EVENT_KEY}`, and carries `--postgres-max-open-conns` (sentinel present).

## Files to Create

- None (the regression guard is folded into `inngest.test.sh` above; the optional cosmetic C4 edge-description refinement is cut — the ADR-030 invariant is the system of record, and touching `.c4` would pull in the C4 test suite for a label tweak).

## Open Code-Review Overlap

None — no open `code-review`-labelled issue references these infra files (verified at plan time; /work re-runs the Phase 1.7.5 grep on the final file list).

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- Confirm inngest reads `INNGEST_REDIS_URI`/`INNGEST_POSTGRES_URI`/`INNGEST_SIGNING_KEY`/`INNGEST_EVENT_KEY` from env at the pinned inngest version (docs verified; if the `inngest` binary is locally available, `inngest start --help` shows no env-var column — env support is documented in `self-hosting.mdx`, the authoritative contract). Pin `<!-- verified: 2026-06-18 -->`.
- **Confirm inngest reads Postgres from NO env var OTHER than `INNGEST_POSTGRES_URI`** (no `DATABASE_URL`-style alias, no config-file fallback) — the `unset INNGEST_POSTGRES_URI` fail-safe is necessary-but-not-sufficient if another alias exists. (Kieran 1a / Architecture P0-verify.)
- Read the inngest pin/build precedent: `2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` + `2026-05-30-feat-cloud-init-inngest-pin-drift-guard-plan.md` to confirm the image-build→pin-bump→deploy chain.
- Confirm `--postgres-max-open-conns 10` is accepted by inngest when Postgres is configured via env (it is a pool-tuning flag independent of how the URI is supplied).
- Confirm `random_password.inngest_redis_password_prd` is `special = false` (`inngest.tf:147`) → the regenerated password is URL-safe, so the constructed `INNGEST_REDIS_URI` cannot be corrupted by `@`/`:`/`/` on rotation (AC9). Already true; record it.

### Phase 1 — Rewrite the ExecStart (RED → GREEN)
- Write/extend `inngest.test.sh` assertions FIRST (no secret flags; durable sentinel = `--postgres-max-open-conns`; `BACKEND_ENV` redis-uri export; fail-safe `unset`). Run → RED.
- Edit `inngest-bootstrap.sh` per Files to Edit. Run `inngest.test.sh` → GREEN.

### Phase 2 — Cross-consumer sentinel sweep
- Update all 7 durable-detection consumers + their tests. Run `inngest-wiped-volume-verify.test.sh`, `ci-deploy.test.sh` (the inngest-relevant cases), `cat-inngest-verify-state.test.sh`.

### Phase 3 — Docs + ADR
- ADR-030 amendment (invariant + amendment-log) + runbook update. No `.c4` edit (cut), so no C4 test run.

### Phase 4 — Full infra test suite
- Run `apps/web-platform/infra/*.test.sh` (the inngest + ci-deploy suite) + any orphan scope-guard suites. Typecheck N/A (shell/infra).

## Infrastructure (IaC)

### Terraform changes
- No new TF resources. `inngest.tf` `random_password.inngest_redis_password_prd` + `doppler_secret.inngest_redis_password_prd` already exist (rotation uses `terraform taint`, not a new resource). `INNGEST_POSTGRES_URI` remains out-of-band (`inngest.tf:162`).

### Apply path
- **Code/IaC (bootstrap) — (b) cloud-init + image-pin bump (the default for existing inngest infra).** Merge the bootstrap change → tagged OCI image build (`build-inngest-bootstrap-image.yml`) → bump the pin in `cloud-init.yml` (follow-up commit/PR per `hr-tagged-build-workflow-needs-initial-tag-push`; the tag must be pushed before the build workflow can fire) → deploy → host re-runs `inngest-bootstrap.sh` → new ExecStart written + inngest-server restarts (the bootstrap script already owns the restart; not a new manual step). Expected blast-radius: one inngest-server restart (~seconds); `verify_inngest_health` HARD-gates the deploy.

### Distinctness / drift safeguards
- prd-only (dev runs ephemeral local `inngest dev`, no durable backend). `doppler_secret … ignore_changes = [value]` unchanged. No tfstate-shape change.

### Vendor-tier reality check
- N/A — no new provider resource. Supabase inngest project is the existing ~$10/mo Micro-compute project.

## Observability

```yaml
liveness_signal:
  what: inngest-server Better Stack heartbeat (betteruptime_heartbeat.inngest_prd, 60s/30s grace) + inngest-heartbeat.timer
  cadence: 60s
  alert_target: Better Stack (email; team t520508)
  configured_in: apps/web-platform/infra/inngest.tf:189, inngest-bootstrap.sh:172
error_reporting:
  destination: ci-deploy.sh `logger -t "$LOG_TAG"` -> journald -> Vector -> Better Stack Logs
  fail_loud: verify_inngest_health is a HARD gate — a durable host whose sentinel is missing FAILs the deploy (no silent SQLite downgrade)
failure_modes:
  - mode: durable host misdetected as SQLite-only after sentinel swap
    detection: verify_inngest_health durable-gate (now keyed on --postgres-max-open-conns)
    alert_route: deploy FAILs; ci-deploy INNGEST_DURABLE log line in Better Stack
  - mode: wiped-volume guard wipes a durable volume (wrong sentinel)
    detection: inngest-wiped-volume-verify.sh abort non_durable_backend; covered by inngest-wiped-volume-verify.test.sh
    alert_route: cutover workflow fails loud before wipe
  - mode: inngest-server crash-loop (redis unreachable / postgres misconfigured)
    detection: Better Stack heartbeat miss + /health non-200
    alert_route: Better Stack email
logs:
  where: journald (inngest-server.service) -> Better Stack Logs via Vector
  retention: Better Stack default
discoverability_test:
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/inngest
  expected_output: "401"
  note: "401 (HMAC challenge) proves the inngest serve route is reachable — a no-ssh liveness proxy. The AUTHORITATIVE durable-detection signal is the ci-deploy `INNGEST_DURABLE: ok` line in Better Stack Logs + the scheduled-inngest-health detector (both no-ssh, auth-gated)."
```

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-030** (`## Updates / amendment log` + `## Load-bearing invariants`): add an invariant — "inngest-server secrets (Postgres/Redis URIs, signing/event keys) are delivered via the doppler-run **environment** (`/proc/<pid>/environ`, owner-only), never argv (`/proc/<pid>/cmdline`, world-readable) — #5560." This hardens, not reverses, the #5450 durable-backend amendment → amend, not new ADR.

### C4 views
- **No structural change — and no `.c4` edit at all** (cosmetic edge-description refinement cut per DHH + Simplicity). Enumerated against all three `.c4` files: actors/systems already modeled — `inngest` container (`model.c4:151`), `inngestPostgres` (`:155`), `inngestRedis` (`:159`), `doppler -> inngest "Injects secrets"` edge (`:248`), all rendered in `views.c4:33`. No new external human actor, external system, data store, or access relationship. A "no C4 impact" conclusion is supported because the secret-delivery mechanism is an attribute of an already-modeled edge, not a new element/relationship — the env-not-argv decision is recorded in the ADR-030 invariant, not the diagram. C4 validation tests are therefore not triggered.

### Sequencing
- ADR amendment authored in this PR (Phase 3), `status: adopting` consistent with the existing #5450 amendment.

## Domain Review

**Domains relevant:** Engineering (infra/security)

### Engineering
**Status:** reviewed (inline; full CTO/security cross-cutting assessment deferred to deepen-plan domain agents + the review-phase `security-sentinel` + `data-integrity-guardian`, which run on the actual diff — higher signal than a plan-text pass).
**Assessment:** Pure infra/security hardening of an existing surface. The load-bearing risks are (1) the SQLite-fail-safe `unset INNGEST_POSTGRES_URI` correctness, (2) the durable-detection sentinel swap across 7 consumers (esp. the wiped-volume data-safety guard), (3) the deploy-then-rotate ordering. All three are covered by tests + the AC split.

### Product/UX Gate
Skipped — no UI surface (no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Edit). Mechanical UI-surface override did not fire.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 (negative — security invariant) — The written inngest-server ExecStart (durable AND fail-safe assembled content) contains **no** `--signing-key`, `--event-key`, `--postgres-uri`, or `--redis-uri` flag, and only `$${…}` env references — never expanded secret values. Asserted by the `inngest.test.sh` regression block.
- [ ] AC1b (positive — guards the inverse failure: secrets reach neither argv nor env, Kieran 3 / Architecture P1) — The durable `bash -c` body (a) uses `exec /usr/local/bin/inngest start`, (b) `export`s `INNGEST_REDIS_URI` (from `INNGEST_REDIS_PASSWORD`) + the stripped `INNGEST_SIGNING_KEY`, (c) references `$${INNGEST_POSTGRES_URI}`/`$${INNGEST_EVENT_KEY}`, (d) carries `--postgres-max-open-conns` (sentinel present). Asserted by `inngest.test.sh`.
- [ ] AC2 — Durable branch: `INNGEST_REDIS_URI` exported (constructed from `INNGEST_REDIS_PASSWORD`) and `--postgres-max-open-conns 10` on argv; `INNGEST_POSTGRES_URI`/`INNGEST_EVENT_KEY` read from doppler env; `INNGEST_SIGNING_KEY` re-exported stripped of `signkey-prod-`.
- [ ] AC3 — Fail-safe branch (REDIS_READY=0): `unset INNGEST_POSTGRES_URI`, no `INNGEST_REDIS_URI`, empty `BACKEND_FLAGS` → SQLite-only. Asserted by `inngest.test.sh`.
- [ ] AC4 — No durable-detection consumer keys on `--postgres-uri`/`--redis-uri` argv substrings anymore. Verify the **full file list** (Kieran 2 / Simplicity / Architecture — the 2-file grep was too narrow): `git grep -nE "\-\-postgres-uri|\-\-redis-uri" apps/web-platform/infra/{ci-deploy.sh,ci-deploy.test.sh,inngest-wiped-volume-verify.sh,inngest-wiped-volume-verify.test.sh,inngest.test.sh}` returns no **detection-logic** hits (provisioning/changelog comments + runbook prose excepted). Each detector keys on `--postgres-max-open-conns`.
- [ ] AC5 — `apps/web-platform/infra/*.test.sh` (inngest + ci-deploy + wiped-volume + cat-verify-state suites) pass.
- [ ] AC6 — ADR-030 amended (invariant + amendment-log); runbook updated (no `--postgres-uri`-as-detection prose remains; secret-delivery = env note added). No `.c4` edit (C4 refinement cut).
- [ ] AC7 — PR body uses `Ref #5560` (NOT `Closes`); post-merge rotation steps enumerated in `### Post-merge (operator)`.

### Post-merge (operator) — sequenced AFTER deploy + secret-free verification
- [ ] AC7.5 (gated handoff — spec-flow Finding 5) — **The pin bump is an explicit named step, not an implicit follow-up.** After the merged bootstrap change triggers the tagged OCI image build, bump the pin in `cloud-init.yml` (separate commit per `hr-tagged-build-workflow-needs-initial-tag-push`) and deploy. Until this runs, the argv leak persists on the host and AC8–AC11 are blocked — do not consider #5560 in-progress-complete until the pin is bumped + deployed. Automation: `gh` (commit/PR) + deploy workflow.
- [ ] AC8 — New bootstrap image built + pinned + deployed; `verify_inngest_health` durable gate passes; **(negative)** on-host `ps -eo args | grep inngest` (or deploy log) shows NO secret values in cmdline; **(positive — Architecture P1)** `/proc/<inngest-pid>/environ` (owner-only read; the read itself is the security-positive proof) contains all four secrets → confirms env-delivery actually works, not just that argv is clean. Automation: deploy via `gh workflow run` / restart-inngest-server.yml.
- [ ] AC8.5 (capture baseline — spec-flow Finding 3) — Capture the armed-reminder count (`inngest-inventory.sh`) **BEFORE** any rotation begins, to compare against AC11.
- [ ] AC9 — Rotate `INNGEST_REDIS_PASSWORD`: `export AWS_ACCESS_KEY_ID/SECRET` (R2 backend, raw, from `doppler secrets get … -c prd_terraform --plain`) → `terraform init -input=false` → `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -replace=random_password.inngest_redis_password_prd` (regenerates + re-Dopplers; `special = false` keeps it URL-safe). Rotation **mutates the Doppler secret only — it does NOT redeploy**; the single AC11 redeploy loads both rotated creds. Automation: feasible (canonical tf triplet, `2026-05-09-drift-runbook-canonical-tf-invocation`).
- [ ] AC10 — Rotate the Supabase inngest-project Postgres password → re-set `INNGEST_POSTGRES_URI` in Doppler prd (stdin, never argv). **Validate the new URI connects (read-only probe, e.g. `psql … -c 'select 1'` or a Supabase MCP query) BEFORE the AC11 redeploy** (spec-flow Finding 3 — avoids cutting over to a bad URI with the old password already gone). `automation-status: UNVERIFIED — /work MUST attempt via Supabase Management API / supabase MCP (reset DB password) before any operator handoff; only mark operator-only if a real attempt reaches a named human gate.`
- [ ] AC11 — Redeploy inngest so rotated creds load; `verify_inngest_health` passes; armed-reminder count equals the AC8.5 baseline. Then `gh issue close 5560`.

**Rollback (spec-flow Findings 1 + 2 — load-bearing hazard):** if `verify_inngest_health` FAILs at AC8 or AC11, rollback = **revert the `cloud-init.yml` pin to the prior version + redeploy** (NOT an in-place edit). **Once rotation (AC9/AC10) has run, rolling back to a pre-fix (argv-form) image is FORBIDDEN** — it would re-leak the freshly rotated creds to `/proc/cmdline`, defeating the entire rotation. The only valid post-rotation rollback target is another env-form image. If no env-form image is healthy, fix forward.

## Test Scenarios
- Durable branch unit assembly → no secret flags, redis-uri exported, postgres-max-open-conns sentinel present.
- Fail-safe branch unit assembly → `unset INNGEST_POSTGRES_URI`, SQLite-only.
- `verify_inngest_health` on a durable ExecStart fixture → ok; on a fail-safe fixture → SKIP (no FALSE durable FAIL).
- `inngest-wiped-volume-verify.sh` on durable fixture → allows wipe; on SQLite-only fixture → aborts `non_durable_backend`.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6 — this one is filled.
- `unset INNGEST_POSTGRES_URI` in the fail-safe branch is **load-bearing**: `INNGEST_POSTGRES_URI` is a Doppler prd secret present in both branches' env; without the unset, the SQLite-only fail-safe would still connect to Postgres and defeat the #5547 fail-safe.
- The wiped-volume guard (`inngest-wiped-volume-verify.sh:98`) is a **data-safety** consumer — a wrong sentinel swap could wipe a durable volume. Cover with the test before editing.
- Rotation MUST be deploy-fix-first: rotating creds while still on the argv form re-leaks the new creds to `/proc/cmdline` instantly.
- The bootstrap is image-pinned — the bootstrap edit does not take effect until the image rebuilds + pin bumps (`hr-tagged-build-workflow-needs-initial-tag-push`).
- **Known debt (DHH — file a follow-up issue at ship, do NOT fix here):** durability is detected by ≥3 scripts independently string-grepping `/proc/cmdline`/ExecStart. This PR swaps the needle (`--postgres-uri` → `--postgres-max-open-conns`) but leaves the fragile pattern intact — any future argv reshuffle re-breaks all detectors. The real fix is one shared `inngest-durable?` helper the consumers call. Out of scope for this security patch; file as `tech-debt` so the next inngest-infra change can consolidate.
