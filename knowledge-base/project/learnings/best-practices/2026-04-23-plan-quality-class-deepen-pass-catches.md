---
date: 2026-04-23
category: best-practices
module: planning
component: plan-skill
tags: [plan-quality, deepen-plan, tool-tier, cost-slo, discriminated-union, sentinel-values, agent-native-parity]
issue: 2853
related:
  - 2026-04-15-plan-skill-reconcile-spec-vs-codebase.md
  - integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md
---

# Plan-quality classes that deepen-plan reliably catches

## Problem

The #2853 plan went through 3 plan-review reviewers (DHH, Kieran, code-simplicity). It passed and was committed. Then `deepen-plan` ran a 5-agent pass (architecture-strategist, security-sentinel, agent-native-reviewer, performance-oracle, type-design-analyzer) and surfaced **27 additional findings** including 14 that warranted rewriting major plan sections (TOOL_TIER_MAP scope misuse, unrealistic cost SLO, polymorphic payload placeholder, magic-string sentinel violating codebase convention, MCP tool parity blind spot). All 14 were plan-quality errors that better up-front discipline could have caught at plan time, sparing the deepen rewrite.

## Solution

Five new plan-skill Sharp Edges, each targeting one error class:

1. **Tool-gating-map scope grep** — when prescribing extension to a tool-tier/permission/registry map, grep its current entries (`grep "^\s*['\"]" <map>` or read 5-10 entries) to verify scope before adding new entries. The #2853 plan extended `TOOL_TIER_MAP` for SDK-native tools, but `TOOL_TIER_MAP` is scoped to `mcp__soleur_platform__*` only — the entries would have been dead code. Permission gating for SDK-native tools (`Bash`, `Edit`, `Write`, etc.) flows through `permission-callback.ts` directly via `isFileTool`/`isSafeTool`/explicit branches.

2. **Cost SLO modeling for skill-mediated routing** — when prescribing aggregate cost SLO for a skill-mediated routing change, sum the per-skill baseline (subagent fan-out × per-leader cost) before fixing the cap. The #2853 plan proposed P95 ≤ $1.00 per conversation; brainstorm Phase 0.5 alone spawns 4 leaders at $0.05-0.15 each = $0.20-0.60 floor before any dialog. Realistic P95: $1.50-3.50 for brainstorm. The cap would fire constantly. Fix: split per-workflow caps ($0.50 for `one-shot`/`work`; $2.50 for `brainstorm`/`plan`).

3. **Polymorphic-payload sub-discrimination at plan time** — when widening a discriminated union with a `kind`-typed polymorphic payload, design the per-variant payload sub-union in the plan, not deferred to implementation. The #2853 plan wrote `interactive_prompt { kind: "ask_user" | "plan_preview" | ...; payload: ... }` with the placeholder elision. Type-design-analyzer flagged this as the highest-risk type gap — landing as `unknown` would create 6 cast-sites. Per-`kind` typed payloads must be in the plan: `| { kind: "ask_user"; payload: { question: string; options: string[]; multiSelect: boolean } }` etc.

4. **Sentinel-vs-NULL codebase convention check** — when proposing a sentinel value in a DB column, grep 2-3 recent migrations for the codebase's discriminator convention. Most codebases use NULL with partial indexes OR explicit boolean column OR proper enum — magic strings in free-text columns are anti-pattern. The #2853 plan used `'__unrouted__'` in `active_workflow text` to mean "born under flag, not yet routed". Architecture-strategist found 5+ migrations using NULL + partial indexes; never magic strings. Fix: wrap as TS ADT at storage boundary so the magic string never leaks past persistence. Even better: drop the sentinel and use a separate boolean column or re-read the flag at dispatch.

5. **WS-surface agent-native parity** — when a plan adds new operator-facing WebSocket events (especially client→server `interactive_prompt_response` style), check whether each new event has an MCP tool counterpart, or file a V2 tracking issue. Existing `cq-when-a-plan-scopes-agent-native-parity` rule covers UI hook surfaces; this generalizes to WS surfaces. The #2853 plan added 6 new client→server events with zero MCP tool counterparts; agent-native-reviewer caught it. Fix: 5 V2 tracking issues for `cc_send_user_message`, `cc_respond_to_interactive_prompt`, `cc_set_active_workflow`, `cc_abort_workflow`, `conversation_get` field exposure.

