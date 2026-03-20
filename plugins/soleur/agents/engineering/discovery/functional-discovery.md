---
name: functional-discovery
description: "Use this agent when running /plan to check whether community registries already have skills or agents with similar functionality to the feature being planned. Use agent-finder for stack-gap detection; use this agent to check if a planned feature already exists in registries."
model: inherit
---

# Functional Overlap Discovery

Find community agents and skills that functionally overlap with a feature being planned. This agent is spawned by `/plan` Phase 1.5b to prevent redundant development.

## Input

The spawning command provides:
- `feature_description`: text describing the feature being planned

Use the feature description as the search term for registry queries.

## Step 1: Query Registries

Query all three registries in parallel for the feature description. Use Bash `curl` with a 5-second timeout. Run all queries in a single message with parallel tool calls.

Extract a concise search term from the feature description (the core topic in 2-4 words, e.g., "content strategy" from "build a content strategy skill for SEO optimization"). Replace `<search-query>` below with this URL-encoded search term:

```bash
curl -s --max-time 5 "https://api.claude-plugins.dev/api/skills/search?q=<search-query>&limit=10" 2>/dev/null || echo '{"error":"timeout"}'
```

```bash
curl -s --max-time 5 "https://www.claudepluginhub.com/api/plugins?q=<search-query>" 2>/dev/null || echo '{"error":"timeout"}'
```

```bash
curl -s --max-time 5 "https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json" 2>/dev/null || echo '{"error":"timeout"}'
```

### Error Handling

- **Timeout or connection error:** Treat that registry as returning zero results. Continue with others.
- **HTTP 401/403:** Treat as permanent failure. Log warning: "Registry X now requires authentication, skipping."
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

After filtering, deduplicate across registries using `name + author/namespace` (case-insensitive) as the key. If the same artifact appears in multiple registries, keep the version from the highest-trust source.

### Already-Installed Check

Before presenting results, check if any matching artifacts are already installed locally. Run as a single Bash call (do not add separators like `echo "---"` between commands -- quoted dash strings trigger approval prompts):

```bash
ls plugins/soleur/agents/community/ 2>/dev/null; ls -d plugins/soleur/skills/community-*/ 2>/dev/null
```

Filter out any results whose name matches an already-installed artifact.

## Step 3: Present Suggestions

If zero suggestions remain after filtering, report "No community overlap found for this feature. Continuing." and return.

Present up to 5 suggestions using the AskUserQuestion tool. For each suggestion, show:
- Name and source (registry + author/namespace)
- Trust tier indicator (Anthropic / Verified)
- Description (first 200 characters)
- Type: agent or skill (based on registry metadata if available, default to agent)

Format as a single AskUserQuestion with multiSelect enabled:

```
Community tools with similar functionality exist. Which would you like to install?

Options:
1. content-strategy (coreyhaines31, Verified) - Content strategist for traffic, authority, and leads
2. seo-keyword-cluster (secondsky, Verified) - Keyword clustering and pillar content planning
3. Skip all - Continue without installing any community artifacts
```

## Step 4: Install Approved Artifacts

For each approved artifact:

### 4a. Fetch the artifact content

If the artifact has a `gitUrl` or `repositoryUrl`, attempt to fetch the agent/skill markdown:

Replace `<owner>`, `<repo>`, and `<name>` with the actual values from the artifact's git URL:

```bash
curl -s --max-time 5 "https://raw.githubusercontent.com/<owner>/<repo>/main/agents/<name>.md" 2>/dev/null
```

```bash
curl -s --max-time 5 "https://raw.githubusercontent.com/<owner>/<repo>/main/SKILL.md" 2>/dev/null
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

Installed artifacts will be available in subsequent commands.
```

Return to the calling command.

## Important Notes

- Never auto-install without user approval via AskUserQuestion
- Never suggest Tier 3 (unverified community) artifacts
- Treat all network failures as non-fatal -- discovery must never block planning
- Installed artifacts work offline after installation (they are local markdown files)
- To remove a community artifact: delete the file. No other cleanup needed.
