# Token-Efficiency Analysis as a Recurring Compound Phase

**Date:** 2026-05-09
**Status:** Decided
**Issue:** #3494 (this brainstorm), #3493 (companion optimizations catalog)
**Branch:** `feat-token-efficiency-analysis`
**PR:** #3495 (draft)
**Participants:** Founder, CTO

## What We're Building

A new sequential phase in the `compound` skill — **Phase 1.6: Token-Efficiency Analysis** — that runs after Phase 1.5 Deviation Analyst and before Constitution Promotion. The phase reads three signals from the just-completed session, identifies the top cost line items, proposes 1–3 mitigations through the same Accept/Skip/Edit gate the Deviation Analyst already uses, and emits an `incidents.sh` telemetry warn under a synthetic `te-*` rule_id namespace when an outlier threshold is breached. A weekly aggregator surfaces longitudinal patterns.

Prerequisite (blocking, in same plan): a PostToolUse hook tees agent-result `total_tokens` lines into `.claude/.session-tokens.jsonl` so subagent envelope sizes — the largest cost line items — are readable from inside the skill.

This closes Open Question #4 from the 2026-04-13 token-optimization brainstorm ("How to measure impact? No token usage instrumentation exists today.") and gives the four optimizations cataloged in #3493 a measurement producer instead of shipping them blind.

## Why This Approach

**Compound, not ship.** Compound runs every commit (high frequency, low blast radius); ship runs once at PR close. Token waste compounds within a session; per-commit cadence catches outliers while the operator can still course-correct. Ship's existing AGENTS.md byte/rule budget is structural (counts a static file); token cost is a flow signal (turns × bytes + subagent envelopes). Different infrastructure, different placement.

**Reuse the Deviation Analyst pipeline.** Phase 1.5 is already retrospective, sequential, and feeds Constitution Promotion's Accept/Skip/Edit gate. Token analysis is the same shape — retrospective signal → proposal → tier-routed mitigation. Composing on the existing gate avoids forking a parallel one.

**No reference rubric file.** The issue body proposed `plugins/soleur/skills/compound/references/token-efficiency-rubric.md`, but a 5k-char file loaded every compound run would tax the very signal it measures. The rubric inlines as ≤30 lines in `compound/SKILL.md`.

