---
spec: feat-flagsmith-per-org-worm-migration
date: 2026-05-25
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-25-feat-flagsmith-per-org-worm-migration-plan.md
umbrella_issue: 4456
---

# Tasks: PR-2 — Migrate both flags + per-org capability + WORM audit

## Phase 0 — Pre-conditions + ADR-043 (TDD-exempt)

- [ ] 0.1 Pre-merge tenant-DPA guard: `awk '/^\| /' knowledge-base/legal/tenant-dpa-register.md | grep -c 'status: dpa-signed'` returns 0
- [ ] 0.2 Migration slot verify: `git ls-tree origin/main -- apps/web-platform/supabase/migrations/ | grep 071` returns empty
- [ ] 0.3 Draft ADR-043: `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`
- [ ] 0.4 File LIA: `knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md`

## Phase 1 — LRU Cache (RED/GREEN)

- [ ] 1.1 RED: Write `apps/web-platform/lib/feature-flags/lru-cache.test.ts` (set/get, TTL expiry, eviction at cap, access-refresh recency, env-tunable max)
- [ ] 1.2 GREEN: Write `apps/web-platform/lib/feature-flags/lru-cache.ts` (generic LRUCache<K,V>, maxSize, ttlMs)

## Phase 2 — Identity Widening (RED/GREEN)

- [ ] 2.1 RED: Write tests in `identity.test.ts` (authenticated with orgId, without orgId, anonymous)
- [ ] 2.2 GREEN: Edit `identity.ts` — widen Identity type + extend resolveIdentity() with workspace_members SELECT

## Phase 3 — Server.ts Capability (RED/GREEN)

- [ ] 3.1 RED: Write tests in `server.test.ts` (orgId trait forwarding, transient:true, LRU (role,orgId) key, dual-control truth tables, Flagsmith outage fallback)
- [ ] 3.2 GREEN: Edit `server.ts` — move flags to RUNTIME_FLAGS, wire LRU, update fetchRuntimeFlagsFromFlagsmith with orgId + transient:true, convert helpers to async
- [ ] 3.3 GREEN: Add `FLAGSMITH_CACHE_MAX_ENTRIES=1000` to `.env.example`

## Phase 4 — WORM Migration 071 (RED/GREEN)

- [ ] 4.1 RED: Write WORM trigger tests (INSERT via RPC, UPDATE reject, DELETE-unexpired reject, DELETE-expired succeeds, actor CHECK reject/accept, zero RLS policies)
- [ ] 4.2 GREEN: Write `071_flag_flip_audit.sql` (table + two triggers + writer RPC)
- [ ] 4.3 GREEN: Write `071_flag_flip_audit.down.sql` (drop in dependency order)

## Phase 5 — Skill-Side Audit Append (TDD-exempt)

- [ ] 5.1 Edit `plugins/soleur/skills/flag-create/scripts/create.sh` — audit_flag_flip RPC before Flagsmith; exit 4 on failure
- [ ] 5.2 Edit `plugins/soleur/skills/flag-set-role/scripts/flip.sh` — audit_flag_flip RPC; add --target role|org; exit 4
- [ ] 5.3 Edit `plugins/soleur/skills/user-set-role/scripts/set-role.sh` — audit_flag_flip RPC; exit 4
- [ ] 5.4 Update SKILL.md files (flag-create, flag-set-role, user-set-role) with audit-row documentation
- [ ] 5.5 Update `plugins/soleur/skills/flag-set-role/SKILL.md` with `--target role|org` argument

## Phase 6 — team-workspace-invite Migration (RED/GREEN)

- [ ] 6.1 RED: Update `test/team-membership-resolver.test.ts` for async gate
- [ ] 6.2 RED: Update `test/team-workspace-boot.test.ts` for async boot path
- [ ] 6.3 RED: Write dual-control truth table in `e2e/team-membership.e2e.ts`
- [ ] 6.4 GREEN: Propagate await — team-membership-resolver.ts:70
- [ ] 6.5 GREEN: Convert team-workspace-boot.ts:13 to async getRuntimeFlag
- [ ] 6.6 GREEN: Propagate await — invite-member/route.ts:40
- [ ] 6.7 GREEN: Propagate await — remove-member/route.ts:30
- [ ] 6.8 GREEN: Propagate await — settings/layout.tsx:22

## Phase 7 — byok-delegations Migration (RED/GREEN)

- [ ] 7.1 RED: Write hot-path latency regression test (10 ops, ≤1 Flagsmith call)
- [ ] 7.2 RED: Write Inngest memo test (≤1 call per step via AsyncLocalStorage)
- [ ] 7.3 RED: Update `test/server/byok-audit-writer-sweep.test.ts`
- [ ] 7.4 RED: Update Inngest function tests (cfo-on-payment-failed, github-on-event)
- [ ] 7.5 GREEN: Edit byok-resolver.ts — delete envOnly(), add async flag check with per-request memo
- [ ] 7.6 GREEN: Wire AsyncLocalStorage memo for Inngest contexts
- [ ] 7.7 GREEN: Verify await propagation at agent-runner.ts:902,2468 + cc-dispatcher.ts:908 + Inngest functions
- [ ] 7.8 GREEN: Create `server/byok-delegations-boot.ts` (Sentry boot breadcrumb)

## Phase 8 — CI + Invariants (TDD-exempt)

- [ ] 8.1 Rewrite `scheduled-membership-health.yml` — HTTP probe `/api/flags?role=prd`; strip_log_injection; fail-closed-to-OFF
- [ ] 8.2 Edit `verify-required-secrets.sh` — add FLAG_TEAM_WORKSPACE_INVITE + FLAG_BYOK_DELEGATIONS mirror invariant checks

## Phase 9 — Flagsmith Segment Bootstrap (operator-mediated)

- [ ] 9.1 Create `org-targeted` segment in dev env (90722) via Management API
- [ ] 9.2 Create `org-targeted` segment in prd env (90721) via Management API
- [ ] 9.3 Create `team-workspace-invite` + `byok-delegations` features; attach to segment
- [ ] 9.4 Audit rows generated for feature-create operations
- [ ] 9.5 Update `plugins/soleur/skills/flag-bootstrap/SETUP.md` with segment IDs

## Phase 10 — Verification (pre-merge ACs)

- [ ] 10.1 `tsc --noEmit` green
- [ ] 10.2 `npx vitest run` — all suites green
- [ ] 10.3 E2E dual-control truth table passes
- [ ] 10.4 Hot-path regression test passes
- [ ] 10.5 `git grep -nE 'process\.env\.FLAG_TEAM_WORKSPACE_INVITE' apps/` — only fallback + test stubs
- [ ] 10.6 `git grep -nE 'process\.env\.FLAG_BYOK_DELEGATIONS' apps/` — only fallback + test stubs
- [ ] 10.7 `verify-required-secrets.sh` green
- [ ] 10.8 Tenant-DPA guard: `awk` returns 0
- [ ] 10.9 Multi-agent review (8 agents per umbrella plan)
- [ ] 10.10 CPO sign-off attested in PR body
