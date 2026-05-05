---
name: deepen-plan
description: "This skill should be used when enhancing an existing plan with parallel research agents for each section."
---

# Deepen Plan - Power Enhancement Mode

## Introduction

**Note: The current year is 2026.** Use this when searching for recent documentation and best practices.

This skill takes an existing plan (from the `soleur:plan` skill) and enhances each section with parallel research agents. Each major element gets its own dedicated research sub-agent to find:

- Best practices and industry patterns
- Performance optimizations
- UI/UX improvements (if applicable)
- Quality enhancements and edge cases
- Real-world implementation examples

The result is a deeply grounded, production-ready plan with concrete implementation details.

## Plan File

<plan_path> #$ARGUMENTS </plan_path>

**If the plan path above is empty:**

1. Check for recent plans: `ls -la knowledge-base/project/plans/`
2. Ask the user: "Which plan would you like to deepen? Please provide the path (e.g., `knowledge-base/project/plans/2026-01-15-feat-my-feature-plan.md`)."

Do not proceed until a valid plan file path is provided.

## Main Tasks

### 1. Parse and Analyze Plan Structure

<thinking>
First, read and parse the plan to identify each major section that can be enhanced with research.
</thinking>

**Read the plan file and extract:**

- [ ] Overview/Problem Statement
- [ ] Proposed Solution sections
- [ ] Technical Approach/Architecture
- [ ] Implementation phases/steps
- [ ] Code examples and file references
- [ ] Acceptance criteria
- [ ] Any UI/UX components mentioned
- [ ] Technologies/frameworks mentioned (Rails, React, Python, TypeScript, etc.)
- [ ] Domain areas (data models, APIs, UI, security, performance, etc.)

**Create a section manifest:**

```
Section 1: [Title] - [Brief description of what to research]
Section 2: [Title] - [Brief description of what to research]
...
```

### 2. Discover and Apply Available Skills

<thinking>
Dynamically discover all available skills and match them to plan sections. Don't assume what skills exist - discover them at runtime.
</thinking>

**Step 1: Discover ALL available skills from ALL sources**

```bash
# 1. Project-local skills (highest priority - project-specific)
ls .claude/skills/

# 2. User's global skills (~/.claude/)
ls ~/.claude/skills/

# 3. soleur plugin skills
ls ~/.claude/plugins/cache/*/soleur/*/skills/

# 4. ALL other installed plugins - check every plugin for skills
find ~/.claude/plugins/cache -type d -name "skills" 2>/dev/null

# 5. Also check installed_plugins.json for all plugin locations
cat ~/.claude/plugins/installed_plugins.json
```

**Important:** Check EVERY source. Don't assume soleur is the only plugin. Use skills from ANY installed plugin that's relevant.

**Step 2: For each discovered skill, read its SKILL.md to understand what it does**

```bash
# For each skill directory found, read its documentation
cat [skill-path]/SKILL.md
```

**Step 3: Match skills to plan content**

For each skill discovered:

- Read its SKILL.md description
- Check if any plan sections match the skill's domain
- If there's a match, spawn a sub-agent to apply that skill's knowledge

**Step 4: Spawn a sub-agent for EVERY matched skill**

**CRITICAL: For EACH skill that matches, spawn a separate sub-agent and instruct it to USE that skill.**

For each matched skill:

```
Task general-purpose: "You have the [skill-name] skill available at [skill-path].

YOUR JOB: Use this skill on the plan.

1. Read the skill: cat [skill-path]/SKILL.md
2. Follow the skill's instructions exactly
3. Apply the skill to this content:

[relevant plan section or full plan]

4. Return the skill's full output

The skill tells you what to do - follow it. Execute the skill completely."
```

**Spawn ALL skill sub-agents in PARALLEL:**

- 1 sub-agent per matched skill
- Each sub-agent reads and uses its assigned skill
- All run simultaneously
- 10, 20, 30 skill sub-agents is fine

**Each sub-agent:**

1. Reads its skill's SKILL.md
2. Follows the skill's workflow/instructions
3. Applies the skill to the plan
4. Returns whatever the skill produces (code, recommendations, patterns, reviews, etc.)

**Example spawns:**

