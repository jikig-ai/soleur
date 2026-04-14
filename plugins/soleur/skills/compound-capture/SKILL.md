---
name: compound-capture
description: "This skill should be used when capturing solved problems as categorized documentation with YAML frontmatter for fast lookup. It auto-documents solutions after confirmation and builds searchable institutional knowledge."
allowed-tools:
  - Read # Parse conversation context
  - Write # Create resolution docs
  - Bash # Create directories
  - Grep # Search existing docs
preconditions:
  - Problem has been solved (not in-progress)
  - Solution has been verified working
---

# compound-capture Skill

**Purpose:** Automatically document solved problems to build searchable institutional knowledge with category-based organization (enum-validated problem types).

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`. Strip `--headless` from `$ARGUMENTS` before processing remaining args. Headless mode affects Steps 2, 3, 5, 8, and auto-consolidation Step E.

## Overview

This skill captures problem solutions immediately after confirmation, creating structured documentation that serves as a searchable knowledge base for future sessions.

**Organization:** Single-file architecture - each problem documented as one markdown file in its symptom category directory (e.g., `knowledge-base/project/learnings/performance-issues/n-plus-one-briefs.md`). Files use YAML frontmatter for metadata and searchability.

---

<critical_sequence name="documentation-capture" enforce_order="strict">

## Documentation Capture Process

<step number="1" required="true">
### Step 1: Detect Confirmation

**Auto-invoke after phrases:**

- "that worked"
- "it's fixed"
- "working now"
- "problem solved"
- "that did it"

**OR manual:** `/doc-fix` command

**Non-trivial problems only:**

- Multiple investigation attempts needed
- Tricky debugging that took time
- Non-obvious solution
- Future sessions would benefit

**Skip documentation for:**

- Simple typos
- Obvious syntax errors
- Trivial fixes immediately corrected
</step>

<step number="2" required="true" depends_on="1">
### Step 2: Gather Context

Extract from conversation history:

**Check for session-state.md:** Run `git branch --show-current`. If on a `feat-*` branch, check if `knowledge-base/project/specs/feat-<name>/session-state.md` exists. If it does, read it and incorporate forwarded errors from `### Errors` and decisions from `### Decisions` into the context below. These came from preceding pipeline phases whose context was compacted.

**Required information:**

- **Module name**: Which module or component had the problem
- **Symptom**: Observable error/behavior (exact error messages)
- **Investigation attempts**: What didn't work and why
- **Root cause**: Technical explanation of actual problem
- **Solution**: What fixed it (code/config changes)
- **Prevention**: How to avoid in future

**Session errors (beyond the target problem):**

Scan conversation history AND session-state.md (if present) for errors unrelated to the main problem investigation documented above. Only capture errors that are NOT part of the investigation attempts. Skip trivial errors immediately corrected (typos in commands, expected test failures during TDD).

Extract for each error found:

- Describe what went wrong (1 sentence)
- Note what was done to recover
- Suggest how to prevent it in future sessions (1 sentence)

If no session errors are found, output "Session errors: none detected" (do not skip silently — the explicit acknowledgment prevents the model from accidentally dropping errors by judging the session as clean).

**Environment details:**

- Rails version
- Stage (0-6 or post-implementation)
- OS version
- File/line references

**BLOCKING REQUIREMENT:** If critical context is missing (module name, exact error, stage, or resolution steps):

**Headless mode:** Infer missing fields from session context (conversation history, session-state.md, git log). Skip any field that cannot be reasonably inferred — do not prompt. Proceed to Step 3 with whatever context is available.

**Interactive mode:** Ask user and WAIT for response before proceeding to Step 3:

```
I need a few details to document this properly:

1. Which module had this issue? [ModuleName]
2. What was the exact error message or symptom?
3. What stage were you in? (0-6 or post-implementation)

[Continue after user provides details]
```

</step>

<step number="3" required="false" depends_on="2">
### Step 3: Check Existing Docs

Search knowledge-base/project/learnings/ for similar issues. **Prefer faceted search** when the current learning carries a specific `tags:` or `category:` value — facet filters cut noise before grep runs and keep related-doc lookups focused:

```bash
# Faceted (preferred when the learning has a tag or category)
/kb-search --tag eager-loading
/kb-search --category performance-issues n+1
```

