---
title: "feat: enforce milestone assignment on all issue creation surfaces"
type: feat
date: 2026-03-26
deepened: 2026-03-26
---

# feat: Enforce Milestone Assignment on All Issue Creation Surfaces

## Enhancement Summary

**Deepened on:** 2026-03-26
**Sections enhanced:** 6
**Research sources:** 7 learnings, 4 workflow files, constitution analysis, guardrails.sh hook analysis

### Key Improvements

1. Added three-tier enforcement strategy (hook + skill-enforced + prose) based on `skill-enforced-convention-pattern` learning
2. Added PreToolUse hook guard (Guard 5) for syntactic enforcement of `--milestone` in `gh issue create` commands
3. Added precise code-level implementation details with exact line numbers and surrounding context for each surface
4. Added edge cases for milestone title changes, new milestone creation, and milestone deletion
5. Added AGENTS.md rule wording optimized for "gotchas-only" principle per `lean-agents-md-gotchas-only` learning

## Problem

GitHub issues are created across 17 different surfaces (shell scripts, GitHub Actions workflows, skill instructions, and agent prompts) but **none** of them enforce milestone assignment at creation time. The only workflow that assigns milestones post-creation is the weekly growth audit, which uses a follow-up CPO agent step. This leaves most issues untracked against roadmap phases.

Currently 10 open issues have no milestone. The roadmap document (`knowledge-base/product/roadmap.md`) defines 6 milestones corresponding to product phases, but the issue creation pipelines do not reference them.

### Research Insights: Problem Scope

The 17 surfaces break down into 4 enforcement tiers:

| Tier | Surface Count | Current Enforcement | Gap |
|---|---|---|---|
| Shell scripts (direct `gh issue create`) | 2 | None | Can be enforced syntactically via hook + code change |
| GitHub Actions workflows (direct `gh issue create` in `run:` blocks) | 4 | None | Can be enforced syntactically via code change (hooks do not run in CI) |
| GitHub Actions workflows (agent-prompted via `claude-code-action`) | 6 | None (except growth-audit CPO follow-up) | Must be enforced via prompt instructions (agent decides the command) |
| Skills (agent-executed per SKILL.md instructions) | 5 | None | Must be enforced via skill instruction changes + AGENTS.md rule |

## Root Cause

No constitution rule, AGENTS.md gate, or skill instruction mandates milestone assignment when creating GitHub issues. The existing AGENTS.md rule about roadmap/milestone consistency (the "Workflow Gates" section) only applies when *moving* issues between milestones -- it does not require assignment at creation.

### Research Insights: Enforcement Tier Analysis

Per the `skill-enforced-convention-pattern` learning (2026-03-19), there are three enforcement tiers:

- **PreToolUse hooks** (strongest): Syntactic rules -- pattern-match on tool inputs. A hook CAN detect `gh issue create` without `--milestone`. This is mechanical prevention.
- **Skill instructions** (medium): Semantic rules evaluated at specific workflow phases. Skills can read `roadmap.md` to determine the correct milestone. This is LLM-evaluated at the right phase.
- **Prose rules** (weakest): AGENTS.md and constitution entries. These require agent compliance with no verification.

This plan uses all three tiers for defense-in-depth:

1. **Hook** (Guard 5 in `guardrails.sh`): Blocks `gh issue create` without `--milestone` in the local shell
2. **Skill instructions**: Updated plan/brainstorm/workshop skills with milestone assignment steps
3. **Prose**: AGENTS.md hard rule and constitution.md convention

## Approach

### Strategy: Three-tier enforcement (defense-in-depth)

1. **Hook layer (PreToolUse guard):** Add Guard 5 to `guardrails.sh` that blocks `gh issue create` commands missing `--milestone`. This is syntactic enforcement -- the strongest tier. It prevents the agent from creating issues without milestones in the local shell. It does NOT run in CI (GitHub Actions), so tiers 2 and 3 are still needed.

