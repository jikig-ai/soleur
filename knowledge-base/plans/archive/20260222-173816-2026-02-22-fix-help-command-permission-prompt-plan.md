# fix: Eliminate $() permission prompts in help command

**Type:** Bug fix
**Priority:** High -- blocks autonomous workflow execution
**Version bump:** PATCH
**Deepened on:** 2026-02-22

## Enhancement Summary

**Sections enhanced:** 3 (Proposed Solution, Implementation Notes, Test Scenarios)
**Research sources:** Glob tool pattern verification, 3 learnings docs, ship skill reference, constitution rules

### Key Improvements from Deepening

1. **Glob pattern correction:** `*/SKILL.md` does NOT work with the Glob tool -- must use `**/SKILL.md` with the skills directory as the path parameter. Verified empirically.
2. **Accurate baseline counts established:** 60 agents, 3 commands, 50 skills, 9 domains (community directory exists but has no SKILL.md, correctly excluded).
3. **Glob tool requires absolute paths for the `path` parameter** -- relative paths return no results. The help command must instruct the LLM to use the repo root path or the plugin installation path as the Glob base.
4. **Edge case: `community` skill directory exists without SKILL.md** -- the `**/SKILL.md` pattern correctly excludes it, confirming the count at 50 not 51.

### New Considerations Discovered

- The help command's output template lists agent categories as "review, research, design, workflow" -- but the actual domains are engineering, finance, legal, marketing, operations, product, sales, support, community (9 top-level). The template is stale and conflates engineering subcategories with top-level domains. This is a pre-existing issue outside our fix scope.
- The `text` code fence used for the output template does not trigger permission prompts (only `bash` fences do). The template can remain as-is.

## Summary

The `/soleur:help` command (`plugins/soleur/commands/soleur/help.md`) uses `find ... | wc -l` piped Bash commands in Step 2 to count agents, commands, skills, and categories. While these commands do not contain literal `$()` command substitution, they use `find` and `cat` via the Bash tool -- both of which Claude Code's own guidelines say to avoid in favor of dedicated tools (Glob, Read). The piped `find | wc` commands also trigger Claude Code's security prompt for complex shell constructs.

The fix replaces all bash code blocks with prose instructions directing the LLM to use native Claude Code tools (Read for plugin.json, Glob for file discovery, direct counting from Glob results).

## Problem Analysis

### Current help.md Structure

1. **Step 1** -- `cat plugins/soleur/.claude-plugin/plugin.json` (Bash) -- reads plugin manifest
2. **Step 2** -- Four `find ... | wc -l` commands (Bash) -- counts agents, commands, skills, categories
3. **Step 3** -- Formatted text output template with `[N]`, `[M]`, `[count]` placeholders

### Why This Triggers Problems