Fall back to raw grep when no facet fits or the facet artifact is missing:

```bash
# Keyword grep (fallback)
grep -r "exact error phrase" knowledge-base/project/learnings/

# Symptom category browse
ls knowledge-base/project/learnings/[category]/
```

Valid tag/category values are listed in `knowledge-base/kb-tags.txt` and `knowledge-base/kb-categories.txt` (regenerated by `scripts/generate-kb-index.sh`).

**IF similar issue found:**

**Headless mode:** Auto-select "Create new doc with cross-reference" without prompting.

**Interactive mode:** Present decision options:

```
Found similar issue: knowledge-base/project/learnings/[path]

What's next?
1. Create new doc with cross-reference (recommended)
2. Update existing doc (only if same root cause)
3. Other

Choose (1-3): _
```

WAIT for user response, then execute chosen action.

**ELSE** (no similar issue found):

Proceed directly to Step 4 (no user interaction needed).
</step>

<step number="4" required="true" depends_on="2">
### Step 4: Generate Filename

Format: `[sanitized-symptom]-[module]-[YYYYMMDD].md`

**Sanitization rules:**

- Lowercase
- Replace spaces with hyphens
- Remove special characters except hyphens
- Truncate to reasonable length (< 80 chars)

**Examples:**

- `missing-include-BriefSystem-20251110.md`
- `parameter-not-saving-state-EmailProcessing-20251110.md`
- `webview-crash-on-resize-Assistant-20251110.md`
</step>

<step number="5" required="true" depends_on="4" blocking="true">
### Step 5: Validate YAML Schema

**CRITICAL:** All docs require validated YAML frontmatter with enum validation.

<validation_gate name="yaml-schema" blocking="true">

**Validate against schema:**
Load `schema.yaml` and classify the problem against the enum values defined in [yaml-schema.md](./references/yaml-schema.md). Ensure all required fields are present and match allowed values exactly.

**BLOCK if validation fails:**

```
❌ YAML validation failed

Errors:
- problem_type: must be one of schema enums, got "compilation_error"
- severity: must be one of [critical, high, medium, low], got "invalid"
- symptoms: must be array with 1-5 items, got string

Please provide corrected values.
```

**GATE ENFORCEMENT:** Do NOT proceed to Step 6 (Create Documentation) until YAML frontmatter passes all validation rules defined in `schema.yaml`.

**Headless mode exception:** If `HEADLESS_MODE=true` and YAML validation fails after auto-correction attempts, skip the problematic learning and continue with remaining work. Log the skipped learning for manual review.

</validation_gate>
</step>

<step number="6" required="true" depends_on="5">
### Step 6: Create Documentation

**Determine category from problem_type:** Use the category mapping defined in [yaml-schema.md](./references/yaml-schema.md) (lines 49-61).

**Create documentation file:**

Determine the category from the validated YAML `problem_type` field and generate a filename. Then:

1. Create the category directory: `mkdir -p knowledge-base/project/learnings/<category>`
2. Write the documentation file to `knowledge-base/project/learnings/<category>/<filename>.md` using the template from [resolution-template.md](./assets/resolution-template.md)

Replace `<category>` with the mapped category and `<filename>` with the generated filename.

**Result:**

- Single file in category directory
- Enum validation ensures consistent categorization

**Create documentation:** Populate the structure from [resolution-template.md](./assets/resolution-template.md) with context gathered in Step 2 and validated YAML frontmatter from Step 5.
</step>

<step number="7" required="false" depends_on="6">
### Step 7: Cross-Reference & Critical Pattern Detection

If similar issues found in Step 3:

**Update existing doc:**

Append a "See also" cross-reference link to the similar document, using the new document's filename and path.

**Update new doc:**
Already includes cross-reference from Step 6.

**Update patterns if applicable:**

If this represents a common pattern (3+ similar issues):

```bash
# Add to knowledge-base/project/learnings/patterns/common-solutions.md
cat >> knowledge-base/project/learnings/patterns/common-solutions.md << 'EOF'

## [Pattern Name]

**Common symptom:** [Description]
**Root cause:** [Technical explanation]
**Solution pattern:** [General approach]

**Examples:**
- [Link to doc 1]
- [Link to doc 2]
- [Link to doc 3]
EOF
```

