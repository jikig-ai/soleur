---
name: compound-docs
description: This skill should be used when capturing solved problems as categorized documentation with YAML frontmatter for fast lookup. It auto-documents solutions after confirmation and builds searchable institutional knowledge. Triggers on "that worked", "it's fixed", "document this fix", "capture this solution", "problem solved", "/doc-fix".
allowed-tools:
  - Read # Parse conversation context
  - Write # Create resolution docs
  - Bash # Create directories
  - Grep # Search existing docs
preconditions:
  - Problem has been solved (not in-progress)
  - Solution has been verified working
---

# compound-docs Skill

**Purpose:** Automatically document solved problems to build searchable institutional knowledge with category-based organization (enum-validated problem types).

## Overview

This skill captures problem solutions immediately after confirmation, creating structured documentation that serves as a searchable knowledge base for future sessions.

**Organization:** Single-file architecture - each problem documented as one markdown file in its symptom category directory (e.g., `knowledge-base/learnings/performance-issues/n-plus-one-briefs.md`). Files use YAML frontmatter for metadata and searchability.

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

**Required information:**

- **Module name**: Which module or component had the problem
- **Symptom**: Observable error/behavior (exact error messages)
- **Investigation attempts**: What didn't work and why
- **Root cause**: Technical explanation of actual problem
- **Solution**: What fixed it (code/config changes)
- **Prevention**: How to avoid in future

**Session errors (beyond the target problem):**

Scan conversation history for errors unrelated to the main problem investigation documented above. Only capture errors that are NOT part of the investigation attempts. Skip trivial errors immediately corrected (typos in commands, expected test failures during TDD).

Extract for each error found:
- Describe what went wrong (1 sentence)
- Note what was done to recover
- Suggest how to prevent it in future sessions (1 sentence)

If no session errors are found, skip this extraction silently.

**Environment details:**

- Rails version
- Stage (0-6 or post-implementation)
- OS version
- File/line references

**BLOCKING REQUIREMENT:** If critical context is missing (module name, exact error, stage, or resolution steps), ask user and WAIT for response before proceeding to Step 3:

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

Search knowledge-base/learnings/ for similar issues:

```bash
# Search by error message keywords
grep -r "exact error phrase" knowledge-base/learnings/

# Search by symptom category
ls knowledge-base/learnings/[category]/
```

**IF similar issue found:**

THEN present decision options:

```
Found similar issue: knowledge-base/learnings/[path]

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

</validation_gate>
</step>

<step number="6" required="true" depends_on="5">
### Step 6: Create Documentation

**Determine category from problem_type:** Use the category mapping defined in [yaml-schema.md](./references/yaml-schema.md) (lines 49-61).

**Create documentation file:**

Determine the category from the validated YAML `problem_type` field and generate a filename. Then:

1. Create the category directory: `mkdir -p knowledge-base/learnings/<category>`
2. Write the documentation file to `knowledge-base/learnings/<category>/<filename>.md` using the template from [resolution-template.md](./assets/resolution-template.md)

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
# Add to knowledge-base/learnings/patterns/common-solutions.md
cat >> knowledge-base/learnings/patterns/common-solutions.md << 'EOF'

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

When user selects Option 3 (Add to Required Reading), use the template from [critical-pattern-template.md](./assets/critical-pattern-template.md) to structure the pattern entry. Number it sequentially based on existing patterns in `knowledge-base/learnings/patterns/critical-patterns.md`.
</step>

<step number="8" required="false" depends_on="6">
### Step 8: Route Learning to Definition

After capturing and cross-referencing the learning, route the insight to the skill, agent, or command definition that needs it. This ensures definitions improve over time with sharp-edge gotchas that prevent repeated mistakes.

**Skip this step if:**
- `plugins/soleur/` directory does not exist
- No skills, agents, or commands were invoked in this session

#### 8.1 Detect Active Components

Identify which skills, agents, or commands were invoked in this session by examining the conversation history.

Map detected component names to file paths:
- Skill `foo` -> `plugins/soleur/skills/foo/SKILL.md`
- Agent `soleur:engineering:review:baz` -> `plugins/soleur/agents/engineering/review/baz.md`
- Command `soleur:bar` -> `plugins/soleur/commands/soleur/bar.md`

If no components detected, skip to the decision menu.

#### 8.2 Select Target

If one component detected: propose it as the routing target.

If multiple detected: use **AskUserQuestion** to present a numbered list ordered by relevance to the learning content. Include an option to skip.

If the target file does not exist at the expected path, warn and skip.

#### 8.3 Propose Edit

1. Read the target definition file
2. Find the most relevant existing section for a new bullet -- do not create new sections
3. If no section with bullets exists in the target file, warn and skip this target
4. Draft a one-line bullet capturing the sharp edge -- non-obvious gotcha only, skip if the insight is general knowledge the model already knows
5. Display the proposed edit showing the section name, existing bullets, and the new bullet

#### 8.4 Confirm

Use **AskUserQuestion** with options:
- **Accept** -- Apply the edit to the definition file
- **Skip** -- Do not modify the definition; the learning is still captured in knowledge-base/learnings/
- **Edit** -- Modify the bullet text, then re-display for confirmation

If accepted, write the edit to the definition file. Then update the learning file's `synced_to` frontmatter to prevent `/soleur:sync` from re-proposing this pair:

- If `synced_to` array exists in frontmatter: append the definition name
- If frontmatter exists but `synced_to` is absent: add `synced_to: [definition-name]`
- If no YAML frontmatter block exists: prepend a minimal `---` block with only `synced_to: [definition-name]`

Do NOT commit or version-bump -- the edits are staged for the normal workflow completion protocol.
</step>

</critical_sequence>

---

## Automatic Consolidation (feat-* branches)

After documentation is complete and before the decision menu, automatically consolidate and archive KB artifacts on feature branches. This replaces the former manual Option 2 in the decision menu.

**Branch detection:**

Run `git branch --show-current` to get the current branch. If it does not start with `feat-`, skip consolidation entirely.

**If on a `feat-*` branch, run the following steps automatically:**

### Auto-Consolidation Step A: Artifact Discovery

Extract the slug from the current branch name:

```bash
slug="${current_branch#feat-}"
```

Glob for related artifacts:

Search for artifacts matching the feature slug. Replace `<slug>` with the actual feature slug derived from the branch name:

```bash
find knowledge-base/brainstorms/ -name "*<slug>*" -not -path "*/archive/*" 2>/dev/null
find knowledge-base/plans/ -name "*<slug>*" -not -path "*/archive/*" 2>/dev/null
test -d "knowledge-base/specs/feat-<slug>" && echo "knowledge-base/specs/feat-<slug>/"
```

**If no artifacts found:** Skip consolidation silently and proceed to the decision menu.

**If artifacts found:** Present the discovered list:

```text
Found artifacts for feat-<slug>:

