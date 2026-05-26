---
title: Tier-classify in-process MCP tools for cc-soleur-go (V2-13)
date: 2026-05-13
issue: 2909
plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
branch: feat-mcp-tier-classify-2909
draft_pr: 3720
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Brainstorm — MCP tier classification for cc-soleur-go (#2909)

## User-Brand Impact

**Artifact:** the `soleur_platform` in-process MCP server registered for the cc-soleur-go router path (17 tools across kb_share, conversations, GitHub, Plausible families).

**Vectors endorsed by operator (all three):**
- **Cross-tenant data read** — a misclassified read tool returns one user's KB / conversations / analytics to another user's agent session.
- **Credential / token leak** — a misclassified GitHub or Plausible tool exposes an installation-token or shared backend service-token to an unauthorized router session.
- **Unauthorized writes** — a Tier 2 write tool (kb_share_create/revoke, github_push_branch, plausible_*) becomes callable from the router without per-user authorization.

**Threshold:** `single-user incident`. Any single-user cross-tenant read, credential leak, or unauthorized write is brand-survival-critical.

## What We're Building

A two-phase rollout, inverting the issue's framing from "ship a tier table" to "lock the deny-by-default posture first, promote later."

**Phase 1 (this PR, scope of #2909):**
- Keep `cc-dispatcher.ts realSdkQueryFactory` at `mcpServers: {}` (no change to current empty-set posture).
- Add a **Doppler-controlled allowlist** env var (`CC_MCP_ALLOWLIST`, default empty) that the factory reads at construction time. When non-empty, the factory registers a narrowed `soleur_platform` server containing only the named tools.
- Add a **Sentry-mirrored silent-failure guard** in `permission-callback.ts createCanUseTool` for any `mcp__soleur_platform__*` invocation that lands while the tool isn't registered. Today this is an invisible failure; the guard closes the regression surface the tier-table feature would otherwise create.
- Add the **DPA prerequisite rows** (GitHub Inc, Plausible Analytics) to `knowledge-base/legal/compliance-posture.md` per the #3594 precedent. Without these rows, no tool from those families can ever be promoted regardless of tier table.
- Document the **tier vocabulary** as comments on the existing `TOOL_TIER_MAP` in `apps/web-platform/server/tool-tiers.ts` — the runtime infrastructure already exists; we are formalizing semantics, not adding mechanism.

**Phase 2 (deferred, new issue, NOT this PR):**
- Promote the 8 unambiguously-Tier-1 reads (`kb_share_list`, `kb_share_preview`, `conversations_lookup`, `github_read_*` × 6) via `CC_MCP_ALLOWLIST` once empirical demand is observed AND Stage 6 (#2939) closes AND CLO confirms DPA rows are accepted.
- Promote Tier 2 writes only if a router-dispatched skill demonstrates a use case the review-gate UX can serve.
- **Permanent Tier 3 (never promoted):** all three `plausible_*` tools. They share a single backend `PLAUSIBLE_API_KEY` with no per-user / per-site enforcement — exposing them via the router is a definitionally cross-tenant credential, regardless of tier label.

## Why This Approach

The synthesis bridges three convergent leader findings and one new constraint surfaced by research:

1. **CPO: zero confirmed demand.** cc-soleur-go has been always-on in prod since #3270 closed on 2026-05-11. In ~2 days with `mcpServers: {}` empty, no Sentry signal has surfaced for skill-dispatched tool-not-found errors. Empirical demand for any of the 17 tools is currently zero. Shipping a tier table now is premature taxonomy.
2. **CLO: hard-block on DPA gap.** GitHub Inc and Plausible Analytics are missing from `compliance-posture.md` Vendor DPA Status table. This blocks ship for ANY shape of router exposure of those families (matches #3594 precedent for Anthropic DPA gap). Adding those rows is a prerequisite that must land in this PR regardless of tier-table shape.
3. **CTO: infrastructure already exists.** `tool-tiers.ts`, `permission-callback.ts createCanUseTool`, `review-gate.ts`, `buildAgentQueryOptions` are all in place. The "new" work is configuration + a denylist constant + tests, not new infrastructure. So we lose nothing by deferring the explicit tier-table promotion to Phase 2.
4. **Plan/issue scope drift.** The source plan §V2-13 row (line 385) scopes tier-classification to PLUGIN MCPs (Pencil/Playwright/Supabase/Stripe/Cloudflare/Vercel); issue body scopes to IN-PROCESS soleur_platform tools. The deny-by-default + Doppler-allowlist scaffolding is the **superset solution** — it covers both surfaces without re-litigating which the issue "really" meant. Plugin MCPs are denied today (the cc-dispatcher's `pluginMcpServerNames: []` is empty); this PR preserves that posture and exposes the same Doppler-controlled allowlist mechanism for future promotion of any MCP server, plugin or in-process.
5. **Brand-survival threshold tightens.** The 2026-04-23 source plan §Stage 2.17 set the threshold as "no router-MCP exposure until per-tool justification." Under the user-brand-critical framing (all three vectors endorsed) and with no empirical demand, the threshold tightens to "no router-MCP exposure until per-tool justification AND a closed empirical-demand signal from Stage 6 telemetry." Phase 1 carries that forward; Phase 2 cannot ship until those gates clear.

## Key Decisions

| # | Decision | Rationale | Source |
|---|----------|-----------|--------|
| 1 | Ship Phase 1 as deny-by-default + Doppler `CC_MCP_ALLOWLIST` flag; defer Phase 2 promotion to a new issue gated on Stage 6 (#2939) + empirical demand | Zero confirmed router-skill need in 2 days of always-on prod; synthesizes CPO/CTO/CLO verdicts | CPO assessment; cc-dispatcher.ts:948; #3270 closure |
| 2 | Add GitHub Inc + Plausible Analytics DPA rows to `compliance-posture.md` in THIS PR (hard prerequisite) | CLO hard-block; matches #3594 precedent for Anthropic DPA gap | CLO assessment; knowledge-base/legal/compliance-posture.md Active Items row 3 |
| 3 | Plausible tools (`plausible_create_site/add_goal/get_stats`) are permanently Tier 3 (never promotable via Doppler flag) | All three share a single backend `PLAUSIBLE_API_KEY` with no per-user/per-site enforcement — cross-tenant by construction | CTO assessment; plausible-tools.ts:52-74; agent-runner.ts:1319 |
| 4 | Add Sentry-mirrored silent-failure guard in `permission-callback.ts createCanUseTool` for unregistered `mcp__soleur_platform__*` invocations | Per `cq-silent-fallback-must-mirror-to-sentry`; today this is an invisible failure surface that the tier feature would otherwise compound | CTO assessment §4; agent-runner.ts:1269 (default-branch-lookup precedent) |
| 5 | Doppler env var `CC_MCP_ALLOWLIST` is comma-separated tool names, validated against `TOOL_TIER_MAP` at factory construction time; unknown names fail-closed (factory throws on boot) | Fail-closed matches `tool-tiers.ts:54-56` default; unknown tool name = configuration error, not silent omit | CTO assessment §2; tool-tiers.ts |
| 6 | Phase 1 tests live in a new file `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` covering: (a) empty allowlist → `mcpServers: {}`, (b) populated allowlist → only named tools registered, (c) unknown name in allowlist → factory throws, (d) Sentry mirror fires on unregistered-tool invocation | New surface = new test file; extending `canusertool-tiered-gating.test.ts` (legacy path) would conflate concerns | CTO assessment §3; cq-test-fixtures-synthesized-only |
| 7 | `tool-tiers.ts` is annotated (comments only) with cc-router tier semantics; no code change to `TOOL_TIER_MAP` in Phase 1 | The existing map serves the legacy `startAgentSession` path correctly; conflating cc-router tiers with legacy tiers would force a breaking change to the legacy contract | CTO assessment; tool-tiers.ts:20-47 |

## Non-Goals (deferred to Phase 2 or rejected)

- **Tier 1 promotion of read-only tools.** Deferred until Stage 6 (#2939) closes + empirical demand telemetry exists. New tracking issue to be created at Phase 3.6.
- **Tier 2 promotion of write tools (kb_share_create/revoke, github writes).** Deferred. Review-gate UX integration with cc-router is a non-trivial scope expansion; treat as a separate brainstorm if/when a router-dispatched skill demands it.
- **Plugin MCP allowlist (Pencil/Playwright/Supabase/Stripe/Cloudflare/Vercel).** Per plan §V2-13 (line 385) and Sharp Edge #10 (line 546), plugin MCPs are out of scope for this iteration. The Doppler flag mechanism is reusable for plugin MCPs in a future PR.
- **Conversations write tools (`conversations_list`, `conversation_archive`, `conversation_unarchive`).** Defined in `conversations-tools.ts` but NOT currently registered on the legacy path either (only `conversations_lookup` is). Out of scope; flag for a separate audit.
- **Per-tool invocation telemetry.** Mentioned by CPO as a Phase 2 guardrail; deferred. The Sentry silent-failure mirror (Decision 4) provides the minimum signal needed for Phase 1.

## Open Questions

1. **Doppler vs in-repo config.** `CC_MCP_ALLOWLIST` could alternatively be a constant in `cc-dispatcher.ts` (PR-gated rather than runtime-gated). Doppler is recommended for the same reason `FLAG_CC_SOLEUR_GO` was Doppler-gated: pull-back without a redeploy. Confirm at plan time which env-management primitive applies (likely `Doppler` per `cc-cost-caps.ts` precedent).
2. **DPA row authorship.** CLO assessment cites `legal-document-generator` + `legal-compliance-auditor` skills. Plan task should explicitly invoke one of these to author the GitHub + Plausible DPA rows, with operator review before ship.
3. **Plan/issue scope drift in #2909 body.** The issue body cites `agent-runner.ts:765-772` which is now the stuck-active reaper (unrelated). The plan should explicitly update the issue body or close-comment to clarify the real registration site (`agent-runner.ts:1276-1381` + `cc-dispatcher.ts:948`).
4. **Stage 6 (#2939) closure dependency for Phase 2.** Phase 2 issue creation should set the Stage 6 issue as `blocked-by`. Confirm Phase 2 tracking-issue title / body shape at Phase 3.6.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Refine framing first — the right product shape is deny-by-default with Doppler-controlled promotion, not a tier label table. Zero confirmed router-skill demand in 2 days of always-on prod (#3270 closed 2026-05-11) means any tier table ships premature taxonomy. Plausible tools are unconditionally Tier 3; everything else stays empty until Stage 6 (#2939) telemetry shows demand. Brand-survival threshold tightens under this scope.

### Legal (CLO)

**Summary:** Soft-block on `kb_share_*` + `conversations_lookup` (in-tool user-scope assertion required, not just router allowlist). **Hard-block** on any GitHub or Plausible router exposure until DPA rows are added to `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table — identical-shape gap to #3594 Anthropic DPA precedent. `gdpr-gate` skill is applicable; spec must include lawful basis per tool, Chapter V cross-border check, mini-DPIA (Art. 35) for `conversations_lookup`'s systematic-monitoring surface, retention bounds, erasure cascade, Art. 9 absence assertion. Prior CLO sign-off on the 2026-04-23 plan covered the empty-set posture and explicitly deferred the act-of-exposing decision to this brainstorm — V2-13 is the gate, not an optional follow-up.

### Engineering (CTO)

**Summary:** Ready-to-spec. Existing infrastructure (`tool-tiers.ts`, `permission-callback.ts createCanUseTool` lines 533-610, `review-gate.ts`, `buildAgentQueryOptions`) is plumbed but unpopulated for cc-router; work is configuration + denylist constant + tests, not new infra. Recommends Option C hybrid (Tier 1 register + pre-approve, Tier 2 register + review-gate, Tier 3 do-not-register + Sentry mirror) — but the deny-by-default Phase 1 synthesis preserves all CTO mechanics while honoring CPO's empirical-demand gate. **Plausible permanently Tier 3** due to shared service-token cross-tenant scope. New silent-failure surface (unregistered-tool invocation) must be Sentry-mirrored per `cq-silent-fallback-must-mirror-to-sentry`. New test file `cc-mcp-tier-allowlist.test.ts` covers factory output + Sentry mirror. Complexity: small (hours), ~3 file edits + 1 new test.

## Capability Gaps

None. CLO and CTO both confirmed existing skills + infrastructure cover the work. `legal-document-generator` authors DPA rows; `gdpr-gate` enforces the privacy-by-default sweep at plan/ship time; `tool-tiers.ts` already encodes the tier vocabulary; `permission-callback.ts createCanUseTool` already enforces tier decisions; `review-gate.ts` already serves Tier 2 review-gate UX (Phase 2 only).

Evidence (per `2026-05-05-brainstorm-capability-gaps-need-repo-grep.md`):

- `apps/web-platform/server/tool-tiers.ts` — `TOOL_TIER_MAP` lines 20-47, `getToolTier` lines 54-56, `buildGateMessage` lines 63-86 (verified by Explore agent)
- `apps/web-platform/server/permission-callback.ts:533-610` — platform tool tier enforcement (verified by Explore agent)
- `apps/web-platform/server/review-gate.ts` — exists, gated tier UX integration (verified by CTO)
- `plugins/soleur/skills/gdpr-gate/SKILL.md` — exists with canonical regex (verified by CLO)
- `plugins/soleur/agents/legal-document-generator.md` — exists (verified by CLO)
- `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table — exists, GitHub + Plausible rows confirmed missing (verified by CLO)
