---
spec: feat-audit-env-flags-flagsmith-policy
date: 2026-05-25
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-25-feat-audit-env-flags-flagsmith-policy-plan.md
umbrella_issue: 4456
---

# Tasks: ENV→Flagsmith flag migration (umbrella #4456)

**Master decomposition.** Each PR below gets its own dedicated `/soleur:plan` cycle when ready to ship — this tasks.md tracks the umbrella sequence. Per-PR tasks live in `knowledge-base/project/specs/<per-pr-feature>/tasks.md` when each PR's worktree is created.

## Phase 0 — Setup (this PR — already complete)

- [x] 0.1 Worktree + draft PR #4455 created
- [x] 0.2 Brainstorm captured: `brainstorms/2026-05-25-audit-env-flags-flagsmith-policy-brainstorm.md`
- [x] 0.3 Spec written: `specs/feat-audit-env-flags-flagsmith-policy/spec.md`
- [x] 0.4 Umbrella issue #4456 created and cross-linked from #4444
- [x] 0.5 Plan written (v1): 6-PR draft
- [x] 0.6 GDPR gate run (Phase 2.7): 0 Critical, 3 Important, 4 PASS
- [x] 0.7 Plan-review (DHH + Kieran + Code Simplicity) run
- [x] 0.8 Plan v2 (collapsed to 3 PRs per consensus) written
- [x] 0.9 Spec, brainstorm, umbrella issue updated to reflect v2 collapse
- [ ] 0.10 CPO sign-off on plan body (required per `requires_cpo_signoff: true` — operator to confirm before /work)

## Phase 1 — PR-1: Flagsmith sub-processor disclosure

**Blocks:** PR-2.
**Worktree:** to be created when ready (`worktree-manager.sh feature flagsmith-subprocessor-disclosure` or similar).
**Plan cycle:** Run `/soleur:plan` from inside that worktree to generate a per-PR plan + per-PR tasks.md.