2. **Convention layer (AGENTS.md rule):** Add a hard rule that all `gh issue create` invocations must include milestone assignment. This catches agent-prompted issue creation in CI and interactive sessions. Per the "gotchas-only" principle from the `lean-agents-md-gotchas-only` learning, this rule belongs in AGENTS.md because agents will not discover it on their own -- milestone assignment is not obvious from the `gh` CLI help text.

3. **Implementation layer (code changes):** Update each concrete issue creation surface to include milestone assignment. For shell scripts and workflow `run:` blocks, add `--milestone` flag. For agent-prompted creation (claude-code-action prompts), update the prompt text to instruct milestone assignment.

### Milestone determination logic

Different surfaces create issues with different domain context. The milestone assignment strategy varies:

| Surface Type | Milestone Determination | Rationale |
|---|---|---|
| **Operational alerts** (token expiry, drift, review reminders) | Default to "Post-MVP / Later" unless the alert is P0/P1 | Operational issues are maintenance, not roadmap features |
| **Content/marketing** (content-publisher, growth-audit, SEO/AEO) | Default to "Post-MVP / Later" unless CPO overrides | Marketing issues are typically low-urgency improvements |
| **Agent-prompted** (roadmap-review, competitive-analysis, content-generator) | Agent reads `roadmap.md` and assigns based on phase fit | These agents already have roadmap context |
| **Skills** (plan, brainstorm, brand-workshop, validation-workshop) | CPO determines via domain review or user selects | Feature work requires product judgment |

### Key learning from #1080

`gh issue create --milestone` requires the milestone **title string**, not the integer number. The two-step pattern (create, then PATCH) is needed if using milestone numbers. For simplicity, use title strings in all surfaces.

## Surfaces to Modify

### Category 0: PreToolUse hook guard (defense-in-depth)

- [ ] Add Guard 5 to `.claude/hooks/guardrails.sh` -- block `gh issue create` without `--milestone`

**Implementation detail:** Match `gh issue create` (or `gh\s+issue\s+create`) in the command string, then check if `--milestone` is present. If missing, deny with message "BLOCKED: gh issue create must include --milestone. Default to 'Post-MVP / Later' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."

```bash
# Guard 5: Block gh issue create without --milestone
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create'; then
  if ! echo "$COMMAND" | grep -qE '--milestone'; then
    jq -n '{
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: gh issue create must include --milestone. Default to '\''Post-MVP / Later'\'' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."
      }
    }'
    exit 0
  fi
fi
```

**Important:** Use `(^|&&|\|\||;)` anchoring per constitution.md convention -- do not anchor to `^` alone since the Bash tool chains commands. Also update AGENTS.md hook awareness line to include Guard 5.

### Category 1: Shell scripts (direct `gh issue create` -- add `--milestone` flag)

- [ ] `scripts/content-publisher.sh` (line 452) -- add `--milestone "Post-MVP / Later"`

Current code:

```bash
if gh issue create --title "$title" --label "$labels" --body "$body"; then
```

Change to:

```bash
if gh issue create --title "$title" --label "$labels" --milestone "Post-MVP / Later" --body "$body"; then
```

- [ ] `scripts/strategy-review-check.sh` (line 145) -- add `--milestone "Post-MVP / Later"`

Current code:

```bash
if gh issue create \
  --title "$expected_title" \
  --body "$issue_body" \
  --label "$LABEL"; then
```

Change to:

```bash
if gh issue create \
  --title "$expected_title" \
  --body "$issue_body" \
  --label "$LABEL" \
  --milestone "Post-MVP / Later"; then
```

### Category 2: GitHub Actions workflows (direct `gh issue create` -- add `--milestone` flag)

- [ ] `.github/workflows/review-reminder.yml` (line 129) -- add `--milestone "Post-MVP / Later"`

Current code:

```yaml
if gh issue create \
  --title "$expected_title" \
  --body "$issue_body" \
  --label "review-reminder"; then
```

Change to:

```yaml
if gh issue create \
  --title "$expected_title" \
  --body "$issue_body" \
  --label "review-reminder" \
  --milestone "Post-MVP / Later"; then
```

- [ ] `.github/workflows/scheduled-terraform-drift.yml` (line 180) -- add `--milestone "Post-MVP / Later"`

Current code:

