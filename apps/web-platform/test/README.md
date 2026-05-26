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

## Engine-floor guard (pdfjs-dist)

Three suites — `pdf-text-extract.test.ts`, `pdf-text-extract.bundled-server.test.ts`, and `kb-preview-metadata.bundled-server.test.ts` — use the shared helper `helpers/engines-floor.ts` to short-circuit on Node <22.3 (the pdfjs-dist@5 floor enforced by `process.getBuiltinModule`). Dev path: `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)` + a single stderr diagnostic per file (yellow skip, never silent). CI path: the helper throws at module init when `process.env.CI` is set, so a misconfigured runner cannot ship a vacuous green. The lazy_import_failed test sits OUTSIDE the skipIf block — `vi.doMock` short-circuits the real pdfjs import so it runs on all Node versions.
