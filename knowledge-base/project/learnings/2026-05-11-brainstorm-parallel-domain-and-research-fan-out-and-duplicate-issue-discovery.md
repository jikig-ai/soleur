---
title: "Brainstorm-time parallel fan-out + mid-flight duplicate-issue discovery"
date: 2026-05-11
category: workflow-patterns
tags:
  - brainstorm
  - parallel-fan-out
  - issue-deduplication
  - prior-art-discovery
  - subagent-verification
issue: "#2720"
pr: "#3559"
session: feat-compound-promotion-loop brainstorm
---

# Brainstorm-time parallel fan-out + mid-flight duplicate-issue discovery

## Problem

Three distinct workflow signals surfaced in one brainstorm session and are worth codifying together so the next brainstorm is faster, more honest, and avoids duplicating closed design conversations.

1. **Issue #2720 was a re-framing of already-deferred #421.** The 2026-05 claude-skills audit (#2718) generated #2720 as a Tier-1 action item without cross-referencing the 2026-03-03 self-healing-workflow brainstorm that had already specified the same mechanism (Layer 2 weekly CI sweep, deferred until Layer 1 proved value). Layer 1 had been shipping for 2 months. #2720 risked becoming a parallel design conversation against a stale Layer 2 design.
2. **Spawning domain leaders + research agents in parallel compressed brainstorm wall-clock time.** Instead of sequencing CPO → CTO → CLO → CMO → repo-research → learnings-research, all 6 ran concurrently via `run_in_background: true` and returned in 60–180s. The orchestrator processed them as they arrived rather than blocking on the slowest.
3. **Prior-art directories left empty by worktree-manager produce false-positive signals.** `find knowledge-base/project/specs -iname "*<slug>*"` returned `feat-compound-promotion-loop/` as a hit even though the directory was empty (created earlier by `worktree-manager.sh feature` but never written to). The orchestrator briefly treated this as evidence of prior spec work.

## Solution

### Pattern 1 — Always check sibling/parent issues for prior framing of the same mechanism

When a brainstorm starts with an issue reference (`#N`), the brainstorm research phase MUST do two GitHub-side checks beyond just verifying `#N` is OPEN:

1. Read the parent (issue body's `Parent: #M` or umbrella issue) and look at the sibling tier-1/tier-2 children. Check if any sibling describes a similar mechanism.
2. Run `gh issue list --state all --search "<core-mechanism-keywords>"` (e.g., `"self-healing OR rule promotion OR recurring pattern"`) to surface deferred or closed prior framings.

In this session, step 2 surfaced #421 immediately. Without it, the brainstorm would have produced a parallel spec without scope reconciliation, and the eventual implementing PR would have orphaned #421 in the backlog.

### Pattern 2 — Spawn domain leaders + research agents in one parallel batch at brainstorm Phase 0.5/1.1

The brainstorm skill's Phase 0.5 (domain leaders) and Phase 1.1 (research) are sequential in the spec but trivially independent in practice. Spawn them in one batch via `run_in_background: true`. Process results as the agents complete (the harness sends a `task-notification` per completion). Use ScheduleWakeup with 60–270s if you have nothing else to do meanwhile, but in practice the orchestrator can use the wait time for local checks (reading prior-art files, formulating the next dialogue question) rather than burning a wakeup.

Concretely, in this session:

- 4 domain leaders (CPO, CTO, CLO, CMO) + 2 research agents (repo-research, learnings) were dispatched in a single message containing 6 `Agent` tool calls.
- All 6 returned within 180s.
- The orchestrator did the prior-art file check + read self-healing brainstorm + read #421 body in parallel with the agents.
- Total brainstorm Phase 0.5 + 1.1 wall-clock: ~3 minutes vs. ~10 minutes if sequenced.

### Pattern 3 — Empty-but-existing spec directories are not prior-art evidence

`worktree-manager.sh feature <name>` creates `knowledge-base/project/specs/feat-<name>/` as part of worktree provisioning. If a prior session bailed before writing spec.md, the directory persists empty. A later brainstorm's `find ... -iname "*<slug>*"` (default `find`, hits both files AND directories) treats this as a signal that prior spec work exists.

Fix: brainstorm Phase 1.1 prior-art check should use `find ... -type f` so only file hits count, OR test directory emptiness before treating as evidence:

```bash
find knowledge-base/project/{brainstorms,specs} -maxdepth 3 -type f -iname "*<keyword>*" 2>/dev/null | head -n 20
```

The `-type f` flag is the minimal change.

## Session Errors

- **AskUserQuestion 4-option cap exceeded** — passed `multiSelect: true` with 5 options; got `InputValidationError: too_big maximum: 4`. Recovery: collapsed two guardrail options into one combined option. **Prevention:** Skill instructions for AskUserQuestion (in skill files that use it heavily) should explicitly state the 4-option cap and warn that the runtime auto-appends "Other" — do NOT include "Other" yourself. The brainstorm skill's Phase 0.1 already calls this out; should propagate the same note to other skills that ask multi-option questions (plan, deepen-plan).

- **Subagent phantom file-existence citation** — `learnings-researcher` cited `feat-agents-rule-threshold` spec + plan files as prior art; independent `find` confirmed neither exists. The phantom citation would have driven scope reconciliation against non-existent artifacts. **Prevention:** the brainstorm skill's Phase 1.1 already requires verifying file-existence claims from subagents (see the `2026-05-10` learning referenced in `hr-when-in-a-worktree-never-read-from-bare`). The orchestrator did verify before propagating into the brainstorm doc; the gate worked. No new code change needed — this is an existing rule operating correctly.

- **Empty-directory false-positive from `find` without `-type f`** — see Pattern 3 above.

- **Worktree-relative read attempt** — tried to Read a bare-repo path from inside the worktree. Already covered by `hr-when-in-a-worktree-never-read-from-bare`. No new prevention needed.

- **Bare-path Edit during route-to-definition** — same root cause as the prior bullet, repeat offense in a single session. While applying the three accepted skill-edits, I called Edit with `/home/jean/git-repositories/jikig-ai/soleur/plugins/soleur/skills/brainstorm/SKILL.md` (bare-repo absolute path) instead of `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-compound-promotion-loop/plugins/soleur/skills/brainstorm/SKILL.md` (worktree-absolute). Edit succeeded silently; `git status --short` showed no modifications because the edit landed outside the working tree. Caught only by the `git status --short` verification step in compound's Route-Learning-to-Definition routing mechanics. **Recovery:** re-applied via the worktree-absolute path. **Prevention:** the existing rule and route-to-definition guidance already prescribe (a) worktree-absolute paths, (b) `git status --short` verification after edits. Both fired correctly here. The repeat-offense pattern in a single session suggests the orchestrator should construct the worktree-absolute path mechanically (`echo "$PWD/plugins/soleur/skills/brainstorm/SKILL.md"` from inside the worktree CWD) rather than typing absolute paths from memory.

## Key Insight

A brainstorm session has three sequential bottlenecks (domain assessment, repo research, dialogue) that are commonly assumed to depend on each other. In practice the first two are independent, can be batched into one parallel fan-out, and the orchestrator can do prior-art file checks + parent/sibling issue inspection in parallel with the agent runs. The dialogue (Phase 1.2) is the only step that genuinely blocks on the user. Compressing the front of the brainstorm from sequential to parallel saves 5–7 minutes per session and surfaces near-duplicate issues (like #421 / #2720) early enough to reconcile before any design effort is wasted.

## Tags

category: workflow-patterns
module: brainstorm
