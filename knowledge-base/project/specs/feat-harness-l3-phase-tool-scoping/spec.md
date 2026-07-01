---
feature: harness-l3-phase-tool-scoping
issue: 5768
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-06-30-harness-l3-phase-tool-scoping-brainstorm.md
---

# Spec: L3 per-phase tool/skill scoping (#5768)

## Problem Statement

Soleur's agent harness exposes a large, static surface — 92 skill descriptions (always in
the system prompt) + 68 agents + MCP tools — without scoping to the active workflow phase.
A planning step still "sees" deploy/ship/merge. Large tool surfaces impose a measurable
tool-selection tax (the agent spends tokens reasoning about which tool to use). The MCP
surface is already mitigated (ToolSearch defers schemas) and change-class scoping already
ships (`session-rules-loader.sh`, #3493), but the **92 always-loaded skill descriptions**
and the **absence of any phase signal** remain unaddressed.

## Goals

- Derive and persist a **current-phase token** (brainstorm/plan/work/review/ship) from
  skill invocation, self-healing on task switch.
- Inject a **fail-open additive hint** that foregrounds phase-relevant skills/agents in the
  CLI harness — removing nothing.
- Apply **strictly additive** phase scoping in the web `agent-runner` (hint + high-
  confidence never-needed subset, full-set on ambiguity), never via a `canUseTool` deny.
- Provide **before/after measurement** of wrong-tool selection / token spend via a new
  `eval-harness` tool-selection target (AC(c)).
- Author an **ADR** capturing the two-tier fail-open rule.

## Non-Goals

- A full per-phase allowlist *framework* that hard-denies tools by phase (rejected:
  safety-hook-bypass risk, low marginal gain).
- Re-scoping the MCP surface (already deferred via ToolSearch).
- Changing the `canUseTool` deny-by-default security floor (stays as-is, security-only).
- Un-advertising skills mid-session (the Claude Code runtime owns the menu; out of Soleur's
  control — hint is the ceiling for CLI).
- Wiring the eval target into CI (API-budget gate keeps it opt-in/manual).
- Any UI surface (pure hooks/harness/SDK infra).

## Functional Requirements

### FR1: Phase-state derivation (CLI)

`skill-invocation-logger.sh` (PreToolUse matcher `Skill`) maps the invoked skill to a phase
via a `skill → phase` map and persists a phase token. Re-derives on every Skill call.
Unknown/unmapped skill → `full` (no scoping).

### FR2: Additive phase hint (CLI)

A hook injects a concise phase hint into `additionalContext` (the `session-rules-loader.sh`
injection point): the phase name + the phase-relevant skill/agent shortlist + an explicit
note that later-phase skills are not yet live. The hint MUST NOT remove or deny any tool.

### FR3: Additive phase scoping (web `agent-runner`) — DEFERRED to #5772

[Plan-time revision 2026-06-30] The web SDK agent runs with `settingSources: []`
(`agent-runner-query-options.ts:155`) so the CLI hook cannot reach it, and the only
surface-shrinking web lever (`disallowedTools`) is fail-closed (silent "unknown tool").
Both contradict "fail-open only," so the web half is deferred to **#5772** (SDK-native
phase hint + `disallowedTools` subset + TR3 telemetry), gated on v1's eval evidence.
v1 is **CLI-only**. MUST NOT add any per-phase entry to the `canUseTool` deny path (when built).

### FR4: Tool-selection measurement (eval-harness)

A new eval-harness target with golden tasks whose correct answer is "which tool/skill should
fire," two arms (full-surface vs phase-scoped), recording wrong-tool rate + token spend.
Opt-in/manual.

## Technical Requirements

### TR1: Two-tier fail-open rule (load-bearing)

Deny-by-default permitted ONLY on the already-fail-open MCP/ToolSearch layer. All other
layers (built-in tools, the ~20 PreToolUse safety hooks, web `canUseTool`) are additive-hint
only. Any phase classifier ambiguity → full surface (mirrors `session-rules-loader.sh`
multi-class/empty → load-all).

### TR2: Safety-hook independence

The ~20 PreToolUse safety hooks (`prod-write-defer-gate`, `git-commit-secret-scan`,
`worktree-write-guard`, …) run regardless of phase. Phase scoping must never hide a tool in a
way that routes an agent around a safety hook.

### TR3: Web silent-failure telemetry — DEFERRED to #5772

[Plan-time revision 2026-06-30] Moves with the web half to **#5772**. v1 (CLI-only,
additive PostToolUse hint) removes nothing → zero silent-unknown-tool surface → no
telemetry needed. When #5772 builds the `disallowedTools` subset, it instruments both
the model-intent surface (tool_use blocks) AND the authorization surface (`canUseTool`)
so a mis-scope surfaces as a metric, not a silent "unknown tool" error to a paying user
(per `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools`).

### TR4: Mapping registry consistency (ADR-053 pattern)

If a phase→surface manifest is introduced, couple it with a per-phase config map + a CI
consistency test so a phase entry cannot ship dormant (per
`2026-06-29-eval-gate-target-validity-and-three-map-drift`).

### TR5: Phase-token persistence

The phase token updates on each Skill call and survives compact/resume (extend
`.claude/.session-manifests/<id>.json` or a dedicated `.claude/.session-phase`).

### TR6: ADR deliverable

Author an ADR recording the additive-hint-vs-deny decision and the two-tier fail-open rule.
