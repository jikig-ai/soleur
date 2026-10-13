---
name: mcp-tier-classify-2909
plan: knowledge-base/project/plans/2026-05-13-feat-mcp-tier-classify-cc-soleur-go-phase-1-plan.md
spec: knowledge-base/project/specs/feat-mcp-tier-classify-2909/spec.md
issue: 2909
phase_2_tracking: 3722
branch: feat-mcp-tier-classify-2909
worktree: .worktrees/feat-mcp-tier-classify-2909/
draft_pr: 3720
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks: MCP tier classify for cc-soleur-go (Phase 1)

## Phase 1: RED tests (`cq-write-failing-tests-before`)

- [ ] 1.1 Extend `apps/web-platform/test/tool-tiers.test.ts` with `describe("CC_ROUTER_TIER3_DENYLIST")` block
  - [ ] 1.1.1 Assert size is 3
  - [ ] 1.1.2 Assert exact membership (3 Plausible FQNs)
  - [ ] 1.1.3 Assert no other names in set
- [ ] 1.2 Create `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` with `readCcMcpAllowlist` cases
  - [ ] 1.2.1 Empty / unset env returns `{}`
  - [ ] 1.2.2 Whitespace-only / comma-only env returns `{}`
  - [ ] 1.2.3 Tier 3 denylist short-name throws plain Error with name + "permanent Tier 3 denylist"
  - [ ] 1.2.4 Pin denylist-first ordering: `"foo,plausible_create_site"` throws with Plausible name (not `foo`)
  - [ ] 1.2.5 Non-denylist valid names (e.g., `kb_share_list`) do NOT throw in Phase 1; factory still returns `{}` (Phase 1 stops there — full validation is Phase 2)
- [ ] 1.3 Sentry mirror tests (Candidate B — SDK iterator hook in `dispatchSoleurGo`)
  - [ ] 1.3.1 Mock iterator yields `tool_use` block naming `mcp__soleur_platform__kb_share_list` in cc-router session → `reportSilentFallback` called with `{ feature: "cc-mcp-tier", op: "unregistered-tool-invoked", extra: { toolName, userId, conversationId, leaderId: "cc_router" } }`
  - [ ] 1.3.2 Mirror does NOT fire for legacy sessions (`leaderId !== CC_ROUTER_LEADER_ID`)
- [ ] 1.4 Run both test files; confirm all new assertions FAIL; commit `[RED]`

## Phase 2: GREEN — implementation

### 2.1 tool-tiers.ts (contract surface — ships first)

- [ ] 2.1.1 Add `CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string>` export with 3 Plausible FQNs + JSDoc
- [ ] 2.1.2 Annotate `TOOL_TIER_MAP` entries with cc-router intent comments (NO value changes)
- [ ] 2.1.3 Run `bun test tool-tiers.test.ts` → denylist GREEN, legacy GREEN; commit `[GREEN denylist]`

### 2.2 cc-dispatcher.ts (inline allowlist + Sentry mirror)

- [ ] 2.2.1 Read `cc-dispatcher.ts:792-1000` to confirm exact insertion points
- [ ] 2.2.2 Add inline `readCcMcpAllowlist(env)` function near top of `realSdkQueryFactory`; import `CC_ROUTER_TIER3_DENYLIST` from `./tool-tiers`
- [ ] 2.2.3 Replace `mcpServers: {}` at line 948 with `mcpServers: readCcMcpAllowlist()`
- [ ] 2.2.4 Add Sentry mirror in `dispatchSoleurGo`'s SDK iterator (`for await` loop) for `tool_use` blocks naming `mcp__soleur_platform__*` — use `reportSilentFallback` with `feature: "cc-mcp-tier"`, `op: "unregistered-tool-invoked"`, `extra: { toolName, userId, conversationId, leaderId: CC_ROUTER_LEADER_ID }`
- [ ] 2.2.5 Run all tests; confirm all Phase 1 assertions GREEN; `tsc --noEmit` clean; commit `[GREEN]`

### 2.3 Helper-bypass verification

- [ ] 2.3.1 Helper-centric grep: `rg 'reportSilentFallback\(' apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/permission-callback.ts | grep -i 'cc-mcp-tier'` → returns Phase 2.2.4 call site
- [ ] 2.3.2 Bypass grep: `rg 'Sentry\.capture(Message|Exception)' apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/permission-callback.ts | grep -v 'reportSilentFallback'` → empty

