---
date: 2026-05-09
category: workflow-gap
topic: brainstorm skill heuristics — substring-match, roadmap-skip, CMO scope
session: brainstorm for #3493 change-class AGENTS.md loader
branch: feat-agents-md-change-class-loader
pr: "#3496"
related_issues: ["#3493"]
related_learnings:
  - 2026-04-23-agents-md-governance-measure-before-asserting.md
  - 2026-04-21-agents-md-rule-retirement-deprecation-pattern.md
  - 2026-04-18-agents-md-byte-budget-and-why-compression.md
tags:
  - brainstorm
  - skill-heuristics
  - substring-match
  - roadmap-freshness
  - domain-routing
  - workflow-gap
---

# Brainstorm skill heuristics: three concrete gaps surfaced by a USER_BRAND_CRITICAL session

## Problem

Running the brainstorm skill on issue #3493 (a developer-tool, internal-CLI, USER_BRAND_CRITICAL session) surfaced three load-bearing heuristics in the brainstorm skill that gave wrong answers and forced ad-hoc operator override:

1. **Phase 0.1 substring-match misses semantic-intent endorsements.** The framing question's keyword-match scans only the free-text answer. When the operator picks a multi-option endorsement like "All of them" via `AskUserQuestion`'s native multi-select-by-shorthand UX, the literal answer string contains zero AGENTS.md trigger keywords (auth, credential, secret, token, …) even when the *endorsed options* enumerate credential-class risk vectors. Strict reading would have set `USER_BRAND_CRITICAL=false` and skipped the mandatory CPO+CLO+CTO trio. The session set the flag anyway based on operator-visible semantic intent — a defensible override but a heuristic gap that future sessions cannot rely on.

2. **Phase 0.25 roadmap-freshness skip-on-internal-topic isn't a valid skip criterion.** The skill text says "Skip if `knowledge-base/product/roadmap.md` does not exist." The session rationalized a topical skip ("internal CLI tooling, leaders won't sequence against product phases"), which is not in the skill's skip criteria. At Phase 3.6 the skip's cost surfaced: the Phase 4 milestone row was stale (28/68 listed, 54/70 actual), and the count had to be patched at the wrong phase, polluting the artifact-capture commit with a roadmap edit that should have been done five phases earlier.

3. **`hr-new-skills-agents-or-user-facing` CMO inclusion is ambiguous for developer-tool capabilities.** The rule says "New skills, agents, or user-facing capabilities must include CPO and CMO at minimum." A change-class loader is user-facing for the operator running Claude Code (the only "user" today), but CMO assessment isn't load-bearing for an internal hook architecture. The session skipped CMO and rationalized the omission. Strict reading is unclear; the skill's domain-config defaults rely on the operator's relevance assessment, which is unauditable.

A fourth tension: `wg-before-every-commit-run-compound-skill` says "before every commit, run compound." Brainstorm Phase 3.6 step 6 commits artifacts BEFORE Phase 4 (where compound runs). The skill prescribes a flow that violates the workflow gate, or the workflow gate's "every commit" scope excludes skill-orchestrated artifact captures. Either is a defensible interpretation — flagging as documentation drift.

A fifth observation: `wg-at-session-start-run-bash-plugins-soleur` (cleanup-merged + .mcp.json refresh) wasn't run at session start. The `/soleur:go` skill went straight to issue classification without a session-start hygiene step. Not a brainstorm-skill issue specifically, but a session-onboarding gap that could land in /soleur:go's Step 0.

## Solution

### For gap 1 (substring-match scope)

Edit `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.1 Step 2 so the keyword scan unions the free-text answer with the option text the user endorsed. Concretely: when the user picks "All of them" or selects multiple options, concatenate the endorsed option labels + descriptions and run substring match across the union. The current single-string match is correct for single-option answers; the bug is for multi-endorsement answers.

### For gap 2 (roadmap-freshness skip scope)

Edit `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.25 to remove implicit topical-skip latitude. Keep the explicit "Skip if roadmap.md does not exist" criterion, but add: "Topic ('internal tooling', 'CLI infra', 'developer-tool') is NOT a skip criterion. Roadmap freshness affects domain-leader counts and phase milestone alignment regardless of brainstorm topic." Cost is bounded — even on internal-tooling sessions, the milestone count check completes in a few seconds.