```yaml
gh issue create \
  --title "$TITLE" \
  --label "infra-drift" \
  --body-file /tmp/issue-body.md
```

Change to:

```yaml
gh issue create \
  --title "$TITLE" \
  --label "infra-drift" \
  --milestone "Post-MVP / Later" \
  --body-file /tmp/issue-body.md
```

- [ ] `.github/workflows/scheduled-linkedin-token-check.yml` (line 78) -- add `--milestone "Post-MVP / Later"`

Current code:

```yaml
gh issue create --repo "$GH_REPO" \
  --title "$TITLE" \
  --label "action-required" \
  --body "$BODY"
```

Change to:

```yaml
gh issue create --repo "$GH_REPO" \
  --title "$TITLE" \
  --label "action-required" \
  --milestone "Post-MVP / Later" \
  --body "$BODY"
```

- [ ] `.github/workflows/scheduled-cf-token-expiry-check.yml` (line 121) -- same pattern as LinkedIn check

### Category 3: GitHub Actions workflows (agent-prompted -- update prompt instructions)

For all agent-prompted workflows, add this standard instruction block to the prompt:

```text
MILESTONE RULE: Every gh issue create command must include --milestone.
Use --milestone "Post-MVP / Later" for operational/maintenance issues.
For feature issues, read knowledge-base/product/roadmap.md and assign the milestone matching the relevant phase.
Available milestones: "Phase 1: Close the Loop (Mobile-First, PWA)", "Phase 2: Secure for Beta", "Phase 3: Make it Sticky", "Phase 4: Validate + Scale", "Phase 5: Desktop Native App (Browser Automation)", "Post-MVP / Later".
```

- [ ] `.github/workflows/scheduled-roadmap-review.yml` (line 59) -- add milestone instruction before "After your analysis, create a GitHub issue"
- [ ] `.github/workflows/scheduled-content-generator.yml` (lines 82, 94, 112, 119, 137) -- add milestone instruction. This workflow has 5 separate issue creation points (growth plan fallback, citation failure, build failure, broken links, audit issue). All should use `--milestone "Post-MVP / Later"`.
- [ ] `.github/workflows/scheduled-growth-audit.yml` (line 154) -- add milestone instruction to the tracking issue creation step. The CPO step (line 188) already assigns milestones retroactively; adding `--milestone "Post-MVP / Later"` at creation ensures no gap between creation and CPO assignment.
- [ ] `.github/workflows/scheduled-seo-aeo-audit.yml` (line 64) -- add milestone instruction before "create a GitHub issue titled"
- [ ] `.github/workflows/scheduled-growth-execution.yml` (line 76) -- add milestone instruction before "create a GitHub issue titled"
- [ ] `.github/workflows/scheduled-competitive-analysis.yml` (line 56) -- add milestone instruction before "create a GitHub issue titled"

### Research Insights: Agent-Prompted Enforcement

Agent-prompted issue creation is the weakest enforcement surface because:

1. The agent interprets the prompt -- it may omit `--milestone` if other parts of the prompt seem more important
2. No hook runs in CI to catch the omission
3. The `--allowedTools` list for these workflows includes `Bash` but no validation hook runs inside CI

**Mitigation:** Place the milestone instruction as the FIRST rule in the prompt (before other instructions), use capitalized "MILESTONE RULE:" prefix for salience, and include the exact flag syntax to reduce interpretation error. This follows the same pattern as the "IMPORTANT: This is an automated CI workflow" preamble already used in these prompts.

### Category 4: Skills (agent-executed -- update skill instructions)

- [ ] `plugins/soleur/skills/plan/SKILL.md` (Issue Creation section, line 476)

Current code:

```bash
gh issue create --title "<type>: <title>" --body-file <plan_path>
```

Change to two-step pattern with milestone:

```text
1. Create the issue:
   gh issue create --title "<type>: <title>" --body-file <plan_path> --milestone "Post-MVP / Later"
2. If knowledge-base/product/roadmap.md exists, read it to determine the correct milestone phase for this feature
3. If a more specific milestone is appropriate, update: gh issue edit <number> --milestone '<correct milestone title>'
```

