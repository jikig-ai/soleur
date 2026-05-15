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

- [ ] 0.1 Re-run per-file site enumeration at /work-time HEAD; compare
      against plan §0.3 table. Halt + plan-delta if drift ≥ 5 lines or
      count mismatch.
- [ ] 0.2 Verify infrastructure shapes at the installed version
      (`getFreshTenantClient` at `tenant.ts:236`, `mintFounderJwt` at
      `tenant.ts:124`, `runWithByokLease` at `byok-lease.ts:213`,
      `lease.getApiKey(): string | Promise<string>` at `byok-lease.ts:104`).
- [ ] 0.3 Confirm plan §0.3 classification table by walking each row
      against the file at HEAD. Pay special attention to the 3 PERMANENT
      auth/attachments sites: `ws-handler.ts:1812`, `api-messages.ts:36`,
      `cc-dispatcher.ts:1395`.
- [ ] 0.4 Confirm migration cite: `027_mtd_cost_aggregate.sql:68`
      (`REVOKE EXECUTE … FROM authenticated`) and
      `029_plan_tier_and_concurrency_slots.sql:91-92` (`slots_owner_read`).

## Phase 2 — Per-file migration (one commit per file; smallest first)

Each file's commit must include: code edits + auth probe at literal entry
points + new tenant-isolation test (inline `vi.mock`, no helper extraction
in this PR).

- [ ] 2.1 `apps/web-platform/server/session-sync.ts` (4 sites; probe in
      `syncPull(userId)` and `syncPush(userId, ...)`).
- [ ] 2.2 `apps/web-platform/server/api-messages.ts` (2 SELECTs at `:55`
      + `:79` migrate; `auth.getUser` at `:36` UNCHANGED — file stays on
      allowlist as PERMANENT).
- [ ] 2.3 `apps/web-platform/server/api-usage.ts` (1 SELECT migrates; RPC
      at `:104` keeps service-role with `// SERVICE-ROLE: RPC revoked from
      authenticated — see migration 027` comment).
- [ ] 2.4 `apps/web-platform/server/conversation-writer.ts` (1 UPDATE;
      preserve the canonical `conversations.update` lint contract per file
      header).
- [ ] 2.5 `apps/web-platform/server/lookup-conversation-for-path.ts` (1 site).
- [ ] 2.6 `apps/web-platform/server/current-repo-url.ts` (1 site;
      `getCurrentRepoUrl(userId)` probe).
- [ ] 2.7 `apps/web-platform/server/kb-document-resolver.ts` (1 site;
      `fetchUserWorkspacePath(userId)` probe).
- [ ] 2.8 `apps/web-platform/server/kb-route-helpers.ts` (2 sites; probes
      in `authenticateAndResolveKbPath`, `resolveUserKbRoot(userId)`,
      `syncWorkspace(userId, ...)`).
- [ ] 2.9 `apps/web-platform/server/conversations-tools.ts` (4 sites; probe
      at each of the 4 tool factories returned by
      `buildConversationsTools(userId)`).
- [ ] 2.10 `apps/web-platform/server/ws-handler.ts` (13 sites migrate;
      `auth.getUser` at `:1812` UNCHANGED). Probes at
      `tryLedgerDivergenceRecovery`, `refreshSubscriptionStatus`,
      `dispatchSoleurGoForConversation`, `setupWebSocket` handshake-completion,
      `handleMessage` router top. Per-site UPDATE-vs-SELECT classification
      done at start of this commit using the plan §0.3 rows marked
      "classify at /work."
- [ ] 2.11 `apps/web-platform/server/cc-dispatcher.ts` — wrap
      `realSdkQueryFactory` body in `runWithByokLease(args.userId, async
      (lease) => { ... })`. Hoist `const apiKey = await lease.getApiKey();`
      OUT of `Promise.all` (per `agent-runner.ts:2361` canonical pattern;
      avoids `string | Promise<string>` union in `Promise.all` array element
      type). Migrate 2 `messages.insert` writes at `:1367` + `:1464` to
      tenant-client. Site `:1395` (attachments injection into
      `persistAndDownloadAttachments`) UNCHANGED; file stays on allowlist.

