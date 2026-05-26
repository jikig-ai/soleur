---
title: "5-agent plan-review panel surfaces both over-engineering and correctness — and architectural false-trails compound"
date: 2026-05-11
category: workflow-patterns
tags:
  - plan-review
  - multi-agent-review
  - user-brand-critical
  - architectural-false-trail
  - paper-resolution
  - claude-code-action
  - gdpr-gate
issue: "#2720"
pr: "#3559"
session: feat-compound-promotion-loop plan
---

# 5-agent plan-review panel surfaces both over-engineering and correctness — and architectural false-trails compound

## Problem

Three intertwined patterns surfaced when planning #2720 (compound-promotion-loop) under the `single-user incident` brand-survival threshold:

1. **The 5-agent plan-review panel** (DHH + Kieran + Code Simplicity + Architecture-Strategist + SpecFlow re-validation) caught failures that any single 1- or 3-agent panel would have missed. DHH+Code-Simplicity converged on aggressive simplification (~70% LOC reduction); Kieran+Architecture+SpecFlow converged on correctness gaps (P0 set -eo vs -euo, contract-change ordering, template-injection on matrix.cluster.*, cluster-hash integrity, Q1 actually unresolved). The two perspectives were ORTHOGONAL — neither panel-of-3 would have surfaced the other panel's findings.

2. **An architectural false-trail compounded** through 953 lines of plan. The v1 plan adopted a two-job split (`cluster` job using `claude-code-action` → `promote` job using a matrix) to dance around `claude-code-action`'s post-step App-token revocation. That single architectural choice introduced 4 distinct follow-on problems: (a) Q1 — the `claude-code-action@v1.0.101` outputs mechanism for arbitrary agent JSON is undocumented and may not exist; (b) matrix DOS — no hard cap on `clusters_json` length; (c) template injection — `matrix.cluster.*` values from LLM-generated JSON expand into workflow `${{ }}` interpolations on a public-PR-body surface; (d) cluster-hash integrity gap — the `Cluster-Hash` trailer is a passthrough from LLM output, not a recomputation. ALL FOUR dissolve when claude-code-action is dropped in favor of plain `curl` to the Anthropic Messages API.

3. **Plan-time `/soleur:gdpr-gate` invocation revealed a pre-existing systemic gap** unrelated to #2720: the Anthropic processor has NO row in `knowledge-base/legal/compliance-posture.md` Vendor DPAs, despite the gdpr-gate skill itself + every `claude-code-action` workflow being load-bearing dependents. The gate fires the `GDPR-Chapter-V` Important finding on this plan because the plan widens the processing surface — but the underlying gap predates #2720 and applies to a dozen prior workflows.

## Solution

### Pattern 1 — User-brand-critical features warrant the 5-agent panel

When a plan declares `Brand-survival threshold: single-user incident`, the standard 3-agent plan-review baseline (DHH/Kieran/Code Simplicity) catches overengineering and convention drift but MISSES blast-radius and flow gaps. Adding `architecture-strategist` (blast-radius lens) and `spec-flow-analyzer` re-validation (flow-gap detection over the plan, not just the spec) closes the loop. The plan-review skill already has this gating: `if Brand-survival threshold == 'single-user incident' then 5-agent panel`. This learning confirms the gating is load-bearing, not ceremony.

The two panels' findings need different consolidation passes:

- **Simplification panel (DHH/CS):** treat as a single voice; act on consensus; defer non-consensus items to `Mixed opinion` review.
- **Correctness panel (Kieran/Arch/SpecFlow):** treat each finding individually; correctness items don't aggregate (a P0 from any one of them is P0).

The synthesis insight: many "paper-resolution" findings from the correctness panel VANISH when the simplification panel's cuts land. Architecture #2 (matrix DOS) and #3 (cluster-hash integrity) both dissolve when DHH #1 (drop matrix split) lands. SpecFlow NG-1 (Jaccard not implemented) dissolves when DHH #2 (drop FR10) lands. Always evaluate cuts BEFORE chasing correctness fixes for the cut features.

### Pattern 2 — When a tool's lifecycle constraint forces architectural contortions, drop the tool

`claude-code-action` is a useful wrapper for workflows where the agent IS the entire job (e.g., `scheduled-bug-fixer.yml`). But for workflows that need to mutate repo state AFTER the LLM call (commit, push, open PR), the post-step token revocation is a hard constraint. The right response is NOT to architect around the wrapper (two-job split, matrix marshalling, base64 sentinel transport) — it's to drop the wrapper and call the Anthropic API directly via `curl https://api.anthropic.com/v1/messages`.

Concrete trigger: ask "what does this look like as 5 lines of `curl` + `jq`?" BEFORE committing to the wrapper-friendly architecture. If the answer is "fine," skip the wrapper. The wrapper's value is in the agent's tool-use loop (Bash, Read, MCP); a single clustering-and-emit-JSON call doesn't need that.

### Pattern 3 — Paper-resolution as a failure mode

Folding a review finding by adding FR/AC text without verifying the implementation can encode the fix is a real and detectable failure mode. SpecFlow's re-validation against the plan (vs. the spec) caught 4 paper-resolutions in v1: FR10 Jaccard had no Jaccard logic in the script, FR11 retired-rule had no breadcrumb extraction, FR8 revised had no per-learning issue filing, TR1 branch-regex still used label search.