**No per-session learning files.** Auto-writing to `knowledge-base/project/learnings/efficiency/` per outlier creates write-churn for signals that only mean something in aggregate. Reuse `incidents.sh emit_incident` (already flock'd, schema-versioned, weekly-aggregated). The aggregator promotes a learning file only when a pattern recurs across multiple sessions.

**Block on the hook tee.** The largest cost items (subagent envelopes — 45–128k tokens each in the parent session) aren't grabbable without transcript access. Shipping Phase 1.6 with degraded signal first would make the producer go live blind to its biggest signal; instead, the hook + Phase 1.6 land together as one plan.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Compound Phase 1.6 (Option A), not ship Phase 5.6 (Option B) | Per-commit cadence aligns with flow-signal nature of token cost; reuses existing Deviation Analyst → Constitution Promotion pipeline; ship Phase 5.5 byte-counter is structural-not-flow precedent. |
| 2 | Inline rubric ≤30 lines in `compound/SKILL.md`; **no** `references/token-efficiency-rubric.md` | The reference file would itself add ~5k chars to every compound run, defeating the measurement purpose. |
| 3 | Phase 1.6 token budget: ≤1.5k tokens added per fire | No subagent spawn, no new rubric file load, bash + small awk only, generated text capped at ~600 tokens. LLM reasoning gated behind outlier trigger (lazy expansion). |
| 4 | Skip Phase 1.6 entirely on small diffs (`git diff --stat | tail -1` <50 lines changed) | Docs-only sweeps don't warrant the meta-cost; longitudinal signal is preserved by aggregating only on substantive sessions. |
| 5 | Outlier `te-*` telemetry emit triggers: any single subagent envelope >100k tokens **OR** session tokens / lines-changed ratio breaches starting heuristic ~2k tokens/line | Two complementary axes: absolute (single-spawn outlier) and relative (work-delivered ratio). Starting heuristic to be tuned during plan. |
| 6 | Outlier capture via `incidents.sh emit_incident <te-id> warn ...`, **not** auto-written learning files | Reuses existing flock'd writer, schema versioning, weekly aggregator. Patterns surface in aggregate, not per-fire. |
| 7 | Synthetic `te-*` rule_id namespace reserved for token-efficiency telemetry | Keeps token-event ids distinct from real AGENTS.md rule fires in the aggregator's `rule_id` join. Initial ids: `te-skill-payload-floor`, `te-subagent-overshoot`, `te-agents-md-turn-cost`. |
| 8 | Block on PostToolUse hook tee (`.claude/.session-tokens.jsonl`) — single plan covers hook + Phase 1.6 | Without subagent envelope signal, Phase 1.6 misses the largest cost line items. Shipping with degraded signal first would normalize a partial producer. |
| 9 | Pipeline-mode exception to `wg-zero-agents-until-user-confirms` applies | Phase 1.6 is a measurement step inside an already-running pipeline; the rule's "ask before spawning" intent doesn't apply to in-pipeline phases that don't fan out new agents. |
| 10 | Sharp Edge: token-efficiency reports are advisory; only large outliers (>50k token surplus relative to delivered work) warrant a follow-up issue | Per the issue's stated guard against alarm fatigue. |

## Open Questions

1. **Hook implementation surface.** Is `PostToolUse` the right Claude Code hook event for intercepting agent-result blocks, or does the agent-result envelope arrive via a different lifecycle event? Plan must verify against the live hook spec before committing to a name. (Falls out of plan-phase research, not a brainstorm-blocker.)
2. **Skill manifest discovery.** When compound runs at the end of a one-shot pipeline, how does Phase 1.6 know which skills' bodies were loaded into main context? Candidates: (a) maintain a static manifest per pipeline in `plugins/soleur/skills/<pipeline>/SKILL.md`, (b) infer from `.rule-incidents.jsonl` entries (skills emit telemetry on entry), (c) accept best-effort and note the limitation in the report header. Plan picks one.
3. **Ratio heuristic tuning.** ~2k tokens/line is a starting point. After 4–6 weeks of data, the threshold should be re-evaluated against actual ratios. Out of scope here; track in plan as a follow-up.
4. **Aggregator surface.** Does the weekly `rule-metrics-aggregate.sh` need a separate `te-*` partition, or does the existing aggregation handle synthetic ids cleanly? Plan-time grep.

## Scope Boundaries

**In scope:**
- New `compound/SKILL.md` Phase 1.6 (insertion between line ~236 Deviation Analyst empty-case and line ~265 Constitution Promotion)
- PostToolUse hook tee writing to `.claude/.session-tokens.jsonl`
- `te-*` synthetic rule_id namespace reservation (extend `scripts/retired-rule-ids.txt` semantics if needed)
- Inline rubric (≤30 lines) in `compound/SKILL.md`
- Compound-phase skip rule (`git diff --stat | tail -1` <50 lines changed)
- Outlier emit logic (subagent envelope >100k OR ratio breach)
- Test scenarios: pipeline-mode invocation, headless skip on small diff, outlier detection on planted high-token mock session

**Out of scope (defer to follow-ups):**
- Implementing the four optimizations from #3493 (this issue ships the producer; #3493 ships the consumers)
- Aggregator surface change for `te-*` namespace if the existing one absorbs it cleanly (treat as plan-time decision)
- Ship Phase 5.6 (Option B) — explicitly rejected
- `references/token-efficiency-rubric.md` — explicitly rejected
- Auto-writing per-session learning files for outliers — explicitly rejected

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Compound Phase 1.6 over ship Phase 5.6 — per-commit frequency aligns with token cost as a flow signal; ship's byte-counter is structural-not-flow precedent. Inline rubric mandatory (5k-char reference file would defeat the measurement). Realistic in-process signals: AGENTS.md size + declared skill payload + `.rule-incidents.jsonl` are grabbable; subagent envelope sizes need a hook tee (file as prerequisite, blocking). Capture via existing `incidents.sh emit_incident` with synthetic `te-*` rule_id namespace, **not** auto-learning-files. Token budget ≤1.5k per fire, no subagent spawn. Skip on small diffs.

## Capability Gaps

**Hook tee for subagent `total_tokens` envelopes.** No existing infrastructure exposes per-subagent token counts to skill execution context.

- **What's missing:** A PostToolUse (or equivalent lifecycle) hook that intercepts agent-result blocks and appends `total_tokens` lines to `.claude/.session-tokens.jsonl` for the active session.
- **Domain:** Engineering (workflow tooling).
- **Why needed:** Without it, Phase 1.6 misses the largest cost line items. Subagent spawns of 45–128k tokens each were the dominant cost in the parent session (PR #3491) and are completely invisible to a non-introspective skill execution.
- **Evidence:** CTO assessment 2026-05-09 enumerated grabbable signals: AGENTS.md size (yes), declared skill payload (partial, depends on Open Question #2), `.rule-incidents.jsonl` (yes), subagent envelopes (no — needs new infrastructure). Confirmed by inspection: `.claude/hooks/lib/` contains `incidents.sh` only; no token-tee hook present.
- **Resolution:** In-scope for this plan (decision #8 above blocks on this).

## References

- Companion optimizations catalog: #3493
- Prior brainstorm closing the loop on its Open Question #4: `knowledge-base/project/brainstorms/2026-04-13-token-optimization-brainstorm.md`
- Existing telemetry infrastructure: `.claude/hooks/lib/incidents.sh`
- Compound insertion point: `plugins/soleur/skills/compound/SKILL.md` (after Phase 1.5 empty-case, before Constitution Promotion at line ~265)
- Rule reference: AGENTS.md `cq-agents-md-why-single-line` (existing AGENTS.md byte budget — extends to flow-signal version)

## Sharp Edge

Token-efficiency reports are advisory. Only large outliers (>50k token surplus relative to delivered work, **or** any single subagent envelope >100k tokens) warrant a follow-up issue. Smaller drifts get rolled into the weekly aggregator's longitudinal trend; a single noisy session shouldn't prompt a learning file.
