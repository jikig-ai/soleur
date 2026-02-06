---
name: soleur:compound
description: Document a recently solved problem to compound your team's knowledge
argument-hint: "[optional: brief context about the fix]"
---

# /compound

Coordinate multiple subagents working in parallel to document a recently solved problem.

## Purpose

Captures problem solutions while context is fresh, creating structured documentation in `docs/solutions/` with YAML frontmatter for searchability and future reference. Uses parallel subagents for maximum efficiency.

**Why "compound"?** Each documented solution compounds your team's knowledge. The first time you solve a problem takes research. Document it, and the next occurrence takes minutes. Knowledge compounds.

## Usage

```bash
/soleur:compound                    # Document the most recent fix
/soleur:compound [brief context]    # Provide additional context hint
```

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
   - Searches `specs/solutions/` for related documentation
   - Identifies cross-references and links
   - Finds related GitHub issues
   - Returns: Links and relationships

### 4. **Prevention Strategist** (Parallel)
   - Develops prevention strategies
   - Creates best practices guidance
   - Generates test cases if applicable
   - Returns: Prevention/testing content

### 5. **Category Classifier** (Parallel)
   - Determines optimal `specs/solutions/` category
   - Validates category against schema
   - Suggests filename based on slug
   - Returns: Final path and filename

### 6. **Documentation Writer** (Parallel)
   - Assembles complete markdown file
   - Validates YAML frontmatter
   - Formats content for readability
   - Creates the file in correct location

### 7. **Optional: Specialized Agent Invocation** (Post-Documentation)
   Based on problem type detected, automatically invoke applicable agents:
   - **performance_issue** → `performance-oracle`
   - **security_issue** → `security-sentinel`
   - **database_issue** → `data-integrity-guardian`
   - **test_failure** → `cora-test-reviewer`
   - Any code-heavy issue → `kieran-rails-reviewer` + `code-simplicity-reviewer`

## Knowledge Base Integration

**If knowledge-base/ directory exists, compound saves learnings there and offers constitution promotion:**

### Save Learning to Knowledge Base

```bash
if [[ -d "knowledge-base" ]]; then
  # Save learning to knowledge-base/learnings/
  learning_file="knowledge-base/learnings/$(date +%Y-%m-%d)-<topic>.md"
else
  # Fall back to docs/solutions/
  learning_file="docs/solutions/<category>/<topic>.md"
fi
```

**Learning format for knowledge-base/learnings/:**

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

### Constitution Promotion (Manual)

After saving the learning, prompt the user:

**Question:** "Promote anything to constitution?"

**If user says yes:**
1. Show recent learnings (last 5 from `knowledge-base/learnings/`)
2. User selects which learning to promote
3. Ask: "Which domain? (Code Style / Architecture / Testing)"
4. Ask: "Which category? (Always / Never / Prefer)"
5. User writes the principle (one line, actionable)
6. Append to `knowledge-base/constitution.md` under the correct section
7. Commit: `git commit -m "constitution: add <domain> <category> principle"`

**If user says no:** Continue to next step

### Worktree Cleanup (Manual)

At the end, if on a feature branch:

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

- File: `specs/solutions/[category]/[filename].md`

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

```
✓ Parallel documentation generation complete

Primary Subagent Results:
  ✓ Context Analyzer: Identified performance_issue in brief_system
  ✓ Solution Extractor: Extracted 3 code fixes
  ✓ Related Docs Finder: Found 2 related issues
  ✓ Prevention Strategist: Generated test cases
  ✓ Category Classifier: docs/solutions/performance-issues/
  ✓ Documentation Writer: Created complete markdown

Specialized Agent Reviews (Auto-Triggered):
  ✓ performance-oracle: Validated query optimization approach
  ✓ kieran-rails-reviewer: Code examples meet Rails standards
  ✓ code-simplicity-reviewer: Solution is appropriately minimal
  ✓ every-style-editor: Documentation style verified

File created:
- docs/solutions/performance-issues/n-plus-one-brief-generation.md

This documentation will be searchable for future reference when similar
issues occur in the Email Processing or Brief System modules.

What's next?
1. Continue workflow (recommended)
2. Link related documentation
3. Update other references
4. View documentation
5. Other
```

## The Compounding Philosophy

This creates a compounding knowledge system:

1. First time you solve "N+1 query in brief generation" → Research (30 min)
2. Document the solution → docs/solutions/performance-issues/n-plus-one-briefs.md (5 min)
3. Next time similar issue occurs → Quick lookup (2 min)
4. Knowledge compounds → Team gets smarter

The feedback loop:

```
Build → Test → Find Issue → Research → Improve → Document → Validate → Deploy
    ↑                                                                      ↓
    └──────────────────────────────────────────────────────────────────────┘
```

**Each unit of engineering work should make subsequent units of work easier—not harder.**

## Auto-Invoke

<auto_invoke> <trigger_phrases> - "that worked" - "it's fixed" - "working now" - "problem solved" </trigger_phrases>

<manual_override> Use /soleur:compound [context] to document immediately without waiting for auto-detection. </manual_override> </auto_invoke>

## Routes To

`compound-docs` skill

## Applicable Specialized Agents

Based on problem type, these agents can enhance documentation:

### Code Quality & Review
- **kieran-rails-reviewer**: Reviews code examples for Rails best practices
- **code-simplicity-reviewer**: Ensures solution code is minimal and clear
- **pattern-recognition-specialist**: Identifies anti-patterns or repeating issues

### Specific Domain Experts
- **performance-oracle**: Analyzes performance_issue category solutions
- **security-sentinel**: Reviews security_issue solutions for vulnerabilities
- **cora-test-reviewer**: Creates test cases for prevention strategies
- **data-integrity-guardian**: Reviews database_issue migrations and queries

### Enhancement & Documentation
- **best-practices-researcher**: Enriches solution with industry best practices
- **every-style-editor**: Reviews documentation style and clarity
- **framework-docs-researcher**: Links to Rails/gem documentation references

### When to Invoke
- **Auto-triggered** (optional): Agents can run post-documentation for enhancement
- **Manual trigger**: User can invoke agents after /soleur:compound completes for deeper review

## Related Commands

- `/research [topic]` - Deep investigation (searches docs/solutions/ for patterns)
- `/soleur:plan` - Planning workflow (references documented solutions)