**Critical Pattern Detection (Optional Proactive Suggestion):**

If this issue has automatic indicators suggesting it might be critical:

- Severity: `critical` in YAML
- Affects multiple modules OR foundational stage (Stage 2 or 3)
- Non-obvious solution

Then in the decision menu, add a note:

```
💡 This might be worth adding to Required Reading (Option 2)
```

But **NEVER auto-promote**. User decides via decision menu (Option 2).

**Template for critical pattern addition:**

When user selects Option 3 (Add to Required Reading), use the template from [critical-pattern-template.md](./assets/critical-pattern-template.md) to structure the pattern entry. Number it sequentially based on existing patterns in `knowledge-base/project/learnings/patterns/critical-patterns.md`.
</step>

<step number="8" required="false" depends_on="6">
### Step 8: Route Learning to Definition

After capturing and cross-referencing the learning, route the insight to the skill, agent, or command definition that needs it. This ensures definitions improve over time with sharp-edge gotchas that prevent repeated mistakes.

**Skip this step if:**

- `plugins/soleur/` directory does not exist
- No skills, agents, or commands were invoked in this session

<!-- markdownlint-disable-next-line MD001 -- h4 under h3 is correct; linter resets at <step> tags -->
#### 8.1 Detect Active Components

Identify which skills, agents, or commands were invoked in this session by examining the conversation history.

Map detected component names to file paths:

- Skill `foo` -> `plugins/soleur/skills/foo/SKILL.md`
- Agent `soleur:engineering:review:baz` -> `plugins/soleur/agents/engineering/review/baz.md`
- Command `soleur:bar` -> `plugins/soleur/commands/bar.md`

If no components detected, skip to the decision menu.

#### 8.2 Select Target

If one component detected: propose it as the routing target.

If multiple detected: use **AskUserQuestion** to present a numbered list ordered by relevance to the learning content. Include an option to skip.

**Headless mode:** If `HEADLESS_MODE=true` and multiple components detected, select the component most relevant to the learning content using LLM judgment. If one component detected, use it. Do not prompt.

If the target file does not exist at the expected path, warn and skip.

#### 8.3 Propose Edit

Route **two categories** of insights to each target:

**A. Solution insight** (the main learning):

1. Read the target definition file
2. Find the most relevant existing section for a new bullet -- do not create new sections
3. If no section with bullets exists in the target file, warn and skip this target
4. Draft a one-line bullet capturing the sharp edge -- non-obvious gotcha only, skip if the insight is general knowledge the model already knows
5. Display the proposed edit showing the section name, existing bullets, and the new bullet

**B. Error prevention** (from session errors):

1. Check the learning file's `## Session Errors` section. For each error with a `**Prevention:**` line, determine if the error could have been prevented by a skill instruction in the target definition.
2. If yes, draft a one-line bullet for the target's Sharp Edges or equivalent section (e.g., "Verify relative paths by tracing each `../` step before prescribing them in plans.").
3. If the target has no section suitable for preventive bullets, skip.
4. Display the proposed edit alongside the solution edit.

This dual-routing ensures session errors feed back into the definitions that caused them, not just the learning archive.

#### 8.4 Confirm

**Headless mode:** If `HEADLESS_MODE=true`, do not apply the edit directly. Instead, create a GitHub issue to track the proposed edit. Write the issue body to a temporary file, then create the issue:

1. Write the body to `/tmp/compound-rtd-body.md` containing: the proposed edit text (as a fenced code block), the target file path, and the source learning file path
2. Run: `gh issue create --title "compound: route-to-definition proposal for <target-basename>" --body-file /tmp/compound-rtd-body.md --milestone "Post-MVP / Later"`
3. If `gh issue create` fails (network error, auth failure), log the error and continue to the decision menu -- do not block the pipeline on issue creation failure
4. If successful, log the created issue URL
5. Update the learning file's `synced_to` frontmatter with the bare `<definition-name>` (same format as interactive mode) to prevent `/soleur:sync` from re-proposing this pair
6. Proceed to the decision menu

**Interactive mode:** Use **AskUserQuestion** with options:

- **Accept** -- Apply the edit to the definition file
- **Skip** -- Do not modify the definition; the learning is still captured in knowledge-base/project/learnings/
- **Edit** -- Modify the bullet text, then re-display for confirmation

