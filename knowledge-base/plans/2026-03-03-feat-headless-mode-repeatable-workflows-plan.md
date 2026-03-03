---
title: "feat: Headless Mode for Repeatable Workflows"
type: feat
date: 2026-03-03
---

# feat: Headless Mode for Repeatable Workflows

## Overview

Add a `--headless` flag convention to Soleur skills so they can run without interactive prompts. When `$ARGUMENTS` contains `--headless`, skills use sensible defaults instead of calling AskUserQuestion. This enforces the existing constitution rule (line 71) that every prompt must have a bypass path for programmatic callers.

**Scope:** ship, compound, work skills + worktree-manager.sh `--yes` flag + constitution update + lefthook enforcement check. Two scheduled GitHub Actions workflows (ship-merge, compound-review) are **descoped to follow-up issues** based on SpecFlow analysis findings (see [Descoped Items](#descoped-items)).

## Problem Statement / Motivation

- 42 merge PR sessions (50%+ of top goals) are highly repeatable pipelines
- 865 AskUserQuestion calls, many routine confirmations
- Constitution mandates `$ARGUMENTS` bypass (line 71) but it's unenforced across 23+ prompts
- `merge-pr` and `changelog` are already fully headless, proving the pattern works
- One-shot pipeline stalls at compound/ship interactive gates

## Proposed Solution

### Architecture: Bottom-Up Compliance

Enforce the existing `$ARGUMENTS` bypass convention. Each skill handles `--headless` independently — no new orchestration layer, no wrapper scripts. The schedule skill is the reference implementation for flag-based bypass.

### Flag Parsing Convention

Skills parse `--headless` from `$ARGUMENTS` using word-boundary matching, then strip it before processing remaining positional arguments:

```
# In SKILL.md instruction text:
If $ARGUMENTS contains the word --headless (word-boundary match, not substring):
  Set HEADLESS_MODE = true
  Strip --headless from $ARGUMENTS before further processing
  All AskUserQuestion calls use sensible defaults instead of prompting
```

**Word-boundary matching prevents false positives:** `--headless-test` or `mentioning --headless in prose` must NOT trigger headless mode. The pattern is: `$ARGUMENTS` split by whitespace, check if any token equals exactly `--headless`.

### Flag Propagation

`--headless` does NOT propagate automatically through Skill tool invocations. When ship invokes compound, it must explicitly pass the flag: `skill: soleur:compound --headless`. Each skill is responsible for forwarding the flag to child skill invocations when in headless mode.

## Technical Considerations

### Prompt Inventory (from deep-read analysis)

**ship (2 prompts to bypass):**

| Location | Current Prompt | Headless Default |
|----------|---------------|-----------------|
| Phase 2 | "Run /compound to capture learnings?" | Auto-invoke `skill: soleur:compound --headless` |
| Phase 6 | "Confirm PR title/body before editing" | Auto-accept generated title/body from diff analysis |

**compound (5 prompts to bypass):**

| Location | Current Prompt | Headless Default |
|----------|---------------|-----------------|
| Constitution promotion | "Promote anything to constitution?" | Auto-promote using LLM judgment (max 3 per run) |
| Route-to-definition | "Accept/Skip/Edit component edit?" | Auto-accept LLM-proposed edit |
| Auto-consolidation | "Proceed with consolidation?" + per-proposal gates | Auto-accept all proposals |
| Decision menu | 7-option menu after capture | Auto-select "Continue workflow" |
| Worktree cleanup | "Feature complete? Clean up worktree?" | Auto-skip (cleanup-merged handles this) |

**work (5 prompts, all conditional on interactive mode):**

| Location | Current Prompt | Headless Default |
|----------|---------------|-----------------|
| Phase 1 | "Continue on current branch or create new?" | Continue on current branch |
| Phase 1 | "Clarifying questions + approval gate" | Skip (pipeline pre-validates input) |
| Phase 2 | "Tier 0 parallelism offer" | Auto-select without prompting |
| Phase 2 | "Tier A/B agent teams offer" | Auto-accept Tier B if eligible |
| Phase 4 | Handoff decision | Detect invocation context, auto-continue |

**worktree-manager.sh (4 `read -r` calls):**

| Line | Function | Prompt | `--yes` Default |
|------|----------|--------|-----------------|
| 84 | `create_worktree()` | "Switch to it instead? (y/n)" | Auto-switch (yes) |
| 96 | `create_worktree()` | "Proceed? (y/n)" | Auto-proceed (yes) |
| 231 | `switch_worktree()` | "Switch to which worktree?" | Require name argument |
| 316 | `cleanup_worktrees()` | "Remove N worktree(s)? (y/n)" | Auto-remove (yes) |

### Safety Constraints

**Branch requirement for headless compound:** Headless compound must abort if on `main` or `master`. Auto-promoted rules go through PR review. Add an explicit check:

```
If HEADLESS_MODE and (branch is main or master):
  Abort with error: "Headless compound cannot run on main. Create a branch first."
```

**Auto-promotion volume limit:** Max 3 constitution promotions per headless compound run. Deduplication via substring match against existing rules. Prevents constitution.md bloat.

**Error handling in headless mode:**
- Test failure in headless ship → abort pipeline, do not attempt auto-fix
- Merge conflict in headless ship → abort pipeline, log conflicting files
- YAML validation failure in headless compound → skip the problematic learning, continue with remaining
- All abort conditions produce non-zero exit code for CI reporting

### Constitution Update

Add to the `$ARGUMENTS` bypass rule (line 71) a reference implementation:

```markdown
**Headless mode convention:** When `$ARGUMENTS` contains `--headless` (exact word match),
all AskUserQuestion prompts use sensible defaults. Skills must:
1. Strip `--headless` from $ARGUMENTS before processing remaining args
2. Forward `--headless` to any child Skill tool invocations
3. Abort on unrecoverable errors instead of prompting (non-zero exit)
4. Never run headless on main/master when writing to constitution.md
```

### Lefthook Enforcement

Add a pre-commit check (warning, not blocking) that greps skills for `AskUserQuestion` and verifies the same file also contains `--headless` or a bypass pattern. Skills that are intentionally interactive-only (brainstorm, plan, brainstorm-techniques) are excluded from the check.

## Acceptance Criteria

- [ ] `skill: soleur:ship --headless` runs to completion without any AskUserQuestion calls
- [ ] `skill: soleur:compound --headless` auto-promotes learnings (max 3) without human approval
- [ ] `skill: soleur:compound --headless` aborts if on main/master branch
- [ ] `skill: soleur:work --headless knowledge-base/specs/feat-foo/tasks.md` strips `--headless` and processes the plan path correctly
- [ ] `worktree-manager.sh create feat-foo --yes` completes without `read -r` prompt
- [ ] `worktree-manager.sh cleanup --yes` completes without `read -r` prompt
- [ ] Constitution.md updated with `--headless` convention
- [ ] Lefthook check warns on new AskUserQuestion without bypass

## Test Scenarios

- Given `$ARGUMENTS` is `--headless`, when ship invokes compound, then compound receives `--headless` and skips all prompts
- Given `$ARGUMENTS` is `--headless knowledge-base/specs/feat-foo/tasks.md`, when work parses arguments, then `--headless` is detected AND `knowledge-base/specs/feat-foo/tasks.md` is treated as the plan path
- Given headless compound runs on main branch, when constitution promotion triggers, then compound aborts with error
- Given headless compound runs on feat-branch, when 5 learnings are promotion-worthy, then only 3 are promoted (max cap)
- Given headless ship runs, when tests fail, then pipeline aborts with non-zero exit
- Given `worktree-manager.sh create feat-foo --yes`, when the branch already exists, then auto-switches without prompting
- Given `$ARGUMENTS` is `--headless-test`, when ship checks for headless mode, then headless mode is NOT activated (word-boundary match)

## Descoped Items

The following items from the original spec are descoped to follow-up GitHub issues based on SpecFlow analysis:

**1. scheduled-ship-merge.yml (Gap 7, 8, 9)**
- "Qualifying PRs" criteria are undefined and require careful design
- Workflow architecture is fundamentally different from single-skill invocation
- Interaction with existing auto-merge needs deduplication logic
- **Follow-up issue:** Define qualifying criteria, workflow architecture, and concurrency handling

**2. scheduled-compound-review.yml (Gap 13, 14)**
- Compound requires session context (errors, investigation steps, solutions) that doesn't exist in a cron job
- Route-to-definition cannot function without session history
- This needs a new compound mode that accepts git-log or issue-based input
- **Follow-up issue:** Design "sessionless compound" architecture for scheduled execution

**3. PreToolUse hook verification in claude-code-action (Gap 10, 11, 12)**
- Whether hooks fire in claude-code-action is unknown and needs empirical testing
- This is a prerequisite for all scheduled workflows but not for local headless mode
- **Follow-up issue:** Verify hook execution, add inline branch checks as fallback if needed

## Dependencies & Risks

**Risk: Constitution bloat from auto-promotion.** Mitigation: 3-per-run cap, deduplication, PR review.

**Risk: `--headless` flag interpreted as plan path by work skill.** Mitigation: Explicit strip-before-process convention documented in constitution.

**Risk: Compound HARD RULE about constitution promotion.** The HARD RULE says "MUST run even in pipelines." Headless mode satisfies this — promotion runs, it just auto-approves. The HARD RULE is about not skipping promotion, not about requiring human approval.

**Dependency: No scheduled workflows in this PR.** The skill-level headless work is independent and can ship without the Actions workflows.

## References & Research

### Internal References

- Constitution `$ARGUMENTS` bypass rule: `knowledge-base/overview/constitution.md:71`
- Schedule skill flag pattern: `plugins/soleur/skills/schedule/SKILL.md:18`
- Ship skill: `plugins/soleur/skills/ship/SKILL.md`
- Compound skill: `plugins/soleur/skills/compound/SKILL.md`
- Work skill: `plugins/soleur/skills/work/SKILL.md`
- Worktree manager: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- Merge-pr (reference headless skill): `plugins/soleur/skills/merge-pr/SKILL.md`

### Related Work

- Issue: #393
- Brainstorm: `knowledge-base/brainstorms/2026-03-03-headless-mode-brainstorm.md`
- Spec: `knowledge-base/specs/feat-headless-mode/spec.md`
- Learning (plugin headless auto-load failure): `knowledge-base/learnings/2026-02-25-plugin-command-double-namespace.md`
- Learning (skill handoff contradicts pipeline): `knowledge-base/learnings/2026-03-03-skill-handoff-contradicts-pipeline-continuation.md`
- Learning (skill code fence permission flow): `knowledge-base/learnings/2026-02-22-skill-code-fence-permission-flow.md`
