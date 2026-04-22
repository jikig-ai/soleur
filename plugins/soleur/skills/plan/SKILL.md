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

### 1.4. Network-Outage Hypothesis Check (Conditional)

If the feature description matches any of the patterns `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` (case-insensitive substring match on the feature description), read [plan-network-outage-checklist.md](./references/plan-network-outage-checklist.md) and require its output in the `## Hypotheses` section of the final plan.

The checklist enforces an L3->L7 diagnostic order: firewall allow-list and DNS/routing MUST be verified before sshd/fail2ban/service-layer hypotheses. Per AGENTS.md `hr-ssh-diagnosis-verify-firewall`, this is a hard rule -- plans that propose sshd or fail2ban fixes without first verifying firewall + egress IP are workflow violations.

This step is a single file read, not a subagent spawn. If the feature description does not match any trigger pattern, skip this step silently.

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
- **Reconcile spec claims against codebase reality.** If the repo-research-analyst returned any "Gap callouts" or equivalent mismatches, the plan MUST include a "Research Reconciliation — Spec vs. Codebase" section (3-column table: spec claim / reality / plan response) placed between "Overview" and "Implementation Phases". This prevents the plan from inheriting spec fiction (e.g., claimed infrastructure that doesn't exist) as phase estimates. See `knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`.

**Optional validation:** Briefly summarize findings and ask if anything looks off or missing before proceeding to planning.

### 1.7.5. Code-Review Overlap Check

After the plan draft has enumerated its `## Files to Edit` and `## Files to Create` sections (i.e., run this check AFTER Step 2 Issue Planning produces the file list, and BEFORE Step 4 Detail Level selection), verify whether any open code-review issues touch files the plan intends to modify. This prevents two failure modes:

- **Rework:** a pre-existing scope-out names a file the plan will rewrite — if unnoticed, the plan ships, then the scope-out surfaces and drives a second refactor PR that could have been folded in.
- **Double-counting:** the review phase files a new scope-out for a concern a still-open issue already tracks.

**Procedure:**

1. Read the plan's `## Files to Edit` and `## Files to Create` sections (the plan draft exists by this point). Extract every file path. If the plan is still being drafted and those sections are not yet written, defer this check until they exist rather than guessing from the feature description — guessing produces false negatives.

2. Query open code-review issues. **Use two-stage piping (`--json` then a standalone `jq --arg`), not single-stage `gh --jq` with `--arg`.** The `gh` CLI does NOT forward `--arg` to its embedded jq; a single-stage form produces `unknown arguments` at runtime. See learning `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`.

    ```bash
    gh issue list --label code-review --state open \
      --json number,title,body --limit 200 > /tmp/open-review-issues.json
    ```

3. For each planned file path, search the issue bodies using standalone `jq` with `--arg` (safe against regex metacharacters in paths):

    ```bash
    jq -r --arg path "<file-path>" '
      .[] | select(.body // "" | contains($path))
      | "#\(.number): \(.title)"
    ' /tmp/open-review-issues.json
    ```

4. If any matches are returned, write a `## Open Code-Review Overlap` section to the plan file with a one-line bullet per match and an explicit disposition for each:

    > X open scope-outs touch these files: #2466 (Range cache), #2483 (helper extraction). Fold in / acknowledge / defer: …

    For each match, the planner MUST explicitly choose one of:

    - **Fold in:** plan extends to close the scope-out in the same PR. Add the scope-out's file paths to `## Files to edit` and note `Closes #<N>` in the PR-body reminder.
    - **Acknowledge:** plan deliberately does NOT fix the scope-out (e.g., different concern, needs its own cycle). Record a 1-sentence rationale. The scope-out remains open.
    - **Defer:** plan is not the right place; update the scope-out issue with a re-evaluation note (e.g., "revisit after feat-X lands"). Do NOT silently leave the overlap unaddressed — the reviewer will re-surface it.

5. If no matches, still record `## Open Code-Review Overlap` with `None` so the next planner can see the check ran.

**Why this matters:** In the 2026-04-17 window, PR #2486 closed three scope-outs (#2467 + #2468 + #2469) because the planner noticed the overlap. PRs #2463 and #2477 grew the backlog instead because no overlap check ran. This phase makes the #2486 pattern the default, not the exception. See `knowledge-base/project/learnings/best-practices/2026-04-17-review-backlog-net-positive-filing.md`.

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
- [ ] When the plan prescribes scoping a helper function by a new column/predicate, `rg` the codebase for every other inline query on the same table that BYPASSES the helper (id-based lookups, pre-helper historical queries, WS-handler inline SELECTs) and list each as a `Files to Edit` entry -- sibling queries are the most common silent backdoor after a tenant-scope change. See learning `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md`.

### 2.5. Domain Review Gate

After generating the plan structure, assess which business domains this plan has implications for. This gate enforces constitution line 122: plans must receive cross-domain review before implementation.

**Step 1 — Domain Sweep:**

1. **Brainstorm carry-forward check:** If the brainstorm document (loaded in Phase 0.5) contains a `## Domain Assessments` section, carry forward the findings. Extract relevant domains and their summaries. Skip fresh assessment.

2. **Fresh assessment (if no brainstorm or no `## Domain Assessments` section):** Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. Assess all 8 domains against the plan content in a single LLM pass using each domain's Assessment Question. Use semantic assessment — not keyword matching.

3. **Spawn domain leaders:** For each domain assessed as relevant **except Product** (handled in Step 2), spawn the domain leader as a blocking Task using the Task Prompt from brainstorm-domain-config.md, substituting `{desc}` with the plan summary. Spawn in parallel if multiple are relevant.

4. **Collect findings:** Wait for all domain leader Tasks to complete. Each returns a brief structured assessment. If a domain leader Task fails (timeout, error), write partial findings for that domain with `Status: error` and continue with remaining domains.

**Step 1.5 — Brainstorm Specialist Carry-Forward Gate:**

After domain sweep, scan the brainstorm document's `## Domain Assessments` section (and any `## Capability Gaps` section) for domain leaders that recommended specific specialists by name (e.g., "delegates to conversion-optimizer", "recommends copywriter for cancellation copy", "invoke ux-design-lead for wireframes"). Build a `REQUIRED_SPECIALISTS` list from these recommendations.

For each specialist in `REQUIRED_SPECIALISTS`:

1. If the specialist will be invoked by the Product/UX Gate pipeline below (ux-design-lead, copywriter, spec-flow-analyzer), mark it as "covered by UX Gate" — it will run in Step 2.
2. If the specialist is NOT covered by the UX Gate pipeline (e.g., conversion-optimizer, retention-strategist, pricing-strategist), invoke it as a Task now with a scoped prompt derived from the recommendation context. Spawn in parallel if multiple.
3. Record all brainstorm-recommended specialists in the Domain Review section under `**Brainstorm-recommended specialists:**`.

**Enforcement:** Specialists recommended by name in brainstorm domain assessments MUST be either invoked or explicitly declined by the user via AskUserQuestion ("Domain leader recommended [specialist] for [reason]. Run now / Skip with acknowledgment"). Silent skipping is a workflow violation. **Why:** In #1078, the CMO recommended conversion-optimizer and copywriter for the cancellation flow, but the plan skill silently wrote them into `Skipped specialists:` without asking, producing UX artifacts that lacked brand review.

**Step 2 — Product/UX Gate:**

After Steps 1 and 1.5 complete, if Product domain was flagged as relevant, run the existing three-tier classification:

- **BLOCKING**: Creates new user-facing pages, multi-step user flows, or significant new UI components — including modals, dialogs, confirmation flows, and interstitials with emotional or persuasive copy (e.g., signup flows, dashboards, onboarding wizards, chat interfaces, retention modals, cancel confirmation screens, prompts, banners)
- **ADVISORY**: Modifies existing user-facing pages or components without adding new interactive surfaces (e.g., layout changes, form updates, adding fields to existing screens)
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
- [ ] **CLI-verification gate (#2566):** For every CLI invocation the plan prescribes to land in user-facing docs (`*.njk`, `*.md`, README, `apps/**`), verify the tokens exist. One of: (a) run `<tool> --help` or `<tool> <subcommand> --help` locally and paste the relevant line into Research Insights; (b) cite the tool's official command reference URL; (c) annotate the plan snippet with `<!-- verified: YYYY-MM-DD source: <url> -->`. A plan that embeds a CLI invocation without ONE of the three MUST NOT ship -- silence (omit the snippet) beats fabrication. `tsc` and Eleventy build do NOT catch fabricated tokens. **Why:** #1810/#2550 shipped `ollama launch claude --model gemma4:31b-cloud` -- every token fabricated, caught 8 days later.

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

**Why Plan Review runs BEFORE Save Tasks:** `tasks.md` is a derivative breakdown of the plan's phases. If review prompts material changes (phase cuts, deliverable rewrites), generating `tasks.md` beforehand would immediately go stale and require regeneration. Running review first → applying changes → then deriving tasks ensures `tasks.md` reflects the final plan as a single source of truth, and the commit below covers both files in one atomic history entry.

## Save Tasks to Knowledge Base (if exists)

**After Plan Review has applied any requested changes**, generate `tasks.md` from the finalized plan and commit all artifacts together:

Check if `knowledge-base/` exists. If so, run `git branch --show-current` to get the current branch. If on a `feat-*` branch, create the spec directory with `mkdir -p knowledge-base/project/specs/<branch-name>`.

**If knowledge-base/ exists and on a feature branch:**

1. **Generate tasks.md** using `spec-templates` skill template, derived from the finalized (post-review) plan:
   - Extract actionable tasks from the plan
   - Organize into phases (Setup, Core Implementation, Testing)
   - Use hierarchical numbering (1.1, 2.1, 2.1.1, etc.)

2. **Save tasks.md** to `knowledge-base/project/specs/feat-<name>/tasks.md`

3. **Announce:** "Tasks saved to `knowledge-base/project/specs/feat-<name>/tasks.md`. Use `skill: soleur:work` to implement."

4. **Commit and push plan artifacts:**

   Both the plan file and tasks.md are committed together so the final plan and its task breakdown land in the same history entry:

   ```bash
   git add knowledge-base/project/plans/ knowledge-base/project/specs/feat-<name>/tasks.md
   git commit -m "docs: create plan and tasks for feat-<name>"
   git push
   ```

   If the push fails (no network), print a warning but continue.

**If knowledge-base/ does NOT exist or not on feature branch:**

- Plan saved to `knowledge-base/project/plans/` only (current behavior)

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
3. Display the resume prompt (per AGENTS.md Communication rule). Format:

   ```text
   All artifacts are on disk. Run `/clear` then paste this to resume:

   /soleur:work <plan-file-path>

   Context: branch <branch>, worktree <worktree-path>, PR #<N>, issue #<N>.
   <one-line summary of what was already done>
   ```

   Replace placeholders with actual values from the session. The user must be
   able to paste the command and go without re-explaining context.

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
- Before a plan's Test Strategy names a specific framework (bats, pytest, rspec, vitest, etc.), verify the framework is actually installed: `command -v <tool>` AND grep existing test files for the pattern (`ls plugins/*/test/`, `find . -name '*.bats' -o -name '*_test.*'`). If absent, default to the existing convention. Never prescribe a new test framework without an explicit "Add <framework> dependency" task AND reconciling with any "no new dependencies" claim in the plan Overview. **Why:** In #2212, the plan prescribed `bats` while also saying "no new dependencies" — bats was not installed; the implementer adapted to `.test.sh` convention at work-skill time, paying attention cost that a 2-line check in the plan would have avoided.
- When a plan prescribes a specific CLI invocation form (stdin/stdout pipes via `-`, particular long options, flag combinations that vary by tool version), the preflight task MUST exercise the exact form with realistic input — not just `--version` or `--help`. Installability ≠ usability: `--version` proves the tool exists; it proves nothing about whether the flags your helper depends on are recognized by the installed version. **Why:** In the #2456 PDF linearization plan, the initial preflight only ran `qpdf --version`. A reviewer challenged whether `qpdf --linearize - -` actually supports stdin/stdout pipes. Expanding preflight to pipe a real fixture PDF through the exact form (and `qpdf --check` the output) caught the ambiguity before implementation — a failure would have collapsed the helper design mid-build. See `knowledge-base/project/learnings/best-practices/2026-04-17-plan-preflight-cli-form-verification.md`.
- When a plan addresses alignment of a toggleable UI control (collapse/expand, accordion, drawer, tab visibility), verify alignment in **both toggle states** before writing the plan — not just the state named in the bug report. The two states often render different DOM subtrees with different parent geometry; a fix for one state can leave the other misaligned. Fold both states into the same PR, or document why only one state needs the fix. **Why:** PR #2494 fixed the collapsed-state settings-nav chevron but left the expanded-state chevron misaligned, requiring a follow-up PR #2504. The gap existed because the bug report mentioned only one state. See `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`.
- When a plan's Non-Goals or Risks section makes a claim about third-party vendor default behavior (Cloudflare cache eligibility, Supabase connection limits, Next.js body-size defaults, Stripe webhook retry semantics, AWS S3 consistency model), the claim MUST cite the specific doc URL and include a verification step — or drop the claim entirely. Asserting "the default handles this" without a citation is a plan-quality failure that downstream review agents have to catch. **Why:** In PR #2532, the plan asserted Cloudflare would cache `public, max-age=…` responses on `/api/shared/*` by default; the architecture reviewer proved otherwise (CF bypasses dynamic paths regardless of Cache-Control), forcing a Terraform `cloudflare_ruleset` to be added inline during review-fix. See `knowledge-base/project/learnings/2026-04-18-cloudflare-default-bypasses-dynamic-paths.md`.
- When a plan bumps `--max-turns` on a `claude-code-action` workflow, it MUST also bump `timeout-minutes` to keep the ratio aligned with peer workflows (median 0.75 min/turn, 0.60 acceptable for data-only tasks). A raised turn budget with an unchanged timeout is a silent failure mode — the agent hits the wall clock before exhausting the turns it was granted. See `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` for the peer ratio table. **Why:** In PR #2536, the initial plan raised bug-fixer max-turns 35 → 55 but kept `timeout-minutes: 30` (0.55 ratio, below the median). The review agent caught it; the follow-up commit bumped timeout to 45 (0.82 ratio).
- When a plan adds a regex over user-controlled input (PII scrubbers, log sanitizers, URL validators, CSV parsers), the Risks section MUST state the **maximum input size reachable by the regex engine** — not just a smoke-test number. If upstream callers can send unbounded input (e.g., Next.js's 1MB default body size, no per-field length cap in a JSON validator), the plan must specify a pre-regex `.slice()` bound and justify it. Smoke-testing a 2000-char string proves nothing about a 1MB pathological input. For UUIDs/IDs, match the **structural shape** (8-4-4-4-12 hex), not a specific version — version-restricted regexes (e.g., v4-only) leak stronger-PII variants (v1 MAC+timestamp) when a caller uses a different generator. Avoid `/g` regex + `.test()` gates; prefer `const next = s.replace(RE, ...); if (next !== s) { fired.push(name); s = next; }` — the `.test()` pattern relies on `.replace()` resetting `lastIndex` and silently leaks on a future edit that removes the `.replace()`. See `knowledge-base/project/learnings/security-issues/2026-04-17-pii-regex-scrubber-three-invariants.md`.
- Do not prescribe exact learning filenames with dates in `tasks.md`. Dates drift across session boundaries. Prescribe directory + topic only (e.g., `knowledge-base/project/learnings/bug-fixes/<topic>.md`) and let the author pick the date at write-time. **Why:** PR #2226 prescribed a `2026-04-14-...` filename but the file was created on the 15th, forcing a tasks.md fix-up.
- When a PR has post-merge operator actions (terraform apply, manual verification, external service setup), split `## Acceptance Criteria` into `### Pre-merge (PR)` and `### Post-merge (operator)` subsections. Flat lists make reviewer check-offs ambiguous. **Why:** PR #2226 P1 review finding.
- Before prescribing a rename of any `AGENTS.md` rule id (`[id: hr-*]`, `[id: wg-*]`, `[id: cq-*]`), grep the whole repo for the old id (`grep -rn '<old-id>' . --exclude-dir=.git`) and update every call site in the same commit. The `cq-rule-ids-are-immutable` rule covers only AGENTS.md itself — downstream references in `.claude/hooks/`, tests, docs, and `.github/workflows/` must be updated manually. **Why:** 2026-04-15 rename broke two test files because the rename was not grep-propagated.
- For any acceptance criterion that cites an external corpus (`gh issue list`, file globs, label queries, etc.), run the exact query before freezing the AC. If the corpus returns zero, either scope the AC out or file a deferral issue in the same commit — don't freeze an AC that depends on a corpus you haven't verified exists. **Why:** PR #2346 golden-set AC deferred via #2352.
- When a plan specifies a fixture seeding N entities, classify each entity as **DB-only** / **external service** / **hybrid** before freezing the spec. External-service entities (files in external repos, OAuth-gated resources, third-party APIs) often need separate seed strategies and may require deferral. **Why:** PR #2346 KB fixture lived in GitHub workspace, not Supabase — deferred via #2351.
- When a plan prescribes `flock -x N ( ... ) N>>"$file"` with a variable reassigned inside the subshell that a later outer command consumes, state explicitly where the assignment lives. Subshell reassignments do NOT propagate — the outer command sees the pre-subshell value. Hoist the assignment outside the `( ... )`, or complete consumption inside. **Why:** PR #2573 initial rotation block reassigned `archive=` inside the flock subshell; the outer `gzip -f "$archive"` targeted a non-existent path and T9 failed until the uniquify block moved out. See `knowledge-base/project/learnings/best-practices/2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`.
- When a plan prescribes a `SCHEMA_VERSION` constant or any cross-process contract field, it MUST include a task for asserting the value at every consumer boundary — not just on the producer side. A field written but never read is cosmetic; a schema contract is the set of places it is asserted. **Why:** PR #2573 shipped SCHEMA_VERSION as a self-referential check in the aggregator; consumer-side gating was added inline during review when the architecture reviewer flagged the gap.
- When a plan says "extract a shared factory/helper for N files" or enumerates a file list scoped from an issue body, validate N at planning time by grepping the distinguishing pattern (`rg '<pattern>' test/ src/`) — never trust the issue's enumerated list. Issue authors typically scan one directory; the real pattern usually spans more. **Why:** PR #2574 plan scoped 7 sidebar test files; review's pattern-recognition agent found 3 more (`chat-page*`, `error-states`) requiring inline scope extension. See `knowledge-base/project/learnings/best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`.
- When a plan adds a Supabase DDL migration, `ls apps/web-platform/supabase/migrations/` and read the 2-3 most recent files before prescribing DDL constructs. Supabase's migration runner wraps each file in a transaction, so `CREATE INDEX CONCURRENTLY`, `VACUUM`, `ALTER SYSTEM`, and other non-transactional DDL will fail at deploy with SQLSTATE 25001 — sibling migrations typically document the constraint inline. Cite the specific sibling migration that demonstrates the pattern your plan adopts. **Why:** PR #2579 plan prescribed `CREATE INDEX CONCURRENTLY` verbatim from Postgres docs; migrations 025 and 027 had explicit comments rejecting CONCURRENTLY that the deepen-pass didn't read. See `knowledge-base/project/learnings/integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md`.
- When a plan prescribes testing a security invariant of an LLM-mediated tool (SDK-invoked sandbox, agent-routed API call, MCP server driven by natural-language input), the test harness MUST remove the LLM from the assertion path. Natural-language prompts (`query({ prompt: "Run this command..." })`) are non-deterministic — the model may introspect, reword, refuse, or emit as text. A green suite proves model compliance, not the security invariant. Prefer: direct tool-invocation entry, captured-argv `child_process.spawn`, or any path that short-circuits the model. **Why:** #1450 plan initially scaffolded `query()`-prompt-based tier-4 bwrap assertions; plan-review caught this before any test shipped. See `knowledge-base/project/learnings/best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`.
- When a plan adds a source-template drift-guard test (regex/grep over `.njk`, `.hbs`, `.html`, `.jsx`, etc.), the test's file list MUST be a directory walk over the source root — never a hardcoded file list taken from the issue body. Issue authors typically name 1-2 files; the bug class usually spans more. Prescribe `walkDir(resolve(REPO_ROOT, "<source-root>"))` plus a sanity assertion that the walk found ≥ N known templates. **Why:** #2609 plan scoped the drift-guard to `base.njk` + `blog-post.njk`; review found 9 other `.njk` files with the same bug pattern (`<script type="application/ld+json">` interpolations), widening required inline during review. See `knowledge-base/project/learnings/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md`.
- When a plan prescribes HTML-escape-aware fixes inside `<script>` blocks (JSON-LD, inline config, hydration blobs), `JSON.stringify` / Nunjucks `dump` / similar JSON-serializers are necessary but not sufficient. The plan's Risks section MUST enumerate three hazard classes: (1) JSON parse failure (raw `"` / control chars), (2) HTML tag breakout (`</script>` / `</SCRIPT>` closes the outer tag), (3) JS runtime string termination (U+2028 / U+2029 in legacy runtimes). Prescribe a dedicated filter that applies all three escapes (`</` → `<\/`, `\u2028`, `\u2029`) rather than raw `dump`/`stringify`. **Why:** #2609 initial plan chose `| dump | safe` which left `</script>` breakout live for any attacker-controlled frontmatter field; review forced a `jsonLdSafe` filter inline. See the same learning file.
- When a plan adds a new skill OR a new AGENTS.md rule, the Acceptance Criteria section MUST include the measured **current** budget headroom so the work phase knows how much room it has, not just the cap. For skills: run `bun test plugins/soleur/test/components.test.ts` at plan time and note `current/1800` words; prescribe the new description ≤ `1800 - current` words. For AGENTS.md rules: run `awk '/<rule-id>/ {print length($0)}' AGENTS.md` during drafting (not after), and verify the count with a grep of the new rule's byte length. **Why:** PR #2683 — initial skill description was 43 words over a 1799-word baseline (required trimming three sibling skills); initial AGENTS.md rule was 687 bytes over the 600-byte cap (required two trim iterations). See `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md` session errors.
- When a plan prescribes pre-merge verification of a **new** CI workflow via `workflow_dispatch`, flag it as infeasible — GitHub requires the workflow file to exist on the **default branch** before `gh workflow run <file>.yml --ref <feature-branch>` can dispatch it (returns `HTTP 404: workflow not found on the default branch`). For pre-merge verification of a new workflow or composite action, choose one of: (1) wire the check as a job in an existing `pull_request`-triggered workflow so it runs on PR events against the feature branch, (2) extract the logic into a shell script / module that is locally testable with mocked inputs, or (3) explicitly defer verification to post-merge `gh workflow run <existing-workflow>.yml`. Never plan "add a temporary test workflow with `workflow_dispatch`, trigger from the feature branch, delete before merge" — step 2 is impossible and the plan's mock-code-path in production will become dead-code + insider-bypass surface when the unreachable test is removed. **Why:** PR #2717 — see `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`.
- When a plan prescribes an **aggregate numeric target** in Acceptance Criteria (bytes saved, rules removed, perf delta, coverage %), the plan body MUST show the per-item contributions that sum to the target. If per-item estimates sum to a number that disagrees with the aggregate, the aggregate is wrong — fix it at plan time, don't leave the mismatch to be negotiated at work time via spec strikethrough+replacement. Plan-review agents (code-simplicity + architecture-strategist) do not check numeric self-consistency by default; the plan author owns this. **Why:** PR #2754 — plan prescribed "≥800 bytes saved" while its own per-rule byte-impact table projected only ~260 bytes; actual outcome was +21 bytes, forcing a spec FR4 relaxation mid-implementation. See `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`.
- When a plan AC claims the state of an external-service config (Doppler values, Supabase rows, Cloudflare applied state, GitHub secret presence, Stripe product config), verify via the actual API at plan time — code-grep confirms consumers exist, NOT that the config holds values. These are different questions, and plan-review agents cannot detect the conflation without making the API call themselves. Generalizes beyond Doppler. **Why:** PR #2769 — plan AC claimed "dev Doppler has all 6 NEXT_PUBLIC_* secrets; confirmed by codebase audit" but dev was missing 3 keys; AC had to be rewritten at work-phase. See `knowledge-base/project/learnings/best-practices/2026-04-22-plan-ac-external-state-must-be-api-verified.md`.

NEVER CODE! Just research and write the plan.