If accepted, write the edit to the definition file. Then update the learning file's `synced_to` frontmatter to prevent `/soleur:sync` from re-proposing this pair:

- If `synced_to` array exists in frontmatter: append the definition name
- If frontmatter exists but `synced_to` is absent: add `synced_to: [definition-name]`
- If no YAML frontmatter block exists: prepend a minimal `---` block with only `synced_to: [definition-name]`

Do NOT commit -- the edits are staged for the normal workflow completion protocol.
</step>

</critical_sequence>

---

## Automatic Consolidation (feature branches)

After documentation is complete and before the decision menu, automatically consolidate and archive KB artifacts on feature branches. This replaces the former manual Option 2 in the decision menu.

**Branch detection:**

Run `git branch --show-current` to get the current branch. If it does not start with `feat-`, `feat/`, `fix-`, or `fix/`, skip consolidation entirely.

**If on a feature branch (`feat-*`, `feat/*`, `fix-*`, or `fix/*`), run the following steps automatically:**

### Auto-Consolidation Step A: Artifact Discovery

Extract the slug from the current branch name by stripping the branch type prefix. Handle all prefix variants:

- `feat/` -- strip prefix (e.g., `feat/domain-leaders` becomes `domain-leaders`)
- `feat-` -- strip prefix (e.g., `feat-domain-leaders` becomes `domain-leaders`)
- `fix/` -- strip prefix (e.g., `fix/typo` becomes `typo`)
- `fix-` -- strip prefix (e.g., `fix-typo` becomes `typo`)

Glob for related artifacts:

Search for artifacts matching the feature slug. Replace `<slug>` with the actual feature slug derived from the branch name:

```bash
find knowledge-base/project/brainstorms/ -name "*<slug>*" -not -path "*/archive/*" 2>/dev/null
find knowledge-base/project/plans/ -name "*<slug>*" -not -path "*/archive/*" 2>/dev/null
test -d "knowledge-base/project/specs/feat-<slug>" && echo "knowledge-base/project/specs/feat-<slug>/"
```

**If no artifacts found:** Skip consolidation silently and proceed to the decision menu.

**If artifacts found:** Present the discovered list:

```text
Found artifacts for feat-<slug>:

1. knowledge-base/project/brainstorms/2026-02-09-<slug>-brainstorm.md
2. knowledge-base/project/plans/2026-02-09-feat-<slug>-plan.md
3. knowledge-base/project/specs/feat-<slug>/

Proceed with consolidation? (Y/n/add more)
```

Replace `<slug>` with the actual feature slug throughout.

If user selects "add more," prompt for additional file paths and append to the list.

### Auto-Consolidation Step B: Knowledge Extraction

A single agent reads ALL discovered artifacts and proposes updates to:

- `knowledge-base/project/constitution.md` -- new Always/Never/Prefer rules under the appropriate domain
- `knowledge-base/project/components/*.md` -- new component documentation entries
- `knowledge-base/project/README.md` -- architectural insights or pattern notes

The agent produces proposals as structured markdown blocks. Each proposal specifies:

- **Target file**: Which project file to update
- **Section**: Where in the file to insert (e.g., "Architecture > Always")
- **Content**: The exact text to add

### Auto-Consolidation Step C: Approval Flow

Present proposals one at a time:

```text
Proposal 1 of N:

Target: knowledge-base/project/constitution.md
Section: Architecture > Always
Content:
- Archive completed feature artifacts after consolidation to prevent knowledge-base bloat

Accept / Skip / Edit? _
```

**Accept:** Apply the proposal immediately (see Step D).

**Skip:** Move to the next proposal. The skipped content is not applied.

**Edit:** User provides corrected text. Re-display the edited proposal for Accept/Skip.

**Idempotency check:** Before applying, perform a simple substring check against the target file. If similar content already exists, flag it:

```text
Similar content found in constitution.md:
  "Archive outdated learnings to knowledge-base/project/learnings/archive/"

Still apply this proposal? (Y/n)
```

### Auto-Consolidation Step D: Apply Accepted Proposals

Apply each accepted proposal immediately after approval:

- **Constitution updates:** Append the rule to the correct domain/category section
- **Component doc updates:** Add new entries to the relevant component file
- **Overview README updates:** Add architectural notes to the appropriate section

