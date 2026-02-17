---
name: soleur:sync
description: Analyze codebase and populate knowledge-base with conventions, patterns, and technical debt
argument-hint: "[area: conventions|architecture|testing|debt|overview|all]"
---

# Sync Codebase to Knowledge Base

Analyze an existing codebase and populate knowledge-base files with coding conventions, architecture decisions, testing practices, and technical debt markers.

**Use this command when:**

- Adopting Soleur on an existing project (initial bootstrap)
- Periodically updating knowledge-base as codebase evolves (maintenance)

## Input

<sync_area> #$ARGUMENTS </sync_area>

**Valid areas:** `conventions`, `architecture`, `testing`, `debt`, `overview`, `all` (default)

## Execution Flow

### Phase 0: Setup

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

Read `CLAUDE.md` if it exists - apply project conventions during sync analysis.

**Validate knowledge-base directory exists:**

```bash
if [[ ! -d "knowledge-base" ]]; then
  mkdir -p knowledge-base/{learnings,brainstorms,specs,plans,overview/components}
  echo "Created knowledge-base/ directory structure"
fi
```

If `knowledge-base/` does not exist, create it with standard subdirectories.

**Validate git repository:**

```bash
if [[ ! -d ".git" ]]; then
  echo "Warning: Not a git repository. Some analysis features may be limited."
fi
```

Warn but continue if not a git repo.

### Phase 1: Analyze

Based on the area specified (or `all` if none):

**1.1 Parse Area Filter**

If `<sync_area>` is empty or `all`, analyze all areas. Otherwise, analyze only the specified area.

**1.2 Codebase Analysis**

For each selected area, analyze the codebase:

#### Conventions Analysis

Look for coding conventions by examining:

- **Naming patterns**: Variable naming (camelCase, snake_case), file naming, class naming
- **Code style**: Indentation, bracket style, import ordering
- **Linting config**: `.eslintrc`, `.rubocop.yml`, `pyproject.toml`, etc.
- **Common patterns**: Guard clauses, early returns, error handling style

Extract as constitution.md rules in Always/Never/Prefer format.

#### Architecture Analysis

Look for architecture patterns by examining:

- **Directory structure**: Layer organization (models, services, controllers)
- **Module boundaries**: How code is organized into modules/packages
- **Dependency patterns**: Import relationships, service dependencies
- **Design patterns**: Repository pattern, service objects, etc.

Extract as learnings in `learnings/architecture/` with YAML frontmatter.

#### Testing Analysis

Look for testing practices by examining:

- **Test file patterns**: Where tests live, naming conventions
- **Test frameworks**: What testing tools are used
- **Fixture/factory patterns**: How test data is managed
- **Coverage config**: What coverage tools and thresholds are configured

Extract as constitution.md rules (Testing section).

#### Technical Debt Analysis

Look for technical debt by examining:

- **TODO/FIXME comments**: Grep for TODO, FIXME, HACK, XXX
- **Complexity hotspots**: Large files, deeply nested code
- **Outdated dependencies**: Package versions, deprecation warnings
- **Code smells**: Duplicate code patterns, long methods

Extract as learnings in `learnings/technical-debt/` with severity tags.

#### Overview Analysis

Generate or update project overview documentation by examining:

- **Project structure**: Top-level directories, entry points, main components
- **Component boundaries**: Logical groupings of related code (not just directories)
- **Data flow**: How information moves between components
- **Dependencies**: Internal and external dependencies per component

**Component Detection Heuristics:**

1. Top-level directories under primary source path (e.g., `src/`, `plugins/`, `lib/`)
2. Directories containing index files or multiple related modules
3. Exclude: `tests/`, `dist/`, `node_modules/`, generated code

**Output:**

- `knowledge-base/overview/README.md` - Project purpose, architecture diagram, component index
- `knowledge-base/overview/components/<name>.md` - One file per detected component

**Component Template:** Use the template from the `spec-templates` skill.

**Update Behavior:**

- **New components**: Create new `.md` file from template
- **Existing components**: Check if `updated` date is current; if not, offer to refresh
- **Removed components**: Add `status: deprecated` to frontmatter (do not delete)

**1.3 Assign Confidence Scores**

For each finding, assign confidence:

- **high**: Clear, explicit pattern (linting rule, documented convention)
- **medium**: Consistent but implicit pattern (80%+ of files follow it)
- **low**: Possible pattern (some evidence but not conclusive)

**1.4 Limit Findings**

