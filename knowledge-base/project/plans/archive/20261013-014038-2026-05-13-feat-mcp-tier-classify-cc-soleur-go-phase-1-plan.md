---
title: "feat: V2-13 MCP tier classify for cc-soleur-go (Phase 1 deny-by-default scaffolding)"
date: 2026-05-13
issue: 2909
phase_2_tracking: 3722
spec: knowledge-base/project/specs/feat-mcp-tier-classify-2909/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-13-mcp-tier-classify-cc-soleur-go-brainstorm.md
source_plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
source_plan_section: "§Stage 2.17, Sharp Edge #10"
branch: feat-mcp-tier-classify-2909
draft_pr: 3720
worktree: .worktrees/feat-mcp-tier-classify-2909/
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
domains_reviewed: [Product, Legal, Engineering]
type: feature
classification: scaffolding-only-config-write
---

# Plan: MCP tier classification for cc-soleur-go (Phase 1 deny-by-default scaffolding)

## Overview

Lock the cc-soleur-go router's current empty `mcpServers: {}` posture in code, add a permanent Tier 3 denylist for cross-tenant credentials (3 Plausible tools), close the silent-failure surface via `reportSilentFallback`, and close the CLO DPA hard-block (GitHub Inc + Plausible Analytics rows in `compliance-posture.md`). **Phase 1 ships zero tool promotions** — runtime behavior is preserved bit-for-bit. Phase 2 (#3722, deferred) handles read-only promotion gated on Stage 6 (#2939) closure + empirical demand.

