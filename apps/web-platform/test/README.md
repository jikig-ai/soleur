# Web Platform Test Suite

This directory holds the unit + integration test files for the web platform. Test runner: `vitest`. Most tests are gated behind their own opt-in env flag because the integration suites mutate the real Supabase `dev` project and require Doppler-provided credentials.

## Integration tests (opt-in)

| Test file | Env flag | Purpose |
|---|---|---|
| `byok.integration.test.ts` | `BYOK_INTEGRATION_TEST=1` | Per-tenant ciphertext isolation against the real `api_keys` table + crypto round-trip. |
| `conversations-rail-cross-tenant.integration.test.ts` | `SUPABASE_DEV_INTEGRATION=1` | User A's `command-center` Realtime subscription receives ZERO `postgres_changes` payloads from user B's INSERT/UPDATE/DELETE on `conversations`. Load-bearing case is DELETE (bypasses RLS by Postgres design). |

### Running

All integration tests require `doppler run -p soleur -c dev --` to provide `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`. From `apps/web-platform`:

```bash
# BYOK isolation
doppler run -p soleur -c dev -- env BYOK_INTEGRATION_TEST=1 \
  ./node_modules/.bin/vitest run test/byok.integration.test.ts

# Cross-tenant Realtime isolation (Phase 5b for feat-command-center-conversation-nav)
doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1 \
  ./node_modules/.bin/vitest run test/conversations-rail-cross-tenant.integration.test.ts
```

CI without the env flag runs the suite with `it.skipIf(...)` short-circuiting these files cleanly. Operators MUST run the cross-tenant suite locally before marking the rail PR ready — it's the merge-gate per the plan's HARD ACCEPTANCE CRITERION.

### Synthetic email allowlist

Both integration tests use a per-suite synthetic email pattern (e.g. `conv-rail-cross-tenant-[a-f0-9]{16}@soleur.test`). Hard rule `hr-destructive-prod-tests-allowlist` forbids these tests from touching any non-synthetic account.