Present only the top 20 findings by confidence. If more exist, inform user: "Found N findings. Showing top 20 by confidence. Run `/sync` again to discover more."

### Phase 2: Review

**2.1 Load Existing Entries**

Before reviewing findings, load existing knowledge-base content for deduplication:

- **Constitution rules:** Parse `knowledge-base/overview/constitution.md` and extract all bullet points under Always/Never/Prefer sections
- **Learnings:** List files in `knowledge-base/learnings/` and extract titles from YAML frontmatter or first heading

Store as a list of existing entry texts for comparison.

**2.2 Check for Duplicates (Exact and Fuzzy)**

For each finding, check for duplicates:

**Exact match check:**

- For constitution.md: Check if exact rule text exists in target section
- For learnings/: Check if file with same title exists
- If exact duplicate found, skip silently. Track count for summary.

**Fuzzy match check (Jaccard similarity):**

Compute word-based Jaccard similarity between the finding and all existing entries:

```text
Jaccard(a, b) = |intersection(words_a, words_b)| / |union(words_a, words_b)|

Where:
- words_a = lowercase words from text a (split by whitespace)
- words_b = lowercase words from text b (split by whitespace)
```

Find the existing entry with highest similarity score.

**If max similarity > 0.8:**

Use **AskUserQuestion** to prompt user:

```text
## Similar Entry Found

**New finding:**
[finding text]

**Similar to existing:**
[existing entry text]

**Similarity:** [score as percentage]%
```

**Options:**

1. **Skip** - Don't add this finding (likely a duplicate)
2. **Keep** - Proceed to review this finding anyway

If user selects **Skip**, continue to next finding. If user selects **Keep**, proceed to normal Accept/Skip/Edit review.

**2.3 Sequential Review** (for findings that pass deduplication checks)

Present remaining findings one at a time using the **AskUserQuestion tool**:

**Format:**

```text
## Sync Review (1/N)

**Finding:** [type] [description]
**Target:** [constitution.md > Section > Subsection] or [learnings/category/filename.md]
**Confidence:** [high/medium/low]
```

**Options:**

1. **Accept** - Add this to knowledge-base
2. **Skip** - Don't add this finding
3. **Edit** - Modify the finding before accepting

**If user selects Edit:**

Use AskUserQuestion with a text input option to let user modify the finding text. Then present the modified version for final approval.

**Continue until all findings reviewed or user selects "Done reviewing".**

### Phase 3: Write

**3.1 Write Constitution Entries**

For accepted constitution findings:

1. Read current `knowledge-base/overview/constitution.md`
2. Find the target section (Code Style, Architecture, Testing, etc.)
3. Find the subsection (Always, Never, Prefer)
4. Append the new rule as a bullet point: `- [Rule text]`
5. Write updated file

**Format:**

```markdown
## Code Style

### Prefer

- Prefer early returns over nested conditionals
- [NEW] Prefer snake_case for local variables
```

**3.2 Write Learnings Entries**

For accepted learnings findings:

1. Create new file in appropriate category: `learnings/[category]/[kebab-case-title].md`
2. Use compound-docs YAML schema with `problem_type: best_practice`

**Template:**

```yaml
---
module: [Extracted module name or "General"]
date: [TODAY]
problem_type: best_practice
component: [Mapped component type]
tags: [relevant, tags]
severity: [info|low|medium|high]
---

# [Finding Title]

## Context

[Why this pattern exists or was chosen]

## Pattern

[Description of the pattern or convention]

## Examples

[Code examples if applicable]
```

**3.3 Generate Summary**

After writing, display summary:

```text
## Sync Complete

**Created:** N new entries
**Skipped:** M exact duplicates (already in knowledge-base)
**Fuzzy duplicates:** F similar entries (user chose to skip)
**User skipped:** P findings (during review)

### New Constitution Rules
- [Rule 1] (Code Style > Prefer)
- [Rule 2] (Testing > Always)

### New Learnings
- learnings/architecture/service-layer-pattern.md
- learnings/technical-debt/legacy-api-endpoints.md

Run `/sync` again to discover additional patterns.
```

### Phase 4: Definition Sync

Scan accumulated learnings against skill, agent, and command definitions. Propose one-line bullet edits to route institutional knowledge to the definitions that need it. This complements the per-session routing in compound-docs Step 8 by catching cross-cutting learnings, retroactive learnings, and learnings from sessions where the relevant definition was not directly invoked.

**4.1 Gate**

Skip Phase 4 with an info message if any of these conditions are true:

