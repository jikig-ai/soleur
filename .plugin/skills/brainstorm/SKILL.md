---
name: brainstorm
description: "Explore requirements and approaches through collaborative dialogue before planning implementation. Answers WHAT to build through structured idea exploration, domain assessment, and approach evaluation."
triggers:
- brainstorm
- explore idea
- what should we build
- feature exploration
- brainstorm feature
---

# Brainstorm a Feature or Improvement

**Note: The current year is 2026.** Use this when dating brainstorm documents.

Brainstorming helps answer **WHAT** to build through collaborative dialogue. It precedes the plan skill, which answers **HOW** to build it.

**Process knowledge:** Read `.plugin/skills/brainstorm/references/` files for detailed question techniques, approach exploration patterns, and YAGNI principles.

## Feature Description

If the user has not provided a feature description in the conversation, ask: "What would you like to explore? Please describe the feature, problem, or improvement you're thinking about."

Do not proceed until you have a feature description from the user.

## Execution Flow

### Phase 0: Setup and Assess Requirements Clarity

**Load project conventions:**

```bash
if [[ -f "AGENTS.md" ]]; then
  cat AGENTS.md
fi
```

Read `AGENTS.md` if it exists — apply project conventions during brainstorming.

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, and `knowledge-base/` exists, create the worktree immediately (pulling Phase 3 forward) so that dialogue and file writes happen on a feature branch. Derive the feature name from the feature description (kebab-case). Run worktree creation via terminal, then `cd` into it. If `knowledge-base/` does not exist, abort with: "Error: brainstorm cannot run on main/master without knowledge-base/. Checkout a feature branch first."

Evaluate whether brainstorming is needed based on the feature description.

**Clear requirements indicators:**

- Specific acceptance criteria provided
- Referenced existing patterns to follow
- Described exact expected behavior
- Constrained, well-defined scope

**If requirements are already clear:**
Ask the user: "Your requirements seem clear enough to skip brainstorming. How would you like to proceed?"

Options:

1. **Plan first** — Use the plan skill to create a plan before implementing
2. **Brainstorm anyway** — Continue exploring the idea

### Phase 0.5: Domain Leader Assessment

Assess whether the feature description has implications for specific business domains. Domain leaders participate in brainstorming when their domain is relevant.

**Read `.plugin/skills/brainstorm/references/brainstorm-domain-config.md` now** to load the Domain Config table with all 8 domain rows (Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support). Each row contains: Assessment Question, Leader, Routing Prompt, Options, and Task Prompt.

#### Processing Instructions

1. Read the feature description and assess relevance against each domain in the table using the Assessment Question column.
2. For each relevant domain, use the `delegate` tool to spawn and delegate tasks to domain leader agents in parallel. Use the Task Prompt from the table, substituting `{desc}` with the feature description. Weave each leader's assessment into the brainstorm dialogue alongside repo research findings.
3. If the user explicitly requests a brand workshop or validation workshop, follow the named workshop section below.
4. If no domains are relevant, continue to Phase 1.

#### Brand Workshop (if explicitly requested)

**Read `.plugin/skills/brainstorm/references/brainstorm-brand-workshop.md` now** for the full Brand Workshop procedure. Follow all steps in the reference file, then STOP — do not proceed to Phase 1.

#### Validation Workshop (if explicitly requested)

**Read `.plugin/skills/brainstorm/references/brainstorm-validation-workshop.md` now** for the full Validation Workshop procedure. Follow all steps in the reference file, then STOP — do not proceed to Phase 1.

### Phase 1: Understand the Idea

#### 1.0 External Platform Verification (if applicable)

If the feature description references an external platform, marketplace, or service, fetch the URL first before launching any research. Classify by: (1) self-service or waitlist? (2) discovery surface or procurement layer? (3) does it accept the product category? (4) quantitative limits? (5) does the limit cover the scope? This 30-second gate prevents spawning agents that analyze a false premise.

#### 1.1 Research (Context Gathering)

Use the `delegate` tool to run research agents **in parallel**:

