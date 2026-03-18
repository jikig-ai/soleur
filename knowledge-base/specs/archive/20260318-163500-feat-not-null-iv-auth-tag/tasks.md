# Tasks: fix NOT NULL iv and auth_tag

## Phase 1: Implementation

- [ ] 1.1 Create migration file `apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql`
  - [ ] 1.1.1 Add header comment documenting purpose, locking behavior, and idempotency
  - [ ] 1.1.2 Add DO block safety check that raises exception if null `iv` or `auth_tag` rows exist
  - [ ] 1.1.3 Add ALTER TABLE with `ALTER COLUMN iv SET NOT NULL, ALTER COLUMN auth_tag SET NOT NULL`
  - Note: SET NOT NULL is naturally idempotent in PostgreSQL (no-op if already constrained)
  - Note: Supabase wraps each migration in a transaction, so DO block + ALTER are atomic

## Phase 2: Verification

- [ ] 2.1 Run `bun test` to verify existing BYOK round-trip tests pass (no regression)
- [ ] 2.2 Verify migration SQL syntax is valid (no parse errors)

## Phase 3: Ship

- [ ] 3.1 Run compound (`skill: soleur:compound`)
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR with `Closes #681` in body, set `semver:patch` label
