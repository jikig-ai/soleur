---
name: compound
description: "This skill should be used when documenting a recently solved problem to compound your team's knowledge."
---

# /compound

Coordinate multiple subagents working in parallel to document a recently solved problem.

## Purpose

Captures problem solutions while context is fresh, creating structured documentation in `knowledge-base/project/learnings/` with YAML frontmatter for searchability and future reference. Uses parallel subagents for maximum efficiency.

**Why "compound"?** Each documented solution compounds your team's knowledge. The first time you solve a problem takes research. Document it, and the next occurrence takes minutes. Knowledge compounds.

## Usage

```bash
skill: soleur:compound               # Document the most recent fix
skill: soleur:compound [brief context]  # Provide additional context hint
skill: soleur:compound --headless    # Headless mode: auto-approve all prompts
```

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`. Strip `--headless` from `$ARGUMENTS` before processing remaining args.

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort immediately with: "Error: compound cannot run on main/master. Checkout a feature branch first." This check fires in all modes (headless and interactive) as defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI).

When `HEADLESS_MODE=true`, forward `--headless` to the `compound-capture` invocation (e.g., `skill: soleur:compound-capture --headless`).

## Phase 0: Setup

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

Read `CLAUDE.md` if it exists - apply project conventions during documentation.

## Phase 0.5: Session Error Inventory (MANDATORY)

HARD RULE: Before writing any learning, enumerate ALL errors encountered in this session. Output a numbered list to the user. This step cannot be skipped even if the session felt clean.

**Check for session-state.md:** Run `git branch --show-current`. If on a `feat-*` branch, check if `knowledge-base/project/specs/feat-<name>/session-state.md` exists. If it does, read it and include any forwarded errors from `### Errors` in the inventory. These errors occurred in preceding pipeline phases (e.g., plan+deepen subagent) whose context was compacted.

Include:

- Errors forwarded from session-state.md (if present)
- Skill or command not found errors (e.g., wrong plugin namespace)
- Wrong file paths, directories, or branch confusion
- Failed bash commands or unexpected exit codes
- API errors or unexpected responses
- Wrong assumptions that required backtracking
- Tools or agents that returned errors
- Permission denials or hook rejections

If genuinely no errors occurred (including no forwarded errors), output: "Session error inventory: none detected."

This list feeds directly into the Session Errors section of the learning document. Every item on this list MUST appear in the final output unless the user explicitly excludes it.

FAILURE MODE THIS PREVENTS: Compound runs in pipeline mode, the model judges the session as "clean," and silently drops errors that happened earlier in the conversation (e.g., a skill-not-found error from one-shot Step 1 gets omitted because compound focuses only on the main implementation task).

### Post-Documentation Verification Gate (MANDATORY)

After the learning file is written (by compound-capture Step 6), read it back and verify:

1. If Phase 0.5 produced a non-empty error inventory, the learning file MUST contain a `## Session Errors` section with at least as many items as the inventory.
2. For each session error, the learning MUST include a `**Prevention:**` line proposing how to avoid it in future sessions.
3. If the verification fails (section missing or item count mismatch), append the missing errors to the learning file immediately. Do not proceed to Constitution Promotion until the learning is complete.

This gate closes the gap where errors were enumerated in conversation but never made it into the persisted document.

### Error-to-Workflow Feedback (MANDATORY)

After verifying session errors are in the learning, determine if any error warrants a workflow change. For each session error, ask: "Could a rule, hook, or skill instruction have prevented this?"

- If yes, produce a proposal in the same format as Phase 1.5 Deviation Analyst (rule text + enforcement tier) and feed it into Constitution Promotion alongside any deviation proposals.
- If no (the error was a one-off or already covered by existing rules), skip.

This ensures session errors don't just get documented — they feed back into the rules and definitions that govern future sessions. The goal is a closed loop: error happens → gets documented → workflow changes → error cannot recur.

