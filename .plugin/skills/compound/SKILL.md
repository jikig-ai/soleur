---
name: compound
description: "Document a recently solved problem to compound your team's knowledge. Captures problem solutions in knowledge-base/project/learnings/ with parallel subagent analysis."
triggers:
- compound
- document learning
- capture learning
- that worked
- it's fixed
- problem solved
- working now
---

# Compound — Document What You Learned

Coordinate multiple subagents working in parallel to document a recently solved problem.

## Purpose

Captures problem solutions while context is fresh, creating structured documentation in `knowledge-base/project/learnings/` with YAML frontmatter for searchability. Uses parallel subagents for maximum efficiency.

**Why "compound"?** Each documented solution compounds your team's knowledge. The first time you solve a problem takes research. Document it, and the next occurrence takes minutes. Knowledge compounds.

## Usage

If the user has not described the problem that was solved, ask: "What problem did you just solve? Please describe briefly, or I'll analyze the recent conversation context."

## Phase 0: Setup

**Load project conventions:**

```bash
if [[ -f "AGENTS.md" ]]; then
  cat AGENTS.md
fi
```

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort immediately with: "Error: compound cannot run on main/master. Checkout a feature branch first."

## Phase 0.5: Session Error Inventory (MANDATORY)

HARD RULE: Before writing any learning, enumerate ALL errors encountered in this session. Output a numbered list. This step cannot be skipped even if the session felt clean.

**Check for session-state.md:** Run `git branch --show-current`. If on a `feat-*` branch, check if `knowledge-base/project/specs/feat-<name>/session-state.md` exists. If so, read it and include any forwarded errors from `### Errors`.

Include:

- Errors forwarded from session-state.md (if present)
- Skill or command not found errors
- Wrong file paths, directories, or branch confusion
- Failed bash commands or unexpected exit codes
- API errors or unexpected responses
- Wrong assumptions that required backtracking
- Tools or agents that returned errors
- Permission denials

If genuinely no errors occurred, output: "Session error inventory: none detected."

### Post-Documentation Verification Gate (MANDATORY)

After the learning file is written, read it back and verify:

1. If Phase 0.5 produced a non-empty error inventory, the learning file MUST contain a `## Session Errors` section with at least as many items as the inventory.
2. For each session error, the learning MUST include a `**Prevention:**` line.
3. If verification fails, append the missing errors immediately.

### Error-to-Workflow Feedback (MANDATORY)

After verifying session errors, determine if any error warrants a workflow change. For each session error, ask: "Could a rule or skill instruction have prevented this?"

- If yes, produce a proposal (rule text + enforcement tier) and feed it into Constitution Promotion.
- If no (one-off or already covered), skip.

## Phase 1: Parallel Subagent Execution

Use the `delegate` tool to run specialized subagents in parallel:

```
spawn: ["context-analyzer", "solution-extractor", "related-docs", "prevention-strategist"]
delegate:
  context-analyzer: "Extract conversation history. Identify problem type, component, symptoms. Return YAML frontmatter skeleton for: {problem_description}"
  solution-extractor: "Analyze all investigation steps. Identify root cause. Extract working solution with code examples for: {problem_description}"
  related-docs: "Search knowledge-base/project/learnings/ for related documentation. Find cross-references and related GitHub issues for: {problem_description}"
  prevention-strategist: "Develop prevention strategies. Create best practices guidance. Generate test cases if applicable for: {problem_description}"
```

## Phase 2: Documentation Assembly

After subagents complete, assemble the learning document:

1. **Determine category** from problem type:
   - build-errors/, test-failures/, runtime-errors/, performance-issues/
   - database-issues/, security-issues/, ui-bugs/, integration-issues/, logic-errors/
   - workflow-patterns/ (for process/workflow learnings)

2. **Create the file** at `knowledge-base/project/learnings/YYYY-MM-DD-<topic>.md`:

   ```markdown
   # Learning: [topic]

   ## Problem
   [What we encountered — exact error messages, observable behavior]

   ## Investigation
   [Steps tried — what didn't work and why]

   ## Root Cause
   [Technical explanation]

   ## Solution
   [Step-by-step fix with code examples]

   ## Prevention
   [How to avoid in future]

   ## Session Errors
   [Process mistakes from Phase 0.5 inventory, each with **Prevention:** line]

   ## Tags
   category: [category]
   module: [module]
   ```

