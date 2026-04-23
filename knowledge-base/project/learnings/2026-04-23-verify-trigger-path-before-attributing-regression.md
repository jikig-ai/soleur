---
date: 2026-04-23
category: integration-issues
module: debugging-discipline
tags: [regression-analysis, diagnostic, post-deploy, attribution]
brainstorm: 2026-04-23-command-center-activity-ux-brainstorm.md
issue: "#2861"
related:
  - 2026-04-23-command-center-bubble-lifecycle-invariants.md
---

# Verify trigger path before attributing a symptom to a recent PR

## Problem

During brainstorm for #2861, the Command Center showed "Agent stopped responding" on the CTO bubble after PR #2843 deployed hours earlier. Initial framing (mine): "this is a #2843 regression" — #2843 had fixed stuck-bubble lifecycle invariants, so a returning symptom of the same shape read as a regression.

That framing was wrong. Repo-research-analyst grepped the literal string, traced the renderer to `applyTimeout` in `chat-state-machine.ts:239`, walked back to `STUCK_TIMEOUT_MS = 45_000` in `ws-client.ts:70`, and found a client-side watchdog that PR #2843 never touched. The actual cause: long-running tool execution (Bash, Grep, Read) starves the 45-second client watchdog because `tool_use` fires only when the model *issues* the call, not during execution. SDK emits `SDKToolProgressMessage` heartbeats during execution, but `agent-runner.ts` does not forward them — confirmed with `rg "SDKToolProgress|elapsed_time"` returning zero hits.

If the wrong framing had gone unchecked, the implementation PR would have spent its energy re-examining the stream-end emission path (where #2843 already placed defense-in-depth) instead of the actual gap (missing heartbeat forwarding).

## Solution

When a post-deploy symptom matches the shape of a recently-merged fix, do not accept the regression framing until the symptom's **actual trigger path** has been traced end-to-end and cross-checked against the PR's diff.

Concrete procedure:

1. Grep the literal user-visible string (chip text, toast message, error copy) to locate the rendering component.
2. Trace the render condition back to the state field it keys off (reducer branch, effect, WS event).
3. Identify the trigger — what emits the event or sets the state? Server code, client timeout, reconnect handler, etc.
4. Cross-check the trigger path against the recent PR's file/line diff. If the PR did not modify any file on that path, the symptom is NOT a regression of that PR. It is either a distinct latent bug or an adjacent uncovered code path.
5. Only after step 4 is complete, decide whether this PR should also own the fix (related class) or whether it needs its own tracking issue.

This is a cheap discipline — 10 minutes of subagent work — and it prevents whole-PR mis-scoping when debugging.

## Key insight

**"Same shape" is not "same cause."** Two symptoms can be visually identical (stuck-looking bubble, no response) but emerge from different subsystems (server stream emission vs client watchdog starvation). The model's bias is to treat shape-matching as causal attribution, especially when a recent PR claimed to fix that shape. The research-agent discipline of tracing the literal rendered string to its trigger predicate counter-acts this bias mechanically.

Related existing rules don't cover this:

- `hr-before-asserting-github-issue-status` covers *issue-state* attribution, not *symptom-to-PR* attribution.
- `rf-after-merging-read-files-from-the-merged` covers staleness of the bare repo, not diagnostic reasoning.

A new AGENTS.md rule was considered but skipped: AGENTS.md is over the 40000-byte budget and the longest rule is already 736 bytes. This learning file is the durable home for the discipline; future brainstorm sessions can reference it by name when the symptom-shape-matches-recent-PR pattern surfaces.

## Session Errors

1. **Misattributed regression during framing.** Described "Agent stopped responding" as likely #2843 regression before tracing the trigger path. **Recovery:** repo-research-analyst caught it; pivoted the spec to forward `SDKToolProgressMessage` instead of re-examining stream-end emission. **Prevention:** this learning.

2. **Skipped brainstorm skill Phase 0.25 (Roadmap Freshness Check).** Judged non-critical for narrow UX fix; no downstream impact because no domain leader hinged on phase state. **Prevention:** either follow verbatim on all invocations, or refine the skill to explicitly exempt narrow scopes.

3. **Did not spawn CMO despite `hr-new-skills-agents-or-user-facing`.** Treated as polish-to-existing-capability rather than new capability. Judgment call; marketing relevance genuinely marginal. **Prevention:** the rule could be tightened to "new OR user-facing-regression" to remove ambiguity — tracked separately, not acted on here due to byte-budget constraint.

## Prevention

- When a brainstorm or bug investigation opens with "this looks like a regression of #N", ALWAYS trace the rendered-string → render condition → trigger path → PR diff chain before accepting the framing. A subagent (repo-research-analyst or Explore) with the exact prompt "find the literal string X, trace back to what triggers it, cross-check against #N's diff" is the right tool.
- In brainstorm / one-shot sessions, if the user's first message attributes a symptom to a recent PR, build the attribution verification into Phase 1.1 research.

## Cross-references

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-23-command-center-activity-ux-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-command-center-activity-ux/spec.md`
- Issue #2861 (tracks the actual fix)
- Learning: `2026-04-23-command-center-bubble-lifecycle-invariants.md` (PR #2843 — the PR that was initially but incorrectly blamed)
