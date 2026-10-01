---
name: triage
description: "This skill should be used when triaging legacy local todo files in todos/. For GitHub issues, use soleur:support:ticket-triage agent."
---

<!-- Inspired by mattpocock/skills/skills/engineering/triage/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

- First set the /model to Haiku
- Then read all pending todos in the todos/ directory

Present all findings, decisions, or issues here one by one for triage. The goal is to go through each item and decide whether to add it to the CLI todo system.

> **Note:** The `soleur:review` skill now creates GitHub issues directly for all new findings. This triage skill handles only legacy local `todos/*.md` files that predate the GitHub issue integration.

**IMPORTANT: DO NOT CODE ANYTHING DURING TRIAGE!**

This skill is for:

- Triaging code review findings
- Processing security audit results
- Reviewing performance analysis
- Handling any other categorized findings that need tracking

## CodeQL alert-state precheck (security findings)

Before commissioning work on any CodeQL-derived finding (issue title starts with
`sec: CodeQL alert #N` or body cites `alert #N`), verify the alert is still open:

```bash
gh api "/repos/:owner/:repo/code-scanning/alerts/<N>" --jq '.state'
```

If the response is `dismissed` or `fixed`, the finding is an orphan — close it
with a pointer to the dismissing PR (search via `gh pr list --search "alert #<N>" --state merged -L 200` — a *dismissing* PR has merged, and `gh pr list` otherwise defaults to open-only and would never find it, #6786)
instead of approving for work. The `.github/workflows/codeql-to-issues.yml`
`close-orphans` job sweeps these automatically once a day, but a triage-time
check prevents wasted planning when the daily run is hours away. See
`knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md`.

## Workflow

### Step 1: Present Each Finding

**Before presenting anything, run two read-only pre-checks on each finding.** A `todos/*.md` finding
is an internally generated review note rather than a request from a user, which is exactly why it can
legitimately restate something that is already built or something that has already been refused.
Nothing about a finding is self-evidently new.

1. **Already built?** Search the codebase for the behaviour the finding asks for **by domain concept
   rather than by the finding's own wording**, and report where you looked. The procedure is
   `plugins/soleur/skills/brainstorm/SKILL.md` `#### 1.1 Research (Context Gathering)` — cited,
   never restated: a second copy of that sweep drifts from the first, and the drifted copy is the one
   somebody follows. If the behaviour already exists this is a **redundancy finding** — name where
   the implementation lives, and write nothing to the no-list.
2. **Refused before?** Read the no-list at `knowledge-base/project/rejected/*.md`, matching on
   concept and on each entry's `aliases` rather than on keywords, and skip any entry carrying
   `superseded_by`. `README.md` is the convention document, not an entry.

Both pre-checks **advise; neither acts.** A hit is escalated to the founder with the entry named, and
an already-built finding outranks a no-list hit: if the capability exists, the entry is wrong and the
entry is what gets corrected. An entry is also never the decision itself, only evidence that a refusal
was RECORDED, so where it disagrees with a primary record — the issue's own closure, an ADR, a roadmap
decision — the primary record wins and the entry is STALE. Order: running code, then the primary
record, then the entry. An uncertain match **fails open** — name the candidate, say why it is
uncertain, and leave the finding open. Report both results in the presentation block, including the
search that found nothing: a negative carries only the scope that produced it.

For each finding, present in this format:

```
---
Issue #X: [Brief Title]

Severity: P1 (CRITICAL) / P2 (IMPORTANT) / P3 (NICE-TO-HAVE)

Category: [Security/Performance/Architecture/Bug/Feature/etc.]

Description:
[Detailed explanation of the issue or improvement]

Location: [file_path:line_number]

Problem Scenario:
[Step by step what's wrong or could happen]

Proposed Solution:
[How to fix it]

Estimated Effort: [Small (< 2 hours) / Medium (2-8 hours) / Large (> 8 hours)]

Already built: [the search you ran -> found at <path> | not found]
Prior refusal: [<entry path> (matched alias: "<alias>") | no match]

---
Do you want to add this to the todo list?
1. yes - create todo file
2. next - skip this item (the file stays)
3. custom - modify before creating
4. reject - record why, then remove the finding
```

### Step 2: Handle User Decision

**When user says "yes":**

1. **Update existing todo file** (if it exists) or **Create new filename:**

   If todo already exists (from code review):

   - Rename file from `{id}-pending-{priority}-{desc}.md` -> `{id}-ready-{priority}-{desc}.md`
   - Update YAML frontmatter: `status: pending` -> `status: ready`
   - Keep issue_id, priority, and description unchanged

   If creating new todo:

   ```
   {next_id}-ready-{priority}-{brief-description}.md
   ```

   Priority mapping:

   - P1 (CRITICAL) -> `p1`
   - P2 (IMPORTANT) -> `p2`
   - P3 (NICE-TO-HAVE) -> `p3`

   Example: `042-ready-p1-transaction-boundaries.md`

2. **Update YAML frontmatter:**

   ```yaml
   ---
   status: ready # IMPORTANT: Change from "pending" to "ready"
   priority: p1 # or p2, p3 based on severity
   issue_id: "042"
   tags: [category, relevant-tags]
   dependencies: []
   ---
   ```

3. **Populate or update the file:**

   ```yaml
   # [Issue Title]

   ## Problem Statement
   [Description from finding]

   ## Findings
   - [Key discoveries]
   - Location: [file_path:line_number]
   - [Scenario details]

   ## Proposed Solutions

   ### Option 1: [Primary solution]
   - **Pros**: [Benefits]
   - **Cons**: [Drawbacks if any]
   - **Effort**: [Small/Medium/Large]
   - **Risk**: [Low/Medium/High]

   ## Recommended Action
   [Filled during triage - specific action plan]

   ## Technical Details
   - **Affected Files**: [List files]
   - **Related Components**: [Components affected]
   - **Database Changes**: [Yes/No - describe if yes]

   ## Resources
   - Original finding: [Source of this issue]
   - Related issues: [If any]

   ## Acceptance Criteria
   - [ ] [Specific success criteria]
   - [ ] Tests pass
   - [ ] Code reviewed

   ## Work Log

   ### {date} - Approved for Work
   **By:** Claude Triage System
   **Actions:**
   - Issue approved during triage session
   - Status changed from pending -> ready
   - Ready to be picked up and worked on

   **Learnings:**
   - [Context and insights]

   ## Notes
   Source: Triage session on {date}
   ```

4. **Confirm approval:** "Approved: `{new_filename}` (Issue #{issue_id}) - Status: **ready** -> Ready to work on"

**When user says "next":**

- **Leave the todo file where it is.** Skipping is not a decision, and deleting on a skip destroys
  the finding with no record of why — which is the opposite of what the no-list is for. `reject` is
  the only branch that removes a finding.
- Skip to the next item
- Track skipped items for summary

**When user says "custom":**

- Ask what to modify (priority, description, details)
- Update the information
- Present revised version
- Ask again: yes/next/custom/reject

**When user says "reject":**

This is the no-list's named write path, and **the only branch that removes a finding.**

1. **Check the redundancy pre-check came back "not found."** If the behaviour is already built, stop:
   that is a redundancy finding, and its record is the sentence naming where the implementation
   lives. Writing a built capability into the no-list seeds every later duplicate check with a
   refusal nobody made.
2. **Test the reason for durability.** "Outside the product's boundary" is durable. "Nobody has time
   this quarter" is a deferral, not a rejection — leave the finding in place and say so.
3. **Draft the entry** at `knowledge-base/project/rejected/YYYY-MM-DD-<concept-slug>.md`, following
   `knowledge-base/project/rejected/README.md`: every required field, the `why`/`public_note` split,
   an `instead`, a `revisit_if` that can be observed rather than argued, and no field naming a
   person. The write discipline is
   `plugins/soleur/skills/kb-glossary/references/rejected-request-register.md`.
4. **Machine gate, before the human gate:** run `bash scripts/lint-rejected-register.sh <path>` and
   fix everything it names. There is no reason to ask the founder to confirm a malformed record.
5. **Human gate:** ask for confirmation by having the founder **type the concept slug** — not `y`.
   A single keystroke against a permanent refusal is a reflex; typing
   `server-side-browser-automation` is a decision. Any other answer, including an empty one, aborts
   and leaves both the finding and the directory untouched.
6. **Write the entry, then delete the todo file,** in that order: if the write fails, the finding is
   still there. Report both paths — the entry created and the finding removed.

### Step 3: Continue Until All Processed

- Process all items one by one
- Track using TodoWrite for visibility
- Don't wait for approval between items - keep moving

### Step 4: Final Summary

After all items processed:

````markdown
## Triage Complete

**Total Items:** [X] **Todos Approved (ready):** [Y] **Skipped:** [Z] **Rejected (recorded):** [R]

### Approved Todos (Ready for Work):

- `042-ready-p1-transaction-boundaries.md` - Transaction boundary issue
- `043-ready-p2-cache-optimization.md` - Cache performance improvement ...

### Skipped Items (still in todos/):

- Item #5: [reason] - left pending, returns in the next pass
- Item #12: [reason] - left pending, returns in the next pass

### Rejected (recorded on the no-list, finding removed):

- Item #7: `knowledge-base/project/rejected/2026-04-02-<concept-slug>.md` - finding deleted after the entry was written

### Summary of Changes Made:

During triage, the following status updates occurred:

- **Pending -> Ready:** Filenames and frontmatter updated to reflect approved status
- **Skipped:** Todo files left in todos/ untouched — skipping removes nothing
- **Rejected:** A no-list entry was written, and only then was the todo file removed
- Each approved file now has `status: ready` in YAML frontmatter

### Next Steps:

1. View approved todos ready for work:
   ```bash
   ls todos/*-ready-*.md
   ```
````

2. Start work on approved items:

   ```bash
   soleur:resolve-todo-parallel  # Work on multiple approved items efficiently
   ```

3. Or pick individual items to work on

4. As you work, update todo status:
   - Ready -> In Progress (in your local context as you work)
   - In Progress -> Complete (rename file: ready -> complete, update frontmatter)

```

## Example Response Format

```

---

Issue #5: Missing Transaction Boundaries for Multi-Step Operations

Severity: P1 (CRITICAL)

Category: Data Integrity / Security

Description: The google_oauth2_connected callback in GoogleOauthCallbacks concern performs multiple database operations without transaction protection. If any step fails midway, the database is left in an inconsistent state.

Location: app/controllers/concerns/google_oauth_callbacks.rb:13-50

Problem Scenario:

1. User.update succeeds (email changed)
2. Account.save! fails (validation error)
3. Result: User has changed email but no associated Account
4. Next login attempt fails completely

Operations Without Transaction:

- User confirmation (line 13)
- Waitlist removal (line 14)
- User profile update (line 21-23)
- Account creation (line 28-37)
- Avatar attachment (line 39-45)
- Journey creation (line 47)

Proposed Solution: Wrap all operations in ApplicationRecord.transaction do ... end block

Estimated Effort: Small (30 minutes)

---

Do you want to add this to the todo list?

1. yes - create todo file
2. next - skip this item (the file stays)
3. custom - modify before creating
4. reject - record why, then remove the finding

```

## Important Implementation Details

### Status Transitions During Triage

**When "yes" is selected:**
1. Rename file: `{id}-pending-{priority}-{desc}.md` -> `{id}-ready-{priority}-{desc}.md`
2. Update YAML frontmatter: `status: pending` -> `status: ready`
3. Update Work Log with triage approval entry
4. Confirm: "Approved: `{filename}` (Issue #{issue_id}) - Status: **ready**"

**When "next" is selected:**
1. Leave the todo file in todos/ -- `reject` is the only branch that removes a finding
2. Skip to next item
3. The file stays pending and comes back in the next triage pass

**When "reject" is selected:**
1. Write the no-list entry, after `bash scripts/lint-rejected-register.sh <path>` passes
2. Take the founder's confirmation as the typed concept slug, never as `y`
3. Only then delete the todo file, and report the entry path alongside the removed filename

### Progress Tracking

Every time you present a todo as a header, include:
- **Progress:** X/Y completed (e.g., "3/10 completed")
- **Estimated time remaining:** Based on how quickly you're progressing
- **Pacing:** Monitor time per finding and adjust estimate accordingly

Example:
```

Progress: 3/10 completed | Estimated time: ~2 minutes remaining

```

### Do Not Code During Triage

- Present findings
- Make yes/next/custom/reject decisions
- Update todo files (rename, frontmatter, work log)
- Do NOT implement fixes or write code
- Do NOT add detailed implementation details
- That's for soleur:resolve-todo-parallel phase
```

When done give these options

```markdown
What would you like to do next?

1. run soleur:resolve-todo-parallel to resolve the todos
2. commit the todos
3. nothing, go chill
```
