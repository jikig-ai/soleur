---
title: "feat: Headless Mode for Repeatable Workflows"
type: feat
date: 2026-03-03
---

# feat: Headless Mode for Repeatable Workflows

## Overview

Add a `--headless` flag convention to Soleur skills so they can run without interactive prompts. When `$ARGUMENTS` contains `--headless`, skills use sensible defaults instead of calling AskUserQuestion. This enforces the existing constitution rule (line 71) that every prompt must have a bypass path for programmatic callers.

**Scope:** ship, compound (+ compound-capture), work skills + worktree-manager.sh `--yes` flag + constitution update. This PR addresses **local headless mode** — a human runs `skill: soleur:ship --headless` locally to avoid routine confirmations. Unattended CI headless (scheduled GitHub Actions workflows) is descoped to follow-up issues.

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

If `$ARGUMENTS` contains `--headless`, set headless mode. Strip `--headless` from `$ARGUMENTS` before processing remaining positional arguments.

**Naming convention:** `--headless` for skills (semantic: "non-interactive mode"). `--yes` for shell scripts (POSIX convention: auto-confirm prompts). These are independent flags for different layers.

### Flag Propagation

`--headless` does NOT propagate automatically through Skill tool invocations. Each skill is responsible for explicitly forwarding the flag to child skill invocations:

- ship → `skill: soleur:compound --headless`
- compound → `skill: soleur:compound-capture --headless`
- work → `skill: soleur:compound --headless` and `skill: soleur:ship --headless` (Phase 4 handoff, when invoked directly)

## Technical Considerations

### Prompt Inventory

**ship (4 prompts to bypass):**

| Location | Current Prompt | Headless Default |
|----------|---------------|-----------------|
| Phase 2 | "Run /compound to capture learnings?" | Auto-invoke `skill: soleur:compound --headless` |
| Phase 4 | "Test files missing — write tests now?" | Continue without writing (CI gate catches this) |
| Phase 6 | "Confirm PR title/body before editing" | Auto-accept generated title/body from diff analysis |
| Phase 7 | "Flaky CI check — proceed or wait?" | Abort (consistent with headless abort-on-error principle) |

**compound (5 prompts to bypass):**

| Location | Current Prompt | Headless Default |
|----------|---------------|-----------------|
| Constitution promotion | "Promote anything to constitution?" | Auto-promote using LLM judgment |
| Route-to-definition | "Accept/Skip/Edit component edit?" | Auto-accept LLM-proposed edit |
| Auto-consolidation | "Proceed with consolidation?" + per-proposal gates | Auto-accept all proposals |
| Decision menu | 7-option menu after capture | Auto-select "Continue workflow" |
| Worktree cleanup | "Feature complete? Clean up worktree?" | Auto-skip (cleanup-merged handles this) |

**compound-capture (3 additional prompts):**

| Location | Current Prompt | Headless Default |
|----------|---------------|-----------------|
| Step 2 | "I need a few details to document this properly" | Infer from session context; skip fields that can't be inferred |
| Step 3 | "Found similar issue — create new, update existing?" | Create new doc with cross-reference |
| Auto-consolidation Step E | "Archive the source artifacts?" | Auto-archive (yes) |

**work (0 new changes needed):**

Work already has pipeline mode that skips all prompts when `$ARGUMENTS` contains a file path. `--headless` is stripped from `$ARGUMENTS` and pipeline mode handles the rest. The only addition: forward `--headless` to compound and ship in the Phase 4 handoff when invoked directly by the user.

**worktree-manager.sh (4 `read -r` calls):**

| Line | Function | Prompt | `--yes` Default |
|------|----------|--------|-----------------|
| 84 | `create_worktree()` | "Switch to it instead? (y/n)" | Auto-switch (yes) |
| 96 | `create_worktree()` | "Proceed? (y/n)" | Auto-proceed (yes) |
| 231 | `switch_worktree()` | "Switch to which worktree?" | Require name argument |
| 316 | `cleanup_worktrees()` | "Remove N worktree(s)? (y/n)" | Auto-remove (yes) |

### Safety Constraints

**Branch requirement for headless compound:** Headless compound must abort if on `main` or `master`. This is defense-in-depth — PreToolUse hooks and AGENTS.md already enforce this, but a one-liner check in compound catches it at the skill level too.

**Deduplication:** Constitution promotions use substring match against existing rules to prevent duplicates.

**Error handling in headless mode:**