```
spawn: ["repo-research", "learnings-research"]
delegate:
  repo-research: "Research the repository for existing patterns, similar features, and AGENTS.md guidance related to: {feature_description}"
  learnings-research: "Search knowledge-base/project/learnings/ for documented solutions, past gotchas, and lessons learned related to: {feature_description}"
```

If either agent fails or returns empty, proceed with whatever results are available. Weave findings naturally into your first question.

#### 1.2 Collaborative Dialogue

Ask questions **one at a time** to understand the idea.

**Guidelines:**

- Prefer multiple choice when natural options exist
- Start broad (purpose, users) then narrow (constraints, edge cases)
- Validate assumptions explicitly
- Ask about success criteria
- If the feature involves an external API, verify its current pricing/tier capabilities via live docs

**Exit condition:** Continue until the idea is clear OR user says "proceed"

### Phase 2: Explore Approaches

Propose **2-3 concrete approaches** based on research and conversation.

For each approach, provide:

- Brief description (2-3 sentences)
- Pros and cons
- When it's best suited

Lead with your recommendation and explain why. Apply YAGNI — prefer simpler solutions.

Ask the user which approach they prefer.

**Domain re-assessment.** If the scope has materially changed from the original feature description, re-run Phase 0.5 domain assessment for any domains not already consulted.

### Phase 3: Create Worktree (if knowledge-base/ exists)

**IMPORTANT:** Create the worktree BEFORE writing any files so all artifacts go on the feature branch.

**Check for knowledge-base directory:**

```bash
if [[ -d "knowledge-base" ]]; then
  # knowledge-base exists, create worktree first
fi
```

**If knowledge-base/ exists:**

1. **Get feature name** from user or derive from brainstorm topic (kebab-case)
2. **Create worktree:**

   ```bash
   ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>
   ```

3. **Set worktree path** for subsequent file operations
4. **Create draft PR:**

   ```bash
   cd .worktrees/feat-<name>
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
   ```

### Phase 3.5: Capture the Design

Write the brainstorm document.

**File path:**

- If worktree exists: `<worktree-path>/knowledge-base/project/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`
- If no worktree: `knowledge-base/project/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`

**Document structure:** Key sections: What We're Building, Why This Approach, Key Decisions, Open Questions.

If domain leaders participated in Phase 0.5, include a `## Domain Assessments` section after "Open Questions" with structured carry-forward data:

```markdown
## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### [Domain Name]

**Summary:** [1-2 sentence assessment summary from domain leader]
```

If domain leaders reported capability gaps, include a `## Capability Gaps` section listing each gap.

### Phase 3.6: Create Spec and Issue (if worktree exists)

**If worktree was created:**

1. **Check for existing issue reference** in the feature description — parse for `#N` patterns. If found, validate via `gh issue view <number> --json state`.
2. **Create GitHub issue** if no valid existing issue:

   ```bash
   gh issue create --title "feat: <Feature Title>" --milestone "Post-MVP / Later" --body "..."
   ```

3. **Generate spec.md** — fill in Problem Statement, Goals, Non-Goals, Functional Requirements, Technical Requirements from brainstorm.
4. **Save spec.md** to `<worktree-path>/knowledge-base/project/specs/feat-<name>/spec.md`
5. **Commit and push** all brainstorm artifacts:

   ```bash
   git add knowledge-base/project/brainstorms/ knowledge-base/project/specs/feat-<name>/
   git commit -m "docs: capture brainstorm and spec for feat-<name>"
   git push
   ```

6. **Create tracking issues** for deferred items found in Key Decisions or Non-Goals.
7. **Switch to worktree** for subsequent work.

### Phase 4: Next Steps

After brainstorm is complete, ask the user:

"Brainstorm captured. What would you like to do next?"

1. **Plan** — Create an implementation plan (use the plan skill)
2. **Refine** — Continue exploring a specific aspect
3. **Done** — Stop here, artifacts are committed

If the user chooses Plan, provide the brainstorm document path as context and proceed to planning.