Per plan review (DHH + Kieran + code-simplicity, 2026-05-13): the Phase 1 deliverable is intentionally minimal — ~10-line inline allowlist function in `cc-dispatcher.ts` (no separate file), denylist-only validation in Phase 1 (full unknown-name validation lives in Phase 2 alongside the first real promotion), Sentry mirror at the SDK iterator hook (Candidate B per Kieran's SDK-source read — `canUseTool` does NOT fire for tools the SDK never registered).

## User-Brand Impact

**If this lands broken, the user experiences:** a router-dispatched skill silently failing to call a tool (`unknown tool` swallowed by the model, no Sentry signal, no chat-bubble error) → user sees an unhelpful assistant response and no diagnostic trail.

**If this leaks, the user's data is exposed via:** a future PR (post-Phase-1) ad-hoc widening `mcpServers` without going through the inline allowlist function → a misclassified write tool reachable from the router → cross-tenant write or credential exposure.

**If Doppler is misconfigured** (operator typo or accidental write of a Tier 3 short-name into `CC_MCP_ALLOWLIST`): `readCcMcpAllowlist()` throws at factory construction → every cc-router conversation fails to start until Doppler is corrected. Bounded: throw fires at session-start with the offending name in the error message; Phase 6 prescribes dev-first ordering so operator sees it in dev before prd. The throw is preferred over a silent `{}` fallback because a misconfigured denylist is a security control failure, not a degraded-experience failure.

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time. `user-impact-reviewer` agent invoked at PR-review time.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| `agent-runner.ts:765-772` is the MCP server registration site | FALSE — that range is the stuck-active reaper. Real sites: `agent-runner.ts:1276-1381` (legacy accumulator) + `cc-dispatcher.ts:948` (router factory passes `mcpServers: {}`). | Plan uses real line refs; Phase 4.1 corrects issue #2909 body inline. |
| `permission-callback.ts createCanUseTool` fires for any tool the model attempts | FALSE per Kieran's SDK-source read (`node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:122-140`). `canUseTool` is invoked before each registered tool's execution. When `mcpServers === {}`, unknown `mcp__soleur_platform__*` calls are rejected by the SDK's model-validation loop and `canUseTool` is never reached. | FR2 Sentry mirror lives at the SDK iterator hook in `dispatchSoleurGo` (Candidate B), NOT in `createCanUseTool`. |
| `TOOL_TIER_MAP` already covers all 17 platform tools | FALSE — 13 entries; `plausible_*` and `conversations_*` default to `gated` via `getToolTier()` fallback. | Annotate map with cc-router intent comments (no value mutation); add `CC_ROUTER_TIER3_DENYLIST` as separate export. |
| `reportSilentFallback` is the Sentry-mirror primitive | TRUE — `observability.ts:135 export function reportSilentFallback(err, options)`; auto-pseudonymizes `userId` at the boundary. Already used 13+ times in cc-dispatcher.ts. | FR2 uses `reportSilentFallback`. |
| `CC_ROUTER_LEADER_ID` lives in cc-dispatcher.ts | PARTIAL — source of truth is `@/lib/cc-router-id` (`export const CC_ROUTER_LEADER_ID = "cc_router" as const`); re-exported from cc-dispatcher.ts:109. | Import from `@/lib/cc-router-id` in all new code. |
| `CC_PATH_ALLOWED_TOOLS` is unrelated to tier classification | TRUE — defined at cc-dispatcher.ts:560 as a separate auto-approve list. | Phase 1 does NOT touch. Phase 2 (#3722) extends when promoting Tier 1 tools. |

## Open Code-Review Overlap

3 open scope-outs touch planned files. All orthogonal — **Acknowledge** for each.

- **#3243** (Ref #3235): `arch: decompose cc-dispatcher.ts into focused modules` — different concern (file-size refactor); MCP tier-classify adds ~15 LoC.
- **#3242** (Ref #3235): `review: tool_use WS event lacks raw name field` — orthogonal WS-event schema change.
- **#3345** + **#3344**: Bash approval modal + safe-bash allowlist — both affect different branches of `createCanUseTool`; Phase 1 only touches the iterator hook in `cc-dispatcher.ts`.

## Domain Review

**Domains relevant:** Product, Legal, Engineering (carry-forward from brainstorm Phase 0.5).

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Defer tier-table promotion. Lock deny-by-default posture in code via the inline allowlist function. Zero confirmed router-skill demand in 2 days of always-on prod (#3270 closed 2026-05-11). Plausible permanently Tier 3 regardless of any future demand. **CPO sign-off required** before `/work` begins (`requires_cpo_signoff: true`).

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** **Hard-block** on any GitHub or Plausible router exposure until DPA rows are added to `compliance-posture.md` Vendor DPA Status table (#3594 precedent). Phase 1 closes both halves of the hard-block. Prior CLO sign-off on the 2026-04-23 plan explicitly deferred the act-of-exposing decision to V2-13 (this PR).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Existing infra (`tool-tiers.ts`, `permission-callback.ts:533-610`, `review-gate.ts`) is plumbed but unpopulated for cc-router. Work is configuration + denylist + Sentry mirror + tests, not new infra. New silent-failure surface MUST be Sentry-mirrored per `cq-silent-fallback-must-mirror-to-sentry`.

### Product/UX Gate

**Tier:** none — no new user-facing pages, modals, or components.

## GDPR / Compliance Gate (Phase 2.7)

> **Disclaimer:** advisory only; not legal advice. Operator must seek qualified counsel for DPA / RoPA / DPIA filings.

**Phase 1 promotes no tools.** Lawful basis per tool family is documented at #3722 plan time alongside actual promotion. Phase 1 ships:

- **DPA rows added in this PR** for GitHub Inc (US sub-processor, SCCs apply) and Plausible Analytics (region verified at row-authorship time — see Phase 3.2). Both rows close pre-existing systemic gaps that block ship per `compliance-posture.md` Active Items #3594 precedent.
- **Art. 30 RoPA entries** for the cc-router tool families with Phase 1 status: not exposed.
- **Art. 9 special-category data:** NONE in the 17-tool inventory. Asserted and documented (Critical-finding gate).
- **Chapter V cross-border** is per-DPA-row (GitHub US / Plausible EU-or-self-hosted verified at row creation).
- **Mini-DPIA, retention, erasure cascade, lawful-basis-per-tool** all deferred to #3722 plan with the first actual promotion.

## Files to Edit

| Path | Change | Phase |
|---|---|---|
| `apps/web-platform/server/tool-tiers.ts` | Add `CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string>` export (3 Plausible FQNs); annotate `TOOL_TIER_MAP` entries with cc-router intent comments (NO value changes) | 2.1 |
| `apps/web-platform/server/cc-dispatcher.ts` | (a) Add ~10-line inline `readCcMcpAllowlist()` helper near top of `realSdkQueryFactory`: reads `process.env.CC_MCP_ALLOWLIST`, returns `{}` when empty/unset, throws if any tier-3 short-name appears. (b) Replace `mcpServers: {}` at line 948 with `mcpServers: readCcMcpAllowlist()`. (c) Add Sentry-mirror branch in the iterator's `tool_use` event path: detect `mcp__soleur_platform__<unknown>` invocations and fire `reportSilentFallback`. Import `CC_ROUTER_LEADER_ID` is already present at line 110. | 2.2 |
| `apps/web-platform/test/tool-tiers.test.ts` | Extend with exact-membership + order-independence assertions on `CC_ROUTER_TIER3_DENYLIST` | 1.1 |
| `knowledge-base/legal/compliance-posture.md` | Add GitHub Inc + Plausible Analytics rows to Vendor DPA Status table | 3.1, 3.2 |
| `knowledge-base/legal/article-30-register.md` | Add processing-activity rows for cc-router MCP tool surface (Phase 1 status: not exposed) | 3.3 |
| `apps/web-platform/.env.example` | Document `CC_MCP_ALLOWLIST` env var | 4.2 |

## Files to Create

| Path | Purpose | Phase |
|---|---|---|
| `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` | RED-first tests for the inline `readCcMcpAllowlist` function + Sentry mirror | 1.1 |

(No new source file. Per plan-review synthesis, the ~10-line allowlist function lives inline in `cc-dispatcher.ts` — separate `cc-mcp-allowlist.ts` was overengineered for Phase 1.)

## Implementation Phases

### Phase 1.1 — RED tests

**Goal:** failing tests for all FRs before any source change (`cq-write-failing-tests-before`).

**Steps:**

1.1.1. **Extend `apps/web-platform/test/tool-tiers.test.ts`** with `describe("CC_ROUTER_TIER3_DENYLIST")`:
   - `expect(CC_ROUTER_TIER3_DENYLIST.size).toBe(3)`
   - Exact membership: `mcp__soleur_platform__plausible_create_site`, `mcp__soleur_platform__plausible_add_goal`, `mcp__soleur_platform__plausible_get_stats`
   - No other names

1.1.2. **Create `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts`** with cases (fixtures synthesized per `cq-test-fixtures-synthesized-only`):
   - **Empty / unset env:** `readCcMcpAllowlist({})` returns `{}` (object identity check: `Object.keys(...).length === 0`).
   - **Whitespace-only env values:** `{ CC_MCP_ALLOWLIST: "  " }`, `{ CC_MCP_ALLOWLIST: ", , " }` → return `{}`.
   - **Tier 3 denylist short-names** — each of `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats` → throws plain `Error` with message containing `"permanent Tier 3 denylist"` AND the offending name.
   - **Denylist-first ordering pinned (Kieran P1-1):** `{ CC_MCP_ALLOWLIST: "plausible_create_site,foo,bar" }` AND `{ CC_MCP_ALLOWLIST: "foo,plausible_create_site,bar" }` BOTH throw with the Plausible name in the message (denylist check precedes any unknown-name handling regardless of order in the env value).
   - **Non-denylist names pass through in Phase 1:** `{ CC_MCP_ALLOWLIST: "kb_share_list" }` does NOT throw (Phase 1 does not yet validate unknown names — that's Phase 2's job alongside the first real promotion). The factory still returns `{}` for Phase 1 because the "build mcpServers from non-empty allowlist" branch is deferred to #3722. Document this explicitly in the test.
   - **Sentry mirror (Candidate B — iterator hook):** with a mocked SDK iterator yielding a `tool_use` block naming `mcp__soleur_platform__kb_share_list` in a cc-router session, assert `reportSilentFallback` was called with `{ feature: "cc-mcp-tier", op: "unregistered-tool-invoked", message: ..., extra: { toolName, userId, conversationId, leaderId: "cc_router" } }`. Mirror does NOT fire for legacy sessions (`leaderId !== CC_ROUTER_LEADER_ID`).

1.1.3. Run both test files. Confirm all new assertions FAIL. Commit RED with `[RED]` tag.

**Acceptance:** ≥6 failing assertions; legacy `tool-tiers.test.ts` assertions still GREEN.

### Phase 2.1 — GREEN: tool-tiers.ts (contract ships first)

Per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

**Steps:**

2.1.1. Add to `apps/web-platform/server/tool-tiers.ts`:

```typescript
/**
 * Permanent Tier 3 denylist for the cc-soleur-go router (#2909).
 *
 * Tools in this set MAY NEVER be promoted to the router's mcpServers via
 * CC_MCP_ALLOWLIST. Enforced fail-closed in `cc-dispatcher.ts`'s inline
 * `readCcMcpAllowlist()` helper at factory construction.
 *
 * Plausible tools share a single backend `PLAUSIBLE_API_KEY` with no
 * per-user / per-site enforcement (plausible-tools.ts:52-74). Exposing them
 * via the router is a cross-tenant credential by construction, regardless
 * of any future demand signal.
 *
 * See brainstorm Key Decision #3:
 *   knowledge-base/project/brainstorms/2026-05-13-mcp-tier-classify-cc-soleur-go-brainstorm.md
 */
export const CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string> = new Set([
  "mcp__soleur_platform__plausible_create_site",
  "mcp__soleur_platform__plausible_add_goal",
  "mcp__soleur_platform__plausible_get_stats",
]);
```

2.1.2. Annotate the existing `TOOL_TIER_MAP` entries with cc-router intent comments. **Comment-only edits** — DO NOT change values (legacy `startAgentSession` semantics are preserved).

2.1.3. Run `bun test apps/web-platform/test/tool-tiers.test.ts`. Denylist tests PASS; legacy tests PASS. `[GREEN denylist]` commit.

### Phase 2.2 — GREEN: cc-dispatcher.ts inline allowlist + Sentry mirror

**Goal:** wire the denylist + close the silent-failure surface, all in one file.

**Steps:**

2.2.1. Read `cc-dispatcher.ts:792-1000` (the `realSdkQueryFactory` body) to confirm exact insertion points.

2.2.2. Add the inline helper near top of the factory (after existing imports):

```typescript
import { CC_ROUTER_TIER3_DENYLIST } from "./tool-tiers";

/**
 * Read CC_MCP_ALLOWLIST and return the cc-router's mcpServers config.
 *
 * Phase 1 (#2909): returns {} for empty/unset/whitespace-only env. Throws if
 * any Tier 3 denylist short-name appears. Does NOT yet build a populated
 * `soleur_platform` server — promotion is Phase 2 (#3722).
 *
 * Why inline instead of separate module: ~10 lines doesn't deserve its own
 * file; the per-PR review surface stays scoped to cc-dispatcher.ts.
 */
function readCcMcpAllowlist(
  env: Record<string, string | undefined> = process.env,
): Record<string, unknown> {
  const raw = env.CC_MCP_ALLOWLIST;
  if (raw === undefined || raw.trim() === "") return {};
  const names = raw.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
  for (const name of names) {
    const fqn = `mcp__soleur_platform__${name}`;
    if (CC_ROUTER_TIER3_DENYLIST.has(fqn)) {
      throw new Error(
        `CC_MCP_ALLOWLIST contains permanent Tier 3 denylist tool "${name}" — see CC_ROUTER_TIER3_DENYLIST in tool-tiers.ts`,
      );
    }
  }
  // Phase 1: even with valid non-denylist names present, return {} —
  // building the populated soleur_platform server lives in Phase 2 (#3722).
  return {};
}
```

2.2.3. Replace `mcpServers: {}` at line 948 with `mcpServers: readCcMcpAllowlist()`. **The throw path means a misconfigured Doppler value crashes the factory at conversation start, not silently** — fail-closed for security.

2.2.4. Add the Sentry mirror in the SDK iterator's `tool_use` event handler (Candidate B per Kieran P0-1). Locate the `for await` loop inside `dispatchSoleurGo` that consumes the SDK message stream; for each `tool_use` block whose `name` starts with `mcp__soleur_platform__` AND is not registered (since `mcpServers` is `{}`, none are registered):

```typescript
// FR2 — silent-failure mirror for unregistered platform tools (#2909).
// Per `cq-silent-fallback-must-mirror-to-sentry`: when mcpServers is empty,
// the SDK rejects mcp__soleur_platform__* tool_use blocks before invoking
// canUseTool — the failure would otherwise be invisible. The model receives
// a tool_result error, no Sentry signal, no chat-bubble. This branch makes
// the rejection visible in Sentry so the operator can investigate.
reportSilentFallback(null, {
  feature: "cc-mcp-tier",
  op: "unregistered-tool-invoked",
  message: `cc-router skill attempted unregistered platform tool ${block.name}`,
  extra: {
    toolName: block.name,
    userId: args.userId,
    conversationId: args.conversationId,
    leaderId: CC_ROUTER_LEADER_ID,
  },
});
```

(Note: `CC_ROUTER_LEADER_ID` is already imported at cc-dispatcher.ts:110. The Sentry mirror is INTRINSICALLY scoped to the cc-router because it lives in `dispatchSoleurGo` — legacy `startAgentSession` does not call this iterator path.)

2.2.5. Run all tests. Confirm Phase 1.1 tests GREEN. Run `bunx tsc --noEmit` clean. `[GREEN]` commit.

### Phase 2.3 — Helper-bypass verification (per `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`)

**Goal:** confirm no direct-emit bypass of `reportSilentFallback`.

**Steps:**

2.3.1. Helper-centric grep:

```bash
rg 'reportSilentFallback\(' apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/permission-callback.ts | grep -i 'cc-mcp-tier\|unregistered-tool'
```

Expected: exactly the Phase 2.2.4 call site.

2.3.2. Bypass grep:

```bash
rg 'Sentry\.capture(Message|Exception)' apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/permission-callback.ts | grep -v 'reportSilentFallback'
```

Expected: empty.

**Acceptance:** both greps produce the expected results.

### Phase 3.1 — DPA row: GitHub Inc

**Steps:**

3.1.1. Invoke `plugins/soleur/agents/legal-document-generator` (Task). Prompt context: vendor=GitHub Inc; role=sub-processor (operator GitHub App installations); data categories (issue bodies, commit author emails, repo metadata, installation tokens); legal basis=Art. 6(1)(f) legitimate interest; DPA at <https://github.com/customer-terms/customer-data-protection-agreement>; region=US (SCCs); retention=tied to GitHub's own lifecycle (60-day audit log per published policy).

3.1.2. Operator review the draft. Apply edits if needed.

3.1.3. Append to `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table (line 31+). Read 2-3 sibling rows for formatting.

**Acceptance:** `awk '/^## Vendor DPA Status/,/^## /' knowledge-base/legal/compliance-posture.md | grep -c '^| GitHub Inc'` returns ≥1.

### Phase 3.2 — DPA row: Plausible Analytics

**Steps:**

3.2.1. Invoke `legal-document-generator`. Prompt context: vendor=Plausible Analytics; role=sub-processor (operator analytics); data categories (IP-pseudonymized event data); legal basis=Art. 6(1)(f); DPA at <https://plausible.io/dpa>; region — **VERIFY at row-authorship time**: plausible.io is EU/DE hosted (no Chapter V trigger); self-hosted on US infra requires SCCs; retention per Plausible's documented policy.

3.2.2. Operator review.

3.2.3. Append to Vendor DPA Status table.

**Acceptance:** same shape check for Plausible.

### Phase 3.3 — Article 30 RoPA update

**Steps:**

3.3.1. Read `knowledge-base/legal/article-30-register.md` for row format.

3.3.2. Add rows for kb_share, conversations_lookup, GitHub tools, Plausible (each annotated `Phase 1 status: not exposed; Phase 2 tracked by #3722`).

3.3.3. Cross-link to compliance-posture.md DPA rows added in 3.1/3.2.

**Acceptance:** 4 tool-family rows; cross-link resolves.

### Phase 4.1 — Update issue #2909 body (scope-drift + stale line-ref reconciliation)

```bash
gh issue view 2909 --json body --jq .body > /tmp/issue-2909-body.md
# Append reconciliation block
cat >> /tmp/issue-2909-body.md <<'EOF'

---

## Reconciliation (added 2026-05-13 at plan time)

- **Stale line ref:** the original body cites `agent-runner.ts:765-772`; that range is now the stuck-active reaper. Real registration sites: `agent-runner.ts:1276-1381` (legacy accumulator) + `cc-dispatcher.ts:948` (router factory).
- **Scope drift:** source plan §V2-13 row (line 385) framed tier-classification as covering plugin MCPs (Pencil/Playwright/Supabase/Stripe/Cloudflare/Vercel); this PR scopes to the in-process `soleur_platform` server only. Plugin MCP allowlisting remains out of scope; the `CC_MCP_ALLOWLIST` mechanism is reusable later.
EOF
gh issue edit 2909 --body-file /tmp/issue-2909-body.md
```

**Acceptance:** `gh issue view 2909 --json body --jq .body | grep -c 'Reconciliation (added 2026-05-13'` ≥ 1.

### Phase 4.2 — Document CC_MCP_ALLOWLIST in .env.example

Append to `apps/web-platform/.env.example`:

```bash
# CC_MCP_ALLOWLIST — cc-soleur-go router MCP tool allowlist (#2909).
# Comma-separated list of platform tool short-names. Default (unset/empty)
# preserves the deny-by-default posture: no in-process MCP tools registered
# for router-dispatched skills. Phase 1 (this PR) only enforces the Tier 3
# denylist; full unknown-name validation + tool registration lives in
# Phase 2 (#3722). NEVER include plausible_* short-names — they are in
# CC_ROUTER_TIER3_DENYLIST and will throw at factory construction.
# CC_MCP_ALLOWLIST=
```

**Acceptance:** `grep -c 'CC_MCP_ALLOWLIST' apps/web-platform/.env.example` ≥ 1.

### Phase 5 — Verification

5.1. `bunx tsc --noEmit` from `apps/web-platform/` — zero errors.
5.2. `bun test apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` — all GREEN.
5.3. `bun test apps/web-platform/test/tool-tiers.test.ts` — all GREEN.
5.4. Full project test command — no regressions in adjacent tests.
5.5. Smoke: start cc-soleur-go runner with `CC_MCP_ALLOWLIST` unset — confirm `mcpServers === {}` preserved.

### Phase 6 — Post-merge (operator)

**Pre-merge (PR):** Phases 1.1 through 5. **Post-merge (operator):**

6.1. **Doppler dev:** set `CC_MCP_ALLOWLIST=""` (empty string) via `doppler secrets set CC_MCP_ALLOWLIST="" -p soleur -c dev`. **Automation:** feasible; operator ack per `hr-menu-option-ack-not-prod-write-auth`.
6.2. **Doppler prd:** same with `-c prd`. Operate sequentially per `hr-dev-prd-distinct-supabase-projects`.
6.3. **Conditional issue close (Kieran P1-2):** `gh issue view 2909 --json state -q .state` — if `OPEN`, run `gh issue close 2909 --comment "Closed by PR #3720 — Phase 1 deny-by-default scaffolding shipped. Phase 2 promotion tracked at #3722."`; else skip with log line. (Fallback for PRs where `Closes #N` was forgotten; usually a no-op.)
6.4. Verify #3722 status remains OPEN with `blocked-by: #2939` linkage.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `tool-tiers.ts` exports `CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string>` with exactly the 3 Plausible FQNs; `TOOL_TIER_MAP` values unchanged. Verify: `git diff main -- apps/web-platform/server/tool-tiers.ts | grep -E '^[+-]\s*"mcp__soleur_platform__' | grep -v '//' | wc -l` returns 0.
- [ ] AC2: `cc-dispatcher.ts` defines `readCcMcpAllowlist()` function (inline, not separate file); call site at the former `mcpServers: {}` location.
- [ ] AC3: When `CC_MCP_ALLOWLIST` is unset/empty/whitespace-only, `readCcMcpAllowlist()` returns `{}` (deny-by-default preserved).
- [ ] AC4: When `CC_MCP_ALLOWLIST` contains any Tier 3 short-name (`plausible_create_site`, `plausible_add_goal`, `plausible_get_stats`), `readCcMcpAllowlist()` throws plain `Error` with message containing `"permanent Tier 3 denylist"` AND the offending name. **Denylist check precedes any other validation regardless of position in the env value** — `"foo,plausible_create_site"` throws with `plausible_create_site` in the message, not `foo`.
- [ ] AC5: Sentry mirror (via `reportSilentFallback`) fires with `feature: "cc-mcp-tier"`, `op: "unregistered-tool-invoked"`, `extra: { toolName, userId, conversationId, leaderId: "cc_router" }` when the cc-router iterator observes a `tool_use` block naming `mcp__soleur_platform__<unknown>`. Mirror lives in `dispatchSoleurGo`'s iterator hook (Candidate B), NOT in `createCanUseTool`.
- [ ] AC6: Helper-bypass grep returns empty: `rg 'Sentry\.capture(Message|Exception)' apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/permission-callback.ts | grep -v 'reportSilentFallback'`.
- [ ] AC7: `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table contains rows for **GitHub Inc** AND **Plausible Analytics**.
- [ ] AC8: `knowledge-base/legal/article-30-register.md` has 4 new rows for kb_share, conversations_lookup, GitHub tools, Plausible — each annotated "Phase 1 status: not exposed; Phase 2 tracked by #3722".
- [ ] AC9: `apps/web-platform/.env.example` documents `CC_MCP_ALLOWLIST`.
- [ ] AC10: `bun test` for both touched test files passes; full suite has no regressions.
- [ ] AC11: Issue #2909 body has a "Reconciliation (added 2026-05-13...)" block.
- [ ] AC12: PR body uses `Closes #2909` (auto-close at merge); `Related: #3722` in body but NOT `Closes #3722`.

### Post-merge (operator)

- [ ] AC13: Doppler dev `CC_MCP_ALLOWLIST` set to empty string (operator ack).
- [ ] AC14: Doppler prd same. Verify via `doppler secrets get CC_MCP_ALLOWLIST -p soleur -c prd --plain` returns empty.
- [ ] AC15: Phase 2 tracking issue #3722 remains OPEN with `blocked-by: #2939`.
- [ ] AC16: If issue #2909 was not auto-closed by `Closes #2909`, operator runs the conditional close from Phase 6.3.

## Sharp Edges

- **`TOOL_TIER_MAP` shared with legacy path.** Comment-only edits in Phase 2.1.2 are deliberate; any value change would force a breaking change to the legacy `startAgentSession` contract. AC1 diff command guards this.
- **`CC_ROUTER_TIER3_DENYLIST` is a code constant.** It MUST NOT be overridable via env var, command-line, or any operator surface. The denylist is the cross-tenant credential boundary; configuration override would defeat the entire Phase 1 scaffolding.
- **Phase 1 only enforces the denylist, not unknown-name validation.** A misconfigured Doppler value like `CC_MCP_ALLOWLIST=not_a_real_tool` does NOT throw in Phase 1 — `readCcMcpAllowlist` returns `{}` (Phase 1 always returns `{}` regardless of valid names present). Full unknown-name validation lives in Phase 2 (#3722) alongside the first real tool registration. Document this explicitly in the `.env.example` comment and in the helper docstring.
- **Sentry mirror lives at the iterator hook, NOT canUseTool** (Kieran P0-1). The SDK rejects unknown MCP tools before `canUseTool` is invoked; the iterator hook is the only observable surface. Verify Phase 2.2.4 lands in `dispatchSoleurGo`'s `for await` loop, not `createCanUseTool`.
- **Plausible region verification at DPA-row authorship** (Phase 3.2.1) — plausible.io EU vs self-hosted have different Chapter V postures. Do NOT copy a template row.
- **`legal-document-generator` outputs require operator review** before commit (Phases 3.1.2, 3.2.2). Agent produces DRAFT marked output.
- **`Closes #2909` vs `Related: #3722`** — never close #3722 from this PR (#3722 is the Phase 2 deferral container). Phase 6.3 close is conditional.
- **Denylist is name-based, not shape-based.** `CC_ROUTER_TIER3_DENYLIST` enumerates 3 specific Plausible FQNs. A future tool that mirrors Plausible's shape (single backend service token, no per-user / per-site scoping) is NOT auto-blocked — the future PR author must add the new FQN to the denylist at the same time the tool lands. Phase 2 (#3722) plan MUST include a "shared-credential audit" gate before any tool promotion that asks: does this tool's backing credential support per-user scoping, or is one key used for all tenants? If the latter, add to denylist before promotion. Generalization to a shape-based check (introspect the tool's auth model at registration time) is a Phase 3 concern and tracked as tech debt via this bullet.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `dispatchSoleurGo` iterator hook fires for legacy `startAgentSession` paths too | Low | Iterator lives in cc-dispatcher.ts's dispatch function; legacy uses agent-runner.ts's `startAgentSession`. Confirm at Phase 2.2.4 read time. |
| GitHub Inc / Plausible DPA links broken at row-creation | Low | Operator verifies links live at 3.1.1 / 3.2.1; legal-document-generator drafts marked DRAFT. |
| `TOOL_TIER_MAP` annotation accidentally changes a tier value | Medium | AC1 diff command catches any non-comment value-line change. |
| Phase 2 (#3722) is forgotten | Low | Issue created at brainstorm time; PR body references; Phase 6.4 verifies blocked-by linkage. |

## Non-Goals (deferred to Phase 2 tracking issue #3722)

- Promotion of any read-only Tier 1 candidate.
- Promotion of Tier 2 writes (kb_share_create/revoke, github writes). Review-gate UX integration with cc-router is its own brainstorm.
- Extension of `CC_PATH_ALLOWED_TOOLS` (cc-dispatcher.ts:560).
- Plugin MCP allowlisting (Pencil/Playwright/Supabase/Stripe/Cloudflare/Vercel) per source plan §V2-13.
- Per-tool invocation telemetry beyond the Sentry silent-failure mirror.
- Unknown-name validation in `readCcMcpAllowlist` — Phase 1 only enforces the denylist; Phase 2 adds full validation alongside the first real tool registration.
- Conversations write tools (`conversations_list`, `conversation_archive`, `conversation_unarchive`).
- Lawful-basis-per-tool table, mini-DPIA, retention, erasure cascade — all live in #3722 plan with first real promotion.