The default `--milestone "Post-MVP / Later"` at creation satisfies the hook guard. The follow-up edit refines the assignment based on roadmap context. This avoids the "create without milestone, then assign" window where an issue briefly exists without a milestone.

- [ ] `plugins/soleur/skills/brainstorm/SKILL.md` (line 234) -- same two-step pattern

Current code:

```bash
gh issue create --title "feat: <Feature Title>" --body "..."
```

Add after the code block: "Include `--milestone 'Post-MVP / Later'` in the command. After creation, if `knowledge-base/product/roadmap.md` exists, read it to determine the correct milestone and update with `gh issue edit <number> --milestone '<milestone title>'`."

- [ ] `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` (line 11) -- update issue creation instruction

Current:

```text
If not found: create a new issue with `gh issue create --title "feat: <Topic>" --body "..."`
```

Change to:

```text
If not found: create a new issue with `gh issue create --title "feat: <Topic>" --milestone "Post-MVP / Later" --body "..."`. After creation, if `knowledge-base/product/roadmap.md` exists, read it and update the milestone to match the correct phase.
```

- [ ] `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` (line 13) -- same change as brand-workshop

### Category 5: Constitution, AGENTS.md, and hooks (governance)

- [ ] Add to `AGENTS.md` Hard Rules:

```text
- Every `gh issue create` must include `--milestone` [hook-enforced: guardrails.sh Guard 5]. Default to 'Post-MVP / Later' for operational issues. For feature issues (plan, brainstorm, work), read `knowledge-base/product/roadmap.md` to determine the correct phase.
```

This follows the AGENTS.md pattern of annotating hook-enforced rules with `[hook-enforced: ...]`. The rule is concise (one line) per the "gotchas-only" principle.

- [ ] Add to `knowledge-base/project/constitution.md` Architecture > Always:

```text
- GitHub Actions workflows and shell scripts that create issues must include `--milestone` -- issues without milestones are invisible to roadmap tracking and will drift from the canonical roadmap in `knowledge-base/product/roadmap.md`; default to 'Post-MVP / Later' for operational/maintenance issues; the monthly roadmap review re-triages defaults
```

- [ ] Update `.claude/hooks/guardrails.sh` header comment (line 4) to include Guard 5 in the block list
- [ ] Update AGENTS.md PreToolUse hooks awareness line to include "commits with missing milestone on gh issue create"

### Category 6: Fix existing un-milestoned issues

- [ ] Assign milestones to all 10 currently un-milestoned open issues (CPO determines correct milestone for each based on roadmap context)

Current un-milestoned issues:

| # | Title | Suggested Milestone | Rationale |
|---|---|---|---|
| #1149 | fix: Cloudflare challenge script blocked by CSP on docs site | Post-MVP / Later | Docs site CSP fix, not blocking any phase |
| #1146 | feat: add functional QA agent/skill for end-to-end feature verification | Post-MVP / Later | New capability, not in any current phase |
| #1142 | feat: website conversion flow review -- waitlist-first funnel | Phase 3: Make it Sticky | Marketing conversion, pre-Phase 4 |
| #1117 | pencil integration: I() insert does not support positional placement | Post-MVP / Later | Pencil tooling bug |
| #1116 | pencil integration: export_nodes uses node IDs as filenames | Post-MVP / Later | Pencil tooling bug |
| #1108 | pencil integration: set_variables requires {type, value} objects | Post-MVP / Later | Pencil tooling bug |
| #1107 | pencil integration: padding on text nodes silently rejected | Post-MVP / Later | Pencil tooling bug |
| #1106 | pencil integration: alignSelf not supported on frames | Post-MVP / Later | Pencil tooling bug |
| #1083 | [Content Publisher] LinkedIn API failed -- Vibe Coding post | Post-MVP / Later | Content publishing failure, operational |
| #1082 | [Content Publisher] LinkedIn API failed -- Brand Guide post | Post-MVP / Later | Content publishing failure, operational |

**Note:** These suggestions are preliminary. CPO should review #1142 (conversion flow) as it may belong in the Pre-Phase 4 Marketing Positioning Gate instead of Phase 3.

