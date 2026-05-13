---
name: mcp-tier-classify-2909
title: MCP tier classification for cc-soleur-go (Phase 1 deny-by-default scaffolding)
date: 2026-05-13
issue: 2909
brainstorm: knowledge-base/project/brainstorms/2026-05-13-mcp-tier-classify-cc-soleur-go-brainstorm.md
plan_source: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
plan_section: "§Stage 2.17, Sharp Edge #10"
branch: feat-mcp-tier-classify-2909
draft_pr: 3720
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
domains_assessed: [Product, Legal, Engineering]
domain_review_carryforward:
  cpo: "2026-05-13 brainstorm — defer tier-table promotion; deny-by-default + Doppler allowlist + Sentry mirror is the right shape"
  clo: "2026-05-13 brainstorm — DPA rows for GitHub Inc + Plausible Analytics are a HARD prerequisite in this PR; gdpr-gate skill required at ship"
  cto: "2026-05-13 brainstorm — existing infra (tool-tiers.ts, permission-callback.ts, review-gate.ts) covers Phase 1; new work is config + denylist + tests"
---

# Feature: MCP tier classification for cc-soleur-go (Phase 1)

## Problem Statement

The `cc-soleur-go` router (`apps/web-platform/server/cc-dispatcher.ts:948 realSdkQueryFactory`) currently passes `mcpServers: {}` (empty) to the Claude Agent SDK's `query()`. Skills dispatched from the router cannot call any in-process tool from the legacy `soleur_platform` MCP server (17 tools across kb_share, conversations, GitHub, Plausible families). This is the correct deny-by-default posture for an untrusted-user threat model — and per source plan §Stage 2.17, V1 ships this way intentionally — but:

1. The empty-set posture is **enforced by omission**, not by a checked allowlist mechanism. If a future PR widens `mcpServers` ad-hoc, the brand-survival threshold (user_brand_critical: single-user incident) is not protected by code.
2. When a skill attempts to invoke an unregistered `mcp__soleur_platform__*` tool, the SDK reports `unknown tool` to the model — **this is a silent failure surface today** (no Sentry mirror), violating `cq-silent-fallback-must-mirror-to-sentry`. If a router-dispatched skill silently drops a tool call, the regression is invisible until a user complains.
3. **DPA gap (CLO hard-block):** `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table is missing rows for GitHub Inc and Plausible Analytics. Both are processors of operator/user PII (issue bodies, commit author emails, IP-pseudonymized analytics). Per #3594 precedent, this is a ship-blocking gap regardless of tier-table shape — must be closed before any router exposure can be considered.
4. The plan's V2-13 row (line 385) scopes tier-classification to PLUGIN MCPs (Pencil/Playwright/Supabase/Stripe/Cloudflare/Vercel); issue #2909 body scopes to IN-PROCESS soleur_platform tools. Scope drift must be reconciled.
5. Issue body's line reference (`agent-runner.ts:765-772`) is stale; real registration is `agent-runner.ts:1276-1381` + `cc-dispatcher.ts:948`.

## Goals

- **G1.** Lock the deny-by-default posture in code via a Doppler-controlled allowlist (`CC_MCP_ALLOWLIST`) read at factory construction. Default empty = current behavior. Any future promotion requires a Doppler config change, not a code change.
- **G2.** Close the silent-failure surface: add Sentry-mirrored warning in `permission-callback.ts createCanUseTool` for any `mcp__soleur_platform__*` invocation that lands while the tool isn't registered.
- **G3.** Close the CLO DPA hard-block: add GitHub Inc + Plausible Analytics rows to `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table (#3594 precedent).
- **G4.** Document the cc-router tier vocabulary inline in `tool-tiers.ts` (comments only — no `TOOL_TIER_MAP` change). Permanent Tier 3 (never promotable): `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats` (shared backend service token = cross-tenant by construction).
- **G5.** Create a Phase 2 tracking issue for the actual promotion of read-only tools, blocked-by Stage 6 (#2939) + empirical-demand signal.

## Non-Goals

- **NG1.** Do NOT actually promote any tool to Tier 1 / Tier 2 in this PR. `CC_MCP_ALLOWLIST` defaults to empty; no tool is registered by default. Promotion is Phase 2 work.
- **NG2.** Do NOT modify `TOOL_TIER_MAP` in `tool-tiers.ts`. The legacy `startAgentSession` path depends on it and changing the map would force a breaking change to the legacy contract. Comments-only annotations are sufficient.
- **NG3.** Do NOT extend `mcpServers` to plugin MCPs (Pencil/Playwright/Supabase/Stripe/Cloudflare/Vercel). Plan §V2-13 scope; the Doppler allowlist mechanism is reusable later but not exercised here.
- **NG4.** Do NOT integrate review-gate UX with the cc-router (Tier 2 enforcement). Deferred to Phase 2.
- **NG5.** Do NOT add per-tool invocation telemetry beyond the Sentry silent-failure mirror. The mirror provides the minimum signal needed for Phase 1; richer telemetry is Phase 2 guardrail.
- **NG6.** Do NOT modify `conversations-tools.ts` to register the three currently-unregistered write tools (`conversations_list`, `conversation_archive`, `conversation_unarchive`). Out of scope.

## Functional Requirements

### FR1: Doppler-controlled allowlist

- **FR1.1** `cc-dispatcher.ts realSdkQueryFactory` reads `process.env.CC_MCP_ALLOWLIST` at factory construction time. Format: comma-separated tool names (e.g., `kb_share_list,conversations_lookup`). Whitespace tolerant.
- **FR1.2** Empty / unset env var → `mcpServers: {}` (current behavior preserved).
- **FR1.3** Non-empty env var → factory constructs a narrowed `soleur_platform` server containing only tools whose names appear in the allowlist AND in the legacy `platformToolNames[]` set built by `agent-runner.ts:1276-1381`.
- **FR1.4** Tool names in `CC_MCP_ALLOWLIST` that don't exist in any of `github-tools.ts`, `plausible-tools.ts`, `kb-share-tools.ts`, `conversations-tools.ts` → **factory throws at construction time** (fail-closed; matches `tool-tiers.ts:54-56` default).
- **FR1.5** Tool names in `CC_MCP_ALLOWLIST` that match a permanent Tier 3 denylist (initially: `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats`) → **factory throws at construction time**, regardless of operator intent. The denylist is the cross-tenant credential boundary; it cannot be bypassed via config.

### FR2: Silent-failure Sentry mirror

- **FR2.1** `permission-callback.ts createCanUseTool` emits a Sentry-mirrored structured log (pino `log.warn`, NOT `console.log`) when it observes an invocation of `mcp__soleur_platform__<tool>` where `<tool>` is NOT in the currently-registered platform tool set.
- **FR2.2** Log shape: `{ feature: "cc-mcp-tier", op: "unregistered-tool-invoked", toolName, userId, conversationId, leaderId }`. Tag mirrors `2026-04-10-cicd-mcp-tool-tiered-gating-review-findings.md` audit-log pattern.
- **FR2.3** The callback still denies the invocation (SDK behavior unchanged). The mirror is observability, not enforcement.
- **FR2.4** Does NOT fire for legacy-path invocations (only `cc-soleur-go` router context). Use the existing leader-id discrimination (`CC_ROUTER_LEADER_ID` constant) to scope.

### FR3: DPA prerequisite rows (legal hard-block closure)

**Canonical table shape (per `compliance-posture.md` line 35 header — 6 columns):** `| Vendor | DPA Status | Signed/Verified | Transfer Mechanism | Data Region | Notes |`. The role / data-categories / legal-basis / retention fields named below MUST be folded into the `Notes` column — do NOT widen the table. (Per #2909 review: data-integrity-guardian flagged the prior 7-field framing as schema drift; learning `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`.)

- **FR3.1** Add row for **GitHub Inc** to the Vendor DPA Status table. Notes-column content: role (sub-processor for operator GitHub App installations), data categories (issue bodies, commit author emails, repo metadata, installation tokens), legal basis (Art. 6(1)(f)), retention (tied to GitHub's own lifecycle — 60-day audit log per published policy).
- **FR3.2** Add row for **Plausible Analytics (Plausible Insights OÜ)** to the same table. Notes-column content: role (sub-processor for operator-bound analytics), data categories (ephemeral IP processing with 24h hashed retention per Plausible DPA — IPs hashed at intake and discarded within 24h; no cookies, no persistent identifiers), legal basis (Art. 6(1)(f)), region verified at row authorship (EU-hosted vs self-hosted US determines Transfer Mechanism).
- **FR3.3** Both rows authored via `plugins/soleur/agents/legal-document-generator` agent invocation in the plan execution; operator review before commit.
- **FR3.4** `knowledge-base/legal/article-30-register.md` (RoPA) updated with new processing activities for any MCP-exposed tool surface that could be promoted in Phase 2 (read-only annotation; no operational change).

### FR4: Tier vocabulary annotation

- **FR4.1** Add inline comments to `apps/web-platform/server/tool-tiers.ts` `TOOL_TIER_MAP` (lines 20-47) annotating each entry with its cc-router tier intent: `// cc-router: Tier 1 read-only candidate` / `// cc-router: Tier 2 write candidate` / `// cc-router: Tier 3 PERMANENT (never promote)`.
- **FR4.2** Add a new exported constant `CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string>` containing the three Plausible tool names. The factory in FR1.5 reads this constant.
- **FR4.3** Document the rationale for each Tier 3 entry inline (single-sentence comment citing the cross-tenant credential).

### FR5: Phase 2 tracking issue

- **FR5.1** During plan execution, create a new GitHub issue titled `feat: V2-13 Phase 2 — promote read-only MCP tools to cc-router via CC_MCP_ALLOWLIST` with label `priority/p3-low`, `type/feature`, `domain/engineering`, milestone `Post-MVP / Later`.
- **FR5.2** Issue body cites: brainstorm + spec paths, Phase 1 PR (this one), `blocked-by: #2939` (Stage 6 closure), and a checklist of the 8 candidate Tier 1 reads.

## Technical Requirements

### TR1: Tool inventory ground truth (informational)

Confirmed registration sites (post-research):

- **Legacy path:** `agent-runner.ts:1276-1381` accumulates tools via `buildGithubTools` (line 1276), `buildPlausibleTools` (line 1319), `buildKbShareTools` (line 1353), `buildConversationsTools` (line 1370); single `createSdkMcpServer` call at lines 1376-1381 names the server `soleur_platform`.
- **Router path:** `cc-dispatcher.ts:948 realSdkQueryFactory` passes `mcpServers: {}`.

17 tools total. Tier intent (cc-router) annotated in `tool-tiers.ts` per FR4:

| Family | Tools | cc-router tier intent | Permanent denylist? |
|--------|-------|----------------------|---------------------|
| GitHub reads (6) | `github_read_ci_status`, `github_read_workflow_logs`, `github_read_issue`, `github_read_issue_comments`, `github_read_pr`, `github_list_pr_comments` | Tier 1 candidate (Phase 2) | No |
| GitHub writes (3) | `github_trigger_workflow`, `github_push_branch`, `create_pull_request` | Tier 2 candidate (Phase 2) | No |
| Plausible (3) | `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats` | Tier 3 PERMANENT | **YES** |
| kb_share reads (2) | `kb_share_list`, `kb_share_preview` | Tier 1 candidate (Phase 2) | No |
| kb_share writes (2) | `kb_share_create`, `kb_share_revoke` | Tier 2 candidate (Phase 2) | No |
| conversations (1) | `conversations_lookup` | Tier 1 candidate (Phase 2) | No |

### TR2: Doppler env var registration

- **TR2.1** Add `CC_MCP_ALLOWLIST` to Doppler `dev` and `prd` environments (default empty in both). Per `hr-dev-prd-distinct-supabase-projects` precedent, dev and prd configs are independent.
- **TR2.2** Add to `apps/web-platform/server/cc-cost-caps.ts`-equivalent env reader (or wherever cc-runner env vars are centralized — verify at plan time).
- **TR2.3** Document the env var in `apps/web-platform/.env.example` and `apps/web-platform/README.md` (if env-var documentation exists there).

### TR3: Test surface

- **TR3.1** New file `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` covering:
  - Empty `CC_MCP_ALLOWLIST` → `mcpServers: {}`.
  - Valid allowlist (e.g., `kb_share_list,github_read_ci_status`) → only those tools registered in `soleur_platform`.
  - Unknown tool name → factory throws with clear error.
  - Tier 3 denylist tool name (any of three `plausible_*`) → factory throws with clear "permanent denylist" error.
  - Sentry mirror fires when an unregistered tool is invoked (mock `Sentry.captureMessage`).
- **TR3.2** Extend `apps/web-platform/test/tool-tiers.test.ts` to assert `CC_ROUTER_TIER3_DENYLIST` contains exactly the three Plausible tool names.
- **TR3.3** Fixtures synthesized per `cq-test-fixtures-synthesized-only`. Reuse `createApiKeysMock` and `setupSupabaseMock` patterns from `canusertool-tiered-gating.test.ts:158-200`.
- **TR3.4** TDD: failing test lands BEFORE source change per `cq-write-failing-tests-before`.

### TR4: GDPR gate at plan/ship time

- **TR4.1** Spec is on the `gdpr-gate` regulated-data-surface list per CLO assessment (writes to `apps/web-platform/server/cc-dispatcher.ts` which gates PII-bearing tool surfaces). Plan must invoke `plugins/soleur/skills/gdpr-gate` at plan-output stage.
- **TR4.2** Spec carries lawful basis annotations for each tool family in TR1: Art. 6(1)(b) contract for `kb_share_*` + `conversations_lookup`; Art. 6(1)(f) legitimate-interest balancing for GitHub + Plausible (with balancing test documented in plan).
- **TR4.3** Mini-DPIA (Art. 35) for `conversations_lookup` — systematic-monitoring trigger per CLO. Document scope, necessity, safeguards in plan.
- **TR4.4** No Art. 9 special-category data surfaces. Assert and document.

### TR5: Drift-guard snapshot (per #2922 pattern)

- **TR5.1** Add snapshot test asserting the shape of `buildAgentQueryOptions` output's `mcpServers` field when `CC_MCP_ALLOWLIST` is empty (must be `{}`). Snapshot lives next to the new test file.
- **TR5.2** Drift-guard test must be a hard-coded shape assertion, not a Jest snapshot file — silent regressions where `mcpServers` becomes accidentally populated must fail loudly.

### TR6: Plan/issue scope drift reconciliation

- **TR6.1** Plan must post a comment to issue #2909 clarifying: (a) real registration site is `agent-runner.ts:1276-1381` + `cc-dispatcher.ts:948`; (b) plan §V2-13 row (line 385) plugin-MCP framing is out of scope for this iteration; (c) Phase 2 tracking issue is created for actual tool promotion.
- **TR6.2** Plan updates source plan §Stage 2.17 with a back-reference to the Phase 1 PR + Phase 2 tracking issue.
