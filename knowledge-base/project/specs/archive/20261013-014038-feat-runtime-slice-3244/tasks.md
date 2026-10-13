---
title: PR-C — Sibling-query migration — tasks
date: 2026-05-15
plan: knowledge-base/project/plans/2026-05-15-feat-pr-c-sibling-query-migration-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# PR-C — Tasks (#3244 §2)

Phase ordering is dependency-correct: preconditions → per-file migrations
(smallest first, ws-handler + cc-dispatcher last) → allowlist shrink →
bookkeeping → verification. The Phase 1 helper extraction and Phase 3
app/api audit were REMOVED post-review (filed as tracked deferrals in the
plan). Per-file commits within Phase 2; single commit per other phase.

## Phase 0 — Preconditions (single commit)

- [x] 0.1 Re-run per-file site enumeration at /work-time HEAD; compare
      against plan §0.3 table. Halt + plan-delta if drift ≥ 5 lines or
      count mismatch. **Verified 2026-05-15 at HEAD b5f09d35: all 11
      files match plan line numbers exactly (0 drift).**
- [x] 0.2 Verify infrastructure shapes at the installed version
      (`getFreshTenantClient` at `tenant.ts:236`, `mintFounderJwt` at
      `tenant.ts:124`, `runWithByokLease` at `byok-lease.ts:213`,
      `lease.getApiKey(): string | Promise<string>` at `byok-lease.ts:104`).
      **Adaptation:** plan §0.4 sample code uses `const { client } = await
      getFreshTenantClient(userId)` but the actual signature returns
      `Promise<SupabaseClient>` directly (no `{client, jwt}` destructure).
      Canonical pattern in `agent-runner.ts:188,280,419,548,883,2275` is
      `const tenant = await getFreshTenantClient(userId)`. PR-C uses the
      codebase-correct shape.
- [x] 0.3 Confirm plan §0.3 classification table by walking each row
      against the file at HEAD. Pay special attention to the 3 PERMANENT
      auth/attachments sites: `ws-handler.ts:1812`, `api-messages.ts:36`,
      `cc-dispatcher.ts:1395`. **All 3 confirmed.**
- [x] 0.4 Confirm migration cite: `027_mtd_cost_aggregate.sql:68`
      (`REVOKE EXECUTE … FROM authenticated`) and
      `029_plan_tier_and_concurrency_slots.sql:91-92` (`slots_owner_read`).
      **Both confirmed.**

## Phase 2 — Per-file migration (one commit per file; smallest first)

Each file's commit must include: code edits + auth probe at literal entry
points + new tenant-isolation test (inline `vi.mock`, no helper extraction
in this PR).

- [x] 2.1 `apps/web-platform/server/session-sync.ts` (4 sites; probe in
      `syncPull(userId)` and `syncPush(userId, ...)`). **Commit d0e7740b.**
- [x] 2.2 `apps/web-platform/server/api-messages.ts` (2 SELECTs at `:55`
      + `:79` migrate; `auth.getUser` at `:36` UNCHANGED — file stays on
      allowlist as PERMANENT). **Commit c2b20702.**
- [x] 2.3 `apps/web-platform/server/api-usage.ts` (1 SELECT migrates; RPC
      at `:104` keeps service-role with `// SERVICE-ROLE: RPC revoked from
      authenticated — see migration 027` comment). **Commit 900c4241.**
- [x] 2.4 `apps/web-platform/server/conversation-writer.ts` (1 UPDATE;
      preserve the canonical `conversations.update` lint contract per file
      header). **Commit 41fc7e18. Note: explicit auth probe removed mid-
      migration in favor of implicit `getFreshTenantClient` mint
      (RuntimeAuthError = probe) mirroring `agent-runner.ts:188`
      precedent; finalized in commit 0ee90ac0.**
- [x] 2.5 `apps/web-platform/server/lookup-conversation-for-path.ts` (1 site).
      **Commit 9c32fef0.**
- [x] 2.6 `apps/web-platform/server/current-repo-url.ts` (1 site;
      `getCurrentRepoUrl(userId)` probe). **Commit 4ab30dec.**
- [x] 2.7 `apps/web-platform/server/kb-document-resolver.ts` (1 site;
      `fetchUserWorkspacePath(userId)` probe). **Commit c25d27f9.**
- [x] 2.8 `apps/web-platform/server/kb-route-helpers.ts` (2 sites; probes
      in `authenticateAndResolveKbPath`, `resolveUserKbRoot(userId)`,
      `syncWorkspace(userId, ...)`). **Commit c22f6ec2. `resolveUserKbRoot`
      signature refactored to drop caller-supplied `serviceClient` param;
      both route handlers (`app/api/kb/share`, `app/api/kb/upload`)
      updated.**
- [x] 2.9 `apps/web-platform/server/conversations-tools.ts` (4 sites; probe
      at each of the 4 tool factories returned by
      `buildConversationsTools(userId)`). **Commit 732aaae2. Probe is
      implicit via `getCurrentRepoUrl(userId)` preceding each tool body.**
- [x] 2.10 `apps/web-platform/server/ws-handler.ts` (13 sites migrate;
      `auth.getUser` at `:1812` UNCHANGED). Probes at
      `tryLedgerDivergenceRecovery`, `refreshSubscriptionStatus`,
      `dispatchSoleurGoForConversation`, `setupWebSocket` handshake-completion,
      `handleMessage` router top. Per-site UPDATE-vs-SELECT classification
      done at start of this commit using the plan §0.3 rows marked
      "classify at /work." **Commit 0ee90ac0. `tenantFor` helper uses
      implicit-mint probe (RuntimeAuthError) per agent-runner.ts:188
      precedent; explicit SELECT probe omitted for test-ergonomics +
      architectural symmetry. 12 consumer test files updated with
      `vi.mock("@/lib/supabase/tenant")`.**
