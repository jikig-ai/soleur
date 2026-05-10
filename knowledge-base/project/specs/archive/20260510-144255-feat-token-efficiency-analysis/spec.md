---
feature: feat-token-efficiency-analysis
issue: 3494
companion: 3493
brainstorm: knowledge-base/project/brainstorms/2026-05-09-token-efficiency-analysis-brainstorm.md
status: spec
last_updated: 2026-05-09
---

# Spec: Token-Efficiency Analysis as a Recurring Compound Phase

## Problem Statement

Token-efficiency analysis runs only when an operator explicitly asks for it. Without a recurring chokepoint, structural inefficiencies (skill payload sizes, AGENTS.md byte growth, subagent over-spawning) accumulate silently between user-initiated audits. The session that produced PR #3491 surfaced ~60k tokens of skill-payload floor and ~150–180k tokens of repeated AGENTS.md loads — invisible to the workflow because no phase asked the question.

This spec closes Open Question #4 from the 2026-04-13 token-optimization brainstorm and gives the four optimizations cataloged in #3493 a measurement producer instead of shipping them blind.

## Goals

- Bake a recurring, advisory token-efficiency analysis step into the `compound` skill that runs on every commit-time invocation (subject to skip rules).
- Surface the top-3 cost line items relative to delivered work in a single structured block per fire.
- Capture outliers via existing `incidents.sh` telemetry under a synthetic `te-*` rule_id namespace; let the existing weekly aggregator surface longitudinal patterns.
- Add the missing infrastructure (PostToolUse hook tee for subagent `total_tokens`) so Phase 1.6 can read the largest cost signal.
- Keep the measurement step itself cheap: ≤1.5k tokens added per fire, no subagent spawn, no LLM reasoning unless an outlier triggers.

## Non-Goals

- Implementing the four optimizations from #3493 (this spec ships the **producer**; #3493 ships the **consumers**).
- Ship Phase 5.6 (Option B) — explicitly rejected; ship's existing AGENTS.md byte/rule budget is structural-not-flow.
- A `references/token-efficiency-rubric.md` reference file — explicitly rejected; load cost would defeat the measurement purpose.
- Auto-writing per-session learning files to `knowledge-base/project/learnings/efficiency/` — explicitly rejected; aggregate-only signal.
- Blocking gate behavior. Phase 1.6 is non-blocking advisory.
- Tuning the ratio heuristic with production data; starting heuristic only, follow-up tracked separately.

## Functional Requirements

### FR1: Compound Phase 1.6 insertion

A new sequential phase inserts into `plugins/soleur/skills/compound/SKILL.md` between Phase 1.5 (Deviation Analyst) and Constitution Promotion. The phase:

1. Runs after Phase 1.5's empty-case branch.
2. Skips entirely when `git diff --stat | tail -1` reports <50 lines changed.
3. Reads three signals: AGENTS.md byte size × turn count, declared skill-payload sum, subagent envelope sizes from `.claude/.session-tokens.jsonl`.
4. Identifies the top-3 cost line items relative to delivered work (lines changed, files touched).
5. Proposes 1–3 mitigations through the same Accept/Skip/Edit gate the Deviation Analyst already uses.
6. Emits `incidents.sh` telemetry with a `te-*` rule_id when an outlier threshold is breached.

### FR2: PostToolUse hook tee

A new Claude Code lifecycle hook (`PostToolUse` or equivalent — verified during plan) intercepts agent-result blocks, parses the `total_tokens: N` line, and appends a JSONL record to `.claude/.session-tokens.jsonl` for the active session. Format:

```jsonl
{"ts":"2026-05-09T12:34:56Z","session":"<session-id>","subagent":"<agent-name>","total_tokens":48172,"tool_uses":12}
```

The file is per-session and ephemeral; a session-end hook may roll completed sessions into a longer-lived archive (out of scope here).

### FR3: Inline rubric

A ≤30-line rubric inlines in `compound/SKILL.md` documenting the cost-breakdown methodology: which signals to count, how to compute the work-delivered ratio, what an outlier looks like. **No** separate reference file.

### FR4: Outlier detection and emit

Phase 1.6 emits a `te-*` warn telemetry signal when **either**:

- Any single subagent envelope > 100k tokens (absolute axis), **or**
- Total session tokens / lines-changed > ratio heuristic (relative axis; starting value ~2k tokens/line, tunable in plan).

Initial reserved `te-*` rule_ids:

- `te-skill-payload-floor` — declared skill bodies summed exceed an absolute threshold for the session class.
- `te-subagent-overshoot` — single subagent total_tokens > 100k.
- `te-agents-md-turn-cost` — AGENTS.md bytes × turn count exceeds a per-session class threshold.

### FR5: Sharp Edge note in compound SKILL.md

> Token-efficiency reports are advisory. Only large outliers (>50k token surplus relative to delivered work, **or** any single subagent envelope >100k tokens) warrant a follow-up issue. Smaller drifts compound through the weekly aggregator.

### FR6: Skip-rule documentation

