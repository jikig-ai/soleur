---
date: 2026-06-30
topic: L3 per-phase tool/skill scoping — shrink the agent's tool surface by workflow phase
issue: 5768
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: L3 per-phase tool/skill scoping (#5768)

## What We're Building

A **fail-open, phase-aware surfacing layer** that biases which skills/agents/tools the
agent foregrounds based on the active workflow phase (brainstorm → plan → work → review →
ship), across **both** Soleur harnesses (CLI/plugin + web `agent-runner`). The goal is the
L3 "fewer tools = better" win without ever *removing* a tool an agent might need.

Concretely:

1. **Phase-state token (CLI).** Extend `.claude/hooks/skill-invocation-logger.sh`
   (PreToolUse matcher `Skill`, already fires on every skill call) to derive the current
   phase from a `skill → phase` map and persist it (a `.claude/.session-phase` token /
   field on the existing `.claude/.session-manifests/<id>.json`). Re-derives on every
   Skill call, so it self-heals when the operator switches tasks mid-session.
2. **Additive context hint (CLI).** A hook injects a short hint into `additionalContext`
   (the same injection point `session-rules-loader.sh` uses): *"You're in WORK phase;
   the phase-relevant skills are X/Y/Z; ship/deploy/merge aren't live yet."* Removes
   nothing — fail-open by construction.
3. **Additive phase scoping (web `agent-runner`).** Strictly additive: a phase hint in
   the system prompt + scoping *down* only a high-confidence "never-needed-this-phase"
   tool subset, with **full-set restored on any classifier ambiguity**. **Never** a new
   `canUseTool` deny branch — the existing deny-by-default `canUseTool` stays the
   *security* floor only.
4. **Measurement.** A new `eval-harness` tool-selection target (golden tasks whose answer
   is "which tool/skill should fire"; arms = full-surface vs phase-scoped; the MEASUREMENT
   assert records wrong-tool rate + token spend). Satisfies AC(c). Opt-in/manual (API
   budget), not CI-wired.

## Why This Approach

**The premise is partly already solved — and verification reshaped the scope.** Three
facts from the research fan-out (CTO + repo-research + learnings) moved the issue's
framing:

- **MCP — the heaviest surface (~100 tools) — is ALREADY deferred** via the ToolSearch
  deferred-tool mechanism (schemas withheld until fetched). That is already a working,
  inherently fail-open L3 reduction. The issue under-credits it.
- **Change-class scoping already ships** via `session-rules-loader.sh` (#3493): it
  classifies the diff (docs/code/infra) and injects only the relevant
  `AGENTS.{core,docs,rest}.md` bodies, fail-open (multi-class/empty → load all). This is
  the architectural template for phase scoping — same injection point, same fail-open
  discipline.
- **The genuine residual is narrow:** the **92 skill descriptions are always loaded** in
  the system prompt (the one un-deferred heavy surface a hook can influence only by
  *hint*, since the Claude Code runtime — not Soleur — owns the menu), and there is **no
  phase signal** to bias selection. Agents *do* pay a real tool-selection tax with a large
  surface (learning `2026-03-25-check-mcp-api-before-playwright`), so a phase hint is a
  legitimate cost/quality lever, not just cosmetic.

**Two-tier fail-open rule (the load-bearing design constraint).** Deny-by-default is safe
*only* on the already-fail-open layer (MCP/ToolSearch — re-fetches on demand). On every
other layer (built-in tools, the ~20 PreToolUse safety hooks, web `canUseTool`), scoping
must be **additive hint only** — a hard deny there could route an agent *around* the very
safety hook that would have caught it (`prod-write-defer-gate`, `git-commit-secret-scan`,
…) or produce a silent "unknown tool" error to a paying user
(learning `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools`).

**Why not the full per-phase allowlist framework:** highest risk of safety-hook bypass for
low marginal gain (MCP already scoped). CTO flagged it as disproportionate. **Why not
measure-only:** the operator wants a visible behavior change shipped alongside the
measurement.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ambition level | **Cheap-win scoping** (not full framework, not measure-only) | MCP already deferred; residual is narrow. Ship a phase token + additive hint + eval target in one increment. |
| Harness coverage | **Both** (CLI + web `agent-runner`) | Operator chose broad coverage. CLI = the static-92-skill-menu problem; web = where paying users run. |
| Posture per layer | **Two-tier fail-open**: deny-by-default ONLY on MCP/ToolSearch; additive-hint everywhere else | A hard deny on built-in tools / safety hooks / `canUseTool` is fail-closed and can bypass a safety gate or silently fail a user task. |
| Web rollout | **Both active, fail-open only** (no dark-launch gate) | Operator choice. Mitigated by the strict additive constraint: hint + high-confidence subset, full-set on ambiguity, never a `canUseTool` deny. |
| `canUseTool` role | **Unchanged — security floor only** | Phase scoping must NOT become a new `canUseTool` deny branch. Deny-by-default keeps gating unregistered tools as today. |
| Phase definition | **Derived from skill invocation** (brainstorm→plan→work→review→ship); unknown/ambiguous → full surface | No first-class phase state exists; `SOLEUR_SKILL_NAME` + skill-invocation-logger are the natural derivation points. |
| Measurement | **New eval-harness tool-selection target** (opt-in/manual) | Satisfies AC(c) honestly; API-budget gate keeps it out of CI per eval-harness SKILL.md. |
| Architecture record | **ADR authored at plan time** capturing the two-tier fail-open rule | Per `wg-architecture-decision-is-a-plan-deliverable`; CTO recommended `/soleur:architecture create`. |
| Visual design | N/A — no UI surface (pure hooks/harness/SDK infra) | Phase 3.55 trigger boundary: no pages/components/modals/banners. |

## Open Questions (resolve at plan time)

- **Phase→surface mapping source:** new small manifest (`phase-surface.json`) vs reuse the
  `soleur:go` routing table vs a `phase:` field in skill frontmatter. Lean: small manifest
  + the ADR-053 three-coupling-surfaces pattern (registry + per-phase map + CI consistency
  test) so a phase entry can't ship dormant.
- **Phase-token storage:** extend `.claude/.session-manifests/<id>.json` with a `phase`
  field vs a separate `.claude/.session-phase` file. Must update on each Skill call and
  survive compact/resume.
- **Web high-confidence "never-needed-this-phase" subset:** which tools per phase? Needs an
  empirical pass — start with the obvious (no Supabase migration/write tools in
  brainstorm/plan). Anything uncertain → keep in the full set.
- **Web silent-failure instrumentation:** to honor "both active," the web side needs
  tool-attempt-vs-scope telemetry (model-intent surface AND authorization surface, per
  learning #6) so a mis-scope surfaces as a metric, not a silent user error.
- **CLI hint ceiling:** confirm a hook cannot un-advertise a skill mid-session (runtime
  owns the menu); if true, the hint is the ceiling of CLI scoping — note a possible
  upstream Claude Code feature request for hook-scopable skill advertisement.

## User-Brand Impact

- **Artifact:** the phase→tool-scope surfacing layer (per-phase skill/agent/tool hint +
  web `agent-runner` additive scoping).
- **Vector:** a mis-scoped layer silently strips or de-prioritizes a tool/skill an agent
  needs mid-task — skipping a safety gate (CLI) or producing a silent "unknown tool"
  failure for a paying Concierge user (web).
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). The brand vector lands squarely on the web
harness; the two-tier fail-open rule + the "never a `canUseTool` deny" constraint + the
tool-attempt telemetry are the controls that hold the threshold. The CTO lens is applied
with full research grounding; a Product lens is folded in inline (web scoping touches
paying users — the rollout decision was made with that vector explicit). A full CPO/CLO/CTO
triad fan-out would be disproportionate to internal harness infra with no data/credential/
legal surface — same posture the operator set on the sibling harness brainstorm #5703.

## Domain Assessments

**Assessed:** Engineering (full research fan-out: CTO + repo-research + learnings).
Product — folded in inline (web rollout vs paying-user risk). Marketing, Operations, Legal,
Sales, Finance, Support — not relevant (internal agent-harness infra, no external surface).

### Engineering

**Summary:** Feasible with existing primitives — no capability gaps. The heaviest surface
(MCP) is already scoped via ToolSearch; change-class scoping (`session-rules-loader.sh`) is
the fail-open template; `skill-invocation-logger.sh` is the natural phase-derivation point;
`eval-harness` provides AC(c) measurement. The only hard constraint is the two-tier
fail-open rule: never convert a safety/security gate into a phase-feature gate. Recommended
scope is the cheap-win subset, not a full framework. Complexity: medium (days).

### Product

**Summary:** The CLI hint is pure operator-experience upside (removes nothing). The web
scoping is the only surface that reaches paying Concierge users; the "both active,
fail-open only" decision is acceptable *iff* the strict additive constraints + silent-fail
telemetry ship with it, so a mis-scope is a measured metric rather than a silent task
failure.

## Capability Gaps

None. CTO verified every required surface exists in the engineering domain:
`.claude/hooks/session-rules-loader.sh` (fail-open injection template),
`.claude/hooks/skill-invocation-logger.sh` (phase derivation),
`plugins/soleur/skills/eval-harness/` (measurement),
`web-platform/agent-runner` `canUseTool` (web gating floor), and the ToolSearch deferred-
tool mechanism (already-fail-open MCP scoping). Evidence: `find plugins/soleur/skills -name
SKILL.md` = 92 dirs; `find plugins/soleur/agents -name '*.md'` = 68.

## Session Errors

- **Issue framing under-credited existing scoping.** #5768's body asserts "no per-phase
  scoping" and "~92 skills + ~68 agents + MCP loaded simultaneously." Verified-true on the
  counts, but **MCP schemas are already deferred (ToolSearch)** and **change-class scoping
  already ships (#3493)**. #5768 should be updated to reflect that the heaviest surface is
  already scoped and the genuine residual is the 92 always-loaded skill descriptions + the
  missing phase signal. (Captured in the issue-update step.)
