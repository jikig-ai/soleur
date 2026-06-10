# Learning: Model-economics brainstorms — dormant re-evaluation triggers, leader telemetry claims, and the pricing source of truth

## Problem

Brainstorming model-tier optimization after the Fable 5 release ($10/$50 per MTok) surfaced three process findings:

1. Open issue #3791 ("Agent model-downshift audit", deferred 2026-05-15) carried "a pricing change" as an explicit re-evaluation trigger — but nothing fired when Fable 5 shipped. The issue surfaced only because the learnings-researcher prompt happened to include brainstorm-archive search. Without it, the brainstorm would have created a duplicate parallel issue.
2. Two domain leaders (CTO, CFO) independently asserted "no per-agent token telemetry exists." Repo grep found `.claude/hooks/agent-token-tee.sh` (#3494) already capturing per-spawn token envelopes to `.claude/.session-tokens.jsonl` — the real gap was only model-attribution and aggregation. The existing leader-claim cross-check (brainstorm SKILL.md) caught it before it shaped the spec.
3. Model pricing premises ("Fable 5 is very demanding on tokens") needed verification before leader spawn — the claude-api skill's cached model table was the authoritative source (Fable 5 $10/$50 vs Opus 4.8 $5/$25 vs Sonnet 4.6 $3/$15 vs Haiku 4.5 $1/$5), not memory.

## Solution

- Adopted #3791 as the tracking issue (artifacts linked into it) instead of creating a parallel one; its deferral text became the brainstorm's strongest framing evidence ("the trigger fired").
- Corrected the telemetry claim in the brainstorm doc and narrowed the capability gap to "model attribution + aggregation," cutting a build-measurement-first phase from the plan.
- Read the claude-api skill before spawning leaders, so every leader prompt carried verified pricing.

## Key Insight

When a vendor pricing/model event incites a brainstorm, grep open issues for deferred work whose re-evaluation criteria mention pricing/model/vendor changes BEFORE framing the work as new (`gh issue list --state open --search "deferred model OR pricing"`). Deferred issues encode prior leader consensus and re-open criteria — the brainstorm's job may be to certify the trigger fired, not to re-derive the decision.

## Session Errors

1. **Leader telemetry false negative (CTO + CFO)** — both asserted no per-agent token telemetry exists; `agent-token-tee.sh` (#3494) already existed. Recovery: repo-research report + direct grep before writing artifacts. Prevention: existing brainstorm SKILL.md leader-claim cross-check rule (2026-05-07 learning) — fired as designed; capability-gap claims from leaders need the same evidence bar as research agents.
2. **Agent-count drift** — concurrent counts of agent files diverged (66/67/68) across the orchestrator and two subagents. Recovery: none needed (no decision turned on it). Prevention: treat fleet counts as approximate in prompts; re-grep at plan time per the 2026-02-22 model-id learning ("issue inventories undercount").
3. **Dormant re-evaluation trigger (#3791)** — process gap, no automation watches deferred-issue triggers for vendor events. Recovery: learnings-researcher surfaced it mid-brainstorm. Prevention: routed a prior-art bullet to brainstorm SKILL.md (vendor-event → grep deferred issues); a scheduled trigger-watcher was considered and rejected as over-engineering for the frequency.

## Tags

category: workflow-patterns
module: brainstorm, model-policy
