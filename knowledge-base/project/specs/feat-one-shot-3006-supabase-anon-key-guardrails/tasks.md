# Tasks — anon-key build-arg guardrails (issue #3006)

Generated from `knowledge-base/project/plans/2026-04-28-fix-supabase-anon-key-guardrails-plan.md`.

## Status

- [x] Phase 2 — RED: write failing tests for anon-key validator (18 cases)
- [x] Phase 3 — GREEN: create `validate-anon-key.ts`, wire into `client.ts`, all 18 tests pass; blast-radius gate held (4 fixture test files green)
- [x] Phase 4 — Add CI Validate step in `.github/workflows/reusable-release.yml`
- [x] Phase 5 — Mirror JWT check in `apps/web-platform/scripts/verify-required-secrets.sh`
- [x] Phase 6 — Extend Preflight Check 5 (path-gate + Step 5.4)
- [x] Phase 7 — Compound learning file + spec.md + tasks.md
- [ ] Phase 8 — Pre-merge verification (review, QA, ship)

## Acceptance Criteria

- [x] AC1 — CI step inserted after URL Validate, before docker/build-push-action
- [x] AC2 — Asserts iss/role/ref/cross-check
- [x] AC3 — `verify-required-secrets.sh` JWT block added
- [x] AC4 — `validate-anon-key.ts` exists with `assertProdSupabaseAnonKey`
- [x] AC5 — `client.ts` calls validator at module load
- [x] AC6 — 18-case test file (incl. CR-terminated case) passes
- [x] AC7 — Full app test suite green; 4 anon-key-fixture files unaffected
- [x] AC8 — Preflight Check 5 includes Step 5.4 + path-gate covers `validate-anon-key.ts`
- [x] AC9 — New learning file written
- [x] AC10 — spec.md + tasks.md exist
- [ ] AC11 — PR body has User-Brand Impact + Closes #3006 + Ref #2980 (handled in /ship)
- [ ] AC12 — actionlint passes (handled in CI on push)
- [ ] AC13–AC16 — Post-merge operator gates