## Execution Strategy: Parallel Subagents

This command launches multiple specialized subagents IN PARALLEL to maximize efficiency:

### 1. **Context Analyzer** (Parallel)

- Extracts conversation history
- Identifies problem type, component, symptoms
- Validates against solution schema
- Returns: YAML frontmatter skeleton

### 2. **Solution Extractor** (Parallel)

- Analyzes all investigation steps
- Identifies root cause
- Extracts working solution with code examples
- Returns: Solution content block

### 3. **Related Docs Finder** (Parallel)

- Searches `knowledge-base/project/learnings/` for related documentation
- Identifies cross-references and links
- Finds related GitHub issues
- Returns: Links and relationships

### 4. **Prevention Strategist** (Parallel)

- Develops prevention strategies
- Creates best practices guidance
- Generates test cases if applicable
- Returns: Prevention/testing content

### 5. **Documentation Writer** (Parallel)

- Determines optimal `knowledge-base/project/learnings/` category
- Validates category against schema
- Suggests filename based on slug
- Assembles complete markdown file
- Validates YAML frontmatter
- Formats content for readability
- Creates the file in correct location

### 6. **Optional: Specialized Agent Invocation** (Post-Documentation)

Based on problem type detected, automatically invoke applicable agents:

- **performance_issue** --> `performance-oracle`
- **security_issue** --> `security-sentinel`
- **database_issue** --> `data-integrity-guardian`
- Any code-heavy issue --> `kieran-rails-reviewer` + `code-simplicity-reviewer`

## Phase 1.5: Deviation Analyst (Sequential)

After all parallel subagents complete and before Constitution Promotion, scan the session for workflow deviations against hard rules. This phase runs sequentially (not as a parallel subagent) to respect the max-5 parallel subagent limit.

### Purpose

Close the gap between "we learned X" and "X is now enforced." The project has proven that hooks beat documentation — all existing PreToolUse hooks were added after prose rules failed. This phase detects deviations and proposes the strongest viable enforcement.

### Procedure

1. **Gather rules.** Read `AGENTS.md` and extract only `## Hard Rules` and `## Workflow Gates` items (Always/Never). Skip Prefer rules — they are advisory and flagging them adds noise.

2. **Gather session evidence.** Two sources:
   - **session-state.md** (if present): read `knowledge-base/project/specs/feat-<name>/session-state.md` for forwarded errors from preceding pipeline phases (pre-compaction deviations)
   - **Current context**: scan the conversation for post-compaction actions — tool calls, command outputs, file edits

3. **Detect deviations.** For each hard rule, check if session evidence shows a violation. Common examples:
   - Editing files in main repo when a worktree is active
   - Committing directly to main
   - Running `git stash` in a worktree
   - Skipping compound before commit
   - Treating a failed command as success
   - **Manual browser steps in prose output:** Scan all text output (summaries, handoffs, "next steps" lists) for browser tasks labeled as manual without a preceding Playwright MCP attempt. Phrases like "set up X in the browser", "go to the portal and configure", "manually create an account" are violations of the Playwright-first rule unless the session log shows a `mcp__plugin_playwright_playwright__browser_navigate` call for that task. This catches laziness in handoff text that hooks cannot detect.

3.5. **Ingest recent hook incidents.** Read `.claude/.rule-incidents.jsonl` if present (gitignored single-file log written by `.claude/hooks/lib/incidents.sh`). Filter to events emitted since the session started (use the earliest timestamp in the session log, or the last 30 minutes if no anchor is available). Treat each recent `deny` and `bypass` as evidence for the Deviation Analyst — denies confirm a hook caught a violation; bypasses signal a rule the user actively skipped. Per plan ADR-1, this step **does NOT mutate any learning's frontmatter** — counter aggregation lives exclusively in `knowledge-base/project/rule-metrics.json` (written weekly by the aggregator). If the file is absent or empty, note "no recent incidents" and continue.