```
Task general-purpose: "Use the dhh-rails-style skill at ~/.claude/plugins/.../dhh-rails-style. Read SKILL.md and apply it to: [Rails sections of plan]"

Task general-purpose: "Use the frontend-design skill at ~/.claude/plugins/.../frontend-design. Read SKILL.md and apply it to: [UI sections of plan]"

Task general-purpose: "Use the agent-native-architecture skill at ~/.claude/plugins/.../agent-native-architecture. Read SKILL.md and apply it to: [agent/tool sections of plan]"

Task general-purpose: "Use the security-patterns skill at ~/.claude/skills/security-patterns. Read SKILL.md and apply it to: [full plan]"
```

**No limit on skill sub-agents. Spawn one for every skill that could possibly be relevant.**

### 3. Discover and Apply Learnings/Solutions

<thinking>
Check for documented learnings from the `soleur:compound` skill. These are solved problems stored as markdown files. Spawn a sub-agent for each learning to check if it's relevant.
</thinking>

**LEARNINGS LOCATION - Check these exact folders:**

```
knowledge-base/project/learnings/           <-- PRIMARY: Project-level learnings (created by soleur:compound)
├── performance-issues/
│   └── *.md
├── debugging-patterns/
│   └── *.md
├── configuration-fixes/
│   └── *.md
├── integration-issues/
│   └── *.md
├── deployment-issues/
│   └── *.md
└── [other-categories]/
    └── *.md
```

**Step 1: Find ALL learning markdown files**

Run these commands to get every learning file:

```bash
# PRIMARY LOCATION - Project learnings
find docs/solutions -name "*.md" -type f 2>/dev/null

# If docs/solutions doesn't exist, check alternate locations:
find .claude/docs -name "*.md" -type f 2>/dev/null
find ~/.claude/docs -name "*.md" -type f 2>/dev/null
```

**Step 2: Read frontmatter of each learning to filter**

Each learning file has YAML frontmatter with metadata. Read the first ~20 lines of each file to get:

```yaml
---
title: "N+1 Query Fix for Briefs"
category: performance-issues
tags: [activerecord, n-plus-one, includes, eager-loading]
module: Briefs
symptom: "Slow page load, multiple queries in logs"
root_cause: "Missing includes on association"
---
```

**For each .md file, quickly scan its frontmatter:**

```bash
# Read first 20 lines of each learning (frontmatter + summary)
head -20 knowledge-base/project/learnings/**/*.md
```

**Step 3: Filter - only spawn sub-agents for LIKELY relevant learnings**

Compare each learning's frontmatter against the plan:

- `tags:` - Do any tags match technologies/patterns in the plan?
- `category:` - Is this category relevant? (e.g., skip deployment-issues if plan is UI-only)
- `module:` - Does the plan touch this module?
- `symptom:` / `root_cause:` - Could this problem occur with the plan?

**SKIP learnings that are clearly not applicable:**

- Plan is frontend-only -> skip `database-migrations/` learnings
- Plan is Python -> skip `rails-specific/` learnings
- Plan has no auth -> skip `authentication-issues/` learnings

**SPAWN sub-agents for learnings that MIGHT apply:**

- Any tag overlap with plan technologies
- Same category as plan domain
- Similar patterns or concerns

**Step 4: Spawn sub-agents for filtered learnings**

For each learning that passes the filter:

```
Task general-purpose: "
LEARNING FILE: [full path to .md file]

1. Read this learning file completely
2. This learning documents a previously solved problem

Check if this learning applies to this plan:

---
[full plan content]
---

If relevant:
- Explain specifically how it applies
- Quote the key insight or solution
- Suggest where/how to incorporate it

If NOT relevant after deeper analysis:
- Say 'Not applicable: [reason]'
"
```

**Spawn sub-agents in PARALLEL for all filtered learnings.**

**These learnings are institutional knowledge - applying them prevents repeating past mistakes.**

### 4. Launch Per-Section Research Agents

<thinking>
For each major section in the plan, spawn dedicated sub-agents to research improvements. Use the Explore agent type for open-ended research.
</thinking>

**For each identified section, launch parallel research:**