## Phase 3: DPA + RoPA (CLO hard-block closure)

- [ ] 3.1 Add GitHub Inc row to `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table
  - [ ] 3.1.1 Invoke `legal-document-generator` agent with GitHub-specific context
  - [ ] 3.1.2 Operator review the draft
  - [ ] 3.1.3 Append row matching sibling row formatting
- [ ] 3.2 Add Plausible Analytics row to same table
  - [ ] 3.2.1 Invoke `legal-document-generator`; **VERIFY plausible.io EU vs self-hosted US at authorship time** (Chapter V impact)
  - [ ] 3.2.2 Operator review
  - [ ] 3.2.3 Append row
- [ ] 3.3 Update `knowledge-base/legal/article-30-register.md` with processing-activity rows for kb_share, conversations_lookup, GitHub tools, Plausible (each `Phase 1 status: not exposed; Phase 2 tracked by #3722`)

## Phase 4: Documentation reconciliation

- [ ] 4.1 Update issue #2909 body with "Reconciliation (added 2026-05-13...)" block (stale line ref + plan/issue scope drift)
- [ ] 4.2 Add `CC_MCP_ALLOWLIST` documentation block to `apps/web-platform/.env.example`

## Phase 5: Verification

- [ ] 5.1 `bunx tsc --noEmit` from `apps/web-platform/` → zero errors
- [ ] 5.2 `bun test apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` → GREEN
- [ ] 5.3 `bun test apps/web-platform/test/tool-tiers.test.ts` → GREEN
- [ ] 5.4 Full project test command → no regressions
- [ ] 5.5 Smoke: cc-soleur-go runner with `CC_MCP_ALLOWLIST` unset preserves `mcpServers === {}`

## Phase 6: Post-merge (operator)

- [ ] 6.1 Doppler dev: `doppler secrets set CC_MCP_ALLOWLIST="" -p soleur -c dev` (operator ack per `hr-menu-option-ack-not-prod-write-auth`)
- [ ] 6.2 Doppler prd: same with `-c prd`
- [ ] 6.3 Conditional close: `gh issue view 2909 --json state -q .state` — if OPEN, run `gh issue close 2909 --comment "Closed by PR #3720 — Phase 1 deny-by-default scaffolding shipped. Phase 2 promotion tracked at #3722."`; else skip
- [ ] 6.4 Verify #3722 status remains OPEN with `blocked-by: #2939` linkage

## Acceptance Criteria (mirrored from plan)

### Pre-merge (PR)

- [ ] AC1: `tool-tiers.ts` `CC_ROUTER_TIER3_DENYLIST` exports exactly 3 Plausible FQNs; `TOOL_TIER_MAP` values unchanged
- [ ] AC2: `cc-dispatcher.ts` defines inline `readCcMcpAllowlist()`; replaces `mcpServers: {}` literal
- [ ] AC3: Empty/unset/whitespace env → `readCcMcpAllowlist()` returns `{}`
- [ ] AC4: Tier 3 short-name throws plain `Error` with name + `"permanent Tier 3 denylist"`; denylist-first ordering pinned
- [ ] AC5: Sentry mirror fires from `dispatchSoleurGo` iterator hook (Candidate B); scoped to cc-router by surface
- [ ] AC6: Helper-bypass grep empty (all Sentry emissions route through `reportSilentFallback`)
- [ ] AC7: GitHub Inc + Plausible Analytics rows in compliance-posture.md Vendor DPA Status table
- [ ] AC8: 4 article-30-register.md rows for the tool families
- [ ] AC9: `.env.example` documents `CC_MCP_ALLOWLIST`
- [ ] AC10: tests pass; no regressions
- [ ] AC11: Issue #2909 body has Reconciliation block
- [ ] AC12: PR body uses `Closes #2909`; `Related: #3722` (NOT `Closes #3722`)

### Post-merge (operator)

- [ ] AC13: Doppler dev `CC_MCP_ALLOWLIST` empty
- [ ] AC14: Doppler prd `CC_MCP_ALLOWLIST` empty
- [ ] AC15: #3722 OPEN with `blocked-by: #2939`
- [ ] AC16: #2909 closed (auto or conditional fallback)