**Detection heuristic:** every FR/AC added to fold a finding should include a 1-line pointer to where in the implementation (`scripts/X.sh:line`, `workflows/Y.yml:section`, `prompt:step-N`) the fix lives. If the planner can't write that pointer, the FR is paper. A "the agent will read X and then do Y" promise is paper unless it's wired to either (a) deterministic shell logic the planner can describe in code, or (b) an explicit allowed-tool + prompt instruction the planner can quote verbatim.

### Pattern 4 — Invoke `/soleur:gdpr-gate` even when canonical regex doesn't match

The `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex covers schemas, migrations, auth flows, API routes, `.sql`. The compound-promotion-loop plan touches NONE of those — it's a workflow YAML + shell driver + markdown scaffolds. By the regex, gdpr-gate would skip silently.

But the plan adds a NEW processing activity (LLM-summarization of operator-session-derived learnings, sent to Anthropic) on a USER_BRAND_CRITICAL surface. The CLO assessment correctly identified this as a Chapter V / Art. 28 surface during brainstorm. The gate's plan-time invocation (`/soleur:gdpr-gate "feat-compound-promotion-loop plan + spec"`) found 1 Important + 3 Suggestions, including the Anthropic-DPA systemic gap that no other gate would have caught.

**Heuristic:** invoke gdpr-gate when ANY of these hold, even if the canonical regex misses:
- New processing activity using an LLM/external API on operator-session-derived data
- Brand-survival threshold `single-user incident` declared in the plan
- New cron/workflow that READS from `knowledge-base/project/learnings/` or `knowledge-base/project/specs/`
- New artifact distribution surface (plugin update, public PR body, package release)

The cost of invocation is minutes; the cost of missing a Chapter V transfer post-merge is brand-survival.

## Session Errors

- **Plan v1 architectural false-trail.** 953-line v1 prescribed two-job split because of claude-code-action token revocation. **Recovery:** 5-agent plan-review converged on dropping the wrapper; v2 plan (829 lines) uses plain `curl` in a single job. **Prevention:** at plan-Phase-3 workflow drafting time, ask "what does this look like with `curl` + `jq`?" BEFORE adopting a wrapper that constrains the architecture. If the answer is "fine," skip the wrapper.

- **Q1 marked resolved when not actually resolved.** v1 struck through Q1 with "→ resolved via FR12" but FR12 addressed JSON-validation only, not upstream extraction (which was the actual question). Caught by Kieran P0-3 + SpecFlow NG-7. **Recovery:** v2 dropped claude-code-action so Q1 dissolved. **Prevention:** when marking an Open Question as `~~resolved~~`, the resolution text must address the exact question text, not an adjacent concern. Lint: if the strikethrough's "→ resolved via X" doesn't substring-match the question's verb (extract vs. validate), it's not a resolution.

- **Spec-flow paper-resolutions.** v1 folded 6 P0 gaps as FRs/ACs but 4 of them never made it into the script or workflow YAML. **Recovery:** v2 either deleted the gap (per simplification panel) or moved it to deterministic shell pre-pass (Architecture #1). **Prevention:** every FR/AC added to fold a finding MUST cite the implementation location (`scripts/X.sh:Y`, `workflows/Z.yml:section`). Skill-level lint candidate: plan-review skill could verify each P0 resolution mentions a file path under `scripts/`, `.github/`, or `plugins/` in the resolution text.

- **Bot-pr action read truncated on first attempt.** `head -120` missed the full picture (synthetic check-runs + auto-merge were after line 120). Recovered with second tail-read. **Prevention:** when reading an action.yml or workflow file under 200 lines, read full file (`Read` tool default of 2000 lines is fine). Save `head -N` for files where `wc -l` first confirms the file is huge.

- **Stale wakeup-prompt confusion.** Harness replayed two stale wakeup messages ("Continue brainstorm..." + "Continue plan: collect remaining...") mid-plan-review. Correctly identified as stale; no actual error. **Prevention:** none needed — the orchestrator's job is to maintain the current task's context across wakeup-replays; the harness has no way to know which wakeup is stale. Flagging in case the harness's ScheduleWakeup deduplication has a gap.

## Key Insight

A 953-line plan that compresses to 829 lines under 5-agent review while ALSO becoming more correct (4 P0 issues dissolved + 7 P1 issues fixed inline) is the strongest signal the v1 plan was over-architected. The combination of "remove this entire feature" (DHH/CS) and "this feature has 4 specific bugs" (Kieran/Arch/SpecFlow) is the load-bearing diagnostic — when both fire on the same scope, the right move is delete, not fix. Single-panel review (3 reviewers) is an aggregation of one perspective. Multi-panel review (5 reviewers spanning simplicity AND correctness) is an orthogonal-axis sweep that catches the architectural false-trails that a same-perspective panel cannot.

The brand-survival threshold gating (`single-user incident → 5-agent panel`) is the right gate for this. It's not ceremony; it's a structural defense against the false-trail class of failure where a single-perspective panel ratifies an over-architected plan because it's "internally coherent" (Kieran-style) or "appropriately defensive" (DHH would still be missing Architecture's blast-radius lens).

## Tags

category: workflow-patterns
module: plan + plan-review