### For gap 3 (CMO inclusion ambiguity)

File a GitHub issue for design discussion. The rule scope ("user-facing capability") doesn't crisply distinguish operator-facing internal tooling (where CMO is genuinely not load-bearing) from product features (where CMO is). A skill edit alone cannot resolve this; the rule itself needs refinement.

### For gaps 4 and 5 (commit-vs-compound tension; session-start hygiene)

File two issues. Each has competing valid interpretations and the right resolution requires reviewer judgment, not a single bullet append.

## Key Insight

A skill heuristic can be subtly wrong in two distinct ways:

- **Mechanism gap:** the heuristic looks at the wrong substrate (e.g., free-text only when option-text is also relevant).
- **Scope gap:** the heuristic has implicit latitude that's not in its written criteria (e.g., topical skip not codified).

Both are silent failures. The first surfaces only when an operator notices the heuristic gave the wrong answer for the right reason and overrides. The second surfaces only when the cost of the skip is paid in a downstream phase. Neither is captured by `emit_incident` telemetry today (78% of rules are prompt-only and don't self-report — the same blind spot driving #3493's design).

The **complementary observation** from this session: the rule-metrics aggregator reports 67 of 69 AGENTS.md rules have zero hits over 8 weeks (97%). That's empirical corroboration of #3493's premise — most rules don't fire on most sessions. The change-class loader isn't optimization for its own sake; it's the architectural response to a measured underutilization rate.

A pattern worth naming: **when an existing pointer pattern (used for one narrow case — retired rule pointers per `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`) is the right shape for a much larger problem (all rules, conditionally loaded), the cost of generalizing is mostly mechanical rule relocation.** The architectural decision is recognizing the shape match, not inventing the mechanism.

## Session Errors

1. **`cd .worktrees/feat-agents-md-change-class-loader` failed with "No such file or directory."** Recovery: ran `pwd`, confirmed already in the worktree. Prevention: in skills that may run from either bare-repo root or worktree, check `pwd` before any `cd .worktrees/...`. Cost: 1 wasted command.

2. **Phase 0.25 roadmap freshness skipped on weak rationale.** Recovery: caught at Phase 3.6 when the stale Phase 4 milestone count (28/68) didn't match the live count (54/70); patched at Phase 3.6 commit. Prevention: brainstorm Phase 0.25 edit per "Solution / gap 2" above — codify that topic is not a skip criterion.

3. **Phase 0.1 substring-match heuristic gave a false-negative on "All of them".** Recovery: operator-visible semantic-intent override; flag set anyway. Prevention: brainstorm Phase 0.1 edit per "Solution / gap 1" above — match endorsed-option text in addition to free-text.

4. **CMO not included in domain assessment despite `hr-new-skills-agents-or-user-facing` rule.** Recovery: rationalized the omission (developer-tool, not content-bearing). Prevention: file issue per "Solution / gap 3" — rule scope refinement needed; skill edit alone cannot resolve.

5. **`wg-at-session-start-run-bash-plugins-soleur` skipped.** Recovery: none needed in this session — no merged-branch worktrees lying around. Prevention: file issue for `/soleur:go` Step 0 — call `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged` before issue classification. Better long-term: a SessionStart hook that runs cleanup-merged + .mcp.json sync (ironic given this brainstorm's topic).

## Cross-References

- Issue #3493 — token-efficiency catalog, parent of this brainstorm
- Draft PR #3496 — change-class loader brainstorm + spec
- Brainstorm document: `knowledge-base/project/brainstorms/2026-05-09-agents-md-change-class-loader-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md`
- Related learning: `2026-04-23-agents-md-governance-measure-before-asserting.md` (measurement gate cited in spec TR5)
- Related learning: `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` (pointer-pattern precedent generalized)
- Related learning: `2026-02-25-lean-agents-md-gotchas-only.md` (ETH Zurich data on per-turn overhead)
- Empirical signal: rule-metrics aggregator reports 67/69 rules zero-hit over 8 weeks (this session, 2026-05-09)