### Auto-Consolidation Step E: Archival

Archive ALL discovered artifacts regardless of how many proposals were accepted or skipped.

Run the archival script from the repository root:

```bash
bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh
```

The script discovers artifacts matching the current branch's feature slug, creates archive directories, and moves each artifact with a timestamped prefix using `git mv`. It handles untracked files automatically. If the script exits non-zero, display the error and stop -- do not proceed to Step F.

**Context-aware archival confirmation:**

**Headless mode:** Auto-archive without prompting (equivalent to answering "Y").

**Interactive mode:**

If at least one proposal was accepted:

```text
Overview files updated. Archive the source artifacts? (Y/n)
```

If all proposals were skipped:

```text
No project updates applied. Still archive the source artifacts? (Y/n)
```

### Auto-Consolidation Step F: Commit

All changes (project edits + archival moves) go into a single commit:

```bash
git add -A knowledge-base/
git commit -m "compound: consolidate and archive feat-<slug> artifacts"
```

Replace `<slug>` with the actual feature slug.

This ensures `git revert` restores everything in one operation.

After commit, proceed to the decision menu.

---

<decision_gate name="post-documentation" wait_for_user="true">

## Decision Menu After Capture

**Headless mode:** If `HEADLESS_MODE=true`, auto-select "Continue workflow" without presenting the menu.

**Interactive mode:** After successful documentation, present options and WAIT for user response:

```
✓ Solution documented

File created:
- knowledge-base/project/learnings/[category]/[filename].md

What's next?
1. Continue workflow (recommended)
2. Add to Required Reading - Promote to critical patterns (critical-patterns.md)
3. Link related issues - Connect to similar problems
4. Add to existing skill - Add to a learning skill (e.g., hotwire-native)
5. Create new skill - Extract into new learning skill
6. View documentation - See what was captured
7. Other
```

**Note:** Consolidation and archival of KB artifacts now runs automatically before this menu on `feat-*` branches. See "Automatic Consolidation" section above.

**Handle responses:**

**Option 1: Continue workflow**

- Return to calling skill/workflow
- Documentation is complete

**Option 2: Add to Required Reading** ⭐ PRIMARY PATH FOR CRITICAL PATTERNS

User selects this when:

- System made this mistake multiple times across different modules
- Solution is non-obvious but must be followed every time
- Foundational requirement (Rails, Rails API, threading, etc.)

Action:

1. Extract pattern from the documentation
2. Format as ❌ WRONG vs ✅ CORRECT with code examples
3. Add to `knowledge-base/project/learnings/patterns/critical-patterns.md`
4. Add cross-reference back to this doc
5. Confirm: "✓ Added to Required Reading. All subagents will see this pattern before code generation."

**Option 3: Link related issues**

- Prompt: "Which doc to link? (provide filename or describe)"
- Search knowledge-base/project/learnings/ for the doc
- Add cross-reference to both docs
- Confirm: "✓ Cross-reference added"

**Option 4: Add to existing skill**

User selects this when the documented solution relates to an existing learning skill:

Action:

1. Prompt: "Which skill? (hotwire-native, etc.)"
2. Determine which reference file to update (resources.md, patterns.md, or examples.md)
3. Add link and brief description to appropriate section
4. Confirm: "✓ Added to [skill-name] skill in [file]"

Example: For Hotwire Native Tailwind variants solution:

- Add to `hotwire-native/references/resources.md` under "Project-Specific Resources"
- Add to `hotwire-native/references/examples.md` with link to solution doc

**Option 5: Create new skill**

User selects this when the solution represents the start of a new learning domain:

Action:

1. Prompt: "What should the new skill be called? (e.g., stripe-billing, email-processing)"
2. Run `python3 plugins/soleur/skills/skill-creator/scripts/init_skill.py [skill-name]`
3. Create initial reference files with this solution as first example
4. Confirm: "✓ Created new [skill-name] skill with this solution as first example"

**Option 6: View documentation**

- Display the created documentation
- Present decision menu again

**Option 7: Other**

- Ask what they'd like to do

</decision_gate>

---

<integration_protocol>

## Integration Points

**Invoked by:**

- /compound command (primary interface)
- Manual invocation in conversation after solution confirmed
- Can be triggered by detecting confirmation phrases like "that worked", "it's fixed", etc.