- [x] 2.11 `apps/web-platform/server/cc-dispatcher.ts` — wrap
      `realSdkQueryFactory` body in `runWithByokLease(args.userId, async
      (lease) => { ... })`. Hoist `const apiKey = await lease.getApiKey();`
      OUT of `Promise.all` (per `agent-runner.ts:2361` canonical pattern;
      avoids `string | Promise<string>` union in `Promise.all` array element
      type). Migrate 2 `messages.insert` writes at `:1367` + `:1464` to
      tenant-client. Site `:1395` (attachments injection into
      `persistAndDownloadAttachments`) UNCHANGED; file stays on allowlist.
      **Commit b0daedee. Added `supabaseTenantFactory` to test harness;
      6 cc-dispatcher tests updated.**

## Phase 4 — Shrink `.service-role-allowlist` (single commit; CODEOWNERS-pinned)

- [x] 4.1 Remove 7 fully-migrated TRANSITIONAL entries
      (`conversations-tools`, `session-sync`, `conversation-writer`,
      `lookup-conversation-for-path`, `current-repo-url`,
      `kb-document-resolver`, `kb-route-helpers`). **Commit 75ddb7e2.**
- [x] 4.2 Convert 2 TRANSITIONAL → PERMANENT with new comments:
      `ws-handler.ts` (WS auth.getUser handshake) and `api-messages.ts`
      (HTTP Bearer auth.getUser bootstrap). **Commit 75ddb7e2.**
- [x] 4.3 Update 2 PERMANENT-pending rationales: `api-usage.ts` (RPC
      revoke), `cc-dispatcher.ts` (attachments injection, pending PR-D).
      **Commit 75ddb7e2.**
- [x] 4.4 Verify
      `bash apps/web-platform/scripts/service-role-allowlist-gate.sh` and
      `bash apps/web-platform/test/ci/service-role-allowlist-gate.test.sh`
      (3/3 green). **Both gates green: 13 importers enumerated; 3/3 test
      cases pass (green / red / allowlisted).**

## Phase 5 — Update `tasks.md` (single commit)

- [x] 5.1 Check off umbrella `tasks.md §1.5.1 → §1.5.4`, `§1.6.2 → §1.6.5`,
      `§1.7.2` (PR-B closeouts). **Done in commit 39d79a09.**
- [x] 5.2 Add `§2.1` PR-C completion checkboxes for each file in Phase 2 +
      Phase 4. **Done in commit 39d79a09.**
- [x] 5.3 Cross-reference deferrals: 14 review-derived + plan-mandated
      deferrals consolidated into issue **#3869** (single tracker per PR-B
      precedent #3392) — runtime-mocks retrofit (scope corrected 27→56),
      app/api SSR audit, service-tokens BYOK lease, PR-D scope tracker,
      attachments-storage RLS, CI tenant-integration job, helper
      consolidation, error-shape normalization, agent-runner sentinel
      sweep, ServiceClient type rename, tenant-cache LRU, probe-policy
      ADR, tenant-boundary ADR, route-handler probe-mint extraction.

## Phase 6 — Verification + multi-agent review (no commit)

- [x] 6.1 `bun run typecheck` clean.
- [x] 6.2 `bun run test` green — 4370/4370 passed, 84 skipped (integration
      gated). **NOTE:** `TENANT_INTEGRATION_TEST=1` was NOT exercised in
      this verification — silent-skip trap caught by test-design-reviewer;
      filed as #3869 item 6 (CI tenant-integration job) because adding
      Doppler dev-Supabase secrets to CI is out of PR-C scope. Operator
      MUST run integration suite locally before merge (see learning
      `2026-05-16-rls-deny-tests-payload-must-type-validate-…`).
- [x] 6.3 `bun run build` clean.
- [x] 6.4 Allowlist-shrink gate scripts both green (13 importers
      enumerated; 3/3 test cases pass).
- [x] 6.5 Grep AC suite: zero `createServiceClient` matches in 7
      fully-migrated files; ws-handler/api-messages retain 1 import +
      `auth.getUser`; api-usage retains 1 service-role for RPC;
      cc-dispatcher retains 1 service-role (attachments) + 1
      `runWithByokLease`.
- [x] 6.6 Multi-agent review: 8 always-on + 3 conditional (test-design,
      semgrep-sast, user-impact). GDPR-gate PASS. P1/P2 fixed inline per
      `rf-review-finding-default-fix-inline` (commit aa22dc9b): UUID-format
      bug in tenant-isolation test, User-Brand Impact matrix row added,
      cc-dispatcher mint try/catch wrap.
- [x] 6.7 PR body refreshed via `gh pr edit` with artifact + vector
      matrix, multi-agent review summary, CPO sign-off, `Ref #3244, Closes
      #3392 (cc-dispatcher BYOK item only)` in body.
- [x] 6.8 Consolidated to single tracker **#3869** per §5.3.

## Post-merge (operator)

- [ ] M.1 Article 30 register update within 7 calendar days of merge (CLO
      advisory). Extend PA1/PA2 TOM row + name layered controls.
- [ ] M.2 Close umbrella `tasks.md §1.5` and §2.1 on `main` after merge.
- [ ] M.3 `curl -s https://app.soleur.ai/api/health | jq` — confirm
      tenant-JWT surface is live in the prod-deployed bundle.

## Acceptance Criteria — summary

All Phase 6 boxes ticked. PR ready for security-owner review on the
allowlist-shrink commit. Brand-survival threshold `single-user incident`
implies `user-impact-reviewer` agent runs at PR-review time (handled by the
review skill's conditional-agent block, no manual invocation needed here).
