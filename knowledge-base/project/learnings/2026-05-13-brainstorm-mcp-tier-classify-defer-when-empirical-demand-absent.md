---
title: When a tier-classification feature has zero empirical demand, ship the deny-by-default scaffolding instead of the tier table
date: 2026-05-13
category: project
module: brainstorm
issue: 2909
brainstorm: knowledge-base/project/brainstorms/2026-05-13-mcp-tier-classify-cc-soleur-go-brainstorm.md
spec: knowledge-base/project/specs/feat-mcp-tier-classify-2909/spec.md
tags: [brainstorm, mcp, tier-classification, deny-by-default, dpa, user-brand-critical]
---

# Learning: Reframe tier-classification when empirical demand is zero

## Problem

Issue #2909 (V2-13) asked the engineering team to tier-classify the in-process `soleur_platform` MCP server's 17 tools (kb_share, conversations, GitHub, Plausible) for the cc-soleur-go router path. The issue's acceptance criteria implied building a Tier 1 / Tier 2 / Tier 3 label table and updating the cc-soleur-go factory's `mcpServers` config accordingly.

The brainstorm exposed three convergent constraints that made shipping the tier table as scoped a premature commitment:

1. **Zero empirical demand.** cc-soleur-go has been always-on in prod since #3270 closed on 2026-05-11. In ~2 days with `mcpServers: {}`, no Sentry signal has surfaced for unknown-tool errors from router-dispatched skills. The plan's re-eval criteria ("after Stage 4 reveals tool needs" + "after Stage 6 confirms baseline") are partially unmet — Stage 6 (#2939) is still open.
2. **DPA hard-block independent of tier shape.** GitHub Inc and Plausible Analytics are missing from `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table. Per the #3594 Anthropic-DPA precedent, this blocks ship for ANY router exposure of those families regardless of tier label. So the DPA rows must land before any tier table can ship — making the DPA work the load-bearing prerequisite, not a follow-up.
3. **Tier infrastructure already exists.** `tool-tiers.ts` `TOOL_TIER_MAP`, `permission-callback.ts createCanUseTool:533-610`, and `review-gate.ts` are all plumbed for the legacy `startAgentSession` path. The cc-router factory just passes `mcpServers: {}` and `platformToolNames: []`. The work is configuration + a denylist constant + a Sentry mirror — not new infrastructure.

Additionally, the issue body cited a stale line reference (`agent-runner.ts:765-772`) which is now the stuck-active reaper. The real registration site is `agent-runner.ts:1276-1381` + `cc-dispatcher.ts:948`. And the plan §V2-13 row (line 385) scopes tier-classification to *plugin* MCPs while the issue body scopes *in-process* tools — scope drift that, left unreconciled, would have produced an internally-coherent design premised on the wrong surface.

## Solution

Reframe the issue from "ship the tier table" to "lock the deny-by-default posture in code + close the DPA prerequisite + add a permanent Tier 3 denylist for cross-tenant credentials."

**Phase 1 (this PR, closes #2909):**
- Doppler-controlled `CC_MCP_ALLOWLIST` env var (default empty = current behavior) — locks the posture in code, not in code-omission.
- `CC_ROUTER_TIER3_DENYLIST` constant containing the 3 Plausible tools — permanent denylist, cannot be promoted via Doppler. Cross-tenant by construction (shared `PLAUSIBLE_API_KEY`).
- Sentry-mirrored silent-failure guard for unregistered `mcp__soleur_platform__*` invocations.
- DPA rows for GitHub Inc + Plausible Analytics added to `compliance-posture.md`.
- Inline tier-intent annotations on `TOOL_TIER_MAP` (comments only — no map change).

**Phase 2 (new tracking issue #3722, deferred):** actual promotion of read-only Tier 1 tools via `CC_MCP_ALLOWLIST`, gated on Stage 6 (#2939) closure + empirical demand telemetry.

## Key Insight

When a brainstorm produces three convergent verdicts (CPO defer, CLO hard-block, CTO ready-to-spec hybrid) the synthesis often looks like a two-phase split: do the prerequisite + scaffolding work that all three views agree on now, defer the contested deliverable until the prerequisites close and empirical demand confirms the framing.

Specifically:

- **Empirical-demand check.** If a feature exists to satisfy a hypothetical use case AND the system has been running in deny-by-default mode in prod long enough to produce telemetry AND the telemetry shows zero attempts at the use case, the feature is premature. The right shape is to harden the deny-by-default posture (so it cannot drift) and create a Phase 2 issue blocked on the empirical signal.
- **DPA-as-prerequisite pattern.** When a router/surface widens its access to third-party processors, missing DPA rows in `compliance-posture.md` are a HARD prerequisite to be closed in the same PR, not a follow-up. This matches the #3594 Anthropic-DPA precedent. The CLO assessment converted a "soft block" claim into a "hard block" via the precedent grep — without that, the DPA work would have been deferred and the actual feature would have shipped over an open compliance gap.
- **Permanent denylist construction.** A tool whose backing credential is cross-tenant by design (single backend service token serving all tenants — Plausible's `PLAUSIBLE_API_KEY`) is permanently Tier 3 regardless of any future demand. The denylist must be a code constant that the allowlist mechanism CANNOT override — not a doc convention.

## Session Errors

- **`AskUserQuestion` tool called without `questions` parameter** — InputValidationError on first call. **Recovery:** re-called with proper schema. **Prevention:** the tool schema requires `questions` as a non-empty array; the call path that fired the empty invocation should validate before sending. Already-enforced (the harness returned a validation error); no new rule needed.
- **Stale line reference in issue body** (`agent-runner.ts:765-772` was the stuck-active reaper). **Recovery:** repo-research agent re-located the real registration site at `:1276-1381` + `cc-dispatcher.ts:948` before any code-touching work. **Prevention:** brainstorm protocol's "Verifying issue-body line ref claims" guidance worked as designed — the explicit Explore agent task to "locate the real registration site" caught this. No new rule needed; the existing guidance is load-bearing.

## Cross-references

- Source plan: `knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md` §Stage 2.17
- DPA precedent: #3594 (Anthropic DPA gap as ship-blocking prerequisite, not follow-up)
- Stage 6 dependency: #2939
- Phase 2 tracking: #3722
- Related learnings:
  - `knowledge-base/project/learnings/2026-04-10-cicd-mcp-tool-tiered-gating-review-findings.md` (tier-gating pattern in tool-tiers.ts)
  - `knowledge-base/project/learnings/2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md` (kb_share TOCTOU + mock cascade)
  - `knowledge-base/project/learnings/2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md` (verify referenced PR state — same shape as line-ref staleness)
