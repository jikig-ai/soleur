# Web Platform Test Suite

This directory holds the unit + integration test files for the web platform. Test runner: `vitest`. Most tests are gated behind their own opt-in env flag because the integration suites mutate the real Supabase `dev` project and require Doppler-provided credentials.

## Integration tests (opt-in)

| Test file | Env flag | Purpose |
|---|---|---|
| `byok.integration.test.ts` | `BYOK_INTEGRATION_TEST=1` | Per-tenant ciphertext isolation against the real `api_keys` table + crypto round-trip. |
| `beta-crm-dsar.integration.test.ts` | `SUPABASE_DEV_INTEGRATION=1` | Beta-CRM DSAR flows against the shared dev project. |
| `cc-dispatcher-cross-tenant.integration.test.ts` | `SUPABASE_DEV_INTEGRATION=1` | Command-center dispatcher cross-tenant isolation. |
| `conversations-rail-cross-tenant.integration.test.ts` | `SUPABASE_DEV_INTEGRATION=1` | User A's `command-center` Realtime subscription receives ZERO `postgres_changes` payloads from user B's INSERT/UPDATE/DELETE on `conversations`. Load-bearing case is DELETE (bypasses RLS by Postgres design). |
| `dsar-author-redaction.integration.test.ts` | `SUPABASE_DEV_INTEGRATION=1` | DSAR author-redaction against dev. |
| `dsar-export-cross-tenant.integration.test.ts` | `SUPABASE_DEV_INTEGRATION=1` | DSAR export cross-tenant isolation. |
| `server/conversation-visibility.tenant-isolation.test.ts` | `SUPABASE_DEV_INTEGRATION=1` | Dual-predicate visibility RLS (mig 075) + `set_conversation_visibility` SECURITY DEFINER RPC: owner-only writes, workspace-shared reads, cross-workspace deny. Asserts the **RLS-effective** write contract, not the column-level REVOKE (a no-op against any real Supabase project — see the test's AC8 `SOLEUR-DEBT` note). |
| `worktree-write-lease.integration.test.ts` | `WORKTREE_LEASE_INTEGRATION_TEST=1` | Worktree write-lease acquire/release against dev. |
| `concurrency-acquire-slot-workspace-id.integration.test.ts` | `ACQUIRE_SLOT_WS_INTEGRATION_TEST=1` | Workspace-id slot acquisition concurrency. |
| `conversation-archive-release-slot.integration.test.ts` | `SLOT_TRIGGER_INTEGRATION_TEST=1` | Archive-trigger slot release against dev. |
| `workspace-binding-restart-survival.integration.test.ts` | `WORKSPACE_BINDING_INTEGRATION_TEST=1` | Workspace binding survives restart. |
| `mu1.integration.test.ts` | `MU1_INTEGRATION=1` | MU1 signup→clone path; AC-2 mints a live GitHub App installation token + clones the fixture repo (requires `MU1_FIXTURE_*` + `GITHUB_APP_*`). |
| `dsar-departed-member.integration.test.ts` | `TENANT_INTEGRATION_TEST=1` | Departed-member DSAR; lives at `test/` root, so it runs in the scheduled leg — NOT in `tenant-integration.yml`'s `test/server/` leg. |
| `server/**/*.tenant-isolation.test.ts` + other `test/server/` files | `TENANT_INTEGRATION_TEST=1` | The ~38-file tenant-isolation family, run per-PR by `tenant-integration.yml` over the `test/server/` dir filter. |

> **Two env-flag conventions (historical).** `SUPABASE_DEV_INTEGRATION=1` gates the suites above; the broader `*.tenant-isolation.test.ts` family (~55 suites) gates on `TENANT_INTEGRATION_TEST=1`. Both exist; neither was renamed. Set whichever a given file reads (the file's header docstring states it), or set both when running a mixed batch.

> **Run behavioral suites against a DEDICATED, freshly-migrated Supabase project — NOT the shared `dev` project.** The shared `dev` project accumulates manual dashboard state and partial-teardown cruft, and its grant state can diverge from the migration files (e.g. Supabase's blanket `GRANT ALL ON public.<table> TO authenticated` silently subsumes a targeted column `REVOKE`). Assertions that depend on exact grant/trigger/FK state — and the mass synthetic-user create/delete these suites perform — are only reliable on a clean replica. This mirrors the guidance already documented in `test/supabase-migrations/079-workspace-rls-isolation.test.ts`. GoTrue's per-IP/per-email rate limits and the opaque "Database error deleting user" transient are absorbed by `helpers/gotrue-retry.ts` (`withGoTrueRetry`) **at the wrapped call sites** — the shared-workspace fixture's create/delete (`helpers/workspace-members-fixtures.ts`), `tearDownTenantUser`'s delete (`helpers/tenant-isolation-teardown.ts`), and the conversation-visibility sign-ins. Suites that mint users via a direct inline `auth.admin.createUser` loop in their own `beforeAll` are NOT yet wrapped, so a dedicated, freshly-migrated project remains the correct substrate for a deterministic full-batch run.

### Running

All integration tests require `doppler run -p soleur -c dev --` to provide `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`. From `apps/web-platform`:

```bash
# BYOK isolation
doppler run -p soleur -c dev -- env BYOK_INTEGRATION_TEST=1 \
  ./node_modules/.bin/vitest run test/byok.integration.test.ts

# Cross-tenant Realtime isolation (Phase 5b for feat-command-center-conversation-nav)
doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1 \
  ./node_modules/.bin/vitest run test/conversations-rail-cross-tenant.integration.test.ts

# Conversation visibility RLS + RPC (mig 075)
doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1 \
  ./node_modules/.bin/vitest run test/server/conversation-visibility.tenant-isolation.test.ts
```

CI without the env flag runs the suite with `it.skipIf(...)` short-circuiting these files cleanly. Operators MUST run the cross-tenant suite locally before marking the rail PR ready — it's the merge-gate per the plan's HARD ACCEPTANCE CRITERION.

### CI wiring

`.github/workflows/scheduled-integration-suites.yml` runs every env-gated suite in this table nightly at 04:30 UTC (`workflow_dispatch`-able), inside the dev-suite mutex on the **shared dev project**, after applying merged migrations. It exports all eight gates: `SUPABASE_DEV_INTEGRATION`, `WORKTREE_LEASE_INTEGRATION_TEST`, `ACQUIRE_SLOT_WS_INTEGRATION_TEST`, `BYOK_INTEGRATION_TEST`, `SLOT_TRIGGER_INTEGRATION_TEST`, `WORKSPACE_BINDING_INTEGRATION_TEST`, `MU1_INTEGRATION`, and `TENANT_INTEGRATION_TEST` (for `dsar-departed-member` only — the rest of that family runs per-PR in `tenant-integration.yml`). A red leg files or comments a `ci/integration-suites` GitHub issue naming the failing step; a green one auto-closes the stale tracker; a missed run pages the `scheduled-integration-suites` Sentry cron monitor.

**Shared-dev substrate vs. the dedicated-project guidance above.** The dedicated-project paragraph remains the correct advice for *deterministic local full-batch runs*. The scheduled leg deliberately runs on shared dev — the substrate `tenant-integration.yml`'s ~55 suites already use (ADR-061 substrate; ADR-023's Free-tier quota has both projects allocated) — accepting grant/cruft divergence in exchange for exercising the real dev state migrations actually land on. **Revisit trigger:** two consecutive `ci/integration-suites` filings attributable to substrate cruft (not a product defect) → re-evaluate a dedicated project. The dormancy guard `scripts/lint-integration-env-gates.sh` (advisory step in `lint-bot-statuses`, registered in `scripts/test-all.sh`) keeps this table honest: any new `process.env.X === "1"` gate that no workflow sets — or whose file no workflow collects — fails it.

### Synthetic email allowlist

Both integration tests use a per-suite synthetic email pattern (e.g. `conv-rail-cross-tenant-[a-f0-9]{16}@soleur.test`). Hard rule `hr-destructive-prod-tests-allowlist` forbids these tests from touching any non-synthetic account.

### Teardown contract (required for new suites)

Every suite that creates synthetic auth users MUST tear them down through `tearDownTenantUser` (`test/helpers/tenant-isolation-teardown.ts`) — never a raw `service.auth.admin.deleteUser`. The trigger-created `workspace_members` rows are `ON DELETE RESTRICT`, so a raw call 500s deterministically (#9994) or leaks the user if the `{error}` result is ignored. Contract for a new suite:

1. Emit emails as `<prefix>-<16 lowercase hex>@soleur.test` (`randomBytes(8).toString("hex")`).
2. Register the prefix in `SYNTHETIC_PREFIXES` in the helper — it is fail-closed and refuses anything outside the allowlist.
3. Call `tearDownTenantUser(service, { id, email })` in `afterAll` — it runs the parity-guarded 22-RPC anonymise cascade, verifies the id↔email binding against `auth.users`, then deletes.

`test/server/teardown-deleteuser-sentinel.test.ts` censuses every `.ts` file under `test/` for deleteUser call shapes: any carrier outside the canonical helper, the reviewed `MANUAL_TEARDOWN_ALLOWLIST`, or the #10096 legacy drain set fails the always-on shard — and the per-file call counts are pinned, so adding a raw call inside an allowlisted file fails too.

## Engine-floor guard (pdfjs-dist)

Three suites — `pdf-text-extract.test.ts`, `pdf-text-extract.bundled-server.test.ts`, and `kb-preview-metadata.bundled-server.test.ts` — use the shared helper `helpers/engines-floor.ts` to short-circuit on Node <22.3 (the pdfjs-dist@5 floor enforced by `process.getBuiltinModule`). Dev path: `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)` + a single stderr diagnostic per file (yellow skip, never silent). CI path: the helper throws at module init when `process.env.CI` is set, so a misconfigured runner cannot ship a vacuous green. The lazy_import_failed test sits OUTSIDE the skipIf block — `vi.doMock` short-circuits the real pdfjs import so it runs on all Node versions.
