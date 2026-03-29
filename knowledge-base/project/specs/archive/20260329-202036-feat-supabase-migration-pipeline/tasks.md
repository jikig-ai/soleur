# Tasks: Complete Supabase Migration Pipeline

## Phase 1: Verification

- [x] 1.1 Verify `web-platform-release.yml` deploy condition matches expected pattern
- [x] 1.2 Query `_schema_migrations` table to confirm all migrations (001-011) are tracked
- [x] 1.3 Verify migration `011_repo_connection.sql` was applied by the automated runner (not bootstrap)

## Phase 2: Rollback Documentation

- [x] 2.1 Create `apps/web-platform/docs/migration-rollback.md`
  - [x] 2.1.1 Document forward-only principle and rationale
  - [x] 2.1.2 Document manual rollback step-by-step procedure
  - [x] 2.1.3 Document `_schema_migrations` tracking table cleanup
  - [x] 2.1.4 Document emergency deploy blocking procedure
  - [x] 2.1.5 Document migration writing best practices (IF EXISTS guards)
- [x] 2.2 Add reference to rollback docs in `run-migrations.sh` header comment
- [x] 2.3 Run markdownlint on new docs

## Phase 3: Final Verification and Closure

- [x] 3.1 Verify all four #682 acceptance criteria are met
- [ ] 3.2 Run compound to capture learnings
- [ ] 3.3 Ship PR with `Closes #682` in body
