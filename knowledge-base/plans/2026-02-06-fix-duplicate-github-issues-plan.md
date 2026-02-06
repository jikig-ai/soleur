---
title: Fix Duplicate GitHub Issues During Workflow
type: fix
date: 2026-02-06
---

# Fix Duplicate GitHub Issues During Workflow

Fix the `/soleur:brainstorm` command to detect when invoked with an existing GitHub issue reference and skip creating a duplicate issue.

## Acceptance Criteria

- [ ] `/soleur:brainstorm github issue #18` does not create a new issue
- [ ] Output shows "Using existing issue: #18" instead of "Issue: #N (created)"
- [ ] `/soleur:brainstorm add dark mode` (no issue ref) still creates a new issue
- [ ] Invalid issue references (e.g., `#99999`) show warning and prompt to confirm new issue creation
- [ ] Closed issue references warn user and create new issue with link to closed one

## Context

When brainstorm starts with an existing issue (e.g., `github issue #10`), Phase 3.6 currently creates a duplicate issue. This resulted in duplicate pairs like #10/#15 and #14/#16.

## MVP

### plugins/soleur/commands/soleur/brainstorm.md

Modify Phase 3.6 to add issue detection before creation:

```markdown
### Phase 3.6: Create Spec and Issue (if worktree exists)

**If worktree was created:**

1. **Check for existing issue reference in feature_description:**
   ```bash
   # Parse for issue patterns: #N (first occurrence)
   existing_issue=$(echo "<feature_description>" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

   if [[ -n "$existing_issue" ]]; then
     # Validate issue exists and check state
     issue_state=$(gh issue view "$existing_issue" --json state --jq .state 2>/dev/null)

     if [[ "$issue_state" == "OPEN" ]]; then
       echo "Using existing issue: #$existing_issue"
       # Use $existing_issue for all references, skip to step 3
     elif [[ "$issue_state" == "CLOSED" ]]; then
       echo "Warning: Issue #$existing_issue is closed."
       echo "Creating new issue with reference to closed one."
       # Proceed to step 2, include "Replaces closed #$existing_issue" in body
     else
       echo "Warning: Issue #$existing_issue not found."
       # Use AskUserQuestion: "Create new issue anyway?"
       # If yes, proceed to step 2. If no, abort.
     fi
   fi
   ```

2. **Create GitHub issue (only if no valid existing issue):**
   ```bash
   gh issue create --title "feat: <Feature Title>" --body "..."
   ```

3. **Update existing issue with artifact links:**
   When using an existing issue, append to its body:
   ```bash
   existing_body=$(gh issue view "$existing_issue" --json body --jq .body)
   new_body="${existing_body}

   ---
   ## Artifacts
   - Brainstorm: \`knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md\`
   - Spec: \`knowledge-base/specs/feat-<name>/spec.md\`
   - Branch: \`feat-<name>\`
   "
   gh issue edit "$existing_issue" --body "$new_body"
   ```
```

**Output Summary changes:**

Update the Output Summary template to distinguish existing vs created:

```
Issue: #N (using existing) | Issue: #N (created) | Issue: none
```

**Key changes:**
- Add step 1: Parse feature_description for `#\d+` pattern
- Add step 1b: Check issue state (OPEN/CLOSED/not found)
- Handle closed issues: warn, create new with reference
- Handle invalid refs: warn and prompt user
- Step 3: Always update existing issue body with artifact links
- Update output format to show "using existing" vs "created"

## References

- Related issue: #18
- Brainstorm: `knowledge-base/brainstorms/2026-02-06-fix-duplicate-issues-brainstorm.md`
- Spec: `knowledge-base/specs/feat-fix-duplicate-issues/spec.md`
- Target file: `plugins/soleur/commands/soleur/brainstorm.md:114-148`