- Test failure in headless ship → abort pipeline, do not attempt auto-fix
- Merge conflict in headless ship → abort pipeline, log conflicting files
- Flaky CI in headless ship → abort (do not auto-proceed past failed checks)
- YAML validation failure in headless compound → skip the problematic learning, continue with remaining
- All abort conditions produce clear error messages for the user to investigate

### Constitution Update

Add to the `$ARGUMENTS` bypass rule (line 71):

```markdown
**Headless mode convention:** When `$ARGUMENTS` contains `--headless`,
all interactive prompts use sensible defaults. Skills must:
1. Strip `--headless` from $ARGUMENTS before processing remaining args
2. Forward `--headless` to any child Skill tool invocations
3. Abort on unrecoverable errors instead of prompting
4. Never run headless compound on main/master
```

## Acceptance Criteria

- [x] `skill: soleur:ship --headless` runs to completion without any interactive prompts
- [x] `skill: soleur:compound --headless` auto-promotes learnings without human approval
- [x] `skill: soleur:compound --headless` aborts if on main/master branch
- [x] `skill: soleur:work --headless knowledge-base/project/specs/feat-foo/tasks.md` strips `--headless` and processes the plan path correctly
- [x] `worktree-manager.sh create feat-foo --yes` completes without `read -r` prompt
- [x] `worktree-manager.sh cleanup --yes` completes without `read -r` prompt
- [x] Constitution.md updated with `--headless` convention

## Test Scenarios

- Given `--headless` ship invokes compound, which invokes compound-capture, then compound-capture also receives `--headless` and skips all prompts (full propagation chain)
- Given `$ARGUMENTS` is `--headless knowledge-base/project/specs/feat-foo/tasks.md`, when work parses arguments, then `--headless` is stripped and the plan path is treated correctly
- Given headless compound runs on main branch, then compound aborts with error before any promotions
- Given headless ship runs and tests fail, then pipeline aborts with clear error message
- Given headless ship runs and CI is flaky, then pipeline aborts (does not auto-proceed)
- Given `worktree-manager.sh create feat-foo --yes` and the branch already exists, then auto-switches without prompting
- Given `$ARGUMENTS` is `--headless` with no plan path, when work receives it, then work fails with a clear error (headless work requires a plan)

## Descoped Items

The following items are descoped to follow-up GitHub issues:

**1. scheduled-ship-merge.yml** — "Qualifying PRs" criteria undefined, workflow architecture different from single-skill invocation, needs deduplication with existing auto-merge.

**2. scheduled-compound-review.yml** — Compound requires session context that doesn't exist in a cron job. Needs a new "sessionless compound" architecture.

**3. PreToolUse hook verification in claude-code-action** — Whether hooks fire is unknown, needs empirical testing. Prerequisite for CI headless, not local headless.

## Dependencies & Risks

**Risk: Constitution bloat from auto-promotion.** Mitigation: deduplication via substring match, PR review as the quality gate.

**Risk: `--headless` flag interpreted as plan path by work skill.** Mitigation: strip `--headless` before processing, documented in constitution.

**Risk: Compound HARD RULE about constitution promotion.** Headless mode satisfies the HARD RULE — promotion runs, it just auto-approves. The rule is about not skipping promotion, not about requiring human approval.

## References & Research

### Internal References

- Constitution `$ARGUMENTS` bypass rule: `knowledge-base/overview/constitution.md:71`
- Schedule skill flag pattern: `plugins/soleur/skills/schedule/SKILL.md:18`
- Ship skill: `plugins/soleur/skills/ship/SKILL.md`
- Compound skill: `plugins/soleur/skills/compound/SKILL.md`
- Compound-capture skill: `plugins/soleur/skills/compound-capture/SKILL.md`
- Work skill: `plugins/soleur/skills/work/SKILL.md`
- Worktree manager: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- Merge-pr (reference headless skill): `plugins/soleur/skills/merge-pr/SKILL.md`

### Related Work

- Issue: #393
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-03-headless-mode-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-headless-mode/spec.md`
- Learning (plugin headless auto-load failure): `knowledge-base/project/learnings/2026-02-25-plugin-command-double-namespace.md`
- Learning (skill handoff contradicts pipeline): `knowledge-base/project/learnings/2026-03-03-skill-handoff-contradicts-pipeline-continuation.md`
- Learning (skill code fence permission flow): `knowledge-base/project/learnings/2026-02-22-skill-code-fence-permission-flow.md`
