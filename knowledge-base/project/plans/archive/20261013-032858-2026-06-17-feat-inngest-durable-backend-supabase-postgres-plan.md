<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All provisioning is routed through Terraform + cloud-init (see ## Infrastructure (IaC)). Residual systemctl references are cutover VERIFICATION/ROLLBACK/health-probes executed via the existing no-SSH paths (ci-deploy.sh restart inngest / restart-inngest-server.yml / verify_inngest_health), not operator SSH or manual provisioning. -->
---
title: "feat: Durable backend for Inngest scheduled work (Supabase Postgres + self-hosted Redis)"
type: feat
issue: 5450
branch: feat-inngest-scheduled-durability
pr: 5459
worktree: .worktrees/feat-inngest-scheduled-durability
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-17
brainstorm: knowledge-base/project/brainstorms/2026-06-17-inngest-scheduled-durability-brainstorm.md
spec: knowledge-base/project/specs/feat-inngest-scheduled-durability/spec.md
---

# feat: Durable backend for Inngest scheduled work (Supabase Postgres + self-hosted Redis)

🛠️ Infrastructure migration · brand-survival threshold **single-user incident** (silent loss of an armed reminder/oneshot).

## Overview

The self-hosted Inngest server persists state to **bundled SQLite + in-memory Redis on the ephemeral root disk** (`--sqlite-dir /var/lib/inngest`, `inngest-bootstrap.sh:167`). The only persistent Hetzner volume (`hcloud_volume.workspaces`, `server.tf:887`) mounts at `/mnt/data` and holds none of it. A full host re-provision (`terraform` server-replace) boots a fresh root disk and **silently loses** every HTTP-armed `event-scheduled-reminder` (and any oneshot whose conditionally re-armed checkpoint diverged from its hardcoded boot-arm `ts`). Recurring `cron-*` re-arm on web redeploy; first-arm oneshots re-arm on container boot (ADR-046); reminders do not re-arm at all.

This plan executes the **Postgres migration that ADR-030 explicitly deferred** ("Migration to Postgres-backed Inngest deferred to future PR if/when warranted", `ADR-030:123`) by pointing Inngest at **Supabase Postgres** (`--postgres-uri`) for durable state and standing up a **self-hosted Redis** (AOF on `/mnt/data`) for the durable queue. Because Supabase is already our primary database and an existing sub-processor, this adds **no new sub-processor** — dissolving ADR-030's sole deferral reason (fear of a "5th sub-processor").

**Sequencing is load-bearing:** a local spike (Phase 0) resolves the external unknowns BEFORE any irreversible production infra. Provision (Phase 1) → cutover with rollback (Phase 2). Documentation (ADR/C4/runbook/observability) is an **exit-criterion of Phases 1-2**, not a separate phase (per plan-review).

### Isolation decision (resolves the dedicated-project-vs-schema review tension)
Inngest gets its **own dedicated Supabase project** (EU region) — the default, not a fallback. This is the more robust choice at single-user-incident threshold AND the simpler one: it (a) breaks shared-fate + connection-budget contention with the main app (a separate schema in the *same* project does not — architecture review P1-1), and (b) **removes the schema-targeting unknown entirely** (no `--postgres-uri` `search_path` gymnastics, no PostgREST-exposure risk — Inngest owns its own database). Cost: one more EU Supabase project (free-tier-capable for Inngest's modest state). Add it to the Article 30 register + backup runbook.

### ⚠️ Availability coupling (the permanent price — operator-visible)
This migration **removes Inngest's in-memory fallback**: post-cutover, Inngest cannot *start* without Supabase + Redis reachable. Pre-migration, Inngest survived a Supabase outage on local SQLite; it no longer will. This is a permanent downgrade in failure-independence, knowingly traded for durability + PITR + ADR-030 closure. The dedicated Inngest project + co-located Redis keep the blast radius off the main app's Supabase project, but the coupling is inherent to any Postgres-backend choice. Accepted; surfaced explicitly per code-simplicity review.

## Premise Validation

- `#5450` — OPEN issue, this plan's target (verified).
- **ADR-030 `## Trade-offs accepted` (`:123`)**: Postgres is **deferred, not rejected** — re-eval trigger "if/when warranted" + the "3rd founder / operational-cost-exceeds-5th-sub-processor" criterion (`:51`). Our trigger: the #5450 durability gap + the "Supabase already a sub-processor → zero new legal surface" reframe. We **execute the deferred path and amend ADR-030** (Phase 2.10). ADR-030's *rejected* alternatives are Durable Objects, LISTEN/NOTIFY, AWS SQS, and **Inngest Cloud** (`:42-63`) — Postgres-self-hosted is none of these.
- `ADR-046` (oneshot self-arm) cites "bounded by single-host SQLite durability (ADR-030)" — that bound changes; cross-ref note required.
- All cited files exist on `main` (`inngest-bootstrap.sh`, `server.tf`, `cloud-init.yml`, `ci-deploy.sh`, the runbook). No stale premises.

## Research Reconciliation — Spec vs. Codebase/Docs

| Spec/brainstorm claim | Reality (research) | Plan response |
|---|---|---|
| "dedicated `inngest` database/schema in Supabase" (spec FR2) | `--postgres-uri` **schema-targeting is UNCONFIRMED**; a shared schema also shares the pooler budget + project-fate with the main app (architecture P1-1) | **Decision: dedicated Supabase project for Inngest (DEFAULT, not fallback).** Sidesteps the schema-targeting unknown entirely (Inngest owns its DB → no PostgREST-exposure risk, no `search_path` gymnastics) AND breaks shared-fate/connection-budget with the main app. Same vendor → no new sub-processor. |
| "self-hosted durable Redis … pending FR1" (spec FR3) | Inngest queue layer **is Redis**; docs do NOT confirm Postgres-alone persists future-dated events; "external Redis AND Postgres recommended for production" | Treat Redis as **likely-required**, FR1 confirms. Ship both atomically unless the spike proves Postgres-alone survives a restart. |
| "Supabase Postgres backend" (operator decision) | Inngest self-hosted uses **sqlc + prepared statements** → Supabase **transaction pooler (6543) breaks it**; use **Supavisor SESSION mode :5432** | TR: pin session-mode :5432 connection string; never 6543. |
| (implicit) direct DB connection | Direct (`db.<ref>.supabase.co`) is **IPv6-only** without the IPv4 add-on; Hetzner has **free IPv6** + pooler is IPv6-reachable | Default to the Supavisor **session pooler** hostname; no IPv4 add-on. |
| "move SQLite state across" | **No documented SQLite→Postgres migration path** — point at Postgres = fresh state | Cutover = drain-first + enumerate/re-arm armed work; one-time in-flight loss accepted (Phase 2). |
| (brainstorm) migration may fix the cron de-plan asymmetry | A `cron-inngest-cron-watchdog.ts` **already self-heals** de-plan/re-arm (#5159) every 4h | De-plan is **out of scope** (orthogonal, already handled). Spike may *observe* whether durable backend incidentally improves it — bonus, not a goal. Do NOT claim this PR fixes de-plan. |

## Research Insights

- **Infra wiring** (`repo-research-analyst`): ExecStart is `doppler run --project soleur --config prd -- ... inngest start ...` (`inngest-bootstrap.sh:167`) — new creds inject as more `$${...}` refs in the SAME wrapper (avoids the #4116 `EnvironmentFile`-empty trap). `inngest.tf:35-59` already has the `random_id → doppler_secret` pattern (signing/event keys) → Redis/Postgres-role passwords use `random_password + doppler_secret`, **not operator-mint** (#3973). cloud-init `write_files` + sudoers + delivered-bootstrap is the precedent for a new `inngest-redis.service`. `/mnt/data` mounted+chowned at `cloud-init.yml:516-531`.
- **Self-host substrate hazards** (`learnings-researcher`): (#4116) wrap ExecStart in `doppler run`; (#five-bug-cascade) `chown` immediately after `mkdir`, enumerate every write path in `ReadWritePaths`, **tag push must be in the same PR** (the `vinngest-v*` OCI image tag — changing `inngest-bootstrap.sh` rebuilds the image); (2026-06-14) **inline `remote-exec` edits are silent no-ops** — Redis init must live in a *delivered script* whose `file()` feeds `triggers_replace.config_hash`; `variable {sensitive=true}` operator-mint is a design smell → use `random_password`.
- **Inngest contract** (`framework-docs-researcher`): `--postgres-uri`/`--redis-uri` GA since CLI v1.4.0 (Jan 2025), combinable; **FR1 + schema-targeting + de-plan-on-restart all UNCONFIRMED by docs → empirical spike required**; no SQLite→Postgres migration tool.
- **Supabase/Redis best-practice** (`best-practices-researcher`): **Session mode :5432** (transaction 6543 breaks prepared statements); **free IPv6** egress from Hetzner; `--postgres-max-open-conns≈25` (default 100 too high for a shared Supabase budget); a dedicated `inngest` schema/project is **NOT** PostgREST-exposed by default; Redis `maxmemory-policy noeviction` (never evict jobs) + `appendonly yes` + `appendfsync everysec`, AOF on persistent disk.

## Hypotheses (apply-time reachability — Phase 1.4 gate)

This plan names `terraform apply` against `server.tf`, which carries `connection { type = "ssh" }` + `provisioner "remote-exec"` blocks (`server.tf:89-115`). Per `hr-ssh-diagnosis-verify-firewall` the apply path depends on **L3 firewall reachability before any service-layer step**:
- **H1 (firewall/egress):** `terraform apply` must reach the host over SSH:22, which `firewall.tf` restricts to `var.admin_ips`. Before apply, confirm the operator/CI egress IP is in `admin_ips` (the #3061 drift class) — verify firewall + egress IP, never assume sshd.
- **H2 (canonical invocation):** use the `prd_terraform` Doppler triplet — raw `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` exports for the R2 backend + `terraform init -input=false` + `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply` (a bare `doppler run -- terraform plan` fails with ~13 "No value for required variable").
No sshd/fail2ban change is proposed; this section documents the apply dependency only.

## Implementation Phases

### Phase 0 — Spike (local + DEV Supabase; no prod changes) — HARD predecessor to Phase 1 commits
Run a local `inngest start` (docker or binary, CLI ≥ v1.4.0) against the **dedicated DEV Inngest Supabase project** (`dev != prd`, `hr-dev-prd-distinct-supabase-projects`) — never prod. **Phase 1 code must NOT be authored until these verdicts are recorded in `inngest-server.md`** (the "Phase 0 verdicts recorded" AC is a hard predecessor to every Phase 1 AC).
1. **FR1 durability boundary (assert the invariant).** Arm `inngest.send({ ts: now+10min })`; **kill the container and recreate it with a wiped local volume** (simulates host re-provision — NOT a mere process restart) pointing at the same Postgres + (a) in-memory Redis, then (b) external `--redis-uri` AOF. **Verdict rule:** the configuration under which the event still fires after a wiped-local-volume restart is the required one. Expectation: durable Redis required; ship both regardless (FR1 is a *documentation* finding, not a build gate — see below).
2. **Fail-closed vs. silent fallback (NEW — load-bearing for "fail loud").** Start `inngest` with an **unreachable** `--postgres-uri`/`--redis-uri`. Does it exit non-zero (fail closed) or silently fall back to SQLite/in-memory? If it falls back silently, the deploy gate must add an explicit post-start assertion that the durable backend is actually in use — otherwise an unreachable-backend deploy "passes" while silently non-durable.
3. **Cutover-recovery strategy (NEW — resolves spec-flow P0-1).** There is **no app-side reminder store** (`schedule-reminder/route.ts:108` is fire-and-forget `inngest.send`). Determine how armed future events are recovered across the SQLite→fresh-Postgres cutover: (a) does the self-hosted server expose an enumeration API for queued-but-unfired events (`/v1/events`?); (b) is **dual-run-drain** feasible (run old SQLite Inngest alongside new Postgres Inngest until the old drains)? (c) else a minimal **app-side reminder ledger** (a Supabase row written at arm-time + a boot reconciler) is required. Record which path; it determines the Phase 2 cutover shape. Also: does Inngest fail-closed or replay non-idempotently on a backend swap mid-run (drain implications, ADR-030 I1/I2/I6)?
4. **Pooler mode + grants.** Confirm Inngest connects via Supavisor **session :5432** (fails/over-connects on transaction :6543 — documents *why* 5432); validate the dedicated-project owner role.
**Gate:** verdicts recorded in `inngest-server.md`. **Ship both Postgres + Redis** (FR1 confirms the mechanism; at single-user-incident threshold Redis is cheap insurance and the AC assumes it). NO production write in Phase 0.

### Phase 1 — Provision durable backend (Terraform / cloud-init only; no operator SSH)
- **Dedicated Inngest Supabase project + role/grants:** provisioned via a **delivered idempotent SQL bootstrap** (`psql` against the dedicated project, `file()` hashed into `config_hash`), NOT the Supabase TF provider — that provider is **not declared in `main.tf`** and likely cannot provision an org-level project (architecture review P1-3). If Phase 0 proves project creation needs an API call, route it through `service-automator`/an idempotent script, never a dashboard click.
- **Secrets (TF):** `random_password.inngest_redis_password_prd` + `doppler_secret` (prd+dev); `doppler_secret.inngest_postgres_uri_{prd,dev}` = the **session-pooler :5432** connection string for the dedicated Inngest project. Mirror `inngest.tf:35-59` `lifecycle { ignore_changes = [value] }`. No operator-mint sensitive var (`random_password` is in the already-declared `hashicorp/random` provider).
- **Redis service:** new `inngest-redis.service` — long-running, `Restart=on-failure`, **`RequiresMountsFor=/mnt/data`** (architecture review P1-2: without it Redis can start before the `|| true` volume mount and write AOF to the root disk, silently reproducing the trap). `redis.conf`: `maxmemory-policy noeviction`, `appendonly yes`, `appendfsync everysec`, **`maxmemory <bound>` + `auto-aof-rewrite-percentage 100` + `auto-aof-rewrite-min-size 64mb`** (bound the AOF so it cannot fill `/mnt/data` and starve the co-located workspaces volume — spec-flow P2-3), `dir /mnt/data/redis`, `bind 127.0.0.1`, `requirepass` from Doppler. Laid down via cloud-init `write_files` + a **delivered** `inngest-redis-bootstrap.sh` (`file()` in `config_hash` — NOT inline remote-exec). `mkdir -p /mnt/data/redis && chown redis:redis` immediately; add `/mnt/data/redis` to the webhook `ReadWritePaths`; cloud-init `runcmd` enables the unit (canonical IaC enable, not operator SSH).
- **Inngest unit:** extend ExecStart (`inngest-bootstrap.sh:167`) — add `--postgres-uri "$${INNGEST_POSTGRES_URI}" --redis-uri "redis://:$${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379"` (+ `--postgres-max-open-conns N`, N tuned at apply-time to the dedicated project's tier — NOT a hardcoded magic number). **Keep** `--sqlite-dir` removable in one revert step (rollback). RECONCILE-ALWAYS lands ExecStart-only changes.
- **OCI image + tag:** changing `inngest-bootstrap.sh` requires a new `ghcr.io/jikig-ai/soleur-inngest-bootstrap` image; **push the `vinngest-v*` tag in this PR** (`hr-tagged-build-workflow-needs-initial-tag-push`).
- **Docs/observability are deliverables of this phase** (folded from old Phase 3): the `verify_inngest_health` Redis+Postgres **hard-gate** probe (spec-flow P1-4: a HARD gate that returns non-zero, distinct from the advisory cron probe), the runbook durability column, ADR-030 amend + ADR-046 cross-ref + C4 edit.

### Phase 2 — Cutover (low-traffic window; rollback-ready) — shape fixed by Phase-0 verdict
Ordered to close the silent-loss windows the spec-flow review found (P0-1/P0-2/P1-3):
1. **Quiesce arming first.** Flag-gate `schedule-reminder` to 503 (callers retry) for the cutover window so no reminder is armed into the doomed old SQLite mid-cutover (P0-2).
2. **Recover existing armed work** per the Phase-0 cutover-recovery verdict (enumeration API / dual-run-drain / app-side ledger). If the verdict is dual-run-drain, run old SQLite Inngest until it drains armed reminders before decommissioning; if a ledger, re-arm from it. **There is no "reminder store" to enumerate today** — the Phase-0 verdict is what makes recovery possible at all (P0-1).
3. **Drain in-flight runs** (ADR-030 I1/I2/I6): per Phase-0, either observe zero `Running` for N seconds or accept-and-document that in-flight runs are abandoned + enumerate which functions are non-idempotent on replay (the reminder `check`/`action`).
4. **Deploy** via the release pipeline; the no-SSH restart path (`ci-deploy.sh restart inngest`) brings Inngest up on Postgres+Redis (fresh state; old SQLite abandoned).
5. **Verify the REAL invariant (not the proxy, P0-3):** arm a throwaway future reminder, then **recreate the inngest container with a wiped local volume** (the wiped-volume test from Phase 0, in prod shape — a process restart is insufficient because Postgres is off-host and Redis AOF is on the persistent volume), confirm it still fires. Confirm `/health` 200 + `/v1/functions` cron re-arm (watchdog covers de-plan).
6. **Re-open arming**; re-arm any recovered pending reminders/oneshots.
- **Rollback (bounded, P1-3):** revert ExecStart to `--sqlite-dir` + redeploy. **Tripwire:** rollback-to-SQLite is data-safe ONLY before any *real* (non-throwaway) reminder is armed against Postgres — after that, the stale SQLite is missing those reminders AND could double-fire ones Postgres already recorded; **forward-fix only** past that point. On a *committed* cutover, **wipe the old `/var/lib/inngest` SQLite** so a later accidental SQLite boot cannot replay dead reminders.

## Files to Edit
- `apps/web-platform/infra/inngest-bootstrap.sh` — ExecStart: add `--postgres-uri`/`--redis-uri`/`--postgres-max-open-conns`; Redis dir chown + ReadWritePaths.
- `apps/web-platform/infra/inngest.tf` — new `random_password` + `doppler_secret` (Redis pw, Postgres URI) prd+dev; optional Supabase provider resources for the Inngest project/role.
- `apps/web-platform/infra/cloud-init.yml` — `write_files` for `inngest-redis.service` + `redis.conf` + `/etc/default/inngest-redis`; `/mnt/data/redis` mkdir/chown in the volume runcmd; `inngest-redis-bootstrap.sh` delivery + `runcmd` enable.
- `apps/web-platform/infra/server.tf` — `terraform_data`/provisioner wiring for the Redis bootstrap delivery (`file()` into `config_hash`); webhook `ReadWritePaths` += `/mnt/data/redis`.
- `apps/web-platform/infra/ci-deploy.sh` — extend `verify_inngest_health` to probe Redis + Postgres reachability (loopback, no SSH).
- `apps/web-platform/infra/variables.tf` — `inngest_postgres_uri`, `inngest_redis_password` (sensitive) only if not fully `random_password`/`doppler_secret`-derived.
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — amend `## Trade-offs accepted` + `## Decision`.
- `knowledge-base/engineering/architecture/decisions/ADR-046-...md` — cross-ref the changed SQLite-durability bound.
- `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md` + `inngest-server.md` — durability matrix + backend.

- `apps/web-platform/app/api/internal/schedule-reminder/route.ts` — add the cutover quiesce gate (503 when a `cutover-in-progress` flag is set); + an app-side reminder ledger write IF Phase 0's cutover-recovery verdict requires it.

## Files to Create
- `apps/web-platform/infra/inngest-redis-bootstrap.sh` — idempotent Redis install/config (delivered script, `file()` in `config_hash`).
- `apps/web-platform/infra/inngest-supabase-bootstrap.sql` (+ a delivered runner) — idempotent dedicated-project role/grants (`file()` in `config_hash`).
- `apps/web-platform/infra/redis.conf` (or templated in cloud-init) — the queue-Redis config.
- (Phase 0) a throwaway local `docker-compose.spike.yml` — NOT committed; spike artifact only, results recorded in the runbook.
- (conditional, per Phase 0) a `scheduled_reminders` Supabase migration + boot reconciler — only if the cutover-recovery verdict is "app-side ledger".

## Acceptance Criteria

### Pre-merge (PR) — load-bearing post-conditions
- [ ] Phase 0 verdicts recorded in `inngest-server.md` (**hard predecessor** to every AC below): FR1 wiped-volume durability, fail-closed-vs-fallback, cutover-recovery strategy, pooler = session :5432.
- [ ] **Durability invariant** (the AC that carries the PR): arming a future reminder then recreating Inngest **with a wiped local volume** still fires it (Postgres+Redis configuration). Not a process-restart proxy.
- [ ] `inngest-bootstrap.sh` ExecStart contains `--postgres-uri` + `--redis-uri`; **no `6543`** in the connection string.
- [ ] `inngest-redis.service` declares **`RequiresMountsFor=/mnt/data`**; `/mnt/data/redis` `mkdir`+`chown redis:redis` in cloud-init AND in the webhook `ReadWritePaths`.
- [ ] `redis.conf`: `maxmemory-policy noeviction`, `appendonly yes`, `appendfsync everysec`, **`maxmemory` + `auto-aof-rewrite-percentage`/`-min-size`** (AOF cannot fill `/mnt/data`), `dir /mnt/data/redis`, `bind 127.0.0.1`, `requirepass`.
- [ ] Redis/Postgres secrets are `random_password`/`doppler_secret`-derived (no operator-mint sensitive var); `lifecycle { ignore_changes = [value] }`.
- [ ] Inngest project provisioned via a **delivered idempotent SQL bootstrap** whose `file()` is in `config_hash` (no Supabase TF provider added unless Phase 0 proves it necessary); `inngest-redis-bootstrap.sh` likewise `file()`-hashed.
- [ ] `verify_inngest_health` adds a **HARD gate** (returns non-zero) on Redis + Postgres reachability — distinct from the existing advisory cron probe; surfacing reaches Sentry/deploy-status without SSH.
- [ ] `schedule-reminder` route can be quiesced (503) for the cutover window.
- [ ] ADR-030 amended (corrected "Hetzner backups" mitigation + precise `-replace` trigger + "no new sub-processor" reframe + `status: adopting`); ADR-046 cross-ref notes the boot-arm/re-arm remains the dedup-window recovery path (not redundant); C4 Container view updated (Concierge `c4-edit` path); runbook host-rebuild durability column populated.

### Post-merge (operator / CI)
- [ ] `terraform apply` (prd_terraform triplet) provisions the Inngest project + Redis + secrets; deploy gate confirms `inngest-redis.service` active + `inngest-server` healthy (no SSH). *Automation: release pipeline restarts the container on merge; TF apply is the one CI step (egress-IP in `admin_ips` per H1).*
- [ ] Cutover follows the Phase-2 ordering (quiesce → recover → drain → deploy → wiped-volume verify → re-open); pending reminders/oneshots recovered per the Phase-0 strategy.
- [ ] `gh issue close 5450` after cutover verification passes.

*(Process-gate items — `Ref #5450` in PR body, `vinngest-v*` tag push — are enforced by the ship checklist / `hr-tagged-build-workflow-needs-initial-tag-push`, not duplicated as feature ACs.)*

## User-Brand Impact
- **If this lands broken, the user experiences:** a reminder, scheduled report, or oneshot they were promised never fires (or fires twice on a botched cutover) — with no error surfaced.
- **If this leaks, the user's workflow/data is exposed via:** Inngest run-state (which may carry founder-tagged step payloads per ADR-030 I2) now persists in Supabase — same EU sub-processor as the primary DB, so residency is preserved/improved vs. plaintext SQLite on the host; the exposure vector would be an Inngest schema accidentally reachable via Supabase's PostgREST auto-API.
- **Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at PR review.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations (Product = NONE — no UI surface; no `components/**`/`page.tsx`/`layout.tsx` in Files to Create → Product/UX Gate skipped).

### Engineering
**Status:** reviewed (brainstorm carry-forward + Phase 1 research). **Assessment:** gap is real and narrow (HTTP-armed reminders + conditional-re-arm-drift oneshots); durable fix = the ADR-030-named Postgres migration; load-bearing unknown is the Postgres-vs-Redis durability boundary (Phase 0 spike). De-plan asymmetry already self-healed by the watchdog — out of scope.

### Legal
**Status:** reviewed. **Assessment:** **no new sub-processor** (Supabase already primary DB + existing sub-processor; Redis self-hosted on our own host). EU residency preserved (EU Supabase). Article 30 register: a PA note may be warranted if the Inngest event/run-state in Supabase introduces a *new* personal-data category vs. what the app already stores there — confirm at /work once the spike reveals what Inngest persists (see GDPR section).

### Operations
**Status:** reviewed. **Assessment:** adds two persistence dependencies (Supabase session-pooler connection + self-hosted Redis systemd unit, AOF on `/mnt/data`). Both must be reachable from a fresh-host `terraform apply` (`hr-fresh-host-provisioning-reachable-from-terraform-apply`). One-time in-flight cutover loss; sequence on a low-traffic window with pre-cutover enumeration. No separate dev Hetzner host → spike runs locally.

## Infrastructure (IaC)

### Terraform changes
- `inngest.tf`: `random_password.inngest_redis_password_prd` + `doppler_secret` (prd+dev); `doppler_secret.inngest_postgres_uri_{prd,dev}`; optional `supabase_*`/SQL-bootstrap for the dedicated Inngest project/role. All with `lifecycle { ignore_changes = [value] }`.
- `server.tf`: `terraform_data` (or extend the inngest bootstrap resource) delivering `inngest-redis-bootstrap.sh` with its `file()` in `triggers_replace.config_hash`; webhook `ReadWritePaths += /mnt/data/redis`.
- Providers: existing `hcloud`, `doppler`, `random`; add Supabase provider **only** if Phase 0 chooses the schema-in-shared-project path needing TF-managed SQL (else a delivered idempotent SQL bootstrap).
- Sensitive values: `INNGEST_POSTGRES_URI` (Doppler `prd`/`dev`), `INNGEST_REDIS_PASSWORD` (`random_password` → Doppler). No operator-mint default.

### Apply path
**cloud-init + idempotent bootstrap script** (default for existing infra): fresh host gets Redis + units from cloud-init `write_files`+`runcmd`; a running host gets them from the delivered `inngest-redis-bootstrap.sh` re-run via the hashed `terraform_data`. No `-replace` of the server. Expected downtime: a brief `inngest-server` restart at cutover (seconds), via the existing no-SSH restart path.

### Distinctness / drift safeguards
`dev != prd` Supabase projects (separate Doppler configs). `lifecycle { ignore_changes = [value] }` on all generated secrets. The Supabase connection string + Redis password land in `terraform.tfstate` (encrypted R2 backend) — same posture as existing inngest secrets.

### Vendor-tier reality check
Supabase pooler connection limits are compute-tier dependent; `--postgres-max-open-conns 25` leaves headroom for the main app on the shared project (or the dedicated Inngest project has its own budget). Confirm the tier's pooler limit at apply time.

## Observability

```yaml
liveness_signal:
  what: inngest-server /health 200 AND inngest-redis unit active AND Postgres reachable
  cadence: post-deploy (verify_inngest_health) + cron-inngest-cron-watchdog every 4h
  alert_target: Sentry cron monitor (existing H9b safety net) + deploy-status webhook
  configured_in: apps/web-platform/infra/ci-deploy.sh (verify_inngest_health); infra/sentry/*.tf
error_reporting:
  destination: Sentry (Inngest start failure on unreachable Postgres/Redis fails the deploy gate, non-silent)
  fail_loud: true — verify_inngest_health returns non-zero → ci-deploy marks inngest_health_failed
failure_modes:
  - mode: Supabase Postgres unreachable at start
    detection: inngest /health never 200 → verify_inngest_health fails
    alert_route: deploy gate failure + Sentry
  - mode: Redis down / AOF dir full
    detection: inngest-redis unit not active; /mnt/data disk-monitor
    alert_route: disk-monitor + a new unit-active probe in verify_inngest_health
  - mode: Inngest exhausts the (dedicated-project) pooler budget
    detection: Supabase pooler connection metrics on the Inngest project
    alert_route: Supabase alert; dedicated project keeps this OFF the main-app budget (the reason it is the default isolation)
  - mode: unreachable backend at start → silent in-memory fallback (if Phase 0 finds Inngest fails open)
    detection: post-start assertion that the durable backend is in use (added to verify_inngest_health iff Phase 0 shows fail-open)
    alert_route: deploy gate hard-fail
  - mode: armed reminder lost on rebuild (the bug this fixes)
    detection: Phase-2 wiped-volume invariant test; post-fix this cell is durable
    alert_route: N/A once durable
logs:
  where: journalctl inngest-server / inngest-redis (host); Sentry for app-side
  retention: host journal default; Sentry per project
discoverability_test:
  command: "curl -sf http://127.0.0.1:8288/health && curl -sf http://127.0.0.1:8288/v1/functions | grep -q '\"cron\":'"  # run via deploy gate / watchdog — NO ssh
  expected_output: health 200 + >=1 cron trigger present
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-030** (`/soleur:architecture`): in `## Decision`, flip "SQLite for state persistence" → "Postgres (dedicated Supabase project, session-pooler :5432) + self-hosted Redis (AOF on /mnt/data) for durable state/queue"; in `## Trade-offs accepted`, **correct** "Mitigated by: Hetzner backups" — state the **precise loss trigger**: `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ssh_keys, image] }` (`server.tf:70`), so SQLite loss is NOT "every apply" but an explicit `terraform apply -replace` / replace-forcing change, which boots a fresh root disk with no backup restore (rarer than implied, but real). Record the "Supabase already a sub-processor → no 5th sub-processor; deferral trigger = #5450 durability gap, NOT the original 3rd-founder criterion" reframe. Add the **availability-coupling** trade-off (in-memory fallback removed). `status: adopting` until Phase 2 verifies. **Cross-ref ADR-046** — its "bounded by single-host SQLite durability (ADR-030)" line now points at the durable backend; **note the boot-arm/re-arm-every-deploy (I4) remains correct** as the dedup-window recovery path, not made redundant by the durable backend.

### C4 views
**Container view** changes: the Inngest persistence edge moves from *local SQLite (root disk)* to *Supabase Postgres (session pooler) + self-hosted Redis (/mnt/data AOF)*. Route the C4 edit through the **Concierge `c4-edit`-flag path** (KB writes are Concierge-gated). Lands in THIS feature, not a follow-up.

### Sequencing
ADR authored now describing the target state (`status: adopting`); the "durable" claim becomes true after Phase 2 cutover verification — not postponed to its own issue.

## GDPR / Compliance (Phase 2.7 — assessed inline)
Single-user-incident threshold + new persistence surface → gate fires. Assessment: Inngest event/run-state **relocates** from plaintext SQLite-on-Hetzner (EU) to **Supabase Postgres (EU, existing sub-processor)** — not a new processing activity nor a new sub-processor; residency preserved/improved. **Action:** at /work, once the Phase 0 spike reveals exactly what Inngest persists (event payloads / step outputs may carry founder-tagged data per ADR-030 I2), confirm whether the Supabase Article 30 PA needs a one-line "Inngest backend" note; run a formal `/soleur:gdpr-gate` pass against the migration diff before marking the PR ready. No Art. 9 special-category or new-lawful-basis trigger identified.

## Risks & Mitigations
- **KEYSTONE — no app-side reminder store → cutover loses existing armed reminders** (`schedule-reminder/route.ts:108` fire-and-forget): the migration could re-introduce the exact silent loss it fixes. Mitigated by the Phase-0 cutover-recovery verdict (enumeration API / dual-run-drain / app-side ledger) + the quiesce-arming cutover ordering. This is the single most important finding (spec-flow P0-1/P0-2).
- **Verify-proxy trap:** a process restart does NOT test disk-wipe survival (Postgres off-host, Redis AOF on persistent volume). Mitigated by the **wiped-local-volume** invariant test in Phase 0 and Phase 2 (spec-flow P0-3).
- **Redis races the volume mount → AOF on root disk:** mitigated by `RequiresMountsFor=/mnt/data` (architecture P1-2).
- **AOF fills /mnt/data → starves workspaces:** `maxmemory` + `auto-aof-rewrite` bounds (spec-flow P2-3).
- **Silent in-memory fallback on unreachable backend:** Phase-0 fail-closed check + a post-start durable-backend assertion in the hard health gate (spec-flow P1-4).
- **Pooler-mode misconfig (6543) silently breaks Inngest:** AC forbids `6543`; spike confirms session :5432.
- **Connection-budget / shared-fate with the main app:** mitigated by the **dedicated Inngest Supabase project** default (architecture P1-1) — keeps pooler contention + project-fate off the main app.
- **Cutover in-flight run replay / double-fire (ADR-030 I1/I2/I6):** drain or accept-and-document abandonment + enumerate non-idempotent funcs; rollback tripwire (forward-fix only once real reminders are armed against Postgres) + wipe old SQLite on commit.
- **Inline remote-exec silent no-op:** Redis + Supabase-SQL init in delivered scripts with `file()` in `config_hash`.
- **Availability coupling (permanent):** Inngest now depends on Supabase + Redis uptime (in-memory fallback gone). Accepted for durability + PITR + ADR-030 closure; surfaced to the operator; monitored via Observability. The dedicated project bounds the blast radius off the main app.

## Open Code-Review Overlap
2 false-positive matches on `server.tf` — #3216 (regex-canary bundle) and #2197 (billing SubscriptionStatus); neither touches the Inngest volume/secret blocks this plan edits. **Disposition: Acknowledge** (different concerns, remain open).

## Sharp Edges
- **KEYSTONE — the cutover can re-introduce the silent loss it fixes.** Armed reminders live ONLY in Inngest state (no app-side store, `schedule-reminder/route.ts:108`); a fresh-Postgres cutover loses them unless the Phase-0 recovery verdict (enumeration / dual-run-drain / ledger) + quiesce-arming ordering are honored. Do not let `/work` skip Phase 0.
- **Verify the disk-wipe invariant, not a process restart** — Postgres is off-host, Redis AOF on the persistent volume, so a restart fires the event regardless and proves nothing. Use the wiped-local-volume test.
- **`RequiresMountsFor=/mnt/data` on the Redis unit is load-bearing** — without it Redis can write AOF to the root disk before the `|| true` mount, silently reproducing the trap.
- **Do NOT claim this PR fixes the cron de-plan-on-restart asymmetry** — that is the watchdog's job (#5159), orthogonal to the state backend.
- **`6543` is a trap** — Supabase transaction-mode pooler breaks Inngest's prepared statements; session-mode :5432 only.
- A plan whose `## User-Brand Impact` section is empty / `TBD` / threshold-less fails `deepen-plan` Phase 4.6. (This plan's section is filled.)
