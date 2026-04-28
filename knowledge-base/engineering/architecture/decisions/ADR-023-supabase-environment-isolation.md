---
adr: ADR-023
title: Supabase Environment Isolation (dev / prd Separate Projects)
status: active
date: 2026-04-27
---

# ADR-023: Supabase Environment Isolation (dev / prd Separate Projects)

## Context

Until 2026-04-27, the Doppler `soleur/dev` and `soleur/prd` configs both
held connection strings pointing to the **same Supabase project**
(`ifsccnjhymdmidffkzhl.supabase.co`). Discovered during ship of PR
#2858, when a stale `DATABASE_URL` password in `prd` made the migrate
job fail and investigation revealed the two configs target the
identical project ref.

Operationally this meant:

- Every dev migration, fixture, integration test, and ad-hoc query has
  been executing against the user-facing production database.
- The migration "rehearsal" pattern (apply to dev first, verify, then
  prd) was a silent no-op — the dev step wrote to prd.
- A leak of any dev-scoped credential (laptop compromise, committed
  `.env`, agent prompt injection) reads or writes prod rows.
- Defensive guards meant to gate destructive cleanup (`mu1-cleanup-guard.mjs`)
  validated that the URL pointed at the "dev" project ref — but the
  expected ref *was* the prod ref, so the guard accepted prod as dev.

Given Soleur's brand promise ("the agent that compounds your team's
knowledge"), a single user-data exposure incident is brand-ending. The
shared-DB state was a P0 security invariant violation, tracked as
issue #2887.

## Decision

Adopt the **two-project isolation model** for the Soleur Supabase
deployment:

| Doppler config | Supabase project ref       | Purpose                          |
|----------------|----------------------------|-----------------------------------|
| `soleur/dev`   | `soleur-dev` (new)         | Local dev, integration tests, migration rehearsal |
| `soleur/prd`   | `ifsccnjhymdmidffkzhl`     | User-facing production            |

The two projects:

- Have distinct `DATABASE_URL` hosts and distinct service-role keys.
- Receive the same migration sequence, applied dev-first via
  `apps/web-platform/scripts/run-migrations.sh`.
- Are both Free-tier (the org's 2-project quota covers both — no
  incremental spend).

**Rejected alternatives:**

- *Supabase branching (preview branches)* — Pro-plan-only and
  preview-oriented; not the right tool for permanent dev/prd split.
- *Single project with `dev` schema (`search_path` per env)* — same
  blast radius; schema-scoped roles can be misconfigured and
  migrations apply to whichever schema `search_path` points at.
- *Single project with `dev_*` table prefixes* — migration runner is
  filename-driven, not schema-aware; massive churn.
- *Local Postgres in Docker for dev* — diverges from Supabase-specific
  features (auth, RLS, Realtime); tests miss Supabase-specific
  behaviors.

**Staging deferred.** A third project (`soleur-staging`) for
Pro-plan-style multi-stage rollout is tracked in #2910 (milestone:
Post-MVP / Later) and deferred. The dev/prd split is the load-bearing
fix.

The isolation model is enforced at four layers, in order of precedence:

1. **AGENTS.md hard rule** — `hr-dev-prd-distinct-supabase-projects`
   declares the invariant and is loaded on every agent turn.
2. **Preflight Check 4 (`Environment Isolation`)** — runs on every
   `/ship`, dereferences custom-domain CNAMEs, and FAILs if dev and
   prd resolve to the same project ref. Defends against
   subdomain-bypass via canonical-hostname regex
   (`^[a-z0-9]{20}\.supabase\.co$`).
3. **Strengthened `wg-when-a-pr-includes-database-migrations`** —
   migrations must be applied to dev FIRST, then prd, cross-referencing
   the hard rule so runbook and AGENTS rule reinforce each other.
4. **`mu1-cleanup-guard.mjs` `DEV_PROJECT_REF` constant** — refuses
   destructive synthetic-user cleanup unless the active
   `NEXT_PUBLIC_SUPABASE_URL` matches the dev project's exact
   hostname. This guard was a no-op while dev=prd; it begins doing
   its job once the projects diverge.

## Consequences

**Positive:**

- Dev creds compromise no longer reaches prod data.
- Migration rehearsal restored; dev-first apply detects schema bugs
  before they reach users.
- Reference architecture for Soleur plugin users: when customers wire
  their own Doppler configs, the plugin's own deployment models the
  invariant.
- Privacy posture improves — no PII migration occurs (new dev project
  starts empty); the existing prd data is unaffected.

**Negative / costs:**

- 2x project resource usage in Supabase. Free tier covers it; if prd
  upgrades to Pro for custom domain or branching, dev stays Free.
- Operator overhead: rotating one project's password no longer rotates
  the other's. Doppler `dev` and `prd` are independent; password
  managers must track both.
- Bootstrap-trap during the one-time provisioning: the migration
  runner assumes migrations 001–010 are pre-existing on a non-empty
  `_schema_migrations` table. Documented in #2911 (run-migrations.sh
  `--bootstrap=skip` flag).

**Operational sequence (post-merge):** see plan §Acceptance Criteria
in `knowledge-base/project/plans/2026-04-27-fix-supabase-env-isolation-plan.md`
for the full operator checklist (provision project, apply migrations,
rotate 6 Doppler keys, audit `ci` config, update
`mu1-cleanup-guard.mjs` `DEV_PROJECT_REF` in a follow-up PR, close
#2887).

## Cross-references

- Issue: #2887 (P0 single-DB blast radius)
- Discovery: PR #2858 ship Phase 7 migrate-job failure
- Plan: `knowledge-base/project/plans/2026-04-27-fix-supabase-env-isolation-plan.md`
- Follow-up issues: #2910 (staging Supabase project), #2911
  (`run-migrations.sh --bootstrap=skip` flag)
- Adjacent learnings:
  - `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md`
    (subdomain-bypass guard pattern reused in preflight Check 4)
  - `2026-03-29-doppler-service-token-config-scope-mismatch.md`
    (token-scope rule that scoped tokens but not data)
  - `2026-03-28-unapplied-migration-command-center-chat-failure.md`
    (silent migration failure mode the dev-first ordering prevents)
- External: <https://supabase.com/docs/guides/deployment/managing-environments>
- Related ADRs: ADR-006 (Terraform remote backend), ADR-007 (Doppler
  secrets management) — together with this ADR establish the
  configuration plane: infra in Terraform, secrets in Doppler with
  config-distinct project bindings.