4. **Propose enforcement.** For each detected deviation, first check if an existing PreToolUse hook already covers it by scanning `.claude/hooks/*.sh` comment headers. If a hook already enforces the rule, note "already hook-enforced" and skip the proposal. If no hook covers it, propose enforcement following the hierarchy:
   - **PreToolUse hook** (preferred) — mechanical prevention, cannot be bypassed
   - **Skill instruction** — checked when skill runs, can be overridden
   - **Prose rule** (last resort) — requires agent compliance, weakest enforcement

5. **Format output.** For each deviation, produce:

   ```text
   ### Deviation: [short description]
   - **Rule violated:** [exact text from AGENTS.md or constitution.md]
   - **Evidence:** [what happened in the session]
   - **Existing enforcement:** [hook name if already covered, or "none"]
   - **Proposed enforcement:** [hook/skill_instruction/prose_rule]
   ```

   For hook proposals, include an inline draft script following `.claude/hooks/` conventions:

   ```bash
   #!/usr/bin/env bash
   # PreToolUse hook: [what it blocks]
   # Source rule: [AGENTS.md or constitution.md reference]
   set -euo pipefail
   INPUT=$(cat)
   # [detection logic]
   # If violation detected:
   # jq -n '{ hookSpecificOutput: { permissionDecision: "deny", permissionDecisionReason: "BLOCKED: [reason]" } }'
   ```

6. **Feed into learning document.** For each detected deviation, add it to the learning file's `## Session Errors` section (if not already present from Phase 0.5). Format: `**[description]** — Recovery: [what fixed it] — Prevention: [proposed enforcement]`. This ensures workflow violations are documented in the learning, not just proposed as hooks.

7. **Feed into Constitution Promotion.** Present each deviation to the user via the existing Accept/Skip/Edit gate in the Constitution Promotion section below. Accepted hook proposals should be manually copied to `.claude/hooks/` after testing — never auto-install.

8. **Rule budget count.** After deviation analysis, count always-loaded rules in `AGENTS.md` (the only file included via `CLAUDE.md @AGENTS.md`): `grep -c '^- ' AGENTS.md`. Constitution.md is on-demand (loaded by skills when needed, not every turn) and tracked separately. Output: `"Rule budget: A always-loaded rules (AGENTS.md: A), C on-demand rules (constitution.md: C)"`. If A > 100, append: `"[WARNING] AGENTS.md budget exceeded (A/100). Move skill-specific rules to the skills that enforce them."` If C > 300, append: `"[WARNING] constitution.md is large (C/300). Consider migrating narrow rules to skill/agent instructions."` Additionally, if the repo has a rule-metrics aggregator at `rule-metrics-aggregate.sh` under its `scripts/` directory, run it in `--dry-run` mode and parse `summary.rules_unused_over_8w` from the JSON output — if the value is greater than zero, append: `"[INFO] N rules have zero hits over 8 weeks. Run /soleur:sync rule-prune to surface pruning candidates."` Do not fail the phase if the aggregator is missing.

### Empty Case

If no deviations are detected, output: "Deviation Analyst: no violations found." followed by the rule budget count from step 8, then proceed to Knowledge Base Integration.

## Knowledge Base Integration

**If knowledge-base/ directory exists, compound saves learnings there and offers constitution promotion:**

### Save Learning to Knowledge Base