3. **Validate** YAML frontmatter and format.

## Phase 1.5: Deviation Analyst (Sequential)

After documentation is written, scan the session for workflow deviations against hard rules.

### Procedure

1. **Gather rules.** Read `AGENTS.md` and extract `## Hard Rules` and `## Workflow Gates` items.

2. **Gather session evidence.** Check session-state.md (if present) and scan conversation for actions.

3. **Detect deviations.** For each hard rule, check if session evidence shows a violation.

4. **Propose enforcement.** For each deviation:

   ```text
   ### Deviation: [short description]
   - **Rule violated:** [exact text from AGENTS.md]
   - **Evidence:** [what happened in the session]
   - **Proposed enforcement:** [skill instruction or prose rule]
   ```

5. **Feed into learning document.** Add each deviation to `## Session Errors`.

6. **Rule budget count.** Count rules in `AGENTS.md`: `grep -c '^- ' AGENTS.md`. If > 100, warn about budget.

**Empty case:** If no deviations, output: "Deviation Analyst: no violations found." followed by rule budget count.

## Phase 3: Knowledge Base Integration

### Constitution Promotion

After saving the learning, present proposals:

**1. Deviation Analyst proposals (if any):** Present each with Accept/Skip/Edit options.

**2. Constitution promotion:** Ask the user: "Promote anything to constitution?"

If yes:

1. Show recent learnings (last 5 from `knowledge-base/project/learnings/`)
2. User selects which learning to promote
3. Ask: "Which domain? (Code Style / Architecture / Testing)"
4. Ask: "Which category? (Always / Never / Prefer)"
5. User writes the principle (one line, actionable)
6. Append to `knowledge-base/project/constitution.md` under the correct section
7. Commit: `git commit -m "constitution: add <domain> <category> principle"`

### Route Learning to Definition

After constitution promotion, route the captured learning to the skill or agent definition that was active in the session.

1. Detect which skills or agents were invoked in this conversation
2. Route **two categories**: solution insight (main learning) and error prevention (session errors → skill instructions)
3. User confirms with Accept/Skip/Edit

**Graceful degradation:** Skip if `plugins/soleur/` does not exist or no components detected.

### Automatic Consolidation and Archival (feature branches)

On feature branches (`feat-*`, `fix-*`), consolidation runs automatically:

1. **Discover artifacts** — glob `knowledge-base/project/{brainstorms,plans}/*<slug>*` and `knowledge-base/project/specs/feat-<slug>/`
2. **Extract knowledge** — a subagent reads all artifacts and proposes updates to constitution.md, component docs, README.md
3. **Approval flow** — proposals presented one at a time with Accept/Skip/Edit
4. **Archive sources** — run `bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`
5. **Single commit** — edits and archival committed together

If no artifacts found for the feature slug, skip silently.

## Phase 4: Wrap Up

Ask the user: "What's next?"

1. **Continue workflow** (recommended)
2. **Add to Required Reading**
3. **Link related documentation**
4. **View documentation**
5. **Other**

## What It Captures

- **Problem symptom**: Exact error messages, observable behavior
- **Investigation steps**: What didn't work and why
- **Root cause analysis**: Technical explanation
- **Working solution**: Step-by-step fix with code examples
- **Prevention strategies**: How to avoid in future
- **Session errors**: Process mistakes, failed commands, wrong approaches
- **Cross-references**: Links to related issues and docs

## Preconditions

- Problem has been solved (not in-progress)
- Solution has been verified working
- Non-trivial problem (not simple typo or obvious error)

## The Compounding Philosophy

```text
Build → Test → Find Issue → Research → Improve → Document → Validate → Deploy
    ↑                                                                      ↓
    └──────────────────────────────────────────────────────────────────────┘
```

**Each unit of engineering work should make subsequent units of work easier — not harder.**
