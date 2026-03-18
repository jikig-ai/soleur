# Tasks: fix NOT NULL iv and auth_tag

## Phase 1: Implementation

- [ ] 1.1 Create migration file `apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql`
  - [ ] 1.1.1 Add safety check: DO block that raises exception if null rows exist
  - [ ] 1.1.2 Add ALTER TABLE statements to set NOT NULL on `iv` and `auth_tag`

## Phase 2: Verification

- [ ] 2.1 Run `bun test` to verify existing BYOK tests pass
- [ ] 2.2 Verify migration SQL syntax is valid (no parse errors)

## Phase 3: Ship

- [ ] 3.1 Run compound (`skill: soleur:compound`)
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR with `Closes #681` in body, set `semver:patch` label
