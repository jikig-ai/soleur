# Learning: one-shot Plan+Deepen subagent writes to bare-root, not the worktree

## Problem

One-shot's Steps 1-2 spawn a general-purpose subagent to run `soleur:plan` and `soleur:deepen-plan`. The parent agent had already `cd`'d into the worktree (`/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2729/`), so its bash CWD persisted there. The subagent received a prompt with `WORKING DIRECTORY: <worktree-path>` in the body, but the subagent's Bash-tool CWD did not inherit the parent's persistent `cd`. The subagent's `soleur:plan` invocation wrote `2026-05-15-content-category-creation-skill-libraries-vs-workflow-plugins-plan.md` to the **bare-root** synced mirror at `/home/jean/git-repositories/jikig-ai/soleur/knowledge-base/project/plans/`, not to the worktree's `knowledge-base/`.

The bare-root mirror is a sync target maintained by `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (the SessionStart hook runs `Syncing on-disk files from git HEAD`). Any file the subagent writes there is at risk of being clobbered the next time the sync runs from the bare-root context.

## Root Cause

Two compounding facts:

1. **Bash-tool CWD is per-agent, not inherited from the parent.** A subagent's Bash tool starts at the user's initial CWD (the original session start), not at the parent's persisted `cd`. Parent agents that have used `cd <worktree-path> && ...` to move into the worktree need to forward that path to the subagent prompt AND require the subagent to `cd` explicitly as its first action.

2. **The prompt's `WORKING DIRECTORY: <path>` directive is advisory.** The subagent reads it but is not required to `cd` first — many subagents skim the prompt for the action and start invoking the named skill from wherever their Bash CWD happens to be.

When the named skill is `soleur:plan` and the skill creates files via the Write tool, the Write tool's target is the absolute path the skill builds — which is built from the skill's CWD. The bare-root CWD produces a bare-root absolute path. The subagent has no signal that something is wrong; nothing fails loudly.

## Solution

In `plugins/soleur/skills/one-shot/SKILL.md` Steps 1-2 (the plan+deepen subagent prompt template), prepend two requirements:

1. **Force the subagent to `cd` and verify first.** The first tool call MUST be `cd <WORKING_DIRECTORY> && pwd` and the response MUST equal the parent's specified path. If not, the subagent aborts and reports the divergence.

2. **Re-resolve the plan path against the worktree after return.** After parsing `### Plan File` from the subagent's Session Summary, verify the path is inside `<worktree-path>/` (not the bare-root). If it isn't, copy or move it before continuing.

Both gates are cheap, defensive, and address two failure surfaces: subagents that ignore the CWD directive (gate 1) and subagents that report a correctly-resolved path but wrote elsewhere (gate 2).

## Key Insight

**Bash CWD does not survive the agent boundary.** This is structurally different from environment variables or filesystem state. Parent `cd` is per-agent and per-tool-call-chain. Any pipeline that spans multiple subagent invocations (one-shot, deepen-plan, work in agent-team mode) must enforce CWD as part of the subagent contract, not as advisory prose in the prompt body.

## Tags

category: integration-issues
module: one-shot, plan, deepen-plan, subagent-protocol

## Session Errors

1. **Plan written to bare-root (not worktree)** — Recovery: `cp` plan file into worktree before downstream steps. Prevention: enforce `cd <WORKING_DIRECTORY> && pwd` as subagent's first tool call (this learning's Solution §1).

2. **`grep -c` counted matching lines, not occurrences** — first density check returned 5/5 when actual occurrence counts were 13/11. Recovery: switched to `grep -oiE | wc -l`. Prevention: for occurrence counting always use `grep -oE | wc -l`; `grep -c` counts matching lines.

3. **Initial draft "workflow plugin" occurrence count 25× (plan target 5-7, threshold ≤10)** — overuse of the noun phrase as a stand-in for pronouns. Recovery: two passes of edits replacing with "this shape" / "the organization" / "the substrate"; landed at 10. Prevention: when a plan declares a keyword-density target, sketch a per-section occurrence budget BEFORE writing, then count during draft.

4. **Brand-guide banned token "just" slipped into first draft (twice)** — once as "just need more capabilities" (minimizing per brand-guide rule), once as "not just the tools" (acceptable in context but still flagged). Recovery: edits replaced with "want" / "not only". Prevention: run brand-token grep gate (`grep -niE '\b(just|simply|copilot|terminal-first|AI-powered|leverage AI)\b'`) BEFORE AC3/AC4 grep gates so brand violations surface in the same pass.

5. **Distribution URLs included date prefix `/blog/2026-05-15-...`** — Eleventy strips the date in `page.fileSlug`; canonical URL is date-stripped. Caught by `pattern-recognition-specialist` at review. Existing learning (`2026-03-24-eleventy-fileslug-date-stripping.md`) covers this; prevention is the existing `scripts/validate-blog-links.sh` (passes for both forms because Eleventy emits redirect stubs, but precedent-match is the right call).

6. **Bluesky variant 451 chars exceeded 300-char limit; took 3 trim passes** — URL alone is 146 chars; prose budget was overshot. Prevention: for platform-constrained posts, count the URL bytes first, subtract from the limit, then write prose against the remaining budget.