- Area is a specific scope (`conventions`, `architecture`, `testing`, `debt`, `overview`) -- Phase 4 only runs when area is `all` or unspecified
- `knowledge-base/learnings/` directory does not exist
- `plugins/soleur/` directory does not exist

**4.2 Load**

List all learning files from `knowledge-base/learnings/` recursively, excluding `archive/` and `patterns/` directories. For each learning, extract:

- Title (from first `#` heading)
- Tags or metadata (from YAML frontmatter, ad-hoc tags sections, or title keywords -- any format)
- `synced_to` array from YAML frontmatter (treat as empty if absent)

List all definitions by name:

- Skills: `plugins/soleur/skills/*/SKILL.md` (flat, one level)
- Agents: `plugins/soleur/agents/**/*.md` (recursive)
- Commands: `plugins/soleur/commands/soleur/*.md` (flat)

**4.3 Match**

For each learning, determine which definitions it is relevant to. Skip pairs where the definition name is already in the learning's `synced_to` array.

For each relevant pair, read the full learning content and the full definition content. Draft a one-line bullet capturing the sharp-edge gotcha -- non-obvious insight only, skip if the point is general knowledge. Check the definition does not already contain a bullet covering this topic -- if it does, discard silently.

**4.4 Review**

Present proposals one at a time using **AskUserQuestion** with options:

```text
## Definition Sync (1/N)

**Learning:** [learning-title]
**Definition:** [definition-name] ([skill|agent|command])
**Section:** [target-section-name]
**Proposed bullet:** "- [one-line bullet text]"
```

**Options:**

1. **Accept** - Write the bullet to the definition file and add the definition name to the learning's `synced_to` frontmatter. If the learning has no YAML frontmatter block, prepend a minimal `---` block with only `synced_to: [definition-name]`.
2. **Skip** - Move to next proposal. No tracking written (proposal may reappear on next run).
3. **Edit** - Modify the bullet text, then re-display for final Accept/Skip.
4. **Done reviewing** - Stop Phase 4. Unreviewed proposals reappear on next `/sync` run.

**4.5 Summary**

```text
## Definition Sync Complete

- Learnings scanned: N
- Proposals generated: P
- Accepted: A
- Skipped: S
- Not reviewed: U (will reappear next run)

### Definitions Updated
- [definition-name]: +N bullets
```

If zero proposals were generated: "Phase 4: All learnings already synced to relevant definitions (N learnings, M definitions scanned)."

## Output Locations

| Finding Type | Destination |
| ------------ | ----------- |
| Coding conventions | `knowledge-base/overview/constitution.md` |
| Architecture decisions | `knowledge-base/learnings/architecture/` |
| Testing practices | `knowledge-base/overview/constitution.md` (Testing section) |
| Technical debt | `knowledge-base/learnings/technical-debt/` |
| Project overview | `knowledge-base/overview/README.md` |
| Component docs | `knowledge-base/overview/components/` |
| Definition sync bullets | `plugins/soleur/{skills,agents,commands}/*.md` |

## Design Decisions

### Single Command, No Separate Agents

Analysis happens inline in this command rather than spawning separate agents. This keeps the implementation simple and debuggable.

### Sequential Review

Each finding is reviewed one at a time with y/n/edit options. This is familiar UX with no custom query syntax to learn.

### Two-Stage Deduplication

**Stage 1 (Exact match):** If an identical entry exists, skip silently.

**Stage 2 (Fuzzy match):** If a similar entry exists (Jaccard similarity > 0.8), prompt user to skip or keep. Word-based Jaccard coefficient catches textual variations like "use const" vs "always use const" without external dependencies.

### Existing Learnings Schema

Uses the `compound-docs` YAML schema with `problem_type: best_practice` for non-problem learnings. This ensures compatibility with existing learnings tooling.

## Examples

**Bootstrap entire knowledge-base:**

```bash
/sync all
# or just
/sync
```

**Sync only coding conventions:**

```bash
/sync conventions
```

**Sync only technical debt:**

```bash
/sync debt
```

**Sync project overview:**

```bash
/sync overview
```

## Limitations

- No PR analysis (requires GitHub token - deferred)
- No semantic similarity (word-based Jaccard only - embeddings deferred)
- No sampling for large codebases (analyze what fits)
- No parallel agent execution (single-pass analysis)
- No constitution cross-check (deferred - separate concern)
- Definition sync skips when area is scoped (only runs on `all` or default)

Run `/sync` multiple times to discover more patterns as the codebase evolves.
