# Learning: Skill defense-in-depth gate pattern (Phase N.5)

## Problem

The `/ship` skill could be invoked directly, bypassing the review step that `/one-shot` enforces. The `/work` skill's direct-invocation path also chained directly to compound -> ship without review.

## Solution

Added Phase 1.5 (Review Evidence Gate) to `/ship` SKILL.md between Phase 1 and Phase 2. Two detection signals: (1) `grep -rl "code-review" todos/` for review-tagged todo files, (2) `git log` grep for the review commit message pattern. Headless mode aborts on missing evidence; interactive mode presents Run/Skip/Abort options.

Updated `/work` Phase 4 direct-invocation chain from `compound -> ship` to `review -> resolve-todo-parallel -> compound -> ship`.

## Key Insight

Defense-in-depth gates in skills should follow the established Phase N.5 pattern: always run (not conditional on triggers), check for evidence of a prior step, branch on headless/interactive mode, and include a `**Why:**` rationale block. The primary fix is in the calling skill (work Phase 4 ensures review runs), while the gate in the called skill (ship Phase 1.5) is a safety net for direct invocations.

When adding detection signals that grep for specific strings from other skills (e.g., commit messages), document the coupling inline so future changes to the source skill trigger updates to the grep.

## Session Errors

1. **Wrong script path for Ralph loop setup** — Tried `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` (doesn't exist), correct path is `./plugins/soleur/scripts/setup-ralph-loop.sh`. **Prevention:** The one-shot skill instruction says `./plugins/soleur/scripts/setup-ralph-loop.sh` — read the instruction more carefully before running.
2. **Markdown lint failure on session-state.md** — Missing blank lines around headings/lists (MD022, MD032). **Prevention:** Use blank lines around all markdown headings and lists in generated files. The markdown-lint hook catches this at commit time.

## Tags

category: workflow
module: skills/ship, skills/work