## Acceptance Criteria

- [ ] All 17 issue creation surfaces include milestone assignment (either `--milestone` flag or prompt instruction)
- [ ] Guard 5 added to `guardrails.sh` blocking `gh issue create` without `--milestone`
- [ ] AGENTS.md contains a hard rule mandating milestone assignment on issue creation (annotated with `[hook-enforced: guardrails.sh Guard 5]`)
- [ ] Constitution.md contains a convention for milestone assignment in workflows/scripts
- [ ] All currently un-milestoned open issues have been assigned milestones
- [ ] No regression: existing issue creation functionality works (labels, deduplication, body content)
- [ ] Guard 5 does not false-positive on `gh issue edit`, `gh issue list`, `gh issue view`, or `gh issue close` commands
- [ ] Guard 5 does not false-positive on `gh issue create` that appears inside a quoted string (e.g., in a PR body or issue comment)

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** NONE
**Decision:** N/A

This plan modifies internal workflow tooling (shell scripts, CI workflows, skill instructions). No user-facing pages or UI components are affected. The CPO's involvement is as a domain expert for milestone assignment logic, not as a UX gate.

## Test Scenarios

### Hook enforcement (Guard 5)

- Given the agent runs `gh issue create --title "test" --body "test"` without `--milestone`, when the PreToolUse hook fires, then the command is denied with a descriptive error message
- Given the agent runs `gh issue create --title "test" --milestone "Post-MVP / Later" --body "test"`, when the PreToolUse hook fires, then the command is allowed
- Given the agent runs `gh issue edit 123 --title "new title"` (no milestone needed for edit), when the PreToolUse hook fires, then the command is allowed (hook only targets `issue create`, not `issue edit`)
- Given the agent runs `echo 'use gh issue create --title ...' | gh issue comment 123 --body-file -`, when the PreToolUse hook fires, then the command is allowed (the `gh issue create` text is inside a quoted string, not a real invocation)
- Given a chained command like `gh label create "foo" || true && gh issue create --title "test"`, when the PreToolUse hook fires, then it correctly identifies the `gh issue create` portion and denies for missing `--milestone`

### Direct `gh issue create` surfaces

- Given a content-publisher failure creates a fallback issue, when the issue is created, then it has milestone "Post-MVP / Later" assigned
- Given a terraform drift is detected, when the workflow creates an issue, then it has milestone "Post-MVP / Later" assigned
- Given a token expiry is detected (LinkedIn or Cloudflare), when the workflow creates an issue, then it has milestone "Post-MVP / Later" assigned
- Given a review reminder fires for overdue reviews, when issues are created, then each has milestone "Post-MVP / Later" assigned

### Agent-prompted surfaces

- Given the growth audit agent creates tracking issues, when the CPO step runs, then each issue already has a milestone (not left blank for CPO to assign retroactively)
- Given the content generator agent encounters a build failure, when it creates an issue, then the issue has milestone "Post-MVP / Later"
- Given the competitive analysis agent creates a summary issue, when the issue is created, then it has milestone "Post-MVP / Later"

### Skill surfaces

- Given the plan skill creates a GitHub issue, when the issue is created, then it has a milestone matching the roadmap phase for the feature
- Given the brainstorm skill creates a GitHub issue, when the issue is created, then it has a milestone matching the roadmap phase for the feature

### Verification

- Given the monthly roadmap review runs, when it scans for un-milestoned issues, then it finds zero (enforcement prevents the gap)
- Given a milestone title is used with `--milestone`, when the milestone title matches an existing GitHub milestone, then the issue is created successfully
- Given a milestone title does not match any existing milestone (typo or renamed), when `gh issue create --milestone` runs, then the command fails visibly (not silently)

## Implementation Notes

### Milestone title strings

Use exact title strings from GitHub:

- `Phase 1: Close the Loop (Mobile-First, PWA)`
- `Phase 2: Secure for Beta`
- `Phase 3: Make it Sticky`
- `Phase 4: Validate + Scale`
- `Phase 5: Desktop Native App (Browser Automation)`
- `Post-MVP / Later`

