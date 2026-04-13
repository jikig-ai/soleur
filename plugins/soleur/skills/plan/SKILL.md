---
name: plan
description: "This skill should be used when transforming feature descriptions into well-structured project plans following conventions."
---

# Create a plan for a new feature or bug fix

## Introduction

**Note: The current year is 2026.** Use this when dating plans and searching for recent documentation.

Transform feature descriptions, bug reports, or improvement ideas into well-structured markdown files issues that follow project conventions and best practices. This command provides flexible detail levels to match your needs.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If the feature description above is empty, ask the user:** "What would you like to plan? Please describe the feature, bug fix, or improvement you have in mind."

Do not proceed until you have a clear feature description from the user.

### 0. Load Knowledge Base Context (if exists)

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort immediately with: "Error: plan cannot run on main/master. Checkout a feature branch first." This check fires in all modes as defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI).

**Check for knowledge-base directory and load context:**

Check if `knowledge-base/` directory exists. If it does:

1. Run `git branch --show-current` to get the current branch name
2. If the branch starts with `feat-`, read `knowledge-base/project/specs/<branch-name>/spec.md` if it exists

**If knowledge-base/ exists:**

1. Read `CLAUDE.md` if it exists - apply project conventions during planning
2. If `# Project Constitution` heading is NOT already in context, read `knowledge-base/project/constitution.md` - use principles to guide planning decisions. Skip if already loaded (e.g., from a preceding `/soleur:brainstorm`).
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/project/specs/feat-<name>/spec.md` if it exists - use as planning input
5. Announce: "Loaded constitution and spec for `feat-<name>`"

**If knowledge-base/ does NOT exist:**

- Continue with standard planning flow

### 0.5. Idea Refinement

**Check for brainstorm output first:**

Before asking questions, look for recent brainstorm documents in `knowledge-base/project/brainstorms/` that match this feature:

```bash
ls -la knowledge-base/project/brainstorms/*.md 2>/dev/null | head -10
```

**Relevance criteria:** A brainstorm is relevant if:

- The topic (from filename or YAML frontmatter) semantically matches the feature description
- Created within the last 14 days
- If multiple candidates match, use the most recent one

**If a relevant brainstorm exists:**

1. Read the brainstorm document
2. Announce: "Found brainstorm from [date]: [topic]. Using as context for planning."
3. Extract key decisions, chosen approach, and open questions
4. **Skip the idea refinement questions below** - the brainstorm already answered WHAT to build
5. Proceed to Phase 1 -- **all sub-phases still apply** (1, 1.5, 1.5b, 1.6). Having a brainstorm skips idea refinement only, not community discovery or research.

**If multiple brainstorms could match:**
Use **AskUserQuestion tool** to ask which brainstorm to use, or whether to proceed without one.

**If no brainstorm found (or not relevant), run idea refinement:**

Refine the idea through collaborative dialogue using the **AskUserQuestion tool**:

- Ask questions one at a time to understand the idea fully
- Prefer multiple choice questions when natural options exist
- Focus on understanding: purpose, constraints and success criteria
- **Directional ambiguity gate:** If the task involves merging, moving, or restructuring (A into B vs B into A), explicitly confirm the direction with the user before proceeding -- even in pipeline mode. Code evidence can be wrong (see learning: 2026-03-17-planning-direction-confirmation-required)
- Continue until the idea is clear OR user says "proceed"

**Gather signals for research decision.** During refinement, note:

- **User's familiarity**: Do they know the codebase patterns? Are they pointing to examples?
- **User's intent**: Speed vs thoroughness? Exploration vs execution?
- **Topic risk**: Security, payments, external APIs warrant more caution
- **Uncertainty level**: Is the approach clear or open-ended?

**Skip option:** If the feature description is already detailed, offer:
"Your description is clear. Should I proceed with research, or would you like to refine it further?"

## Main Tasks

### 1. Local Research (Always Runs - Parallel)

<thinking>
First, I need to understand the project's conventions, existing patterns, and any documented learnings. This is fast and local - it informs whether external research is needed.
</thinking>

Run these agents **in parallel** to gather local context:

- Task repo-research-analyst(feature_description)
- Task learnings-researcher(feature_description)

**What to look for:**

- **Repo research:** existing patterns, CLAUDE.md guidance, technology familiarity, pattern consistency
- **Learnings:** documented solutions in `knowledge-base/project/learnings/` that might apply (gotchas, patterns, lessons learned)

These findings inform the next step.

### 1.5. Community Discovery Check (Conditional)

**Read `plugins/soleur/skills/plan/references/plan-community-discovery.md` now** for the full community discovery procedure (stack detection, coverage gap check, agent-finder). Skip if no uncovered stacks detected.

### 1.5b. Functional Overlap Check

**Read `plugins/soleur/skills/plan/references/plan-functional-overlap.md` now** for the functional overlap check procedure (always runs, spawns functional-discovery agent).

### 1.6. Research Decision

Based on signals from Step 0 and findings from Step 1, decide on external research.

**High-risk topics → always research.** Security, payments, external APIs, data privacy. The cost of missing something is too high. This takes precedence over speed signals.

**Strong local context → skip external research.** Codebase has good patterns, CLAUDE.md has guidance, user knows what they want. External research adds little value.

**Uncertainty or unfamiliar territory → research.** User is exploring, codebase has no examples, new technology. External perspective is valuable.

**Announce the decision and proceed.** Brief explanation, then continue. User can redirect if needed.

Examples:

- "Your codebase has solid patterns for this. Proceeding without external research."
- "This involves payment processing, so I'll research current best practices first."

### 1.6b. External Research (Conditional)

**Only run if Step 1.6 indicates external research is valuable.**

Run these agents in parallel:

- Task best-practices-researcher(feature_description)
- Task framework-docs-researcher(feature_description)

### 1.7. Consolidate Research

After all research steps complete, consolidate findings:

- Document relevant file paths from repo research (e.g., `app/services/example_service.rb:42`)
- **Include relevant institutional learnings** from `knowledge-base/project/learnings/` (key insights, gotchas to avoid)
- Note external documentation URLs and best practices (if external research was done)
- List related issues or PRs discovered
- Capture CLAUDE.md conventions

**Optional validation:** Briefly summarize findings and ask if anything looks off or missing before proceeding to planning.

### 2. Issue Planning & Structure

<thinking>
Think like a product manager - what would make this issue clear and actionable? Consider multiple perspectives
</thinking>

**Title & Categorization:**

- [ ] Draft clear, searchable issue title using conventional format (e.g., `feat: Add user authentication`, `fix: Cart total calculation`)
- [ ] Determine issue type: enhancement, bug, refactor
- [ ] Convert title to filename: add today's date prefix, strip prefix colon, kebab-case, add `-plan` suffix
  - Example: `feat: Add User Authentication` → `2026-01-21-feat-add-user-authentication-plan.md`
  - Keep it descriptive (3-5 words after prefix) so plans are findable by context

**Stakeholder Analysis:**

- [ ] Identify who will be affected by this issue (end users, developers, operations)
- [ ] Consider implementation complexity and required expertise

**Content Planning:**

- [ ] Choose appropriate detail level based on issue complexity and audience
- [ ] List all necessary sections for the chosen template
- [ ] Gather supporting materials (error logs, screenshots, design mockups)
- [ ] Prepare code examples or reproduction steps if applicable, name the mock filenames in the lists
- [ ] When planning a directory rename, enumerate ALL files in the target directory as potential self-reference holders -- directory trees and conceptual prose derived from the directory name don't match path-pattern greps

### 2.5. Domain Review Gate

After generating the plan structure, assess which business domains this plan has implications for. This gate enforces constitution line 122: plans must receive cross-domain review before implementation.

**Step 1 — Domain Sweep:**

1. **Brainstorm carry-forward check:** If the brainstorm document (loaded in Phase 0.5) contains a `## Domain Assessments` section, carry forward the findings. Extract relevant domains and their summaries. Skip fresh assessment.

2. **Fresh assessment (if no brainstorm or no `## Domain Assessments` section):** Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. Assess all 8 domains against the plan content in a single LLM pass using each domain's Assessment Question. Use semantic assessment — not keyword matching.

3. **Spawn domain leaders:** For each domain assessed as relevant **except Product** (handled in Step 2), spawn the domain leader as a blocking Task using the Task Prompt from brainstorm-domain-config.md, substituting `{desc}` with the plan summary. Spawn in parallel if multiple are relevant.

4. **Collect findings:** Wait for all domain leader Tasks to complete. Each returns a brief structured assessment. If a domain leader Task fails (timeout, error), write partial findings for that domain with `Status: error` and continue with remaining domains.

**Step 2 — Product/UX Gate:**

After Step 1 completes, if Product domain was flagged as relevant, run the existing three-tier classification:

- **BLOCKING**: Creates new user-facing pages, multi-step user flows, or new UI components that users interact with (e.g., signup flows, dashboards, onboarding wizards, chat interfaces, prompts, modals, banners)
- **ADVISORY**: Modifies existing user-facing pages or components (e.g., layout changes, form updates, adding fields to existing screens)
- **NONE**: No user-facing impact

A plan that *discusses* UI concepts but *implements* orchestration changes (e.g., adding a UX gate to a skill) is NONE.

**Mechanical escalation (overrides subjective assessment):** Scan the plan's "Files to create" list. If any new file path matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, the tier is **BLOCKING** regardless of subjective assessment. Creating a new component file = new user-facing surface = UX review required. **Why:** In #1049, a notification prompt component was classified as ADVISORY because the agent judged it "not significant enough." The user had to manually trigger the UX gate post-plan.

**On BLOCKING:**

1. Run spec-flow-analyzer via Task with UI-flow-aware prompt: "Analyze the user flows in this plan. Map each screen, identify entry/exit points, dead ends, missing error states, and flows that drop the user. Focus on user journey completeness, not technical implementation."
2. Run CPO via Task with scoped prompt: "Assess the product implications of this plan: {plan summary}. Cross-reference against brand-guide.md and constitution.md. Identify product strategy concerns, flow gaps, and positioning issues. Output a structured advisory — do not use AskUserQuestion."
3. **Brainstorm carry-forward check.** Before invoking ux-design-lead, check the UX signal source. If the only UX validation is brainstorm carry-forward (brainstorm assessed the *idea*, not the *page design*), reject it: "Brainstorm validated the idea, not the page design. Proceeding to wireframes." Then continue to step 4. This check applies to BLOCKING tier only — ADVISORY and NONE tiers may still carry forward brainstorm UX findings.
4. Invoke ux-design-lead via Task with scoped prompt: "Create wireframes for these user flows: {flow list}. Platform: desktop. Fidelity: wireframe." The agent has its own Pencil MCP prerequisite check — if Pencil is unavailable, the agent will stop with an installation message. If the Task returns without wireframes (agent self-stopped), write `Pencil available: no` in the Domain Review section, add `ux-design-lead` to `**Skipped specialists:**` with the user's justification, and display: "ux-design-lead skipped (Pencil MCP not available). Consider running wireframes manually before implementation."
5. **Content Review Gate.** Check if any domain leader (CMO, CRO, CPO, or other) recommended a copywriter or content specialist in their Step 1 assessment. If yes: invoke copywriter agent via Task with prompt: "Review the planned page content for brand voice compliance, value proposition clarity, and messaging effectiveness. Reference brand-guide.md." If copywriter ran successfully, add `copywriter` to `**Agents invoked:**`. If user declines, add `copywriter` to `**Skipped specialists:**` with the user's reason. If copywriter agent fails (timeout, error), add `copywriter` to `**Skipped specialists:**` with note `(agent error — review manually)` and set `**Decision:** reviewed (partial)`. If no domain leader recommended a copywriter, skip this step silently. This gate also fires on ADVISORY tier when a domain leader recommended a copywriter — the recommendation is the signal, not the tier.
6. Phase 3 SpecFlow is skipped (spec-flow-analyzer already ran in step 1 with UI-aware prompt — avoids duplicate invocation).
7. If any agent in the pipeline fails (timeout, error), write partial findings with `Decision: reviewed (partial)`. **BLOCKING gate enforcement:** If the tier is BLOCKING and any required specialist (ux-design-lead, copywriter, spec-flow-analyzer) failed, do NOT silently proceed. Instead, use AskUserQuestion to present: "BLOCKING Product/UX Gate: [specialist] failed ([reason]). UX artifacts are required before implementation (AGENTS.md). How to proceed?" Options: (a) **Retry now** — re-invoke the failed agents, (b) **Skip with acknowledgment** — proceed without UX artifacts (user accepts the risk), (c) **Defer to next session** — save partial plan, run UX gate when agents are available. Record the user's choice in the Domain Review section. For ADVISORY tier or non-specialist agents, proceed silently with partial findings as before.

**On ADVISORY:**

1. If in pipeline/subagent context (plan file path was provided as argument, not interactive): auto-accept, write Product/UX Gate subsection with `Tier: advisory, Decision: auto-accepted (pipeline)`, proceed silently.
2. If interactive: display notice via AskUserQuestion: "This plan modifies existing UI. Run UX review?" Options: "Yes, run full review" / "Skip — I'll handle UX manually". Record choice.
3. If user chooses full review, run the BLOCKING pipeline above.
4. **Content Review Gate (ADVISORY).** Regardless of the UX review choice, if any domain leader recommended a copywriter or content specialist, run step 5 from the BLOCKING pipeline (Content Review Gate). The recommendation is the signal, not the tier — modifying existing copy still benefits from content review.

**On NONE:** Skip — no Product/UX Gate subsection needed beyond the domain sweep finding.

If Product domain was NOT flagged as relevant in the sweep, skip Step 2 entirely.

**Writing the `## Domain Review` section:**

After both steps complete, write the `## Domain Review` section to the plan file using the heading contract below.

**`## Domain Review` Heading Contract:**

```markdown
## Domain Review

**Domains relevant:** [comma-separated list] | none

### [Domain Name] (one subsection per relevant non-Product domain)

**Status:** reviewed | error
**Assessment:** [leader's structured assessment summary]

### Product/UX Gate (only if Product domain relevant and tier is BLOCKING or ADVISORY)

**Tier:** blocking | advisory
**Decision:** reviewed | reviewed (partial) | skipped | auto-accepted (pipeline)
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead, copywriter | [subset] | none
**Skipped specialists:** ux-design-lead (<reason>), copywriter (<reason>) | none
**Pencil available:** yes | no | N/A

#### Findings

[Agent findings summary]
```

When NO domains are relevant:

```markdown
## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.
```

Place after Acceptance Criteria, before Test Scenarios (or before the last major section). If the plan lacks an Acceptance Criteria heading, place before the last major section or at the end of the plan.

### 3. SpecFlow Analysis

**If spec-flow-analyzer was already invoked in Phase 2.5, skip this phase and proceed to Phase 4.**

After planning the issue structure, run SpecFlow Analyzer to validate and refine the feature specification. SpecFlow is especially valuable for CI/workflow and infrastructure changes where bash conditional logic can silently drop edge cases that human review misses.

- Task spec-flow-analyzer(feature_description, research_findings)

**SpecFlow Analyzer Output:**

- [ ] Review SpecFlow analysis results
- [ ] Incorporate any identified gaps or edge cases into the issue
- [ ] Update acceptance criteria based on SpecFlow findings

### 4. Choose Implementation Detail Level

**Read `plugins/soleur/skills/plan/references/plan-issue-templates.md` now** to load the three issue templates (MINIMAL, MORE, A LOT). Select the appropriate detail level based on complexity -- simpler is mostly better. Use the template structure from the reference file for the chosen level.

### 5. Issue Creation & Formatting

<thinking>
Apply best practices for clarity and actionability, making the issue easy to scan and understand
</thinking>

**Content Formatting:**

- [ ] Use clear, descriptive headings with proper hierarchy (##, ###)
- [ ] Include code examples in triple backticks with language syntax highlighting
- [ ] Add screenshots/mockups if UI-related (drag & drop or use image hosting)
- [ ] Use task lists (- [ ]) for trackable items that can be checked off
- [ ] Add collapsible sections for lengthy logs or optional details using `<details>` tags
- [ ] Apply appropriate emoji for visual scanning (🐛 bug, ✨ feature, 📚 docs, ♻️ refactor)

**Cross-Referencing:**

- [ ] Link to related issues/PRs using #number format
- [ ] Reference specific commits with SHA hashes when relevant
- [ ] Link to code using GitHub's permalink feature (press 'y' for permanent link)
- [ ] Mention relevant team members with @username if needed
- [ ] Add links to external resources with descriptive text

**Code & Examples:**

````markdown
# Good example with syntax highlighting and line references


```ruby
# app/services/user_service.rb:42
def process_user(user)

# Implementation here

end
```

# Collapsible error logs

<details>
<summary>Full error stacktrace</summary>

`Error details here...`

</details>
````

**AI-Era Considerations:**

- [ ] Account for accelerated development with AI pair programming
- [ ] Include prompts or instructions that worked well during research
- [ ] Note which AI tools were used for initial exploration (Claude, Copilot, etc.)
- [ ] Emphasize comprehensive testing given rapid implementation
- [ ] Document any AI-generated code that needs human review

### 6. Final Review & Submission

**Pre-submission Checklist:**

- [ ] Title is searchable and descriptive
- [ ] Labels accurately categorize the issue
- [ ] All template sections are complete
- [ ] Links and references are working
- [ ] Acceptance criteria are measurable
- [ ] Add names of files in pseudo code examples and todo lists
- [ ] Add an ERD mermaid diagram if applicable for new model changes
- [ ] **Browser task automation check:** Scan all tasks for steps labeled "manual", "browser", or "user must". If any task involves browser interaction (account creation, form submission, settings configuration, credential generation), rewrite it as a Playwright MCP automation step. The only genuinely manual browser steps are CAPTCHA solving and interactive OAuth consent -- and even those should be automated up to the CAPTCHA/consent gate, then handed to the user for that single interaction.
- [ ] **Deferral tracking check:** Scan the plan's "Alternative Approaches Considered" table and any "Non-Goals" or "Out of Scope" sections for items explicitly deferred to a later phase. For each deferred item, create a GitHub issue with: what was deferred, why, re-evaluation criteria, and milestone from `knowledge-base/product/roadmap.md`. A deferral without a tracking issue is invisible.

## Output Format

**Filename:** Use the date and kebab-case filename from Step 2 Title & Categorization.

```text
knowledge-base/project/plans/YYYY-MM-DD-<type>-<descriptive-name>-plan.md
```

Examples:

- ✅ `knowledge-base/project/plans/2026-01-15-feat-user-authentication-flow-plan.md`
- ✅ `knowledge-base/project/plans/2026-02-03-fix-checkout-race-condition-plan.md`
- ✅ `knowledge-base/project/plans/2026-03-10-refactor-api-client-extraction-plan.md`
- ❌ `knowledge-base/project/plans/2026-01-15-feat-thing-plan.md` (not descriptive - what "thing"?)
- ❌ `knowledge-base/project/plans/2026-01-15-feat-new-feature-plan.md` (too vague - what feature?)
- ❌ `knowledge-base/project/plans/2026-01-15-feat: user auth-plan.md` (invalid characters - colon and space)
- ❌ `knowledge-base/project/plans/feat-user-auth-plan.md` (missing date prefix)

## Save Tasks to Knowledge Base (if exists)

**After writing the plan to `knowledge-base/project/plans/`, also create tasks.md if knowledge-base/ exists:**

Check if `knowledge-base/` exists. If so, run `git branch --show-current` to get the current branch. If on a `feat-*` branch, create the spec directory with `mkdir -p knowledge-base/project/specs/<branch-name>`.

**If knowledge-base/ exists and on a feature branch:**

1. **Generate tasks.md** using `spec-templates` skill template:
   - Extract actionable tasks from the plan
   - Organize into phases (Setup, Core Implementation, Testing)
   - Use hierarchical numbering (1.1, 2.1, 2.1.1, etc.)

2. **Save tasks.md** to `knowledge-base/project/specs/feat-<name>/tasks.md`

3. **Announce:** "Tasks saved to `knowledge-base/project/specs/feat-<name>/tasks.md`. Use `skill: soleur:work` to implement."

4. **Commit and push plan artifacts:**

   After both the plan file and tasks.md are written, commit and push everything:

   ```bash
   git add knowledge-base/project/plans/ knowledge-base/project/specs/feat-<name>/tasks.md
   git commit -m "docs: create plan and tasks for feat-<name>"
   git push
   ```

   If the push fails (no network), print a warning but continue.

**If knowledge-base/ does NOT exist or not on feature branch:**

- Plan saved to `knowledge-base/project/plans/` only (current behavior)

## Plan Review (Always Runs)

After writing the plan file, automatically run `/plan_review <plan_file_path>` to get feedback from three specialized reviewers in parallel:

- **DHH Rails Reviewer** - Challenges overengineering, enforces simplicity
- **Kieran Rails Reviewer** - Checks correctness, completeness, convention adherence
- **Code Simplicity Reviewer** - Ensures YAGNI, flags unnecessary complexity

**After review completes:**

1. Present consolidated feedback (agreements first, then disagreements)
2. Ask: "Apply these changes?" (Yes / Partially / Skip)
3. If Yes: apply all changes to the plan file
4. If Partially: ask which changes to apply, then apply selected changes
5. If Skip: continue unchanged

## Exit Gate (direct invocation only)

**Pipeline detection:** If this skill is running inside a Task subagent (the conversation
contains a `RETURN CONTRACT` section from a Task delegation), skip the exit gate entirely.
Return the plan file path per the return contract. The calling pipeline handles compound
and lifecycle progression.

**If invoked directly by the user:**

1. Run `skill: soleur:compound` to capture learnings from the planning session.
   If compound finds nothing to capture, it will skip gracefully — do not block on this.
2. Verify all plan artifacts are committed and pushed. The Save Tasks section already
   committed the plan file and tasks.md. Run `git status --short` to check for any
   remaining uncommitted changes. If found:

   ```bash
   git add knowledge-base/project/plans/ knowledge-base/project/specs/feat-<name>/
   git commit -m "docs: plan artifacts for feat-<name>"
   git push
   ```

   If there are no uncommitted changes, skip the commit. If push fails (no network),
   warn and continue.
3. Display: "All artifacts are on disk. Run `/clear` then `/soleur:work` for maximum
   context headroom."

**Resume prompt (MANDATORY):** After the display message above, always output a copy-pasteable resume prompt block. This is required by AGENTS.md whenever `/clear` is mentioned. Format:

```text
Resume prompt (copy-paste after /clear):
/soleur:work <plan-path>. Branch: feat-<name>. Worktree: .worktrees/feat-<name>/. Issue: #<number>. PR: #<pr-number>. Plan reviewed, implementation next.
```

## Post-Generation Options

After plan review, use the **AskUserQuestion tool** to present these options:

**Resume prompt (MANDATORY — AGENTS.md Communication):** Before presenting the question, generate a copy-pasteable resume prompt containing: skill to run (`/soleur:work`), plan file path, branch name, worktree path, PR number, issue number, and a one-line summary of what was already done. Display it in a fenced code block so the user can paste it into a fresh session after `/clear`. This is the single most important output of the post-generation phase — without it, the user cannot resume in a new session without re-explaining context.

**Question:** "Plan reviewed and ready at `knowledge-base/project/plans/YYYY-MM-DD-<type>-<name>-plan.md`. Context is saved to disk — run `/clear` before `/soleur:work` for maximum headroom. What would you like to do next?"

**Options:**

1. **Open plan in editor** - Open the plan file for review
2. **Run `/deepen-plan`** - Enhance each section with parallel research agents (best practices, performance, UI)
3. **Start `soleur:work`** - Begin implementing this plan locally
4. **Start `soleur:work` on remote** - Begin implementing in Claude Code on the web (use `&` to run in background)
5. **Create Issue** - Create issue in project tracker (GitHub/Linear)
6. **Simplify** - Reduce detail level

Based on selection:

- **Open plan in editor** → Run `open knowledge-base/project/plans/<plan_filename>.md` to open the file in the user's default editor
- **`/deepen-plan`** → Call the /deepen-plan command with the plan file path to enhance with research
- **`soleur:work`** → Use `skill: soleur:work` with the plan file path
- **`soleur:work` on remote** → Use `skill: soleur:work` with `knowledge-base/project/plans/<plan_filename>.md` to start work in background for Claude Code web
- **Create Issue** → See "Issue Creation" section below
- **Simplify** → Ask "What should I simplify?" then regenerate simpler version
- **Other** (automatically provided) → Accept free text for rework or specific changes

**Note:** If running `soleur:plan` with ultrathink enabled, automatically use `skill: soleur:deepen-plan` after plan creation for maximum depth and grounding.

Loop back to options after Simplify or Other changes until user selects `soleur:work`.

## Issue Creation

When user selects "Create Issue", detect their project tracker from CLAUDE.md:

1. **Check for tracker preference** in user's CLAUDE.md (global or project):
   - Look for `project_tracker: github` or `project_tracker: linear`
   - Or look for mentions of "GitHub Issues" or "Linear" in their workflow section

2. **If GitHub:**

   Use the title and type from Step 2 (already in context - no need to re-read the file):

   ```bash
   gh issue create --title "<type>: <title>" --body-file <plan_path> --milestone "Post-MVP / Later"
   ```

   After creation, read `knowledge-base/product/roadmap.md` and update the milestone if a more specific phase applies: `gh issue edit <number> --milestone '<phase>'`.

3. **If Linear:**

   Read the plan file content, then run `linear issue create --title "<title>" --description "<plan content>"`.

4. **If no tracker configured:**
   Ask user: "Which project tracker do you use? (GitHub/Linear/Other)"
   - Suggest adding `project_tracker: github` or `project_tracker: linear` to their CLAUDE.md

5. **After creation:**
   - Display the issue URL
   - Ask if they want to proceed to `skill: soleur:work` or `skill: soleur:plan-review`

## Managing Plan Documents

**Update an existing plan:**
If re-running `soleur:plan` for the same feature, read the existing plan first. Update in place rather than creating a duplicate. Preserve prior content and mark changes with `[Updated YYYY-MM-DD]`.

**Archive completed plans:**
Run `bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` from the repository root. This moves matching artifacts to `knowledge-base/project/plans/archive/` with timestamp prefixes, preserving git history. Commit with `git commit -m "plan: archive <topic>"`.

## Sharp Edges

- When a plan corrects a factual claim (e.g., updates a version range from X to Y), grep the plan output for the old incorrect value before finalizing. Subagents can echo stale data from their initial context even when their analysis concludes otherwise.
- When a plan adds `cloudflare_record` resources with `name = "@"`, flag it during plan review — the Cloudflare API normalizes `@` to the FQDN on storage, causing perpetual Terraform drift. Use the FQDN (e.g., `"soleur.ai"`) instead.
- When a plan prescribes a fix based on exit code semantics of shell commands, include a verification step: "Test each command's actual exit code in the target environment before implementing." Plans that assume exit codes without verification (e.g., assuming `git diff --cached --quiet` returns 128 in bare repos when it actually returns 1) lead to implementation pivots during GREEN phase.
- When a plan prescribes dependency upgrades within a major version range, specify the npm version tag explicitly (e.g., `npm install next@15`, not `npm install next@latest`). The `@latest` tag resolves globally and may cross major version boundaries.
- When a plan references specific dependency version ranges or peer constraints, verify them via `npm view <pkg> peerDependencies` before prescribing a fix approach. Plans have prescribed wrong version ranges that were only caught during implementation.
- When a plan adds a new required check to CI/branch protection rulesets, the plan MUST include an audit step that greps for ALL workflows creating PRs via `GITHUB_TOKEN` or `create-pull-request` action and lists each one requiring synthetic check updates. Plans that claim "only N workflows need updating" without showing the grep output are incomplete.
- When a plan prescribes Supabase/PostgREST query syntax (embedded resources, lateral joins, `.select()` with modifiers), include a verification note: "Confirm syntax against Supabase JS client docs before implementing." PostgREST embedded resource syntax is more limited than expected — chained `.limit().order().eq()` inside `select()` does not work.
- When prescribing `gh api` commands with array parameters, always use `--input -` with a heredoc JSON body instead of `--field`. The `--field` flag wraps values in quotes, turning JSON arrays into strings (HTTP 422). After any GitHub settings PATCH, immediately re-read settings to verify the change was applied — the repo API silently ignores some org-level features (returns 200 OK without state change).
- When generating test commands, always reference `package.json scripts.test` rather than assuming a runner (bun test, vitest, jest). Plans that hardcode a specific test runner can fail silently when the project uses a different framework.

NEVER CODE! Just research and write the plan.
