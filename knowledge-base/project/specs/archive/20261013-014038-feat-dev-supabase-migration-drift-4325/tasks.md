---
issue: 4325-followup
spec: knowledge-base/project/specs/feat-dev-supabase-migration-drift-4325/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-22-dev-supabase-drift-deltas-4325-brainstorm.md
brand_survival_threshold: single-user incident
---

# Tasks: dev-Supabase drift forward hardening

## Delta 3 design decision (made at tasks-time, not plan-time)

**Chosen shape:** forward-only migration `064_idempotent_recovery_guards.sql`. Adds `DROP IF EXISTS` guards for the surviving constructs the learning calls out (mig 058's `attestations_select_for_members` policy + `workspace_members_attestation_id_fkey` constraint; mig 060's `user_session_state_owner_select` policy). The guards are no-ops when applied to a healthy schema — only fire on Branch-A recovery re-apply chains.

**Why forward-only over helper-function convention:**
- Helper-function would be a NEW substrate that future migration authors must learn + adopt; lint enforcement comes separately
- Forward-only leverages existing one-file-per-increment migration discipline; reviewers already know how to read it
- Smaller blast radius — touches `_schema_migrations` ledger + 3 policy/constraint objects, nothing else
- The existing brainstorm's "Delta 3" spec line says forward-only is option (a); we pick it

## Task order

Ordering by risk + dependency:

1. **T1 (Delta 4):** Flip `MIGRATION_SCHEMA_PRECONDITION_PROBE` default to 1 in `apps/web-platform/scripts/run-migrations.sh`. Update `apps/web-platform/scripts/run-migrations-schema-probe.test.sh` to assert new default + add opt-out test. One-line code change. Smallest blast radius — ship first to anchor the PR.

2. **T2 (Delta 3):** Add `apps/web-platform/supabase/migrations/064_idempotent_recovery_guards.sql` (forward + down). Idempotent guards for the 3 partial-apply survivors. Add `to_regclass` precondition per FR1 pattern (eats own dogfood). Verify it applies cleanly against current dev schema state.

3. **T3 (Delta 2):** Write `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`. Scan new migration files (PR diff filter) for cross-file `REFERENCES public.<table>` without preceding `to_regclass` `RAISE EXCEPTION` block. Self-FK exclusion via same-file `CREATE TABLE` subtraction. Test via `apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh` (3 cases: negative, positive, self-FK).

4. **T4 (Delta 2 wiring):** Wire T3's lint into `.github/workflows/tenant-integration.yml` as a new step BEFORE the migrate step. Must NOT run on `web-platform-release.yml#migrate` (production path).

5. **T5:** Run `apps/web-platform/scripts/run-migrations.sh` locally via Doppler-dev to verify mig 064 applies cleanly. Confirm via `/tmp/pg-runner/inspect.mjs` the ledger has a 064 row with content_sha + the policy/constraint are intact.

6. **T6:** Push, mark PR #4354 ready, run review + ship per one-shot pipeline.

## Acceptance gates (inherited from spec)

- **AC1 (proof of dev recovery):** Already met — `/tmp/pg-runner/inspect.mjs` captured in #4325 close comment.
- **AC2 (lint synthetic test):** Covered by T3.
- **AC3 (probe opt-out documented):** Covered by T1's test update.
- **AC4 (forward-only mig applies):** Covered by T5.
- **AC5 (#4325 closed):** Already done.

## Sharp edges (inherited)

1. T2's mig 064 MUST NOT modify 053/058/060 in place. Add guards as a new migration only.
2. T4 must not affect `web-platform-release.yml#migrate` — production migrate is unguarded by intent (prd applies are end-to-end).
3. T3's lint regex matches `run-migrations.sh:282-287`'s convention — uppercase DDL, lowercase `public.`-qualified. Dynamic SQL / quoted identifiers bypass; documented as best-effort.
4. T5 must use Doppler `dev` config, NOT `dev_personal` (different DB). The `inspect.mjs` script connects via `DATABASE_URL_POOLER`-with-`:5432`-substitution per existing pattern.
