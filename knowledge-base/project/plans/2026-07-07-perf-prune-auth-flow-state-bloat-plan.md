---
feature: auth-flow-state-retention-prune
issue: 5739
branch: feat-one-shot-5739-auth-wal-reduction-v2
pr: TBD
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-07
supersedes_wip: 5762
---

# ♻️ perf(db): prune unbounded `auth.flow_state` GoTrue bloat + record #5739 WAL decision

## Overview

Issue #5739 tracks the "~18% of prod WAL from Supabase Auth (GoTrue)" residual from the
2026-06-30 Disk-IO-budget investigation on prod `soleur-web-platform`
(ref `ifsccnjhymdmidffkzhl`, Micro / 1 GB RAM). The sibling worktree
`feat-5739-auth-wal-reduction` (draft PR #5762) opened a clean post-#5736 measurement
window (pgss reset 2026-06-30 12:40 UTC) and recorded a day-1 mid-soak snapshot. **This
is separate, fresh work** — it does NOT reuse or nuke that branch/PR; it takes its own
read-only post-soak measurement (soak completes ~2026-07-07 = today) and ships the one
concrete, security-neutral deliverable the investigation surfaced.

**The honest finding (post-soak, live-measured 2026-07-07):** the bulk of Auth WAL is
**legitimate, irreducible volume** — `refresh_tokens` / `sessions` / `mfa_amr_claims`
INSERTs driven by real logins (~214 flows/day, ~1 refresh token per session, **no loop**,
**no short-JWT-TTL churn**). There is no high-ROI *WAL* lever here without changing session
behavior (JWT-TTL lever stays deferred — see Non-Goals NG1).

**What IS actionable:** `auth.flow_state` grows **unbounded and is never pruned by GoTrue**
— 4,300 rows on prod, 3,793 older than 7 days, oldest 2026‑03‑17 (~3.7 months), and
**99.6% are abandoned flows** (auth code never issued/exchanged). Abandoned rows retain
`provider_access_token` / `provider_refresh_token` columns, so this is **also a
security/GDPR data‑minimization improvement** (stale third‑party OAuth tokens sitting in
the DB for months), not only bloat/dead-tuple control. The deliverable is a single
migration adding a daily pg_cron retention prune of **expired** `flow_state` rows, mirroring
the just-merged #5738 pattern (migration `115_prune_cron_job_run_details.sql`) and the
`103_github_events_retention_7day.sql` retention shape.

**Framing discipline (load-bearing):** per learning
`2026-06-30-pgcron-cadence-is-wal-lever-retention-prune-is-disk-play.md`, a retention prune
reduces **table size / dead-tuple churn / disk pressure**, NOT per-INSERT WAL. `flow_state`
INSERTs are ~4.5 MB/7d vs `refresh_tokens` ~20 MB/7d. This PR is framed as **bloat + stale-
secret minimization**, not WAL reduction. The issue's "reduce ~18% WAL" premise is answered
with evidence: the WAL is legitimate volume; no WAL lever ships; the flow_state prune is the
disk/security win. `Closes #5739`.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (live-measured 2026-07-07, prod `ifsccnjhymdmidffkzhl`) | Plan response |
|---|---|---|
| "Auth generates ~18% of WAL; lengthen JWT/session lifetime to cut churn" | Bulk auth WAL is `refresh_tokens`/`sessions`/`mfa` INSERTs = legitimate login volume; no loop; no short-TTL refresh churn observed | Do NOT touch JWT TTL (NG1, deferred with rationale + CLO note). Ship the security-neutral flow_state prune instead. |
| "`recovery_token` UPDATEs (1,586 calls) may indicate a password-recovery loop" | Sibling mid-soak + this measurement: ~1 refresh/session, ~214 flows/day = legitimate; no loop | No loop remediation needed; record the negative finding as evidence for the AC. |
| flow_state prune "reduces WAL" | flow_state INSERTs ~4.5 MB/7d (modest); the prune's own DELETE is itself WAL-logged | Frame as bloat/dead-tuple + stale-OAuth-token minimization, NOT WAL reduction. |
| `auth.flow_state` has an `expires_at` column | **No `expires_at` column** in prod; GoTrue computes expiry lazily at exchange time from `created_at` | Predicate uses `created_at`, not `expires_at`. |
| Pruning auth-schema may need SECURITY DEFINER / special role | `postgres` holds an explicit DELETE grant on `auth.flow_state` **and** `rolbypassrls`; all 14 existing retention crons already run as `postgres` | Plain `cron.schedule(...)` as `postgres`. No SECURITY DEFINER needed. Verify grant read-only in Phase 0 (grant-fragility red flag). |

## User-Brand Impact

- **If this lands broken, the user experiences:** a login that silently fails — if the prune
  predicate were too aggressive and deleted an **in-flight** PKCE / magic-link / MFA
  `flow_state` row, the user's OAuth callback or magic-link click would return
  "invalid flow state" and they could not sign in. (Structurally prevented by the 3-day
  floor — see Risks R1.)
- **If this leaks, the user's data is exposed via:** stale `provider_access_token` /
  `provider_refresh_token` values for abandoned OAuth flows retained indefinitely in
  `auth.flow_state`. Pruning them **reduces** this exposure (data minimization); the change
  cannot *increase* exposure.
- **Brand-survival threshold:** `single-user incident` (a wrong predicate breaks one user's
  login independently). → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at
  review-time (single-user-incident conditional-agent block in `review/SKILL.md`); the
  deepen-plan triad (data-integrity-guardian + security-sentinel + architecture-strategist)
  runs next per the plan-review Sharp Edge.

## Premise Validation (Phase 0.6)

Checked and current: **#5739 OPEN** (`gh issue view 5739`); **PR #5736 MERGED** 2026-06-30
12:01 UTC (the 63% primary WAL fix the measurement window depends on); **#5738 CLOSED** via
**PR #5760 MERGED** with migration `115_prune_cron_job_run_details.sql` on `origin/main`
(the retention-prune precedent — verified present, read in full); `103_github_events_retention_7day.sql`
second precedent (verified present). **Migration 124** is the next free number on
`origin/main` (highest is `123_tame_autovacuum_on_tiny_hot_tables`) — **provisional**, must be
re-checked at ship (see Sharp Edges). Sibling **draft PR #5762 / branch `feat-5739-auth-wal-reduction`**
verified intact — this plan does not touch it. No stale premise.

## Implementation Phases

### Phase 0 — Read-only prod re-verify (no writes)
1. Via Supabase MCP (`execute_sql`, read-only) on `ifsccnjhymdmidffkzhl`, re-confirm before
   writing SQL: (a) `postgres` still holds `DELETE` on `auth.flow_state`
   (`information_schema.role_table_grants`); (b) row-count-by-age
   (total / older-than-3d, oldest `created_at`); (c) pgss window age + that `flow_state`
   INSERT WAL ≪ `refresh_tokens` INSERT WAL (confirms the bloat-not-WAL framing). Record the
   numbers into the PR body evidence block.
2. Re-run the migration-number collision check: `git ls-tree origin/main apps/web-platform/supabase/migrations/`
   — confirm `124_*` is free; if taken, use the next free number and update all references.

### Phase 1 — Migration (mirror 115 / 103 shape)
1. Create `apps/web-platform/supabase/migrations/124_prune_auth_flow_state.sql`:
   - **Header comment** (mirror 115/103 prose density): why (GoTrue never prunes flow_state;
     4.3k rows / 3.7-month backlog; 99.6% abandoned; stale OAuth tokens); the bloat-not-WAL
     framing (cite the cadence-vs-prune learning); the 3-day floor derivation
     (MAILER_OTP_EXP 1d + FlowStateExpiryDuration 5min ⇒ 24h absolute floor, 3d = headroom);
     runs as `postgres` (explicit DELETE grant + rolbypassrls, no SECURITY DEFINER); atomicity
     + idempotency notes (single-transaction runner; NO top-level BEGIN/COMMIT; cron.unschedule
     guard + `EXCEPTION WHEN duplicate_object`).
   - **Statement 1 — schedule the daily retention cron** (idempotent DO block, `cron.unschedule`
     guard, `EXCEPTION WHEN duplicate_object`):
     ```sql
     PERFORM cron.schedule(
       'auth_flow_state_retention',
       '0 4 * * *',
       $$DELETE FROM auth.flow_state WHERE created_at < now() - interval '3 days'$$
     );
     ```
   - **Statement 2 — one-time backlog purge** (immediate verifiability; the table is tiny
     ~4.3k rows so a single in-transaction DELETE is safe — unlike 115's 28k which deferred to
     the first cron run):
     ```sql
     DELETE FROM auth.flow_state WHERE created_at < now() - interval '3 days';
     ```
2. Create `apps/web-platform/supabase/migrations/124_prune_auth_flow_state.down.sql`:
   `cron.unschedule('auth_flow_state_retention')` guarded by `IF EXISTS`. Comment that the
   one-time data deletion is irreversible by design (rows were expired/abandoned; not restorable
   and safe not to restore).

### Phase 2 — Verify (dev via CI apply, then read-only prod post-deploy)
1. Migration applies to dev automatically via `web-platform-release.yml#migrate`
   (`run-migrations.sh`, `psql --single-transaction`). Confirm apply is green and idempotent
   (re-apply is a no-op via the unschedule guard).
2. Post-deploy (prod), read-only via Supabase MCP: the discoverability query (see Observability)
   returns `flow_state` rows < 600, `prunable = 0`, and `cron.job` schedule `'0 4 * * *'`.

### Phase 3 — Record the #5739 decision
1. PR body evidence block: post-soak measurement (legitimate volume, no loop, no short-TTL
   churn) + the flow_state prune outcome (row count before/after) + explicit **JWT-TTL deferral
   rationale** (NG1) so the issue's ACs are answered with evidence. `Closes #5739`.

## Files to Create
- `apps/web-platform/supabase/migrations/124_prune_auth_flow_state.sql`
- `apps/web-platform/supabase/migrations/124_prune_auth_flow_state.down.sql`
- `knowledge-base/project/specs/feat-one-shot-5739-auth-wal-reduction-v2/tasks.md` (task breakdown)

## Files to Edit
- (none — new migration + docs only; no application code changes)

## Open Code-Review Overlap
2 open code-review issues substring-match `supabase/migrations` but neither touches this
migration's content:
- #3220 (postmerge verification of trigger-bearing migrations in prd) — **Acknowledge**:
  different concern (CI verification infra for trigger-bearing migrations generally); this
  migration adds no trigger. Remains open.
- #3221 (nightly cron for env-gated integration tests) — **Acknowledge**: CI test infra,
  unrelated to this file. Remains open.
No overlap on `auth.flow_state` / `flow_state` / `pg_cron` / `retention` in open review issues.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `124_prune_auth_flow_state.sql` schedules `auth_flow_state_retention` at `'0 4 * * *'`
      with the exact predicate `DELETE FROM auth.flow_state WHERE created_at < now() - interval '3 days'`,
      idempotent (unschedule guard + `EXCEPTION WHEN duplicate_object`), NO top-level BEGIN/COMMIT.
- [ ] The predicate interval is **≥ 24h** (assert the literal is `'3 days'`, not below the
      MAILER_OTP_EXP+FlowStateExpiry floor). `grep -c "interval '3 days'" 124_prune_auth_flow_state.sql` ≥ 1.
- [ ] `.down.sql` unschedules the job guarded by `IF EXISTS`.
- [ ] Migration applies green + re-applies as a no-op on dev (idempotency).
- [ ] PR body carries the post-soak evidence block (no-loop, legitimate-volume finding) and the
      JWT-TTL deferral rationale; PR body uses `Closes #5739`.
- [ ] No SECURITY DEFINER function introduced (postgres runs the cron directly — verified grant).

### Post-merge (operator/automated)
- [ ] After prod migrate, Supabase MCP discoverability query returns `flow_state` row count
      < 600 and `prunable (older than 3 days) = 0` (one-time purge drained the 3.7-month backlog).
      *Automation:* Supabase MCP `execute_sql` read-only — automatable inline at /ship post-deploy verify.
- [ ] `SELECT schedule FROM cron.job WHERE jobname='auth_flow_state_retention'` returns `'0 4 * * *'`.
      *Automation:* Supabase MCP read-only.
- [ ] Auth-schema WAL share **re-measured and documented as unchanged by design** (the prune is a
      bloat/disk play, not a WAL lever) — closes the issue's third AC honestly.

## Observability

```yaml
liveness_signal:
  what: cron.job_run_details shows auth_flow_state_retention succeeding
  cadence: daily 04:00 UTC
  alert_target: passive (read via Supabase MCP; no external alert wired for a p3 hygiene cron)
  configured_in: pg_cron on prod ifsccnjhymdmidffkzhl (scheduled by migration 124)
error_reporting:
  destination: cron.job_run_details (status='failed' + return_message), queryable via Supabase MCP
  fail_loud: a failed DELETE leaves rows undeleted; surfaced by the row-count discoverability query (creep back up)
failure_modes:
  - {mode: postgres loses DELETE grant on auth.flow_state after a GoTrue/platform upgrade, detection: cron.job_run_details.status='failed' with 'permission denied', alert_route: row-count creep on the discoverability query + failed-run rows}
  - {mode: predicate deletes an in-flight flow_state row (login break), detection: single-user login failure, alert_route: structurally impossible at the 3-day floor (all flow TTLs ≪ 3d) — no user-reachable path}
  - {mode: migration idempotency bug leaves the cron unscheduled, detection: SELECT from cron.job returns 0 rows for jobname, alert_route: post-deploy discoverability query}
logs:
  where: cron.job_run_details (pg_cron native); pruned after 7 days by the existing cron_job_run_details_retention job
  retention: 7 days
discoverability_test:
  command: "SELECT (SELECT count(*) FROM auth.flow_state) AS rows, (SELECT count(*) FROM auth.flow_state WHERE created_at < now() - interval '3 days') AS prunable, (SELECT schedule FROM cron.job WHERE jobname='auth_flow_state_retention') AS sched;  -- via Supabase MCP execute_sql, no ssh"
  expected_output: "rows < 600, prunable = 0, sched = '0 4 * * *'"
```

**Soak follow-through (Phase 2.9.1):** none required. Verification is **immediate** via the
Statement-2 one-time purge (row count bounded at merge time) + the scheduled-job read — there is
no N-day time-gated close criterion, so no `scripts/followthroughs/` enrollment is needed.

## Architecture Decision (ADR/C4)

**No ADR.** This applies an established, recently-merged retention-prune pattern (migrations
115 / 103 / 094) to one more unbounded table — it is pattern application, not a new
architectural decision. The one decision-shaped item (declining the JWT-TTL lever) is a
**non-change** already recorded as the issue's security rationale and sibling spec NG1; it does
not warrant a new ADR.

**### C4 views — no C4 impact.** Read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Supabase Auth
is already modeled: the `supabase` container carries `technology "Supabase Auth"` (model.c4:44)
and the `webapp -> supabase "Auth and data"` / `api -> supabase "Auth and data"` edges
(model.c4:280,334). Enumerated for this change: (a) **external human actors** — none new (no new
sender/receiver; the prune is internal DB hygiene); (b) **external systems/vendors** — none new
(Supabase already modeled; GoTrue is internal to the `supabase` container); (c) **containers /
data stores** — none new (`auth.flow_state` is an internal table of the already-modeled `supabase`
container); (d) **access relationships** — none change (`postgres → auth.flow_state` DELETE is
intra-container, below C4 element granularity). No `.c4` edit required.

## Infrastructure (IaC)

**Skipped — no new infrastructure.** This is a schema migration against the already-provisioned
Supabase project, applied by the existing `web-platform-release.yml#migrate` pipeline
(`run-migrations.sh`). No new server, secret, vendor, DNS, cert, or persistent runtime process.
The pg_cron job is scheduled *inside* the DB by the migration — it is not an external cron host.
No Terraform change.

## GDPR / Compliance (Phase 2.7)

Touches an auth-schema table → gate considered. Assessment: the change **improves** the compliance
posture — it is **data minimization** (Art. 5(1)(c) / storage limitation Art. 5(1)(e)). Abandoned
`flow_state` rows retain `provider_access_token` / `provider_refresh_token` (third-party OAuth
credentials) indefinitely; pruning expired rows removes that stale-secret retention. **No new
processing activity**, no new data collected, no lawful-basis change, no special-category data.
Advisory only; no Article 30 register entry required (bounding retention of an existing internal
table, not a new activity). CLO carry-forward: the JWT-TTL security tradeoff stays deferred (NG1).

## Domain Review

**Domains relevant:** Engineering (DB/security). Legal/GDPR touched (data-minimization positive,
handled inline above). Product/Marketing/Sales/Finance/Support/Ops: none.

### Engineering (CTO lens)
**Status:** assessed inline; deep review delegated to the **deepen-plan triad**
(data-integrity-guardian + security-sentinel + architecture-strategist), which runs next and
covers the DB-correctness, auth-security, and architecture lenses more deeply than a separate CTO
spawn would — chosen deliberately for budget discipline on a p3 (avoids double-covering
architecture-strategist). **Assessment:** low-risk pattern application; the only non-trivial risks
(grant fragility, predicate floor, migration idempotency, number collision) are enumerated in
Risks & Mitigations and gated by ACs.

### Product/UX Gate
**Tier:** none. Mechanical UI-surface scan of Files-to-Create/Edit: no path matches
`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface term. No wireframe
required (`wg-ui-feature-requires-pen-wireframe` N/A — no UI surface).

## Risks & Mitigations

- **R1 — predicate deletes an in-flight flow (login break, single-user incident).** *Mitigation:*
  3-day floor ≫ every GoTrue flow TTL (PKCE FlowStateExpiryDuration 5 min; magic-link/recovery
  MAILER_OTP_EXP 1 day). A row older than 3 days is unexchangeable by construction. AC asserts the
  `'3 days'` literal; never lower below 24h. Precedent: GoTrue's own `IsExpired()` uses `created_at`.
- **R2 — grant fragility.** `postgres`'s DELETE grant on `auth.flow_state` could be reset by a
  future Supabase/GoTrue platform upgrade. *Mitigation:* Phase 0 read-only grant re-verify before
  writing SQL; on revocation the cron simply errors (visible in `cron.job_run_details`) with **no
  data risk**. No SECURITY DEFINER today (would be the fallback only if grants tighten).
- **R3 — migration-number collision mid-pipeline.** 8+ concurrent worktrees may claim `124`.
  *Mitigation:* re-check at ship after every `git merge origin/main` per
  `2026-06-30-migration-number-collision-mid-pipeline.md`; renumber `.sql`+`.down.sql` + all
  references in one edit cycle (ship's ADR/migration collision gate).
- **R4 — retention window exceeds table age (silent DELETE 0).** *Mitigation:* N/A here — oldest
  row is 3.7 months vs a 3-day window; the first run deletes ~4.1k rows. (Guard against the
  `2026-06-14-pg-cron-retention-window-exceeding-table-age` failure mode by construction.)
- **R5 — over-claiming a WAL win.** *Mitigation:* PR framed as bloat/dead-tuple + stale-secret
  minimization; auth WAL share documented as unchanged by design (Phase 3).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 —
  this one is filled (single-user incident).
- **Migration 124 is provisional.** Re-verify the free number at ship; renumber both files + all
  in-file/plan/tasks references together on collision.
- **Coordination with sibling PR #5762:** this v2 PR `Closes #5739`; #5762 is a superseded WIP
  draft on `feat-5739-auth-wal-reduction`. Recommend the operator/ship **close #5762 as
  superseded** (`gh pr close 5762 --comment "superseded by #<v2>"`) — but **do NOT delete the
  branch/worktree** (operator instruction). Not mandated by /work; surfaced for ship/operator.
- Do NOT wrap the migration body in a top-level `BEGIN;`/`COMMIT;` — `run-migrations.sh` already
  runs `--single-transaction`; a self-issued COMMIT breaks ledger idempotency
  (`2026-05-25-migration-body-no-top-level-begin-commit.md`).

## Non-Goals
- **NG1 — Lengthen JWT/access-token TTL.** Deferred. Widens the token-revocation window
  (sign-out / ban / `user-set-role` demotion don't take effect until expiry) for ~zero user-facing
  ROI at p3, and the measurement shows no short-TTL refresh churn to fix. Revisit only on measured
  need with recorded CLO sign-off (baseline TTL + chosen TTL + revocation-window acceptance +
  rollback trigger + CLO attestation). Security rationale recorded per the issue's ACs.
- **NG2 — Prune active/in-flight `flow_state` rows.** Would break live magic-link/OAuth/MFA logins.
  The 3-day floor is the guard.
- **NG3 — Checkpoint tuning (`max_wal_size`/`checkpoint_timeout`).** Not operator-tunable on
  Supabase Micro (managed).
- **NG4 — Any change to `refresh_tokens` / `sessions` / `mfa_amr_claims` churn.** Legitimate,
  irreducible login volume; not a defect.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Ship the flow_state expired-row prune (this plan) | **Chosen** | Concrete, low-risk, security+bloat win; mirrors merged 115/103 pattern. |
| Close #5739 as no-actionable-WAL-work | Rejected | Under-delivers: flow_state bloat + 3.7-month stale-OAuth-token retention IS actionable; one-shot pipeline expects a merged deliverable. |
| Lengthen JWT TTL to cut refresh churn | Rejected (NG1) | Security tradeoff, CLO sign-off, ~zero ROI at p3, no measured churn to fix. |
| Checkpoint / WAL config tuning | Rejected (NG3) | Not tunable on managed Micro. |
| SECURITY DEFINER function owned by `supabase_auth_admin` | Rejected (unnecessary) | `postgres` already has explicit DELETE + rolbypassrls; plain cron.schedule works. |

## Test Scenarios
1. **Idempotency:** apply 124 twice on dev → second apply is a no-op (unschedule guard); job
   exists exactly once.
2. **Predicate safety:** on dev, insert a synthetic `flow_state` row with `created_at = now()`
   (in-window) and one with `created_at = now() - interval '4 days'` (out-of-window); run the cron
   body → only the 4-day row is deleted; the fresh row survives. (Synthetic fixtures on DEV only —
   `hr-dev-prd-distinct-supabase-projects`; never seed prod.)
3. **Backlog drain:** post-apply prod (read-only) → `prunable (older than 3 days) = 0`.
4. **Down migration:** apply `.down.sql` → `cron.job` has 0 rows for `auth_flow_state_retention`.
