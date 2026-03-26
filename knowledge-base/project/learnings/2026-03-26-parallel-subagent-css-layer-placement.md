# Learning: Parallel subagents and CSS @layer placement

## Problem

When using Tier B subagent fan-out for independent template edits, one agent (Group C) added CSS styles for the Getting Started two-path layout but placed them outside the `@layer components` block. The styles were syntactically correct and visually functional, but violated the CSS cascade architecture. A second agent (Group D) caught and fixed the misplacement when it was assigned to edit the same file.

## Solution

The Group D agent detected the orphaned styles after the `@layer components` closing brace and moved them inside. The fix was mechanical — the styles themselves were well-written, they were just in the wrong location in the file.

The lead agent's post-collection integration review (Step B3 of fan-out protocol) would have caught this via a CSS `@layer` audit, but the Group D agent resolved it first since it was already assigned to the same file.

## Key Insight

When multiple subagents edit the same file (CSS in this case), the last writer can inadvertently place content outside architectural boundaries like `@layer` blocks. The fan-out protocol should minimize same-file assignments across groups, or the lead agent should explicitly audit `@layer` boundaries in CSS files during Step B3 integration review.

## Session Errors

**CWD drift after Eleventy build** — The `--serve` flag caused the working directory to shift to `_site`, breaking subsequent relative path commands. Recovery: used absolute paths. Prevention: always use absolute paths for post-build verification commands, or re-set CWD explicitly after build.

**CSS @layer placement by parallel agent** — Group C wrote styles outside `@layer components`. Recovery: Group D agent caught and fixed it. Prevention: when assigning CSS edits to subagents, include explicit instruction "Add styles inside `@layer components` block, before its closing brace."

## Tags

category: integration-issues
module: docs-site
