# Feature: Consolidate Commands to Skills

## Problem Statement

17 Soleur commands exist with no skill equivalent. 10 of these would be useful to agents during workflows (e.g., `resolve_pr_parallel` during code review, `test-browser` during QA), but as command-only items, agents cannot discover or invoke them. Additionally, 1 command (`create-agent-skill`) is a pure wrapper that duplicates an existing skill.

## Goals

- Convert 10 utility commands into skills for agent discoverability
- Delete 1 redundant pure-wrapper command
- Reduce command count from 26 to 15
- Increase skill count from 19 to 29
- Maintain all existing functionality

## Non-Goals

- Converting orchestration commands (brainstorm, plan, work, review, compound, sync, triage, agent-native-audit) -- these legitimately compose multiple skills
- Converting user-only commands (deploy-docs, generate_command, heal-skill, feature-video, report-bug, help, lfg) -- these require human judgment
- Changing how existing skills work
- Modifying the orchestration commands to reference the new skills (can be done later)

## Functional Requirements

### FR1: Convert 10 commands to skills

Each of these commands becomes a skill directory with SKILL.md:

| Command File | Skill Directory |
|-------------|----------------|
| `release-docs.md` | `skills/release-docs/` |
| `reproduce-bug.md` | `skills/reproduce-bug/` |
| `xcode-test.md` | `skills/xcode-test/` |
| `plan_review.md` | `skills/plan-review/` |
| `resolve_todo_parallel.md` | `skills/resolve-todo-parallel/` |
| `changelog.md` | `skills/changelog/` |
| `deepen-plan.md` | `skills/deepen-plan/` |
| `resolve_pr_parallel.md` | `skills/resolve-pr-parallel/` |
| `test-browser.md` | `skills/test-browser/` |
| `resolve_parallel.md` | `skills/resolve-parallel/` |

### FR2: Delete pure-wrapper command

Remove `commands/create-agent-skill.md` -- the `create-agent-skills` skill already provides this functionality.

### FR3: Skill format compliance

Each new SKILL.md must include:
- YAML frontmatter with `name` (matching directory name, kebab-case) and `description` (third person, with trigger keywords)
- Content adapted from the command markdown
- Proper reference links if `scripts/` or `references/` subdirectories exist

## Technical Requirements

### TR1: Plugin versioning

Update the versioning triad:
- `.claude-plugin/plugin.json` -- MINOR version bump (new skills added)
- `CHANGELOG.md` -- document all changes
- `README.md` -- update component counts and tables
- Root `README.md` -- update version badge
- `.github/ISSUE_TEMPLATE/bug_report.yml` -- update placeholder version

### TR2: Naming normalization

Convert underscore-based command names to kebab-case skill names:
- `plan_review` -> `plan-review`
- `resolve_todo_parallel` -> `resolve-todo-parallel`
- `resolve_pr_parallel` -> `resolve-pr-parallel`
- `resolve_parallel` -> `resolve-parallel`