- [ ] 1.1 Verify Flagsmith DPA URL (Bullet Train Ltd) + sign / capture evidence
- [ ] 1.2 Confirm Flagsmith data region (US edge vs region pinning); classify §11.1 EEA vs §11.2 SCCs (expected: §11.2 — UK-based, non-EEA from EU DPA POV)
- [ ] 1.3 Create `knowledge-base/legal/data-processing-agreements/flagsmith.md` (DPA URL, signature evidence, data region, transfer mechanism, Flagsmith's own sub-processors, execution date)
- [ ] 1.4 Add Flagsmith row to `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table
- [ ] 1.5 Add Flagsmith to `knowledge-base/legal/data-processing-agreement-template.md` Schedule 2 (§11.2 classification)
- [ ] 1.6 Add Flagsmith recipient line to `knowledge-base/legal/article-30-register.md` PA-1 + PA-2
- [ ] 1.7 Update `knowledge-base/legal/tenant-dpa-register.md` Art. 28(4) flow-down note (document no-op state)
- [ ] 1.8 Update `docs/legal/privacy-policy.md` sub-processor list
- [ ] 1.9 Update `docs/legal/data-protection-disclosure.md` (root + Eleventy mirror — `diff` must return zero)
- [ ] 1.10 Update `docs/legal/gdpr-policy.md` sub-processor list
- [ ] 1.11 Grep for AUP file; if exists and lists sub-processors, update lockstep
- [ ] 1.12 Document §6.1 30-day notification clock state (zero customer DPAs → not triggered today)
- [ ] 1.13 AC checks: `git grep -i flagsmith` returns ≥7 hits across legal artifacts; markdownlint passes; DPD root/mirror `diff` zero
- [ ] 1.14 PR created, reviewed (CLO + legal-compliance-auditor), merged

## Phase 2 — PR-2: Migrate both flags + per-org capability + WORM audit (combined)

**Blocked by:** PR-1.
**Worktree:** new worktree from `feat-audit-env-flags-flagsmith-policy` branch or from main post-PR-1.
**Plan cycle:** This is the load-bearing PR. Run `/soleur:plan` from that worktree to generate the deep per-PR plan (will be substantial — expect "A LOT" tier).

### 2.A — Pre-merge tenant-DPA guard (PR-2 first task)

- [ ] 2.A.1 `awk '/^\| /' knowledge-base/legal/tenant-dpa-register.md | grep -c 'status: dpa-signed'` MUST return 0 — if non-zero, halt PR-2 merge and escalate to CLO (§6.1 30-day clock applies)

### 2.B — ADR-043

- [ ] 2.B.1 Draft `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md` (decision: identity-trait `orgId` + single segment with rule `orgId IN [...]`; rationale + alternatives + data-min note)

### 2.C — Identity widening (capability layer)

- [ ] 2.C.1 Widen `Identity` type in `apps/web-platform/lib/feature-flags/identity.ts`: `{ userId, role, orgId }`
- [ ] 2.C.2 Extend `resolveIdentity()` to derive `orgId` from `workspace_members` (single SELECT, React `cache()` for per-request memo)
- [ ] 2.C.3 Extend `getRuntimeFlag(name, identity)` to call `getIdentityFlags(identifier, { role, orgId }, true)` — `transient: true` MANDATORY (data-min lever)
- [ ] 2.C.4 Replace `_roleCache` Map with bounded LRU (N=1000, env-tunable via `FLAGSMITH_CACHE_MAX_ENTRIES`); 30s TTL preserved
- [ ] 2.C.5 Unit tests: anon → no orgId trait; authenticated → orgId trait; Flagsmith down → env fallback; LRU eviction

### 2.D — Flagsmith segment bootstrap

- [ ] 2.D.1 Flagsmith Management API: create `org-targeted` segment in dev (env 90722) + prd (env 90721) with rule `orgId IN ($ORG_IDS_placeholder)` (initial: empty list)
- [ ] 2.D.2 Update `plugins/soleur/skills/flag-bootstrap/SETUP.md` with the segment-creation step + segment IDs
- [ ] 2.D.3 Extend `plugins/soleur/skills/flag-set-role/SKILL.md` with `--target role|org` argument
- [ ] 2.D.4 Skill-description budget check (SKILL.md word count vs 1800 cap) — sibling-trim if needed

### 2.E — WORM `flag_flip_audit` migration 071

- [ ] 2.E.1 Write `apps/web-platform/supabase/migrations/071_flag_flip_audit.sql`:
  - Table with `-- LAWFUL_BASIS:` annotation
  - Columns: id, flag_name, env, target (text with prefix convention), action, before_bool, after_bool, actor (CHECK email regex), created_at, retention_until
  - RLS enabled with ZERO policies
  - Two SECURITY INVOKER triggers (`_no_update`, `_no_delete`) with `SET search_path = public, pg_temp` + REVOKE matrix
  - DELETE trigger has row-state bypass: `OLD.retention_until IS NOT NULL AND OLD.retention_until < now()`
  - Writer RPC `audit_flag_flip(...)` SECURITY DEFINER with `SET search_path = public, pg_temp` + lowercase normalization of `actor`
  - REVOKE ALL ... FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role
- [ ] 2.E.2 Write `apps/web-platform/supabase/migrations/071_flag_flip_audit.down.sql` (drop in correct dependency order)
- [ ] 2.E.3 File LIA doc `knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md` (Art. 6(1)(f) three-part test)
- [ ] 2.E.4 Skill-side append: `plugins/soleur/skills/flag-create/SKILL.md`, `flag-set-role/SKILL.md`, `user-set-role/SKILL.md` call `audit_flag_flip(...)` BEFORE Flagsmith mutation; exit code 4 on append failure (no silent skip)
- [ ] 2.E.5 pg_cron retention heartbeat: create `flag_flip_audit_sweep_heartbeat` table; sweep cron writes row; scheduled workflow alerts if no row >32 days
- [ ] 2.E.6 Tests: real-Postgres tenant write test; UPDATE negative test; DELETE negative test on unexpired row; DELETE positive test on expired row; `actor` CHECK rejection test; skill abort-on-audit-failure test

### 2.F — team-workspace-invite migration

- [ ] 2.F.1 Move `team-workspace-invite` from `ENV_FLAGS` to `RUNTIME_FLAGS` in `lib/feature-flags/server.ts`
- [ ] 2.F.2 Convert `isTeamWorkspaceInviteEnabled(orgId)` to async `(orgId, identity)`: `(await getRuntimeFlag(...)) && getTeamWorkspaceAllowlist().has(orgId)` (dual-control)
- [ ] 2.F.3 Propagate await: `server/team-membership-resolver.ts` (gate site), `server/team-workspace-boot.ts`, `app/api/workspace/invite-member/route.ts`, `app/api/workspace/remove-member/route.ts`, `app/(dashboard)/dashboard/settings/layout.tsx`
- [ ] 2.F.4 Flagsmith feature create + attach to `org-targeted` segment + audit row
- [ ] 2.F.5 Update tests: `test/team-membership-resolver.test.ts`, `test/team-workspace-boot.test.ts`, `e2e/team-membership.e2e.ts`

### 2.G — byok-delegations migration (hot-path)

- [ ] 2.G.1 Move `byok-delegations` to `RUNTIME_FLAGS`; delete duplicate `envOnly()` helper
- [ ] 2.G.2 Introduce async boundary at `server/byok-resolver.ts:resolveKeyOwnerThenLease()`; widen contract (NOT a sync proxy per learning `2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy.md`)
- [ ] 2.G.3 Per-request memoization: React `cache()` for RSC paths; `AsyncLocalStorage` (Node 16+) for Inngest contexts
- [ ] 2.G.4 Propagate await: `server/agent-runner.ts:895, 2461`, `server/cc-dispatcher.ts:890`, `server/inngest/functions/cfo-on-payment-failed.ts`, `server/inngest/functions/github-on-event.ts` (verify exact line numbers at /work time — minor drift expected)
- [ ] 2.G.5 Create `apps/web-platform/server/byok-delegations-boot.ts` (Sentry boot breadcrumb parity with `team-workspace-boot.ts`)
- [ ] 2.G.6 Flagsmith feature create + segment attach + audit row
- [ ] 2.G.7 Hot-path latency regression test: 10 BYOK ops per request → ≤1 Flagsmith call
- [ ] 2.G.8 Update tests: `test/server/byok-audit-writer-sweep.test.ts`, `test/server/inngest/cfo-on-payment-failed.test.ts`, `test/server/inngest/github-on-event.test.ts`

### 2.H — CI + invariants

- [ ] 2.H.1 Rewrite `.github/workflows/scheduled-membership-health.yml`: HTTP probe `/api/flags?role=prd` via `curl --max-time 5`; reuse `strip_log_injection()` from `scheduled-realtime-probe.yml`; fail-closed-to-OFF on 5xx
- [ ] 2.H.2 Extend `apps/web-platform/scripts/verify-required-secrets.sh` to preserve env-fallback mirror invariant for both flags

### 2.I — Pre-merge ACs (PR-2)

- [ ] 2.I.1 `tsc --noEmit` green
- [ ] 2.I.2 All unit + integration + E2E + hot-path latency tests green
- [ ] 2.I.3 `git grep -nE 'process\.env\.FLAG_TEAM_WORKSPACE_INVITE' apps/` shows only fallback + test stubs
- [ ] 2.I.4 `git grep -nE 'process\.env\.FLAG_BYOK_DELEGATIONS' apps/` shows only fallback + test stubs
- [ ] 2.I.5 `verify-required-secrets.sh` green
- [ ] 2.I.6 audit_flag_flip rows visible for feature-create + segment-attach operations
- [ ] 2.I.7 Multi-agent review (architecture-strategist, data-integrity-guardian, identity-rbac-reviewer, security-sentinel, user-impact-reviewer) — single-user-incident threshold mandates broad review
- [ ] 2.I.8 CPO sign-off confirmed (per `requires_cpo_signoff: true`)

### 2.J — Post-merge (operator)

- [ ] 2.J.1 `/api/flags?role=prd` returns `team-workspace-invite: false` and `byok-delegations: false`
- [ ] 2.J.2 `select count(*) from public.flag_flip_audit;` returns ≥2
- [ ] 2.J.3 `gh variable delete FLAG_TEAM_WORKSPACE_INVITE` (legacy GH Actions Variable orphaned)
- [ ] 2.J.4 **#4444 storage-object lifecycle blocker remains open** — flip-ON in prd gated separately, NOT in scope of PR-2

## Phase 3 — PR-3: dev-signin stay-ENV inline comment

**Independent — parallel-OK with PR-1, PR-2.**
**Worktree:** small; can be a single-commit PR from a short-lived worktree or even direct on `main` via a docs-class PR.

- [ ] 3.1 Add comment block above `ENV_FLAGS` in `apps/web-platform/lib/feature-flags/server.ts:16-24` (substance per plan §"Phase 3 — PR-3"; cite ADR-038 + ADR-043; reference PR-2's merge SHA once known)
- [ ] 3.2 `assert-dev-signin-eliminated.sh` still passes (verify; no code change but check anyway)
- [ ] 3.3 Markdownlint green
- [ ] 3.4 PR review + merge

## Phase 4 — Umbrella close

- [ ] 4.1 All 3 PRs merged
- [ ] 4.2 audit_flag_flip spot-check returns ≥2 rows
- [ ] 4.3 Annual Flagsmith DPA review enters compliance cadence
- [ ] 4.4 Close umbrella issue #4456 with summary linking each merged PR
- [ ] 4.5 Capture session learnings via `/soleur:compound` if any new patterns emerged

## Open Questions (deferred to per-PR plan cycles)

- PR-2: AsyncLocalStorage adoption may require its own ADR if it's new to the codebase — verify at PR-2 plan time. If yes, defer ADR to follow-up issue.
- PR-2: pg_cron retention heartbeat table may grow scope of PR-2; if so, scope-out to PR-2-follow-up issue and rely on quarterly manual sweep until follow-up ships.
- PR-2: `flag-set-role --target` arg extension may push SKILL.md description over the 1800-word cap — sibling-trim plan needed at PR-2 plan time (per `cq-skill-description-budget-headroom`).
- PR-1: §11.1 EEA vs §11.2 SCCs classification requires verification of Flagsmith's actual data residency (Bullet Train Ltd UK-based + edge CDN may complicate). Verify before drafting PR-1.

## Per-PR-plan-cycle reminders

When each PR is ready to ship, run `/soleur:plan` from inside that PR's worktree. The per-PR plan MUST:
- Re-cite the umbrella's plan-level ACs.
- Re-run premise probes if the master plan's staleness anchor (2026-05-25) is >30 days old (`gh issue view 4444`, `gh issue view 4232`, `ls apps/web-platform/supabase/migrations/`).
- Honor the dual-control invariant.
- Use `transient: true` on every Flagsmith identity-trait call.
- For PR-2: include the pre-merge `tenant-dpa-register.md` guard.
- For PR-2 WORM SQL: two separate triggers (`_no_update`, `_no_delete`); row-state bypass on DELETE; `SET search_path = public, pg_temp` on all functions; REVOKE matrix.