### Two-step pattern for skills

For skills where the agent needs roadmap context to choose the right milestone, use the two-step pattern:

1. Create the issue with `--milestone "Post-MVP / Later"` (satisfies the hook guard)
2. Read `roadmap.md` to determine the correct phase
3. If a more specific milestone applies: `gh issue edit <number> --milestone '<milestone title>'`

This avoids the "create without milestone" window AND the `--milestone 1` integer gotcha documented in `knowledge-base/project/learnings/2026-03-24-monthly-roadmap-review-process.md`.

### Default milestone rationale

"Post-MVP / Later" as the default for operational/maintenance issues is deliberate:

- It ensures every issue appears in milestone tracking
- Operational issues rarely block product phases
- The monthly roadmap review (`scheduled-roadmap-review.yml`) will re-triage and promote issues to earlier phases if needed
- Better to have an issue in the wrong milestone (visible, correctable) than in no milestone (invisible)

### Edge cases

**Milestone renamed:** If a milestone title changes (e.g., "Phase 3: Make it Sticky" becomes "Phase 3: Make it Indispensable"), all hardcoded `--milestone` strings in workflows and scripts will fail at runtime. `gh issue create --milestone` returns a non-zero exit code when the title does not match. This is the correct behavior -- loud failure is better than silent omission. The fix is to update the title strings in all surfaces. To find them: `grep -rn 'Post-MVP / Later\|Phase [1-5]:' .github/workflows/ scripts/ plugins/soleur/skills/`.

**New milestone added:** If a new phase is added to the roadmap (e.g., "Phase 6: International"), no existing code needs to change -- the default "Post-MVP / Later" still works and the roadmap review will re-triage. The new milestone title should be added to the "Available milestones" instruction block in agent-prompted workflows.

**Milestone deleted/closed:** If a milestone is closed (e.g., Phase 1 completes), issues can still be assigned to closed milestones. No action needed for existing code. However, new issues should not be assigned to closed milestones -- the CPO step in growth-audit and the skill two-step pattern should check milestone state.

**`--repo` flag interaction:** Some workflows use `--repo "$GH_REPO"` (linkedin-token-check, cf-token-expiry-check). The `--milestone` flag works with `--repo` -- it looks up the milestone in the specified repo, not the default repo.

### Hook guard design considerations

**False positive risk:** The hook matches `gh issue create` as a substring. Potential false positives:

- `echo "To create an issue, run: gh issue create --title ..."` -- this contains the substring but is not executing it. The hook uses the same `(^|&&|\|\||;)` anchoring as Guard 1, which correctly ignores strings inside echo/printf. However, if the agent constructs a command dynamically (e.g., `eval "gh issue create ..."`), the hook may not catch the eval'd command. This is acceptable -- `eval` usage is rare and discouraged.
- `gh issue comment 123 --body "... gh issue create ..."` -- the substring appears inside a `--body` argument. The `(^|&&|\|\||;)` anchor prevents this false positive because `gh issue create` is not at a command boundary.

**Exit code preservation:** The hook must exit 0 after writing the deny JSON, per the guardrails.sh pattern. It must NOT exit non-zero, which would be interpreted as a hook failure rather than a deny decision.

### Relevant learnings applied

| Learning | How Applied |
|---|---|
| `2026-03-24-monthly-roadmap-review-process` | Milestone title vs integer gotcha; two-step pattern |
| `2026-03-19-skill-enforced-convention-pattern` | Three-tier enforcement strategy (hook + skill + prose) |
| `2026-02-25-lean-agents-md-gotchas-only` | AGENTS.md rule kept to one line; detailed guidance in constitution |
| `2026-02-21-github-actions-workflow-security-patterns` | `gh issue create` exit code checking pattern |
| `2026-03-21-github-actions-heredoc-yaml-and-credential-masking` | HEREDOC body indentation in YAML `run: \|` blocks -- `--milestone` must be at same indent level |
| `2026-02-22-github-issue-auto-close-syntax` | Pattern for ensuring `Closes #N` in PR body (analogous enforcement gap) |
