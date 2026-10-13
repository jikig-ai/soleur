---
title: PR-C — Sibling-query migration (#3244 §2)
date: 2026-05-15
status: planned
plan: knowledge-base/project/plans/2026-05-15-feat-pr-c-sibling-query-migration-plan.md
tasks: knowledge-base/project/specs/feat-runtime-slice-3244/tasks.md
umbrella_issue: 3244
predecessor_prs: [3240, 3395]
umbrella_spec: knowledge-base/project/specs/feat-agent-runtime-platform/spec.md
umbrella_tasks: knowledge-base/project/specs/feat-agent-runtime-platform/tasks.md
brand_survival_threshold: single-user incident
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-05-15-pr-c-sibling-query-migration-brainstorm.md
---

# PR-C — Sibling-query migration

## Problem Statement

PR-B (#3395) shipped tenant-isolation hardening + BYOK lease for
`apps/web-platform/server/agent-runner.ts` only. The rest of the server-side
Supabase surface (`ws-handler.ts`, `conversations-tools.ts`, `session-sync.ts`,
`api-messages.ts`, `api-usage.ts`, `conversation-writer.ts`,
`cc-dispatcher.ts`, etc.) still uses the service-role singleton for
tenant-scoped reads and writes. These files are enumerated as
**TRANSITIONAL** in `apps/web-platform/.service-role-allowlist` and the CI
grep gate accepts them only until PR-C migrates them.

Until PR-C lands:
- ~30 tenant-scoped queries bypass RLS.
- `cc-dispatcher.ts:426` fetches BYOK plaintext outside any
  `runWithByokLease` scope (V8-heap residency until GC).
- The single-user-incident-class brand-survival vector from PR-B's body
  matrix (cross-tenant read of `messages` / `conversations` / `team_names` /
  `users.{workspace_path,repo_status,github_installation_id}`) remains live
  on every code path other than `agent-runner.ts`.

## Goals

- G1: Zero TRANSITIONAL entries in `.service-role-allowlist` after PR-C.
  Permanent entries remain: bulk sweeps (`agent-runner.ts:421,441`),
  signature-verified webhook (`app/api/webhooks/stripe/route.ts`), audit-only
  paths (`health.ts:15`, `byok-lease.ts`, `kb-share-tools.ts`).
- G2: BYOK plaintext residency in V8 heap bounded by `runWithByokLease`
  scope on **every** dispatch entry point (specifically `cc-dispatcher.ts:426`).
- G3: Cross-tenant denial integration tests cover the new migrated paths —
  one test per (file, table, op) tuple where op ∈ {SELECT, INSERT, UPDATE,
  DELETE} and the tuple is exercised by user-routable code.
- G4: RPC GRANT enumeration upfront. Every `.rpc(...)` site in the 30 hits a
  classification gate: tenant-JWT-compatible (keep migrated) vs
  `REVOKE EXECUTE FROM authenticated` (revert to service-role with comment
  + allowlist entry).

## Non-Goals

- NG1: No new tables, no new RPCs, no migration files. (Audit-writer wiring
  is PR-D scope.)
- NG2: No new MCP tools, no new agent surfaces, no Inngest adoption, no
  background-trigger work.
- NG3: No timer pair / `WorkflowEnd` union re-introduction. Deferred to its
  own PR with the runner consumer landing simultaneously (per #3392).
- NG4: No `/proc/<pid>/environ` env-leak test. Risk-LOW gate (single-host,
  controlled UID); re-evaluation trigger is the 2nd hosted founder.
- NG5: No Daily Priorities surface, no read-only digest. Defer to product
  brainstorm post-PR-C.
- NG6: No `audit_byok_use` writer. PR-D scope.
- NG7: No `is_jti_denied` runtime consumer. PR-D bundle.
- NG8: No DPA / Privacy Policy / sub-processor disclosure changes — internal
  hardening of existing processing.

## Functional Requirements

- **FR1**: Migrate `server/ws-handler.ts` 10 sites
  (`:294, :432, :452, :754, :767, :812, :896, :1116, :1410`) to
  `getFreshTenantClient(userId)` or SSR cookie-anon-key (for app/api callers).
  Auth probe inserted before first migrated query.
- **FR2**: Migrate `server/conversations-tools.ts` 4 sites
  (`:150, :211, :248, :291`).
- **FR3**: Migrate `server/session-sync.ts` 4 sites
  (`:187, :236, :254, :270`). Lift its TRANSITIONAL allowlist entry.
- **FR4**: Migrate `server/api-messages.ts`, `api-usage.ts`,
  `conversation-writer.ts`, `lookup-conversation-for-path.ts`,
  `current-repo-url.ts`, `kb-document-resolver.ts`, `kb-route-helpers.ts`
  (10 total sites).
- **FR5**: Migrate `cc-dispatcher.ts:426` BYOK fetch to `lease.getApiKey()`
  via `runWithByokLease` wrap on the dispatch entry point. Lift its
  TRANSITIONAL allowlist entry.
- **FR6**: Sample-audit 5 `app/api/**/route.ts` files for SSR cookie-anon-key
  client usage. Plan phase decides between alphabetical-first-5 and
  coverage-driven-5 (the latter requires a "which routes are agent-callable"
  enumeration).
- **FR7**: Update `tasks.md` §1.5 checkboxes (close PR-B's stale state) AND
  add §2 checkboxes for PR-C.
- **FR8**: Shrink `.service-role-allowlist` to permanent entries only.
- **FR9**: Verify CI gate green: `rg "createServiceClient|getServiceClient"
  apps/web-platform/server/{ws-handler,conversations-tools,session-sync,api-messages,api-usage,conversation-writer,lookup-conversation-for-path,current-repo-url,kb-document-resolver,kb-route-helpers,cc-dispatcher}.ts`
  returns zero non-allowlisted matches.

## Technical Requirements

- **TR1**: Each migrated site uses `getFreshTenantClient(userId)` (per-tenant
  cached JWT with TTL/2 remint) for tenant-scoped reads and writes.
- **TR2**: Each migrated site has an auth probe before the first migrated
  query (per `2026-04-12-silent-rls-failures-in-team-names`).
- **TR3**: Every `.rpc(...)` site in the 30 is classified upfront: enumerate,
  check `REVOKE EXECUTE FROM authenticated` against migrations 001–043, decide
  keep-migrated or revert-to-service-role with `// SERVICE-ROLE: RPC revoked
  from authenticated — see migration NNN` comment.
- **TR4**: Test mocks routed through the existing `mockFrom`/`mockRpc` chain
  via `vi.mock("@/lib/supabase/tenant", ...)`. **Plan-time decision**:
  extract `test/helpers/runtime-mocks.ts` shared helper now (bundled with
  PR-C) vs follow-up chore PR.
- **TR5**: Cross-tenant denial integration tests (`vitest run` with
  `TENANT_INTEGRATION_TEST=1`) cover each new (file, table, op) tuple. Tests
  use synthesized founder fixtures (per `cq-test-fixtures-synthesized-only`).
- **TR6**: `runWithByokLease` wrap on `cc-dispatcher.ts:426` mirrors
  `agent-runner.ts:startAgentSession` shape — zeroize-on-finally on plaintext
  buffer; `lease.getApiKey()` returns `string | Promise<string>` per the
  existing F3 type-design contract.
- **TR7**: `error-messages.ts` mapper extended for any new error paths
  introduced by the migrated sites (`RuntimeAuthError` and `ByokLeaseError`
  already mapped from PR-B; verify coverage).
- **TR8**: `sanitizeErrorForClient` + `reportSilentFallback` wired at every
  new error path per `cq-silent-fallback-must-mirror-to-sentry`.

## Acceptance Criteria

- [ ] `bun run typecheck` clean.
- [ ] `bun run test` green (vitest, including new cross-tenant denial tests).
- [ ] `bun run build` clean.
- [ ] `service-role-allowlist-gate.sh` returns the new shrunk allowlist.
- [ ] `service-role-allowlist-gate.test.sh` 3/3.
- [ ] Multi-agent review: `security-sentinel`, `user-impact-reviewer`,
  `architecture-strategist`, `data-integrity-guardian`, `semgrep-sast`,
  `code-quality-analyst`, `pattern-recognition-specialist`,
  `code-simplicity-reviewer` — all P1 + P2 fixed inline.
- [ ] PR body documents the artifact + vector matrix (per
  `hr-weigh-every-decision-against-target-user-impact`) — copy template from
  PR-B body.
- [ ] PR uses `Ref #3244, Closes #3392 (cc-dispatcher BYOK item only)` in
  body, NOT title (per `wg-use-closes-n-in-pr-body-not-title-to`).

## Out of Scope

See Non-Goals above. Tracked deferrals:

- Timer pair + `WorkflowEnd` union — its own PR with runner consumer.
- `/proc` env-leak test — until 2nd hosted founder.
- `audit_byok_use` writer + `is_jti_denied` runtime consumer — PR-D.
- Daily Priorities + Inngest + ADR + sub-processor disclosure — separate
  brainstorms.

## References

- Umbrella spec: `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md`
- Umbrella tasks: `knowledge-base/project/specs/feat-agent-runtime-platform/tasks.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-15-pr-c-sibling-query-migration-brainstorm.md`
- PR-A: #3240 (merged)
- PR-B: #3395 (merged) — playbook template for PR-C
- Deferrals: #3392
