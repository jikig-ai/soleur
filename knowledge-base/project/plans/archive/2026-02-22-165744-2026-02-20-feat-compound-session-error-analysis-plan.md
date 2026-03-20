---
title: "feat: Add session error analysis to compound"
type: feat
date: 2026-02-20
issue: "#168"
version_bump: PATCH
---

# feat: Add session error analysis to compound

## Overview

Extend the `/soleur:compound` skill to scan the conversation history for ALL errors that occurred during the session -- not just the target problem's investigation attempts. Capture process mistakes, failed commands, and dead-end approaches as documented learnings, preventing repeated workflow errors across sessions.

## Problem Statement

Compound captures the problem that was intentionally solved (root cause, solution, prevention). Step 2 extracts "investigation attempts: what didn't work and why" -- but only for the TARGET problem.

Session-level errors go undocumented:
- Bash commands that failed (wrong flags, missing tools, path errors)
- Wrong hypotheses investigated and abandoned
- Process mistakes (editing wrong file, wrong branch, forgetting to stage)
- Repeated mistakes across the session

Without capturing these, the same workflow mistakes repeat session after session, wasting tokens and time.

## Proposed Solution

Extend Step 2 of compound-docs to also scan for session-level errors, and add a section to the resolution template. Three small edits, no new files, no new schema, no new abstractions.

### What changes

**1. `plugins/soleur/skills/compound-docs/SKILL.md`** -- Extend Step 2 (Gather Context)

Add a sub-section to Step 2's "Extract from conversation history" block:

```markdown
**Session errors (beyond the target problem):**

Scan conversation history for errors unrelated to the main problem investigation. Only capture errors that are NOT part of the investigation attempts documented above. Skip trivial errors immediately corrected (typos in commands, expected test failures during TDD).

Extract for each error:
- Description of what went wrong (1 sentence)
- What was done to recover
- How to prevent it in future sessions (1 sentence)

If no session errors found, skip this extraction silently.
```

**2. `plugins/soleur/skills/compound-docs/assets/resolution-template.md`** -- Add "Session Errors" section

Add after "What Didn't Work" and before "Solution", using the same bold-heading + bullet format:

```markdown
## Session Errors

[Process mistakes and command failures encountered during this session, beyond the main problem investigation. Omit this section entirely if no session errors occurred.]

**[Brief error description]**
- **Recovery:** [What fixed it]
- **Prevention:** [How to avoid in future]

[Repeat for each session error]
```

**3. `plugins/soleur/commands/soleur/compound.md`** -- Add bullet to "What It Captures"

Add to the existing bullet list at line 209:
```
- **Session errors**: Process mistakes, failed commands, and wrong approaches from the session
```

No new subagent. The session error scan is part of Step 2's context gathering, not a separate parallel unit.

## Technical Considerations

- **No schema changes.** Session errors live in the markdown body as prose, not YAML frontmatter. No validation changes needed.
- **Conversation history is the only data source.** Same pattern as Step 2 and Step 8.
- **Deduplication is implicit.** The instruction "errors unrelated to the main problem investigation" is sufficient. Step 2 handles the target problem; the new sub-section handles everything else.
- **The extraction is optional.** Clean sessions produce unchanged documents.

## Non-Goals

- No new YAML frontmatter fields or schema changes
- No new categories, directories, or error taxonomy enums
- No separate learning files for session errors
- No new subagent in compound.md
- No automated session error detection outside compound

## Acceptance Criteria

- [ ] Step 2 scans conversation history for errors beyond the target problem
- [ ] Session errors appear in the learning document using bold-heading + bullet format
- [ ] Errors already in "What Didn't Work" are not duplicated
- [ ] Trivial/expected errors are filtered out
- [ ] Section is omitted when no session errors are found
- [ ] compound.md "What It Captures" list includes session errors

## Test Scenarios

- Given a session with bash command failures, when compound runs, then the learning document includes those failures in a Session Errors section
- Given a session with no errors beyond the target problem, when compound runs, then no Session Errors section appears
- Given a session where Step 2 already captured "wrong approach X" as an investigation attempt, when Step 2 runs, then "wrong approach X" is not duplicated in Session Errors
- Given a session with a typo in a command immediately re-run correctly, when compound runs, then the typo is filtered out as trivial

## Rollback Plan

Revert the commit. All changes are additive to existing files with no schema or directory changes.

## References

- `plugins/soleur/skills/compound-docs/SKILL.md:57` -- Step 2 (Gather Context), the extension point
- `plugins/soleur/commands/soleur/compound.md:202` -- "What It Captures" list
- `plugins/soleur/skills/compound-docs/assets/resolution-template.md:32` -- "What Didn't Work" section (format reference)
- Issue: #168