The skip rule (`git diff --stat | tail -1` <50 lines changed) is documented adjacent to Phase 1.6 in compound/SKILL.md so future skill edits don't undo the elision unintentionally.

## Technical Requirements

### TR1: `.claude/.session-tokens.jsonl` schema and location

- Path: `.claude/.session-tokens.jsonl` (gitignored — operator-local session state, not committed).
- Append-only per session; each line is a single JSON object with the fields in FR2.
- Verify a `.gitignore` entry exists or add one in the same PR.

### TR2: `te-*` rule_id namespace reservation

The synthetic `te-*` namespace must not collide with real AGENTS.md rule IDs. Approach options (decided in plan):

- Extend the rule-id linter (`scripts/lint-rule-ids.py` per AGENTS.md `cq-rule-ids-are-immutable`) to recognize `te-*` as a reserved prefix that does not require an AGENTS.md entry.
- OR seed the `te-*` ids into `scripts/retired-rule-ids.txt` semantics with a "synthetic, not retired" marker.

### TR3: Aggregator integration

The weekly `scripts/rule-metrics-aggregate.sh` (or equivalent) consumes `incidents.sh` events. Plan-time grep verifies whether `te-*` ids flow through the existing aggregation cleanly or whether a partition is required. No code change here unless the existing aggregator filters on a closed allow-list of rule prefixes.

### TR4: Phase 1.6 token budget enforcement

- No subagent spawn (no `Agent` / `Task` invocation inside Phase 1.6).
- No new file load >800 chars (rules out a separate rubric reference file).
- Generated text capped at ~600 tokens.
- LLM reasoning gated behind outlier trigger only (lazy expansion).
- Implementation: bash + small awk; structured output written directly to stdout in a single template-driven block.

### TR5: Test scenarios

- **Pipeline mode invocation:** running compound with a planted `.claude/.session-tokens.jsonl` containing a 120k-token subagent line emits a `te-subagent-overshoot` warn.
- **Skip on small diff:** running compound with `git diff --stat | tail -1` reporting `1 file changed, 3 insertions(+), 1 deletion(-)` skips Phase 1.6 entirely (verified by absence of the structured output block).
- **Empty session-tokens file:** Phase 1.6 runs but reports "subagent envelopes: not captured this session" gracefully (no crash, no emit).
- **Outlier ratio:** session with 120k total tokens against 30 lines changed (ratio 4k tokens/line) emits a relative-axis warn.

### TR6: AGENTS.md placement-gate compliance

Per `cq-agents-md-tier-gate`, this work is **skill-enforced** (compound Phase 1.6). It does **not** add an AGENTS.md rule — the enforcement lives in the skill body. If a future failure mode demonstrates a hidden cross-cutting invariant, an AGENTS.md rule can be added then with `[skill-enforced: compound Phase 1.6]` tag.

## Acceptance Criteria

From issue #3494, with reductions ratified in brainstorm:

- [x] Decided between Option A (compound Phase 1.6) and Option B (ship Phase 5.6) — chose A.
- [ ] Implement Phase 1.6 as a non-blocking step (warns/records, never aborts).
- [ ] Phase 1.6 runs in pipeline mode (one-shot, ship-from-work) — `wg-zero-agents-until-user-confirms` exception applies because this is a measurement step, not a recommendation.
- [ ] Output is a single structured block: `## Session Token Efficiency` with a 3-row table (top-3 cost items) and 1–3 proposed mitigations, each tagged with an enforcement tier (skill-edit / hook / AGENTS.md / out-of-scope).
- [ ] Sharp Edge documented in compound SKILL.md (FR5).
- [ ] Cost-breakdown methodology documented inline in `compound/SKILL.md` (≤30 lines), **not** in a separate references file.
- [ ] PostToolUse hook tee landed at `.claude/hooks/<name>.sh` writing to `.claude/.session-tokens.jsonl` (gitignored).
- [ ] `te-*` rule_id namespace reserved against the rule-id linter.
- [ ] Test scenarios from TR5 pass.

## Plan Carry-Forward

The plan must answer:

1. Which Claude Code hook event surfaces agent-result blocks? (Verify against live hook spec.)
2. How does Phase 1.6 enumerate "skills loaded this session"? Pick from brainstorm's Open Question #2 candidates.
3. Does the existing `rule-metrics-aggregate.sh` accept `te-*` ids cleanly, or does the aggregator need a partition?
4. Final ratio heuristic for the relative-axis outlier emit (starts at ~2k tokens/line; may tune before merge if the parent-session replay produces a clearly-better default).

## Why This Decision Decay-Resistant

- **Compound is the chokepoint.** Token cost is session-scoped; per-commit measurement aligns with the signal lifecycle.
- **`incidents.sh` is the proven telemetry surface.** The same writer, schema versioning, and weekly aggregator already exist; reusing them avoids parallel infrastructure.
- **Inline rubric.** No reference file means no per-run cost; methodology travels with the skill that uses it.
- **Block on hook prerequisite.** Shipping the producer with degraded signal would normalize a partial measurement; landing both together prevents drift between "what we report" and "what costs us".
