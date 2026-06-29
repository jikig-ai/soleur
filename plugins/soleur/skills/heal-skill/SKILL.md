---
name: heal-skill
description: "This skill should be used when a skill has incorrect instructions, outdated API references, or wrong parameters. Detects, diffs, applies after approval."
---

<objective>
Update a skill's SKILL.md and related files based on corrections discovered during execution.

Analyze the conversation to detect which skill is running, reflect on what went wrong, propose specific fixes, get user approval, then apply changes with optional commit.
</objective>

<context>
Skill detection: !`ls -1 ./skills/*/SKILL.md | head -5`
</context>

<quick_start>
<workflow>
1. **Detect skill** from conversation context (invocation messages, recent SKILL.md references)
2. **Reflect** on what went wrong and how you discovered the fix
3. **Present** proposed changes with before/after diffs
4. **Get approval** before making any edits
5. **Apply** changes and optionally commit
</workflow>
</quick_start>

<process>
<step_1 name="detect_skill">
Identify the skill from conversation context:

- Look for skill invocation messages
- Check which SKILL.md was recently referenced
- Examine current task context

Identify the skill name and locate its directory at `./skills/<skill-name>/`.

If unclear, ask the user.
</step_1>

<step_2 name="reflection_and_analysis">
Focus on $ARGUMENTS if provided, otherwise analyze broader context.

Determine:
- **What was wrong**: Quote specific sections from SKILL.md that are incorrect
- **Discovery method**: Context7, error messages, trial and error, documentation lookup
- **Root cause**: Outdated API, incorrect parameters, wrong endpoint, missing context
- **Scope of impact**: Single section or multiple? Related files affected?
- **Proposed fix**: Which files, which sections, before/after for each
</step_2>

<step_3 name="scan_affected_files">
List the skill directory contents. Replace `<skill-dir>` with the actual skill directory path (e.g., `plugins/soleur/skills/<skill-name>`):

```bash
ls -la <skill-dir>/
ls -la <skill-dir>/references/ 2>/dev/null
ls -la <skill-dir>/scripts/ 2>/dev/null
```
</step_3>

<step_4 name="present_proposed_changes">
Present changes in this format:

```
**Skill being healed:** [skill-name]
**Issue discovered:** [1-2 sentence summary]
**Root cause:** [brief explanation]

**Files to be modified:**
- [ ] SKILL.md
- [ ] references/[file].md
- [ ] scripts/[file].py

**Proposed changes:**

### Change 1: SKILL.md - [Section name]
**Location:** Line [X] in SKILL.md

**Current (incorrect):**
```
[exact text from current file]
```

**Corrected:**
```
[new text]
```

**Reason:** [why this fixes the issue]

[repeat for each change across all files]

**Impact assessment:**
- Affects: [authentication/API endpoints/parameters/examples/etc.]

**Verification:**
These changes will prevent: [specific error that prompted this]
```
</step_4>

<step_5 name="request_approval">
```
Should I apply these changes?

1. Yes, apply and commit all changes
2. Apply but don't commit (let me review first)
3. Revise the changes (I'll provide feedback)
4. Cancel (don't make changes)

Choose (1-4):
```

**Wait for user response. Do not proceed without approval.**
</step_5>

<step_6 name="apply_changes">
Only after approval (option 1 or 2):

**6.0 — Validation gate for gated classifier-skill edits (primary in-session hook).**
Before applying ANY correction, run `node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --check <target-file>` for each file being edited. If `gated` is `false`, apply normally (step 1 below). If `gated` is `true`, the edit may change a verifiable classifier block (the `/go` routing table, the ticket-triage rubric) — gate it:

  a. **Buffer pre-check (the rejected-edit reader).** Read `.claude/.skill-edit-rejections.jsonl` (if present); if a prior entry matches this `source_file` + the same targeted miss (`target_task` id), surface it and do NOT re-propose the same dead-end edit — a previously-rejected edit is recognized, not re-run (avoids re-spending ~230 API calls on a known failure).
  b. **Run the gate.** Write the proposed-edited file to a temp path, then run `eval-gate.cjs --candidate-file <tmp> --target <target> --target-task <synthesized row encoding the miss being fixed>` (synthesized fixtures only, per `cq-test-fixtures-synthesized-only`). The verdict is computed deterministically in `verdict.cjs` (the LLM is out of the assertion path).
  c. **Accept (`accept:true`):** apply the Edit (step 1). Optionally `--append-on-accept` so the fixed case becomes a permanent corpus regression guard.
  d. **Reject (`accept:false`) or any gate error (fail-closed):** do NOT apply; append `{source_file, target_task_id, reason, verdict, timestamp}` to `.claude/.skill-edit-rejections.jsonl`; surface the verdict. Do NOT stamp any sync marker — the fix is not abandoned, it can be re-attempted with a different edit.
  e. **Headless (`HEADLESS_MODE=true`):** skip-gate-and-defer — record a deferred-verification note and apply; the #5703 CI backstop re-asserts at PR time (do not spend the gate's API budget unattended).

  This gate fires only on edits that change a gated block; a correction to prose *outside* the block (the common case) extracts an identical block and short-circuits to `accept` (no API). It never displaces a deterministic hook fix — it only validates a prose-rule change to a classifier surface.

1. Use Edit tool for each correction across all files
2. Read back modified sections to verify
3. If option 1, commit with structured message showing what was healed
4. Confirm completion with file list
</step_6>
</process>

<success_criteria>
- Skill correctly detected from conversation context
- All incorrect sections identified with before/after
- User approved changes before application
- All edits applied across SKILL.md and related files
- Changes verified by reading back
- Commit created if user chose option 1
- Completion confirmed with file list
</success_criteria>

<verification>
Before completing:

- Read back each modified section to confirm changes applied
- Ensure cross-file consistency (SKILL.md examples match references/)
- Verify git commit created if option 1 was selected
- Check no unintended files were modified
</verification>
