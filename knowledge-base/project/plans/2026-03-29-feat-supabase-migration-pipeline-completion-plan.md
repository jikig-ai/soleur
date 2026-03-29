---
title: "feat: complete Supabase migration pipeline with rollback docs and hardening"
type: feat
date: 2026-03-29
---

# feat: complete Supabase migration pipeline with rollback docs and hardening

## Overview

Close issue #682 by addressing the one remaining acceptance criterion -- rollback procedure documentation -- and hardening the existing migration pipeline with deploy-condition fixes discovered during post-implementation CI runs.

The core migration runner (`run-migrations.sh`) and CI integration (`web-platform-release.yml` migrate job) were implemented in PR #1249 and patched in PRs #1276, #1277, #1278. Three of four acceptance criteria are already met. This plan covers the remaining gap and final verification.

## Problem Statement

Issue #682 requires four acceptance criteria:

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Migrations run automatically on deploy or merge | Done | `migrate` job in `web-platform-release.yml` |
| 2 | Migration failures block deployment | Done | `deploy` needs `[release, migrate]` with failure guard |
| 3 | Migration state is tracked (no double-execution) | Done | `_schema_migrations` table + idempotent runner |
| 4 | Rollback procedure documented | **Missing** | No rollback docs exist |

The existing plan (2026-03-28) noted "forward-only" as a deliberate simplification but did not produce a formal rollback procedure document. The original issue explicitly requires this.

## Proposed Solution

### 1. Rollback Procedure Documentation

Create `apps/web-platform/docs/migration-rollback.md` with:

- **Forward-only principle**: Explain that automated rollback is not supported and why (PostgreSQL DDL in transactions makes failed migrations safe -- they roll back automatically, so the only scenario requiring manual intervention is a *successfully applied* migration that needs reversal)
- **Manual rollback procedure**: Step-by-step instructions for reversing a specific migration using `psql` + Doppler
- **Tracking table cleanup**: How to remove a migration record from `_schema_migrations` after manual rollback
- **Emergency procedure**: How to block deploy while fixing a migration (cancel the workflow run, or push a fix that removes the broken migration file)
- **Prevention patterns**: How to write migrations that are safe to reverse (use `IF EXISTS`/`IF NOT EXISTS` guards, avoid destructive DDL without backups)

### 2. Deploy Condition Fix

The current `deploy` job condition in `web-platform-release.yml` uses:

```yaml
if: >-
  always() &&
  needs.release.outputs.version != '' &&
  (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
  (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

This is correct -- it blocks deploy on migration failure while allowing deploy when migrate is skipped (no version bump). Verify this matches the merged state and no regressions exist from recent patches.

### 3. Bootstrap List Update

The bootstrap seed list in `run-migrations.sh` currently includes migrations 001-010. Migration `011_repo_connection.sql` exists in the repo. Verify whether 011 has been applied to production and if the bootstrap list needs updating. If 011 was applied via the automated runner (not manually), the bootstrap list is correct as-is (it only needs to cover pre-runner migrations).

## Technical Considerations

### Rollback Scope

PostgreSQL supports transactional DDL -- `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE` all roll back cleanly within a transaction. The `--single-transaction` flag in `run-migrations.sh` ensures failed migrations leave no partial state. The only rollback scenario that requires documentation is:

1. A migration applies successfully
2. The deployed code reveals it was wrong
3. The migration needs to be manually reversed

This is rare but must be documented per the acceptance criteria.

### Security

No new secrets or credentials required. The rollback procedure uses existing `DATABASE_URL` from Doppler `prd` config.

## Acceptance Criteria

- [x] `apps/web-platform/docs/migration-rollback.md` exists with complete rollback procedure
- [x] Rollback procedure covers: manual reversal, tracking table cleanup, emergency deploy blocking
- [x] All four original issue #682 acceptance criteria are verified met
- [x] `web-platform-release.yml` deploy condition correctly blocks on migration failure

## Test Scenarios

- Given the rollback documentation exists, when a developer reads it, then they can follow step-by-step instructions to reverse a migration using `psql` and update `_schema_migrations`
- Given a migration has been applied to production, when the rollback procedure is followed, then the schema change is reversed and the tracking table no longer lists the migration
- Given the `migrate` job fails, when CI evaluates the `deploy` job, then `deploy` is skipped (verified by checking recent workflow runs)
- Given all migrations are already applied, when the migration runner executes, then it reports "0 applied" and exits successfully (idempotency)

### Integration Verification

- **Workflow verify:** `gh run view <latest-success-id> --json jobs` shows `release -> migrate -> deploy` chain all succeeded
- **DB verify:** Query `_schema_migrations` table to confirm all migrations (001-011) are recorded
- **Doc verify:** `apps/web-platform/docs/migration-rollback.md` exists and passes markdownlint

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change completing an existing CI pipeline. No user-facing changes, no legal/marketing/product impact.

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `apps/web-platform/docs/migration-rollback.md` | Create | Rollback procedure documentation |
| `.github/workflows/web-platform-release.yml` | Verify | Confirm deploy condition is correct (no changes expected) |
| `apps/web-platform/scripts/run-migrations.sh` | Verify | Confirm bootstrap list is correct (no changes expected) |

## Dependencies and Risks

### Dependencies

- Access to verify `_schema_migrations` table state via Doppler + psql (already available)
- Existing `DOPPLER_TOKEN_PRD` GitHub Actions secret (already configured)

### Risks

| Risk | Mitigation |
|------|-----------|
| Rollback docs become stale | Reference the docs from the migration runner script header comment |
| Bootstrap list missing a migration | Query `_schema_migrations` to verify all files are tracked |

## References

- GitHub issue: #682
- Prior plan: `knowledge-base/project/plans/2026-03-28-feat-automated-database-migration-runner-plan.md`
- Implementation PR: #1249
- Follow-up fixes: #1276 (Doppler token scope), #1277 (IPv4 pooler), #1278 (psql variable interpolation)
- Learning: `knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md`
- Learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Migration runner: `apps/web-platform/scripts/run-migrations.sh`
- Workflow: `.github/workflows/web-platform-release.yml`
