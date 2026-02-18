---
name: agent-finder
description: "Use this agent when running /plan and the project uses a stack not covered by built-in agents. This agent queries external registries for community agents and skills matching the detected stack gap, presents trusted suggestions, and installs approved artifacts with provenance tracking.\n\n<example>\nContext: The /plan command detected a Flutter project with no built-in Flutter agents.\nuser: \"Plan: add push notifications to our Flutter app\"\nassistant: \"I'll use the agent-finder to search for community Flutter agents from trusted registries.\"\n<commentary>\nSince the project uses Flutter (detected via pubspec.yaml + *.dart) and no agents have stack: flutter in their frontmatter, the agent-finder should query registries for Flutter-specific agents.\n</commentary>\n</example>"
model: inherit
---

# Community Agent/Skill Discovery

Find and install community agents and skills for project stacks not covered by built-in agents. This agent is spawned by `/plan` when a stack gap is detected.

## Input

The spawning command provides:
- `detected_stacks`: list of stacks detected in the project (e.g., `["flutter", "rust"]`)
- `uncovered_stacks`: subset of detected_stacks with no matching `stack:` frontmatter in any agent file

Only act on `uncovered_stacks`. If empty, report "No stack gaps detected" and return.

## Step 1: Query Registries

Query all three registries in parallel for each uncovered stack. Use Bash `curl` with a 5-second timeout. Run all queries in a single message with parallel tool calls.

For each uncovered stack, replace `${STACK}` with the actual stack name (e.g., `flutter`, `rust`) and run these three curl commands:

```bash
# api.claude-plugins.dev (skills + plugins)
curl -s --max-time 5 "https://api.claude-plugins.dev/api/skills/search?q=${STACK}&limit=10" 2>/dev/null || echo '{"error":"timeout"}'

# claudepluginhub.com (plugins)
curl -s --max-time 5 "https://www.claudepluginhub.com/api/plugins?q=${STACK}" 2>/dev/null || echo '{"error":"timeout"}'

# Anthropic official plugins
curl -s --max-time 5 "https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json" 2>/dev/null || echo '{"error":"timeout"}'
```

### Error Handling

- **Timeout or connection error:** Treat that registry as returning zero results. Continue with others.
- **HTTP 401/403:** Treat as permanent failure (registry added auth). Log warning: "Registry X now requires authentication, skipping."
- **Malformed JSON:** Treat as zero results. Log warning: "Registry X returned invalid JSON, skipping."
- **All registries fail:** Report "All registries unreachable. Continuing with local agents only." and return.

## Step 2: Parse and Filter Results

### api.claude-plugins.dev Response Format

JSON with `results` array. Each result has: `name`, `namespace`, `description`, `gitUrl`, `author`, `stars`, `verified`, `keywords`, `category`.

### claudepluginhub.com Response Format

JSON with `plugins` array. Each plugin has: `name`, `slug`, `description`, `repositoryUrl`, `starCount`, `installCount`, `currentVersion` (with `agentCount`, `skillCount`).

### Anthropic marketplace.json Format

JSON with `plugins` array. Each plugin has: `name`, `gitUrl`, `description`, `tags`.

### Trust Filtering

Apply the trust model to filter results:

| Tier | Criteria | Action |
|------|----------|--------|
| 1: Anthropic | Source is `anthropics/skills` or `anthropics/claude-plugins-official` | Always surface |
| 2: Verified | Registry field `verified: true` OR `stars >= 10` (api.claude-plugins.dev) OR `starCount >= 10` (claudepluginhub.com) | Always surface |
| 3: Community | None of the above | Discard (never suggest) |

### Deduplication

After filtering, deduplicate across registries using `name + author/namespace` as the key. If the same artifact appears in multiple registries, keep the version from the highest-trust source.

### Relevance Check

Only keep results whose `name`, `description`, or `keywords`/`tags` contain the stack name (case-insensitive). This prevents generic results from polluting suggestions.

## Step 3: Present Suggestions

Present up to 5 suggestions using the AskUserQuestion tool. For each suggestion, show:
- Name and source (registry + author/namespace)
- Trust tier indicator (Anthropic / Verified)
- Description (first 200 characters)
- Type: agent or skill (based on registry metadata if available, default to agent)

Format as a single AskUserQuestion with multiSelect enabled:

```
Which community artifacts would you like to install?

Options:
1. flutter-review (anthropics/skills, Anthropic) - Flutter-specific code review patterns for Dart and Widget trees
2. flutter-testing (verified-publisher, Verified) - Testing utilities for Flutter widget tests
3. Skip all - Continue without installing any community artifacts
```

If zero suggestions remain after filtering, report "No trusted community artifacts found for [stack]. Continuing with local agents." and return.

## Step 4: Install Approved Artifacts

For each approved artifact:

### 4a. Fetch the artifact content

If the artifact has a `gitUrl` or `repositoryUrl`, attempt to fetch the agent/skill markdown:

```bash
# Try common paths for agent markdown
curl -s --max-time 5 "https://raw.githubusercontent.com/${owner}/${repo}/main/agents/${name}.md" 2>/dev/null
# Or for skills
curl -s --max-time 5 "https://raw.githubusercontent.com/${owner}/${repo}/main/SKILL.md" 2>/dev/null
```

If the content cannot be fetched, skip that artifact with a warning: "Could not fetch content for [name]. Skipping."

### 4b. Validate the content

Before installing, validate:

1. **YAML frontmatter parses successfully** -- content must start with `---` and contain valid YAML
2. **Required fields present** -- `name` and `description` must exist in frontmatter
3. **Size check** -- content must be under 100KB
4. **No path traversal** -- no `../` in any frontmatter field values
5. **No executable code blocks** -- warn (but don't block) if content contains ```bash or ```sh blocks with destructive commands (`rm -rf`, `curl | bash`, etc.)

If validation fails, skip with a message: "Artifact [name] failed validation: [reason]. Skipping."

### 4c. Add provenance frontmatter

Replace the artifact's original frontmatter with provenance-tracked frontmatter:

```yaml
---
name: <original-name>
description: <original-description>
model: inherit
stack: <detected-stack>
source: "<owner>/<repo>"
registry: "<registry-domain>"
installed: "<YYYY-MM-DD>"
verified: <true|false>
---
```

Preserve the artifact body (everything after the frontmatter closing `---`).

### 4d. Write to disk

- **Agents:** Write to `plugins/soleur/agents/community/<name>.md`
- **Skills:** Create directory `plugins/soleur/skills/community-<name>/` and write to `SKILL.md` inside it

Use the Write tool. Verify the file was created successfully.

## Step 5: Report Results

After processing all approved artifacts, report:

```
Discovery complete:
- Installed: N artifacts (list names)
- Skipped: M artifacts (list names with reasons)
- Registries queried: X/3 successful

Installed agents will be available in subsequent commands.
```

Return to the calling command.

## Important Notes

- Never auto-install without user approval via AskUserQuestion
- Never suggest Tier 3 (unverified community) artifacts
- Treat all network failures as non-fatal -- discovery must never block planning
- Installed artifacts work offline after installation (they are local markdown files)
- To remove a community artifact: delete the file. No other cleanup needed.