1. knowledge-base/brainstorms/2026-02-09-<slug>-brainstorm.md
2. knowledge-base/plans/2026-02-09-feat-<slug>-plan.md
3. knowledge-base/specs/feat-<slug>/

Proceed with consolidation? (Y/n/add more)
```

Replace `<slug>` with the actual feature slug throughout.

If user selects "add more," prompt for additional file paths and append to the list.

### Auto-Consolidation Step B: Knowledge Extraction

A single agent reads ALL discovered artifacts and proposes updates to:

- `knowledge-base/overview/constitution.md` -- new Always/Never/Prefer rules under the appropriate domain
- `knowledge-base/overview/components/*.md` -- new component documentation entries
- `knowledge-base/overview/README.md` -- architectural insights or pattern notes

The agent produces proposals as structured markdown blocks. Each proposal specifies:

- **Target file**: Which overview file to update
- **Section**: Where in the file to insert (e.g., "Architecture > Always")
- **Content**: The exact text to add

### Auto-Consolidation Step C: Approval Flow

Present proposals one at a time:

```text
Proposal 1 of N:

Target: knowledge-base/overview/constitution.md
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
  "Archive outdated learnings to knowledge-base/learnings/archive/"

Still apply this proposal? (Y/n)
```

### Auto-Consolidation Step D: Apply Accepted Proposals

Apply each accepted proposal immediately after approval:

- **Constitution updates:** Append the rule to the correct domain/category section
- **Component doc updates:** Add new entries to the relevant component file
- **Overview README updates:** Add architectural notes to the appropriate section

### Auto-Consolidation Step E: Archival

Archive ALL discovered artifacts regardless of how many proposals were accepted or skipped.

Create archive directories on first use:

```bash
mkdir -p knowledge-base/brainstorms/archive
mkdir -p knowledge-base/plans/archive
mkdir -p knowledge-base/specs/archive
```

Use `git mv` with timestamp prefix for each artifact:

Generate a timestamp in `YYYYMMDD-HHMMSS` format (e.g., `20260222-143000`).

Replace `<timestamp>` with the generated timestamp and `<slug>` with the feature slug. Run each `git mv` as a separate Bash command:

```bash
git mv "knowledge-base/brainstorms/original-name.md" \
       "knowledge-base/brainstorms/archive/<timestamp>-original-name.md"
```

```bash
git mv "knowledge-base/plans/original-name.md" \
       "knowledge-base/plans/archive/<timestamp>-original-name.md"
```

```bash
git mv "knowledge-base/specs/feat-<slug>" \
       "knowledge-base/specs/archive/<timestamp>-feat-<slug>"
```

**If `git mv` fails** (untracked file), run `git add` on the file first, then retry the `git mv`.

**Context-aware archival confirmation:**

If at least one proposal was accepted:

```text
Overview files updated. Archive the source artifacts? (Y/n)
```

If all proposals were skipped:

```text
No overview updates applied. Still archive the source artifacts? (Y/n)
```

### Auto-Consolidation Step F: Commit

All changes (overview edits + archival moves) go into a single commit:

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

After successful documentation, present options and WAIT for user response:

```
✓ Solution documented

File created:
- knowledge-base/learnings/[category]/[filename].md

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
3. Add to `knowledge-base/learnings/patterns/critical-patterns.md`
4. Add cross-reference back to this doc
5. Confirm: "✓ Added to Required Reading. All subagents will see this pattern before code generation."

**Option 3: Link related issues**

- Prompt: "Which doc to link? (provide filename or describe)"
- Search knowledge-base/learnings/ for the doc
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
- ✅ File created in knowledge-base/learnings/[category]/[filename].md
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
   - `knowledge-base/learnings/performance-issues/n-plus-one-brief-generation-BriefSystem-20251110.md`
7. **Cross-reference:** None needed (no similar issues)

**Output:**

```text
✓ Solution documented

File created:
- knowledge-base/learnings/performance-issues/n-plus-one-brief-generation-BriefSystem-20251110.md

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