## Phase 4 — Shrink `.service-role-allowlist` (single commit; CODEOWNERS-pinned)

- [ ] 4.1 Remove 7 fully-migrated TRANSITIONAL entries
      (`conversations-tools`, `session-sync`, `conversation-writer`,
      `lookup-conversation-for-path`, `current-repo-url`,
      `kb-document-resolver`, `kb-route-helpers`).
- [ ] 4.2 Convert 2 TRANSITIONAL → PERMANENT with new comments:
      `ws-handler.ts` (WS auth.getUser handshake) and `api-messages.ts`
      (HTTP Bearer auth.getUser bootstrap).
- [ ] 4.3 Update 2 PERMANENT-pending rationales: `api-usage.ts` (RPC
      revoke), `cc-dispatcher.ts` (attachments injection, pending PR-D).
- [ ] 4.4 Verify
      `bash apps/web-platform/scripts/service-role-allowlist-gate.sh` and
      `bash apps/web-platform/test/ci/service-role-allowlist-gate.test.sh`
      (3/3 green).

## Phase 5 — Update `tasks.md` (single commit)

- [ ] 5.1 Check off umbrella `tasks.md §1.5.1 → §1.5.4`, `§1.6.2 → §1.6.5`,
      `§1.7.2` (PR-B closeouts).
- [ ] 5.2 Add `§2.1` PR-C completion checkboxes for each file in Phase 2 +
      Phase 4.
- [ ] 5.3 Cross-reference deferrals: `§2.2 PR-D scope`, `§3 deferred`
      (audit-writer, is_jti_denied, timer pair, /proc test, Daily
      Priorities, Inngest, runtime-mocks helper retrofit, app/api SSR
      audit, attachments-storage RLS).

## Phase 6 — Verification + multi-agent review (no commit)

- [ ] 6.1 `bun run typecheck` clean.
- [ ] 6.2 `bun run test` green INCLUDING cross-tenant denial integration
      tests. Run with `TENANT_INTEGRATION_TEST=1`,
      `SUPABASE_JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
      injected via Doppler. Confirm describe blocks are `passed`, NOT
      `skipped` — `skipped` reproduces the 2026-05-06 vitest-blind trap.
- [ ] 6.3 `bun run build` clean.
- [ ] 6.4 Allowlist-shrink gate scripts both green (see 4.4).
- [ ] 6.5 Grep AC suite:
  - 7-file migration grep returns zero `createServiceClient` matches.
  - `ws-handler.ts` retains 1 import + lazy-init + `auth.getUser`.
  - `api-messages.ts` retains 1 import + `auth.getUser`.
  - `api-usage.ts` retains 1 `createServiceClient` (RPC).
  - `cc-dispatcher.ts` retains 1 `createServiceClient` (attachments) + ≥ 1
    `runWithByokLease`.
- [ ] 6.6 Multi-agent review: spawn `security-sentinel`,
      `user-impact-reviewer`, `architecture-strategist`,
      `data-integrity-guardian`, `semgrep-sast`, `code-quality-analyst`,
      `pattern-recognition-specialist`, `code-simplicity-reviewer`. Fix
      every P1 + P2 inline per `rf-review-finding-default-fix-inline`.
- [ ] 6.7 PR body: copy artifact + vector matrix from PR-B #3395; record
      CPO sign-off; `Ref #3244, Closes #3392 (cc-dispatcher BYOK item only)`
      in body, NOT title.
- [ ] 6.8 File 5 tracked deferral issues (`gh label list` to verify labels
      exist first): runtime-mocks retrofit (`domain/engineering`,
      `priority/p3-low`), app/api SSR audit (`domain/engineering`,
      `priority/p2-medium`), service-tokens BYOK lease, PR-D scope tracker,
      attachments-storage tenant RLS.

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