- The `find | wc` piped commands are executed via the Bash tool, which works but violates the project convention: "Avoid using Bash with the `find`, `grep`, `cat`, `head`, `tail`, `sed`, `awk`, or `echo` commands" (from Claude Code's own guidelines)
- The `cat` command for reading plugin.json similarly has a dedicated alternative (Read tool)
- While no literal `$()` appears in these commands, the pattern of "run Bash to get a value, substitute into output" is the same fragile pattern that caused `$()` issues elsewhere
- The constitution explicitly says: "Never use shell variable expansion (`${VAR}`, `$VAR`, `$()`) in bash code blocks within skill, command, or agent .md files"
- The help command should use **prose instructions** to tell the LLM which tools to use, not bash code blocks

### Related Learnings

Three documented learnings cover this exact pattern:
- `2026-02-22-command-substitution-in-plugin-markdown.md` -- documents the `$()` recurrence pattern across 3 versions (v2.23.15, v2.23.18, v2.26.1)
- `2026-02-22-shell-expansion-codebase-wide-fix.md` -- documents the broader `${VAR}` fix across 18+ files
- `2026-02-22-skill-count-propagation-locations.md` -- documents that component counts appear in 5+ files (relevant if counts change)
- The ship skill's SKILL.md has the reference implementation: "CRITICAL: No command substitution. Never use `$()` in Bash commands."

### Reference Implementation

The ship skill's pattern (line 10 of SKILL.md): "When a step says 'get value X, then use it in command Y', run them as **two separate Bash tool calls** -- first get the value, then use it literally in the next call."

But for help, an even better approach exists: replace Bash entirely with dedicated tools (Glob, Read) since all operations are file-system reads.

## Proposed Solution

### Approach: Replace Bash with Prose Instructions for Native Tools

Rewrite `help.md` to instruct the LLM to use:
- **Read tool** for `plugin.json` (instead of `cat`)
- **Glob tool** for file/directory discovery (instead of `find`)
- **Direct counting** from Glob results (instead of `wc -l`)

This eliminates all bash code blocks from the help command entirely.

### New help.md Structure

#### Step 1: Read Plugin Manifest

Replace the `cat` bash block with a prose instruction:

> Use the **Read tool** to read `plugins/soleur/.claude-plugin/plugin.json` to get the plugin version and metadata. If that path does not exist, try reading from `~/.claude/plugins/*/soleur/.claude-plugin/plugin.json`.

#### Step 2: Count Components

Replace the four `find | wc` bash blocks with prose instructions using Glob. All four Glob calls are independent and should be made **in parallel** in a single message.

> Use the **Glob tool** to count components. Make all four calls in parallel:
>
> 1. **Count agents:** Use pattern `**/*.md` with path `plugins/soleur/agents` -- count the returned file paths
> 2. **Count commands:** Use pattern `*.md` with path `plugins/soleur/commands/soleur` -- count the returned file paths
> 3. **Count skills:** Use pattern `**/SKILL.md` with path `plugins/soleur/skills` -- count the returned file paths (one SKILL.md per skill)
> 4. **Count agent domains:** Use pattern `*` with path `plugins/soleur/agents` to list top-level domain directories -- count them

**Critical Glob tool behavior (verified empirically):**
- The `path` parameter must be provided for these patterns to work
- `*/SKILL.md` returns zero results; `**/SKILL.md` is required even for depth-1 matches
- The tool returns absolute file paths sorted by modification time

If the plugin paths do not exist (installed via registry), fall back to paths under `~/.claude/plugins/`.

#### Step 3: Output (unchanged)

The formatted text template remains the same -- the LLM fills in counts from Glob results instead of from Bash output. The `text` code fence for the template does NOT trigger permission prompts.

### Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/commands/soleur/help.md` | Remove all bash code blocks; replace with prose instructions for Read and Glob tools |

### Files NOT Changed

- No new files created
- No skills or agents modified
- No constitution update needed (rule already exists)

## Acceptance Criteria

- [x] `help.md` contains zero bash code blocks (no triple-backtick-bash fences)
- [x] `help.md` contains no `$()`, `${VAR}`, `$VAR`, `find`, `wc`, or `cat` commands in executable context
- [ ] Running `/soleur:help` produces correct counts without triggering any permission prompts
- [ ] The help output format matches the existing template (COMMANDS, WORKFLOW SKILLS, AGENTS, SKILLS, MCP SERVERS sections)
- [ ] Glob patterns correctly discover agents (60), commands (3), skills (50), and domains (9)

## Test Scenarios

### Scenario 1: Help runs without permission prompts

**Given** a user invokes `/soleur:help`
**When** Claude Code executes the help command instructions
**Then** no "$() command substitution" or "Shell expansion syntax" permission dialog appears
**And** the output displays correct component counts

### Scenario 2: Counts are accurate

**Given** the plugin currently has 60 agents, 3 commands, 50 skills, 9 domains
**When** the Glob tool counts files matching the specified patterns
**Then** the counts in the help output match these verified values

### Research Insight: Verified Glob Patterns

| Component | Glob Pattern | Path Parameter | Expected Count |
|-----------|-------------|----------------|----------------|
| Agents | `**/*.md` | `plugins/soleur/agents` | 60 |
| Commands | `*.md` | `plugins/soleur/commands/soleur` | 3 |
| Skills | `**/SKILL.md` | `plugins/soleur/skills` | 50 |
| Domains | (use ls via Bash or infer from agent paths) | `plugins/soleur/agents` | 9 |

**Edge case verified:** The `community` skill directory exists but contains no `SKILL.md` (removed in #284). The `**/SKILL.md` pattern correctly excludes it, producing a count of 50 rather than 51.

### Scenario 3: Fallback paths work

**Given** the plugin is installed via the plugin registry (not local development)
**When** `plugins/soleur/.claude-plugin/plugin.json` does not exist
**Then** the help command falls back to `~/.claude/plugins/*/soleur/.claude-plugin/plugin.json`

## Non-Goals

- Changing the help output format or content
- Adding new sections to the help output
- Restructuring the skill listing or agent categorization
- Fixing the stale agent category listing in the template (pre-existing issue; the template shows engineering subcategories rather than top-level domains)
- Fixing `$()` in other files (already addressed in prior versions)
- Adding tests for the help command (it is a markdown instruction file, not code)

## Implementation Notes

### Glob Tool Behavior (Verified)

- The Glob tool returns absolute file paths sorted by modification time -- counting results gives the total
- `**/SKILL.md` is required for skills (not `*/SKILL.md`); single-star patterns fail to match even at depth 1
- `**/*.md` works correctly for recursive agent discovery
- The `path` parameter MUST be provided; omitting it uses the CWD which may not be the repo root

### Skill Discovery Pattern

- `**/SKILL.md` with path `plugins/soleur/skills` is the correct pattern because:
  - The plugin loader only discovers `skills/<name>/SKILL.md` (flat, no recursion)
  - But the Glob tool's `*/SKILL.md` single-star pattern empirically returns zero results
  - `**/SKILL.md` still returns only depth-1 SKILL.md files because no nested `SKILL.md` files exist
  - Directories without `SKILL.md` (like `community/`) are correctly excluded

### Agent Counting

- Agent counting should use `**/*.md` to recurse into subdirectories (agents DO recurse)
- All 60 agent `.md` files are actual agents (no README.md files to filter out)
- Domain count (9) comes from top-level directories under `agents/`: community, engineering, finance, legal, marketing, operations, product, sales, support

### Domain Counting Edge Case

The Glob tool does not have a "directories only" mode. To count domains, either:
1. Infer from the agent file paths (extract unique second path segments after `agents/`)
2. Or use a single `ls` Bash command on `plugins/soleur/agents/` (this is a simple listing, not a piped command, so it should not trigger permission issues)

The plan recommends option 1 (inference from Glob results) to avoid any Bash usage, but option 2 is acceptable as a fallback.

### Version Bump

PATCH bump: 3.0.5 -> 3.0.6. Only `help.md` changes -- no new skills, commands, or agents.

## Rollback Plan

Revert the single file change with `git revert <commit-sha>`. The previous help.md with bash code blocks still works -- it just triggers permission prompts.