```
Task Explore: "Research best practices, patterns, and real-world examples for: [section topic].
Find:
- Industry standards and conventions
- Performance considerations
- Common pitfalls and how to avoid them
- Documentation and tutorials
Return concrete, actionable recommendations."
```

**Also use Context7 MCP for framework documentation:**

For any technologies/frameworks mentioned in the plan, query Context7:

```
mcp__plugin_soleur_context7__resolve-library-id: Find library ID for [framework]
mcp__plugin_soleur_context7__query-docs: Query documentation for specific patterns
```

**Verify API availability against installed SDK version:** Context7 docs may reference APIs not yet available in the project's pinned dependency version. After recommending a specific API (e.g., `getClaims()`), check `node_modules` or `Gemfile.lock` to confirm the method exists in the installed version before including it in the plan.

- When Context7 MCP returns Terraform resource attributes, cross-check against the installed provider version (`grep -A2 'registry.terraform.io/<provider>' .terraform.lock.hcl`). Context7 returns latest docs, not version-pinned docs — attributes may not exist in the pinned version.
- When the plan changes a tunable's **semantic** (reset trigger, scope, evaluation point — e.g., "fires once per turn" → "resets per block"; "absolute" → "rolling"), `grep -rn "<tunable-name>" test/` and audit EVERY matching test file in the test-compatibility section — never sample a subset. Sampling lets at least one test that pinned the old semantic survive into the green-suite claim, surfacing the gap as a broken GREEN run mid-implementation. **Why:** PR #3225 — deepen-pass listed AC7/AC8/AC9/AC17/silent-fallback as compatible with the new "any-block resets" runaway semantic but did not enumerate the Stage 2.2 secondary-trigger test in `soleur-go-runner.test.ts`, which used `wallClockTriggerMs: 30_000` + multiple tool_uses and asserted the OLD "30s from first tool_use" contract. Test broke at GREEN time and required updating mid-implementation. See `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`.

**Use WebSearch for current best practices:**

Search for recent (2024-2026) articles, blog posts, and documentation on topics in the plan.

### 4.5. Network-Outage Deep-Dive (Conditional)

If the plan's Overview, Problem Statement, or Hypotheses contain any of the trigger patterns `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` (case-insensitive), read `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` and spawn a dedicated "Network-Outage Deep-Dive" research agent in parallel with the other deepen agents.

**Resource-shape trigger (implicit SSH dependency).** Also fire this gate when the plan drives `terraform apply` (with or without `-target=`) on any resource whose definition contains `provisioner "file"`, `provisioner "remote-exec"`, or a `connection { type = "ssh" ... }` block. The provisioner block makes SSH a hard apply-time dependency that the prose-only keyword scan won't detect — the plan body need not mention SSH at all and apply still fails on `connection reset by peer` if the operator's egress IP has drifted out of the firewall allowlist. **Why:** #3061 — plan body had zero SSH keywords; apply on `terraform_data.deploy_pipeline_fix` (file+remote-exec provisioners) still hit a handshake reset because Phase 4.5 didn't fire.

The deep-dive agent's task:

1. Read the checklist in full.
2. For each of the four layers (L3 firewall allow-list, L3 DNS/routing, L7 TLS/proxy if HTTPS, L7 application), verify the plan's Hypotheses section cites a concrete verification artifact (CLI output, log excerpt, or explicit "not verified" note).
3. Emit a "Network-Outage Deep-Dive" subsection in the plan with the layer-by-layer verification status and any gaps that need closing before implementation.

Per AGENTS.md `hr-ssh-diagnosis-verify-firewall`, plans addressing SSH/network-connectivity symptoms MUST verify the L3 firewall allow-list against current client egress IP BEFORE proposing service-layer fixes. The deep-dive is the deepen-plan enforcement layer.

When a trigger pattern matches, emit rule-application telemetry so the weekly aggregator records the deepen-plan enforcement layer fired (see AGENTS.md `hr-ssh-diagnosis-verify-firewall`):

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-ssh-diagnosis-verify-firewall applied \
  "When a plan addresses an SSH/network-connectivity s"
```

### 4.6. User-Brand Impact Halt (Always)

Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, every plan MUST contain a `## User-Brand Impact` section before deepen-plan can proceed. This phase is a hard gate — no deepen agents fan out until the section exists and contains concrete content.

