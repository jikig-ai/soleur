---
feature: inngest-scheduled-durability
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-17-feat-inngest-durable-backend-supabase-postgres-plan.md
issue: 5450
---

# Tasks: Durable backend for Inngest scheduled work

> Phase 0 is a **hard predecessor** — no Phase 1 code is authored until Phase 0 verdicts are recorded in `inngest-server.md`.

## Phase 0 — Spike (local + DEV Supabase; no prod writes)
- [ ] 0.1 Stand up local `inngest start` (CLI ≥ v1.4.0) against a dedicated DEV Inngest Supabase project.
- [ ] 0.2 **FR1 wiped-volume durability:** arm a future-`ts` event → recreate the container with a wiped local volume → confirm it fires under (a) in-memory Redis, (b) external AOF Redis. Record the required config.
- [ ] 0.3 **Fail-closed vs fallback:** start with an unreachable backend; record whether Inngest exits non-zero or silently falls back to in-memory.
- [ ] 0.4 **Cutover-recovery strategy:** determine enumeration API vs dual-run-drain vs app-side ledger for recovering armed reminders across the SQLite→fresh-Postgres cutover; record drain semantics for in-flight runs (ADR-030 I1/I2/I6).
- [ ] 0.5 **Pooler + grants:** confirm session :5432 works / :6543 breaks; validate the dedicated-project owner role.
- [ ] 0.6 Record all verdicts in `inngest-server.md` (gate to Phase 1).

## Phase 1 — Provision (Terraform / cloud-init only; no operator SSH)
- [ ] 1.1 Delivered idempotent SQL bootstrap for the dedicated Inngest project role/grants (`file()` in `config_hash`); no Supabase TF provider unless 0.x requires it.
- [ ] 1.2 `random_password` + `doppler_secret` (Redis pw, prd+dev); `doppler_secret` Inngest Postgres URI (session :5432, prd+dev); `lifecycle { ignore_changes = [value] }`.
- [ ] 1.3 `inngest-redis.service` (+ `RequiresMountsFor=/mnt/data`, `Restart=on-failure`) + `redis.conf` (`noeviction`, `appendonly yes`, `appendfsync everysec`, `maxmemory`+`auto-aof-rewrite`, `dir /mnt/data/redis`, `bind 127.0.0.1`, `requirepass`) via cloud-init `write_files` + delivered `inngest-redis-bootstrap.sh` (`file()` in hash); `mkdir`+`chown redis:redis`; webhook `ReadWritePaths += /mnt/data/redis`.
- [ ] 1.4 Extend `inngest-bootstrap.sh:167` ExecStart: `--postgres-uri`/`--redis-uri` (+ tier-tuned `--postgres-max-open-conns`); keep `--sqlite-dir` revertible.
- [ ] 1.5 `verify_inngest_health` HARD gate on Redis + Postgres reachability (no SSH); post-start durable-backend assertion iff 0.3 shows fail-open.
- [ ] 1.6 `schedule-reminder` route: cutover quiesce (503) gate; app-side ledger write iff 0.4 verdict = ledger.
- [ ] 1.7 New OCI image + push the `vinngest-v*` tag in this PR.
- [ ] 1.8 (Deliverables) ADR-030 amend + ADR-046 cross-ref + C4 Container edit; runbook host-rebuild durability column; `inngest-server.md` backend + verdicts.

## Phase 2 — Cutover (low-traffic; rollback-ready)
- [ ] 2.1 Quiesce arming (503).
- [ ] 2.2 Recover existing armed work per 0.4 verdict (enumeration / dual-run-drain / ledger).
- [ ] 2.3 Drain in-flight runs or document abandonment + non-idempotent funcs.
- [ ] 2.4 Deploy via release pipeline (no-SSH restart onto Postgres+Redis).
- [ ] 2.5 **Wiped-volume invariant verify** (arm throwaway → recreate with wiped local volume → fires) + `/health` + cron re-arm.
- [ ] 2.6 Re-open arming; re-arm recovered pending work.
- [ ] 2.7 Rollback tripwire honored (forward-fix only after real reminders armed against Postgres); wipe old SQLite on commit.

## Phase 3 — Verify & close (post-merge)
- [ ] 3.1 `terraform apply` (prd_terraform triplet); deploy gate confirms Redis active + Inngest healthy.
- [ ] 3.2 Formal `/soleur:gdpr-gate` pass on the migration diff (Article 30 PA note if Inngest run-state adds a personal-data category).
- [ ] 3.3 `gh issue close 5450` after cutover verification.

## Review notes (carry to /work)
- Data-integrity + security review of the (conditional) `scheduled_reminders` ledger migration/RLS and the Supabase role grants / Redis secret happens at /work review-time when the SQL/secrets exist.
- `user-impact-reviewer` runs at PR review (threshold = single-user incident; `requires_cpo_signoff: true`).
