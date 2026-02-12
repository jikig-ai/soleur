---
name: release-docs
description: This skill should be used when building and updating the documentation site with current plugin components. It inventories all agents, commands, skills, and MCP servers, then updates HTML documentation pages and metadata files with accurate counts and component listings. Triggers on "update docs", "release documentation", "sync docs site", "regenerate docs", "documentation release".
---

# Release Documentation

Generate and update the documentation site for the soleur plugin, ensuring `plugins/soleur/docs/` is always up-to-date with the actual plugin components.

## Overview

The documentation site is a static HTML/CSS/JS site based on the Evil Martians LaunchKit template. It needs to be regenerated whenever:

- Agents are added, removed, or modified
- Commands are added, removed, or modified
- Skills are added, removed, or modified
- MCP servers are added, removed, or modified

## Step 1: Inventory Current Components

First, count and list all current components:

```bash
# Count agents
find plugins/soleur/agents -name "*.md" -not -name "README.md" | wc -l

# Count commands
find plugins/soleur/commands -name "*.md" -not -name "README.md" | wc -l

# Count skills
find plugins/soleur/skills -name "SKILL.md" | wc -l

# Count MCP servers
ls -d plugins/soleur/mcp-servers/*/ 2>/dev/null | wc -l
```

Read all component files to get their metadata:

### Agents
For each agent file in `plugins/soleur/agents/*.md`:
- Extract the frontmatter (name, description)
- Note the category (Review, Research, Workflow, Design, Docs)
- Get key responsibilities from the content

### Commands
For each command file in `plugins/soleur/commands/*.md`:
- Extract the frontmatter (name, description, argument-hint)
- Categorize as Workflow or Utility command

### Skills
For each skill directory in `plugins/soleur/skills/*/`:
- Read the SKILL.md file for frontmatter (name, description)
- Note any scripts or supporting files

### MCP Servers
For each MCP server in `plugins/soleur/mcp-servers/*/`:
- Read the configuration and README
- List the tools provided

## Step 2: Update Documentation Pages

### 2a. Update `docs/index.html`

Update the stats section with accurate counts:
```html
<div class="stats-grid">
  <div class="stat-card">
    <span class="stat-number">[AGENT_COUNT]</span>
    <span class="stat-label">Specialized Agents</span>
  </div>
  <!-- Update all stat cards -->
</div>
```

Ensure the component summary sections list key components accurately.

### 2b. Update `docs/pages/agents.html`

Regenerate the complete agents reference page:
- Group agents by category (Review, Research, Workflow, Design, Docs)
- Include for each agent:
  - Name and description
  - Key responsibilities (bullet list)
  - Usage example: `claude agent [agent-name] "your message"`
  - Use cases

### 2c. Update `docs/pages/commands.html`

Regenerate the complete commands reference page:
- Group commands by type (Workflow, Utility)
- Include for each command:
  - Name and description
  - Arguments (if any)
  - Process/workflow steps
  - Example usage

### 2d. Update `docs/pages/skills.html`

Regenerate the complete skills reference page:
- Group skills by category (Development Tools, Content & Workflow, Image Generation)
- Include for each skill:
  - Name and description
  - Usage: `claude skill [skill-name]`
  - Features and capabilities

### 2e. Update `docs/pages/mcp-servers.html`

Regenerate the MCP servers reference page:
- For each server:
  - Name and purpose
  - Tools provided
  - Configuration details
  - Supported frameworks/services

## Step 3: Update Metadata Files

Ensure counts are consistent across:

1. **`plugins/soleur/.claude-plugin/plugin.json`**
   - Update `description` with correct counts
   - Update `components` object with counts
   - Update `agents`, `commands` arrays with current items

2. **`.claude-plugin/marketplace.json`**
   - Update plugin `description` with correct counts

3. **`plugins/soleur/README.md`**
   - Update intro paragraph with counts
   - Update component lists

## Step 4: Validate

Run validation checks:

```bash
# Validate JSON files
cat .claude-plugin/marketplace.json | jq .
cat plugins/soleur/.claude-plugin/plugin.json | jq .

# Verify counts match
echo "Agents in files: $(find plugins/soleur/agents -name '*.md' -not -name 'README.md' | wc -l)"
grep -o "[0-9]* specialized agents" plugins/soleur/docs/index.html

echo "Commands in files: $(find plugins/soleur/commands -name '*.md' -not -name 'README.md' | wc -l)"
grep -o "[0-9]* slash commands" plugins/soleur/docs/index.html
```

## Step 5: Report Changes

Provide a summary of what was updated:

```
## Documentation Release Summary

### Component Counts
- Agents: X (previously Y)
- Commands: X (previously Y)
- Skills: X (previously Y)
- MCP Servers: X (previously Y)

### Files Updated
- docs/index.html - Updated stats and component summaries
- docs/pages/agents.html - Regenerated with X agents
- docs/pages/commands.html - Regenerated with X commands
- docs/pages/skills.html - Regenerated with X skills
- docs/pages/mcp-servers.html - Regenerated with X servers
- plugin.json - Updated counts and component lists
- marketplace.json - Updated description
- README.md - Updated component lists

### New Components Added
- [List any new agents/commands/skills]

### Components Removed
- [List any removed agents/commands/skills]
```

## Dry Run Mode

If `--dry-run` is specified:
- Perform all inventory and validation steps
- Report what WOULD be updated
- Do NOT write any files
- Show diff previews of proposed changes

## Error Handling

- If component files have invalid frontmatter, report the error and skip
- If JSON validation fails, report and abort
- Always maintain a valid state - don't partially update

## Post-Release

After successful release:
1. Suggest updating CHANGELOG.md with documentation changes
2. Remind to commit with message: `docs: Update documentation site to match plugin components`
3. Remind to push changes

## Usage Examples

```bash
# Full documentation release
/release-docs

# Preview changes without writing
/release-docs --dry-run

# After adding new agents
/release-docs
```