If `knowledge-base/` directory exists, save the learning file to `knowledge-base/project/learnings/YYYY-MM-DD-<topic>.md` (using today's date). Otherwise, fall back to `knowledge-base/project/learnings/<category>/<topic>.md`.

**Learning format for knowledge-base/project/learnings/:**

```markdown
# Learning: [topic]

## Problem
[What we encountered]

## Solution
[How we solved it]

## Key Insight
[The generalizable lesson]

## Tags
category: [category]
module: [module]
```

### Constitution Promotion (Manual or Auto)

HARD RULE: This phase MUST run even when compound is invoked inside an automated pipeline (one-shot, ship). The model has historically rationalized skipping this as "pipeline mode optimization" -- that is a protocol violation. Constitution promotion and route-to-definition are the phases that prevent repeated mistakes across sessions. If the pipeline is time-constrained, present proposals with a 5-second timeout per item, but never skip entirely.

**Headless mode:** If `HEADLESS_MODE=true`, auto-promote using LLM judgment. Review recent learnings, determine if any warrant constitution promotion, select the domain and category using LLM judgment, generate the principle text, and check for duplicates via substring match against existing rules in `constitution.md`. Skip any principle that is already covered. Append non-duplicate principles and commit. Do not prompt the user. For deviation analyst proposals, auto-accept hook proposals that have clear rule-to-hook mappings and skip ambiguous ones.

**Interactive mode:** After saving the learning, present two categories of proposals:

**1. Deviation Analyst proposals (if any):** If Phase 1.5 produced deviations, present each one with Accept/Skip/Edit. For accepted hook proposals, display the draft script and instruct the user to manually copy it to `.claude/hooks/` after testing. For accepted skill instruction or prose rule proposals, apply the edit to the target file.

**2. Constitution promotion:** Prompt the user:

**Question:** "Promote anything to constitution?"

**If user says yes:**

1. Show recent learnings (last 5 from `knowledge-base/project/learnings/`)
2. User selects which learning to promote
3. Ask: "Which domain? (Code Style / Architecture / Testing)"
4. Ask: "Which category? (Always / Never / Prefer)"
5. User writes the principle (one line, actionable)
6. Append to `knowledge-base/project/constitution.md` under the correct section
7. Commit: `git commit -m "constitution: add <domain> <category> principle"`

**If user says no:** Continue to next step

### Route Learning to Definition

HARD RULE: This phase MUST run even in automated pipelines. See constitution promotion rule above.

After constitution promotion, compound routes the captured learning to the skill, agent, or command definition that was active in the session. This feeds insights back into the instructions that directly govern behavior, preventing repeated mistakes.

1. Detect which skills, agents, or commands were invoked in this conversation. Also check session-state.md `### Components Invoked` for components from preceding pipeline phases.
2. Route **two categories** of insights:
   - **Solution insight:** The main learning (what was solved and how). Propose a one-line bullet edit to the most relevant section of the target definition file.
   - **Error prevention:** For each session error that could have been prevented by a skill instruction, propose a one-line bullet to the skill that was active when the error occurred. Example: if a plan skill prescribed wrong paths, add a bullet to the plan skill's Sharp Edges saying "Verify relative paths by tracing each `../` step before prescribing them."
3. **Default action (interactive and headless):** Apply the edit directly to the
   target skill/agent/AGENTS.md file. Commit with `skill: route <basename>
   <summary>`. Sanitize `<basename>` and `<summary>` before interpolation —
   `BASENAME=$(basename "$TARGET" | tr -cd '[:alnum:]._-')` — or pass the
   message via a heredoc (`git commit -m "$(cat <<EOF\nskill: route ...\nEOF\n)"`)
   so backticks or `$(...)` in a learning-file-derived basename cannot
   command-substitute. The edit surface is BOUNDED: a single bullet-point
   append, a single Sharp Edges entry, or a ≤3-line instruction clarification.
   Edits that change existing bullet semantics, span multiple files, or modify
   AGENTS.md rule wording are OUT OF SCOPE for direct edit — file an issue
   instead.

4. **File-issue exception:** File a GitHub issue when the edit meets one of:
   cross-skill (touches 2+ skill/agent files), contested-design (competing
   valid approaches), agents-md-semantic-change (modifies existing rule text).
   Title: `compound: route-to-definition proposal for <target-basename>`.
   Body: proposed edit text + target path + source learning path + `## Scope-Out
   Justification` naming the criterion. Flags: `--label deferred-scope-out
   --milestone "Post-MVP / Later"`.

5. **Interactive confirmation for direct edits:** If HEADLESS_MODE is unset,
   show the proposed diff and ask Accept/Skip/Edit-then-Accept before committing.
   In headless mode, apply directly without prompting — the bounded surface
   (single bullet append) is safe without per-edit approval.

See compound-capture Step 8 for the full flow.

**Graceful degradation:** Skips if `plugins/soleur/` does not exist or no components detected in the session.

### Managing Learnings (Update/Archive/Delete)

**Update an existing learning:**
Read the file in `knowledge-base/project/learnings/`, apply changes, and commit with `git commit -m "learning: update <topic>"`.

**Archive an outdated learning:**
Move it to `knowledge-base/project/learnings/archive/`: `mkdir -p knowledge-base/project/learnings/archive && git add knowledge-base/project/learnings/<category>/<file>.md && git mv knowledge-base/project/learnings/<category>/<file>.md knowledge-base/project/learnings/archive/`. The `git add` ensures the file is tracked before `git mv`.Commit with `git commit -m "learning: archive <topic>"`.

**Delete a learning:**
Only with user confirmation. `git rm knowledge-base/project/learnings/<category>/<file>.md` and commit.

### Managing Constitution Rules (Edit/Remove)

**Edit a rule:** Read `knowledge-base/project/constitution.md`, find the rule, modify it, commit with `git commit -m "constitution: update <domain> <category> rule"`.

**Remove a rule:** Read `knowledge-base/project/constitution.md`, remove the bullet point, commit with `git commit -m "constitution: remove <domain> <category> rule"`.

### Automatic Consolidation & Archival (feature branches)

On feature branches (`feat-*`, `feat/*`, `fix-*`, or `fix/*`), consolidation runs automatically after the learning is documented and before the decision menu. This ensures artifacts are always cleaned up as part of the standard compound flow, rather than relying on a manual menu choice.

The automatic consolidation:

1. **Discovers artifacts** -- extracts the feature slug by stripping `feat/`, `feat-`, `fix/`, or `fix-` prefix from the branch name, then globs `knowledge-base/project/{brainstorms,plans}/*<slug>*` and `knowledge-base/project/specs/feat-<slug>/` (excluding `*/archive/`)
2. **Extracts knowledge** -- a single agent reads all artifacts and proposes updates to `constitution.md`, component docs, and project `README.md`
3. **Approval flow** -- **Headless mode:** auto-accept all proposals (idempotency still checked via substring match). **Interactive mode:** proposals presented one at a time with Accept/Skip/Edit; idempotency checked via substring match
4. **Archives sources** -- runs `bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` to move all discovered artifacts to `archive/` subdirectories via `git mv` with `YYYYMMDD-HHMMSS` timestamp prefix. **Headless mode:** auto-confirm archival without prompting
5. **Single commit** -- project edits and archival moves committed together for clean `git revert`

If no artifacts are found for the feature slug, consolidation is skipped silently. See the `compound-capture` skill for full implementation details.

### Worktree Cleanup (Manual)

**Headless mode:** If `HEADLESS_MODE=true`, skip worktree cleanup entirely (cleanup-merged handles this post-merge).

**Interactive mode:** At the end, if on a feature branch:

**Question:** "Feature complete? Clean up worktree?"

**If user says yes:**

```bash
git worktree remove .worktrees/feat-<name>
```

**If user says no:** Done

## What It Captures

- **Problem symptom**: Exact error messages, observable behavior
- **Investigation steps tried**: What didn't work and why
- **Root cause analysis**: Technical explanation
- **Working solution**: Step-by-step fix with code examples
- **Prevention strategies**: How to avoid in future
- **Session errors**: Process mistakes, failed commands, and wrong approaches from the session
- **Cross-references**: Links to related issues and docs

## Preconditions

<preconditions enforcement="advisory">
  <check condition="problem_solved">
    Problem has been solved (not in-progress)
  </check>
  <check condition="solution_verified">
    Solution has been verified working
  </check>
  <check condition="non_trivial">
    Non-trivial problem (not simple typo or obvious error)
  </check>
</preconditions>

## What It Creates

**Organized documentation:**

- File: `knowledge-base/project/learnings/[category]/[filename].md`

**Categories auto-detected from problem:**

- build-errors/
- test-failures/
- runtime-errors/
- performance-issues/
- database-issues/
- security-issues/
- ui-bugs/
- integration-issues/
- logic-errors/

## Success Output

```text
✓ Parallel documentation generation complete

Primary Subagent Results:
  ✓ Context Analyzer: Identified performance_issue in brief_system
  ✓ Solution Extractor: Extracted 3 code fixes
  ✓ Related Docs Finder: Found 2 related issues
  ✓ Prevention Strategist: Generated test cases
  ✓ Documentation Writer: Classified to performance-issues/, created complete markdown

Specialized Agent Reviews (Auto-Triggered):
  ✓ performance-oracle: Validated query optimization approach
  ✓ kieran-rails-reviewer: Code examples meet Rails standards
  ✓ code-simplicity-reviewer: Solution is appropriately minimal
  ✓ every-style-editor: Documentation style verified

File created:
- knowledge-base/project/learnings/performance-issues/n-plus-one-brief-generation.md

This documentation will be searchable for future reference when similar
issues occur in the Email Processing or Brief System modules.

What's next?  (Headless mode: auto-selects "Continue workflow")
1. Continue workflow (recommended)
2. Add to Required Reading
3. Link related documentation
4. Update other references
5. View documentation
6. Other
```

## The Compounding Philosophy

This creates a compounding knowledge system:

1. First time you solve "N+1 query in brief generation" → Research (30 min)
2. Document the solution → knowledge-base/project/learnings/performance-issues/n-plus-one-briefs.md (5 min)
3. Next time similar issue occurs → Quick lookup (2 min)
4. Knowledge compounds → Team gets smarter

The feedback loop:

```text
Build → Test → Find Issue → Research → Improve → Document → Validate → Deploy
    ↑                                                                      ↓
    └──────────────────────────────────────────────────────────────────────┘
```

**Each unit of engineering work should make subsequent units of work easier—not harder.**

## Auto-Invoke

<auto_invoke> <trigger_phrases> - "that worked" - "it's fixed" - "working now" - "problem solved" </trigger_phrases>

<manual_override> Use `skill: soleur:compound` [context] to document immediately without waiting for auto-detection. </manual_override> </auto_invoke>

## Routes To

`compound-capture` skill

## Applicable Specialized Agents

Based on problem type, these agents can enhance documentation:

### Code Quality & Review

- **kieran-rails-reviewer**: Reviews code examples for Rails best practices
- **code-simplicity-reviewer**: Ensures solution code is minimal and clear
- **pattern-recognition-specialist**: Identifies anti-patterns or repeating issues

### Specific Domain Experts

- **performance-oracle**: Analyzes performance_issue category solutions
- **security-sentinel**: Reviews security_issue solutions for vulnerabilities
- **data-integrity-guardian**: Reviews database_issue migrations and queries

### Enhancement & Documentation

- **best-practices-researcher**: Enriches solution with industry best practices
- **every-style-editor**: Reviews documentation style and clarity
- **framework-docs-researcher**: Links to Rails/gem documentation references

### When to Invoke

- **Auto-triggered** (optional): Agents can run post-documentation for enhancement
- **Manual trigger**: User can invoke agents after `soleur:compound` completes for deeper review

## Related Commands

- `/research [topic]` - Deep investigation (searches knowledge-base/project/learnings/ for patterns)
- `soleur:plan` skill - Planning workflow (references documented solutions)