## Key insight

**Deepen-plan reviewers are not redundant with plan-review reviewers.** The two phases catch different error classes:

- **Plan-review** (DHH/Kieran/code-simplicity) is *generalist* — challenges overengineering, tightens TDD discipline, simplifies file count and stage count. They catch "is this plan well-structured and minimal?" but rarely "is this plan technically correct against the codebase's actual scope?"
- **Deepen-plan** specialists (architecture-strategist, security-sentinel, performance-oracle, type-design-analyzer, agent-native-reviewer) catch *specific* technical gaps: scope misunderstanding of an existing module, unrealistic SLO modeling, untyped polymorphic payloads, codebase-convention violations, agent-native parity gaps.

The #2853 session would have shipped a structurally clean plan with 5 silent technical bugs without the deepen pass. Five new plan-skill Sharp Edges (proposed below) move the catches into the plan phase itself, so future plans catch these classes before deepen, sparing the rewrite cost.

## Session Errors

1. **AskUserQuestion rejected on first orthogonality question** — drilled into mechanism before validating architectural framing. Recovery: re-asked with 3 readings of "use /soleur:go". **Prevention:** in brainstorms, validate the architectural premise before drilling into implementation tactics. *(Already covered by brainstorm skill Phase 1 instruction "validate assumptions explicitly".)*

2. **`type-design-analyzer` agent namespace wrong** — used `soleur:engineering:review:type-design-analyzer`; actual namespace is `pr-review-toolkit:type-design-analyzer`. Got error response with the available agent list. Recovery: relaunched with correct namespace. **Prevention:** when spawning a `*reviewer` agent, scan the available agent list for the correct plugin namespace before invoking. Skill-loader pattern note: agents in `pr-review-toolkit` plugin coexist with overlapping names in `soleur` plugin's `engineering/review/` directory. The two plugins are distinct namespaces.

3. **Context7 MCP quota exhausted mid-deepen** — could not verify SDK API. Recovery: relied on claude-code-guide agent's earlier research. **Prevention:** front-load Context7 queries early in the research phase (Phase 1.6b of the plan skill), not opportunistically during deepen. *(Worth a one-line note in the deepen-plan skill.)*

4. **TOOL_TIER_MAP scope misunderstanding in original plan** — wrote Stage 2.7 to extend `TOOL_TIER_MAP` for SDK-native tools, which would have been dead code. Caught by security-sentinel during deepen-pass. Recovery: rewrote Stage 2.7 to extend `permission-callback.ts` directly. **Prevention:** new plan-skill Sharp Edge #1 above.

5. **Cost SLO wishful thinking** — proposed TR5 P95 ≤ $1 without modeling brainstorm subagent fan-out cost. Caught by performance-oracle. Recovery: split per-workflow cap. **Prevention:** new plan-skill Sharp Edge #2 above.

6. **`payload: ...` placeholder** — Stage 3 deferred polymorphic-payload sub-discrimination to implementation. Caught by type-design-analyzer. Recovery: rewrote to discriminated sub-union with 6 typed payloads. **Prevention:** new plan-skill Sharp Edge #3 above.

7. **`'__unrouted__'` sentinel violated codebase NULL-convention** — used magic string in DB column. Caught by architecture-strategist + type-design-analyzer. Recovery: wrapped as `ConversationRouting` TS ADT at storage boundary. **Prevention:** new plan-skill Sharp Edge #4 above.

8. **No mention of MCP tool parity in original plan** — silent on agent-native parity for new operator-only WS surfaces. Caught by agent-native-reviewer. Recovery: added 5 V2 tracking issues. **Prevention:** new plan-skill Sharp Edge #5 above (extends existing `cq-when-a-plan-scopes-agent-native-parity`).