**Invokes:**

- None (terminal skill - does not delegate to other skills)

**Handoff expectations:**
All context needed for documentation should be present in conversation history before invocation.

</integration_protocol>

---

<success_criteria>

## Success Criteria

Documentation is successful when ALL of the following are true:

- ✅ YAML frontmatter validated (all required fields, correct formats)
- ✅ File created in knowledge-base/project/learnings/[category]/[filename].md
- ✅ Enum values match schema.yaml exactly
- ✅ Code examples included in solution section
- ✅ Cross-references added if related issues found
- ✅ User presented with decision menu and action confirmed

</success_criteria>

---

## Error Handling

**Missing context:**

- Ask user for missing details
- Don't proceed until critical info provided

**YAML validation failure:**

- Show specific errors
- Present retry with corrected values
- BLOCK until valid

**Similar issue ambiguity:**

- Present multiple matches
- Let user choose: new doc, update existing, or link as duplicate

**Module not in modules documentation:**

- Warn but don't block
- Proceed with documentation
- Suggest: "Add [Module] to modules documentation if not there"

---

## Execution Guidelines

**MUST do:**

- Validate YAML frontmatter (BLOCK if invalid per Step 5 validation gate)
- Extract exact error messages from conversation
- Include code examples in solution section
- Create directories before writing files (`mkdir -p`)
- Ask user and WAIT if critical context missing

**MUST NOT do:**

- Skip YAML validation (validation gate is blocking)
- Use vague descriptions (not searchable)
- Omit code examples or cross-references

---

## Quality Guidelines

**Good documentation has:**

- ✅ Exact error messages (copy-paste from output)
- ✅ Specific file:line references
- ✅ Observable symptoms (what you saw, not interpretations)
- ✅ Failed attempts documented (helps avoid wrong paths)
- ✅ Technical explanation (not just "what" but "why")
- ✅ Code examples (before/after if applicable)
- ✅ Prevention guidance (how to catch early)
- ✅ Cross-references (related issues)

**Avoid:**

- ❌ Vague descriptions ("something was wrong")
- ❌ Missing technical details ("fixed the code")
- ❌ No context (which version? which file?)
- ❌ Just code dumps (explain why it works)
- ❌ No prevention guidance
- ❌ No cross-references

---

## Example Scenario

**User:** "That worked! The N+1 query is fixed."

**Skill activates:**

1. **Detect confirmation:** "That worked!" triggers auto-invoke
2. **Gather context:**
   - Module: Brief System
   - Symptom: Brief generation taking >5 seconds, N+1 query when loading email threads
   - Failed attempts: Added pagination (didn't help), checked background job performance
   - Solution: Added eager loading with `includes(:emails)` on Brief model
   - Root cause: Missing eager loading causing separate database query per email thread
3. **Check existing:** No similar issue found
4. **Generate filename:** `n-plus-one-brief-generation-BriefSystem-20251110.md`
5. **Validate YAML:**

   ```yaml
   module: Brief System
   date: 2025-11-10
   problem_type: performance_issue
   component: rails_model
   symptoms:
     - "N+1 query when loading email threads"
     - "Brief generation taking >5 seconds"
   root_cause: missing_include
   severity: high
   tags: [n-plus-one, eager-loading, performance]
   ```

   ✅ Valid
6. **Create documentation:**
   - `knowledge-base/project/learnings/performance-issues/n-plus-one-brief-generation-BriefSystem-20251110.md`
7. **Cross-reference:** None needed (no similar issues)

**Output:**

```text
✓ Solution documented

File created:
- knowledge-base/project/learnings/performance-issues/n-plus-one-brief-generation-BriefSystem-20251110.md

What's next?
1. Continue workflow (recommended)
2. Add to Required Reading - Promote to critical patterns (critical-patterns.md)
3. Link related issues - Connect to similar problems
4. Add to existing skill - Add to a learning skill (e.g., hotwire-native)
5. Create new skill - Extract into new learning skill
6. View documentation - See what was captured
7. Other
```

---

## Future Enhancements

**Not in Phase 7 scope, but potential:**

- Search by date range
- Filter by severity
- Tag-based search interface
- Metrics (most common issues, resolution time)
- Export to shareable format (community knowledge sharing)
- Import community solutions