**Step 1 — Locate the section.** Grep the target plan file:

```bash
grep -q '^## User-Brand Impact' <plan-file>
```

If the heading is absent, HALT with:

> Error: Plan is missing `## User-Brand Impact` section.
> See `plugins/soleur/skills/plan/references/plan-issue-templates.md` for the template.
> Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, every plan
> must answer the user-impact framing question before deepen-plan can proceed.
> Re-run `/soleur:plan` (or edit the plan directly) to add the section, then re-run deepen-plan.

**Step 2 — Validate the body.** If the heading exists, extract the section body (everything between `^## User-Brand Impact` and the next `^## ` heading). Reject the section as non-compliant if ANY of:

- The body is empty (only whitespace between headings).
- Every bullet contains only `TBD`, `TODO`, `N/A`, `<placeholder>`, or single-word stubs.
- The threshold line is missing or the value is not one of `none`, `single-user incident`, or `aggregate pattern`.
- The threshold is `none` AND the diff (or referenced `Files to edit` list) matches the canonical sensitive-path regex (single source of truth — kept in sync with `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1):

  ```bash
  SENSITIVE_PATH_RE='^(apps/web-platform/(server|supabase|app/api|middleware\.ts$)|apps/web-platform/lib/(stripe|auth|byok|security-headers|csp|log-sanitize|safe-session|safe-return-to|supabase)|apps/web-platform/lib/(legal|auth)/|apps/[^/]+/infra/|.+/doppler[^/]*\.(yml|yaml|sh)$|\.github/workflows/.*(doppler|secret|token|deploy|release|version-bump|web-platform|infra-validation|cla|cf-token|linkedin-token).*\.ya?ml$)'
  ```

  AND no `threshold: none, reason: <one-sentence>` scope-out bullet (with a non-empty reason) is present in the section.

On rejection, HALT with the same error message as Step 1, replacing the first line with the specific failure (`empty body`, `placeholder content`, `missing threshold`, `none-threshold without scope-out`).

**Step 3 — Emit telemetry.** When the halt fires (Step 1 OR Step 2), emit rule-application telemetry so the weekly aggregator records the deepen-plan enforcement layer fired:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-weigh-every-decision-against-target-user-impact applied \
  "Every plan/PR touching credentials, auth, data, paym"
```

**Step 4 — Pass-through.** If the section is present, non-empty, has a valid threshold, and (when `none`) has a scope-out line for sensitive-path diffs, deepen-plan proceeds normally. No telemetry is emitted on pass — the gate only records when it activates.

**Why:** The framing layer (brainstorm Phase 0.1) and the template layer (plan Phase 2.6) can both be skipped or filled with placeholders. This phase is the load-bearing pre-implementation gate that catches both — a plan with an empty section cannot pass deepen-plan, which means it cannot proceed to `/work`. Combined with preflight Check 6 (ship-time gate) and the `user-impact-reviewer` conditional agent (review-time gate), this closes the workflow loop introduced for #2887.

### 5. Discover and Run ALL Review Agents

<thinking>
Dynamically discover every available agent and run them ALL against the plan. Don't filter, don't skip, don't assume relevance. 40+ parallel agents is fine. Use everything available.
</thinking>

**Step 1: Discover ALL available agents from ALL sources**

```bash
# 1. Project-local agents (highest priority - project-specific)
find .claude/agents -name "*.md" 2>/dev/null

# 2. User's global agents (~/.claude/)
find ~/.claude/agents -name "*.md" 2>/dev/null

# 3. soleur plugin agents (all subdirectories)
find ~/.claude/plugins/cache/*/soleur/*/agents -name "*.md" 2>/dev/null

# 4. ALL other installed plugins - check every plugin for agents
find ~/.claude/plugins/cache -path "*/agents/*.md" 2>/dev/null

# 5. Check installed_plugins.json to find all plugin locations
cat ~/.claude/plugins/installed_plugins.json

# 6. For local plugins (isLocal: true), check their source directories
# Parse installed_plugins.json and find local plugin paths
```

**Important:** Check EVERY source. Include agents from:

- Project `.claude/agents/`
- User's `~/.claude/agents/`
- soleur plugin (but SKIP engineering/workflow/ agents - only use review, research, and design)
- ALL other installed plugins (agent-sdk-dev, frontend-design, etc.)
- Any local plugins

**For soleur plugin specifically:**

- USE: `agents/engineering/review/*` (all reviewers)
- USE: `agents/engineering/research/*` (all researchers)
- USE: `agents/engineering/design/*` (design agents)
- SKIP: `agents/engineering/workflow/*` (workflow orchestrators, not reviewers)

**Step 2: For each discovered agent, read its description**

Read the first few lines of each agent file to understand what it reviews/analyzes.

**Step 3: Launch ALL agents in parallel**

For EVERY agent discovered, launch a Task in parallel:

```
Task [agent-name]: "Review this plan using your expertise. Apply all your checks and patterns. Plan content: [full plan content]"
```

**CRITICAL RULES:**

- Do NOT filter agents by "relevance" - run them ALL
- Do NOT skip agents because they "might not apply" - let them decide
- Launch ALL agents in a SINGLE message with multiple Task tool calls
- 20, 30, 40 parallel agents is fine - use everything
- Each agent may catch something others miss
- The goal is MAXIMUM coverage, not efficiency

**Step 4: Also discover and run research agents**

Research agents (like `best-practices-researcher`, `framework-docs-researcher`, `git-history-analyzer`, `repo-research-analyst`) should also be run for relevant plan sections.

### 6. Wait for ALL Agents and Synthesize Everything

<thinking>
Wait for ALL parallel agents to complete - skills, research agents, review agents, everything. Then synthesize all findings into a comprehensive enhancement.
</thinking>

**Collect outputs from ALL sources:**

1. **Skill-based sub-agents** - Each skill's full output (code examples, patterns, recommendations)
2. **Learnings/Solutions sub-agents** - Relevant documented learnings from `soleur:compound`
3. **Research agents** - Best practices, documentation, real-world examples
4. **Review agents** - All feedback from every reviewer (architecture, security, performance, simplicity, etc.)
5. **Context7 queries** - Framework documentation and patterns
6. **Web searches** - Current best practices and articles

**For each agent's findings, extract:**

- [ ] Concrete recommendations (actionable items)
- [ ] Code patterns and examples (copy-paste ready)
- [ ] Anti-patterns to avoid (warnings)
- [ ] Performance considerations (metrics, benchmarks)
- [ ] Security considerations (vulnerabilities, mitigations)
- [ ] Edge cases discovered (handling strategies)
- [ ] Documentation links (references)
- [ ] Skill-specific patterns (from matched skills)
- [ ] Relevant learnings (past solutions that apply - prevent repeating mistakes)

**Deduplicate and prioritize:**

- Merge similar recommendations from multiple agents
- Prioritize by impact (high-value improvements first)
- Flag conflicting advice for human review
- Group by plan section

### 7. Enhance Plan Sections

<thinking>
Merge research findings back into the plan, adding depth without changing the original structure.
</thinking>

**Enhancement format for each section:**

```markdown
## [Original Section Title]

[Original content preserved]

### Research Insights

**Best Practices:**
- [Concrete recommendation 1]
- [Concrete recommendation 2]

**Performance Considerations:**
- [Optimization opportunity]
- [Benchmark or metric to target]

**Implementation Details:**
```[language]
// Concrete code example from research
```

**Edge Cases:**

- [Edge case 1 and how to handle]
- [Edge case 2 and how to handle]

**References:**

- [Documentation URL 1]
- [Documentation URL 2]

```

### 8. Add Enhancement Summary

At the top of the plan, add a summary section:

```markdown
## Enhancement Summary

**Deepened on:** [Date]
**Sections enhanced:** [Count]
**Research agents used:** [List]

### Key Improvements
1. [Major improvement 1]
2. [Major improvement 2]
3. [Major improvement 3]

### New Considerations Discovered
- [Important finding 1]
- [Important finding 2]
```

### 9. Update Plan File

**Write the enhanced plan:**

- Preserve original filename
- Add `-deepened` suffix if the user prefers a new file
- Update any timestamps or metadata

## Output Format

Update the plan file in place (or if user requests a separate file, append `-deepened` after `-plan`, e.g., `2026-01-15-feat-auth-plan-deepened.md`).

## Quality Checks

Before finalizing:

- [ ] All original content preserved
- [ ] Research insights clearly marked and attributed
- [ ] Code examples are syntactically correct
- [ ] Links are valid and relevant
- [ ] No contradictions between sections
- [ ] Explicit string literals (error messages, log strings, Sentry messages, feature flags) match across Helper Contract / Acceptance Criteria / Test Scenarios / Test Implementation Sketch. Verbatim-preserved strings (e.g., for dashboard/alert continuity) are the highest-risk drift class — grep the whole plan for each quoted literal and confirm one canonical value.
- [ ] Every cited external SHA, tag, release version, or commit reference has been **resolved live** via `gh api` or an equivalent authoritative source in the same deepen pass — never cite SHAs from memory or training data. Show the command + output in a fenced block next to the claim. **Why:** In the #2540 plan, the fallback SHA for `claude-code-action@v1.0.100` was cited as `8a953ded...` (actually the `v1` floating tag), and `scheduled-roadmap-review.yml` was described as using `@v1` floating ref when it's actually a pinned SHA `@ff9acae5... # v1`. Both errors survived into the plan and were caught only in review.
- [ ] For any bash test scenario that claims "bad input is caught by \<operator\>", verify the operator's behavior under `set -euo pipefail`. Common operators that CRASH instead of catch under strict mode: `-gt`/`-lt`/`-eq` on non-numeric RHS, `$(( ))` on non-numeric, `${var?}` when var is unset. If the claim depends on catching, the plan must prescribe a preceding regex/emptiness guard. **Why:** PR #2716 T10 asserted "malformed TASKS row caught by threshold comparison" — under `set -e`, `[[ $n -gt $malformed ]]` crashed the whole step; caught in QA, fixed with explicit `[[ "$max_gap_days" =~ ^[0-9]+$ ]]` guard. See `knowledge-base/project/learnings/2026-04-21-cloud-task-silence-watchdog-pattern.md`.
- [ ] Enhancement summary accurately reflects changes

## Post-Enhancement Options

After writing the enhanced plan, use the **AskUserQuestion tool** to present these options:

**Question:** "Plan deepened at `[plan_path]`. What would you like to do next?"

**Options:**

1. **View diff** - Show what was added/changed
2. **Run `/plan_review`** - Get feedback from reviewers on enhanced plan
3. **Start `soleur:work`** - Begin implementing this enhanced plan
4. **Deepen further** - Run another round of research on specific sections
5. **Revert** - Restore original plan (if backup exists)

Based on selection:

- **View diff** -> Run `git diff [plan_path]` or show before/after
- **`/plan_review`** -> Call the /plan_review command with the plan file path
- **`soleur:work`** -> Use `skill: soleur:work` with the plan file path
- **Deepen further** -> Ask which sections need more research, then re-run those agents
- **Revert** -> Restore from git or backup

## Example Enhancement

**Before (from `soleur:plan`):**

```markdown
## Technical Approach

Use React Query for data fetching with optimistic updates.
```

**After (from /deepen-plan):**

```markdown
## Technical Approach

Use React Query for data fetching with optimistic updates.

### Research Insights

**Best Practices:**
- Configure `staleTime` and `cacheTime` based on data freshness requirements
- Use `queryKey` factories for consistent cache invalidation
- Implement error boundaries around query-dependent components

**Performance Considerations:**
- Enable `refetchOnWindowFocus: false` for stable data to reduce unnecessary requests
- Use `select` option to transform and memoize data at query level
- Consider `placeholderData` for instant perceived loading

**Implementation Details:**
```typescript
// Recommended query configuration
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 minutes
      retry: 2,
      refetchOnWindowFocus: false,
    },
  },
});
```

**Edge Cases:**

- Handle race conditions with `cancelQueries` on component unmount
- Implement retry logic for transient network failures
- Consider offline support with `persistQueryClient`

**References:**

- <https://tanstack.com/query/latest/docs/react/guides/optimistic-updates>
- <https://tkdodo.eu/blog/practical-react-query>

```
