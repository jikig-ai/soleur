---
title: "feat: Domain-First Directory Restructure"
type: feat
date: 2026-02-12
version_bump: MAJOR
---

# feat: Domain-First Directory Restructure

[Updated 2026-02-12 after plan review + PR #60 merge (commands consolidated into skills)]

## Overview

Restructure the Soleur plugin to use domain-first directory organization. Cross-domain components stay at root (root IS the shared namespace). Engineering-specific components move into `engineering/` subdirectories. ~30 file moves total. Single atomic commit.

## Current State (post PR #60)

| Component | Count | Current Structure |
|-----------|-------|-------------------|
| Agents | 22 | `agents/{research,review,design,workflow}/` |
| Commands | 8 | `commands/soleur/` (all core workflow) |
| Skills | 35 | `skills/<name>/` (flat) |

## Proposed Solution

Move engineering-specific agents and skills into `engineering/` subdirectories. Commands require zero moves -- they are all core workflow already under `commands/soleur/`. Cross-domain components stay at root.

## Target Structure

```
agents/
  research/                    # Cross-domain (5 agents, unchanged)
  workflow/                    # Cross-domain (2 agents, unchanged)
  engineering/
    review/                    # 14 review agents (moved from agents/review/)
    design/                    # 1 design agent (moved from agents/design/)

commands/
  soleur/                      # All 8 commands (unchanged, no moves needed)

skills/
  brainstorming/               # Cross-domain (20 skills, unchanged)
  git-worktree/
  changelog/
  ... (20 cross-domain skills stay at root)
  engineering/                 # 15 engineering-specific skills
    agent-native-architecture/
    agent-native-audit/
    atdd-developer/
    ...
```

## Classification

### Cross-domain agents (7) -- stay at root

| Agent | Current Path | Action |
|-------|-------------|--------|
| best-practices-researcher | agents/research/ | No move |
| framework-docs-researcher | agents/research/ | No move |
| git-history-analyzer | agents/research/ | No move |
| learnings-researcher | agents/research/ | No move |
| repo-research-analyst | agents/research/ | No move |
| pr-comment-resolver | agents/workflow/ | No move |
| spec-flow-analyzer | agents/workflow/ | No move |

### Engineering agents (15) -- move to engineering/

| Agent | From | To |
|-------|------|-----|
| agent-native-reviewer | agents/review/ | agents/engineering/review/ |
| architecture-strategist | agents/review/ | agents/engineering/review/ |
| code-quality-analyst | agents/review/ | agents/engineering/review/ |
| code-simplicity-reviewer | agents/review/ | agents/engineering/review/ |
| data-integrity-guardian | agents/review/ | agents/engineering/review/ |
| data-migration-expert | agents/review/ | agents/engineering/review/ |
| deployment-verification-agent | agents/review/ | agents/engineering/review/ |
| dhh-rails-reviewer | agents/review/ | agents/engineering/review/ |
| kieran-rails-reviewer | agents/review/ | agents/engineering/review/ |
| legacy-code-expert | agents/review/ | agents/engineering/review/ |
| pattern-recognition-specialist | agents/review/ | agents/engineering/review/ |
| performance-oracle | agents/review/ | agents/engineering/review/ |
| security-sentinel | agents/review/ | agents/engineering/review/ |
| test-design-reviewer | agents/review/ | agents/engineering/review/ |
| ddd-architect | agents/design/ | agents/engineering/design/ |

### Commands (8) -- all stay put

All commands are core workflow under `commands/soleur/`: brainstorm, compound, help, one-shot, plan, review, sync, work. Zero moves.

### Cross-domain skills (20) -- stay at root

agent-browser, brainstorming, changelog, compound-docs, create-agent-skills, deepen-plan, every-style-editor, feature-video, file-todos, gemini-imagegen, git-worktree, heal-skill, plan-review, rclone, report-bug, ship, skill-creator, spec-templates, triage, user-story-writer

### Engineering skills (15) -- move to engineering/

| Skill | Reason |
|-------|--------|
| agent-native-architecture | Software architecture patterns |
| agent-native-audit | Code auditing for agent-native patterns |
| andrew-kane-gem-writer | Ruby gem development |
| atdd-developer | Test-driven development |
| deploy-docs | Plugin docs deployment |
| dhh-rails-style | Rails code style |
| dspy-ruby | Ruby LLM framework |
| frontend-design | Frontend UI development |
| release-docs | Plugin docs release |
| reproduce-bug | Code bug reproduction |
| resolve-parallel | Parallel PR comment resolution |
| resolve-pr-parallel | PR comment resolution |
| resolve-todo-parallel | Todo resolution |
| test-browser | Browser testing |
| xcode-test | iOS testing |

## Acceptance Criteria

- [x] Plugin loader confirmed to discover agents in nested `engineering/` directories
- [x] 15 engineering agents moved to `agents/engineering/{review,design}/`
- [N/A] ~~15 engineering skills moved to `skills/engineering/`~~ (skill loader does NOT recurse into subdirectories -- discovered during Phase 0 testing)
- [x] 0 command moves (all already under `commands/soleur/`)
- [x] All broken cross-references fixed
- [x] AGENTS.md directory structure documentation updated + "Adding a new domain" section
- [x] README.md tables include domain classification
- [x] Version bump (MAJOR) applied to triad + root README + bug report template
- [x] CHANGELOG updated with BREAKING notice
- [x] Constitution.md updated
- [x] `grep -r` audit confirms zero stale path references
- [x] Old empty directories removed (review/, design/)
- [ ] Single atomic commit

## Test Scenarios

- Given the restructured plugin, when Claude Code loads it, then all 22 agents are discoverable by name
- Given `Task code-quality-analyst` is called, when it runs, then the agent at `agents/engineering/review/code-quality-analyst.md` is found
- Given a cross-domain agent (repo-research-analyst) stays at `agents/research/`, when called, then it resolves unchanged
- Given an engineering skill (dhh-rails-style) moves to `skills/engineering/`, when invoked, then it loads correctly
- Given a new domain is needed, when `agents/product/` is created, then the plugin discovers it without config changes

## Implementation Phases

### Phase 0: Verify Plugin Loader Recursion

**BLOCKER.** If the loader doesn't walk nested directories, the plan is void.

```bash
mkdir -p plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/code-simplicity-reviewer.md plugins/soleur/agents/engineering/review/
# Reload plugin, verify agent is still callable by name
# If fails: abort, investigate alternatives
# If succeeds: continue
```

Also test: does the skill loader handle `skills/engineering/<name>/SKILL.md`?

### Phase 1: Move Files (30 moves)

**1a. Move engineering agents (14 remaining after Phase 0 test):**

```bash
mkdir -p plugins/soleur/agents/engineering/design/

git mv plugins/soleur/agents/review/agent-native-reviewer.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/architecture-strategist.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/code-quality-analyst.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/data-integrity-guardian.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/data-migration-expert.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/deployment-verification-agent.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/dhh-rails-reviewer.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/kieran-rails-reviewer.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/legacy-code-expert.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/pattern-recognition-specialist.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/performance-oracle.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/security-sentinel.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/review/test-design-reviewer.md plugins/soleur/agents/engineering/review/
git mv plugins/soleur/agents/design/ddd-architect.md plugins/soleur/agents/engineering/design/

rmdir plugins/soleur/agents/review/ plugins/soleur/agents/design/
```

**1b. Move engineering skills (15):**

```bash
mkdir -p plugins/soleur/skills/engineering/

git mv plugins/soleur/skills/agent-native-architecture plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/agent-native-audit plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/andrew-kane-gem-writer plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/atdd-developer plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/deploy-docs plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/dhh-rails-style plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/dspy-ruby plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/frontend-design plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/release-docs plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/reproduce-bug plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/resolve-parallel plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/resolve-pr-parallel plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/resolve-todo-parallel plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/test-browser plugins/soleur/skills/engineering/
git mv plugins/soleur/skills/xcode-test plugins/soleur/skills/engineering/
```

### Phase 2: Fix Broken References

**2.1 Agent category references in commands/skills that reference old paths:**

Scan all commands and skills for references to:
- `agents/review/` → `agents/engineering/review/`
- `agents/design/` → `agents/engineering/design/`
- `skills/dhh-rails-style` → `skills/engineering/dhh-rails-style`
- `skills/frontend-design` → `skills/engineering/frontend-design`
- `skills/agent-native-architecture` → `skills/engineering/agent-native-architecture`
- And all other moved skill paths

Key files to check (from earlier cross-reference analysis):

| File | What to update |
|------|---------------|
| `commands/soleur/review.md` | Agent category references (review/ → engineering/review/) |
| `skills/deepen-plan/SKILL.md` | Agent directory refs, skill path refs for dhh-rails-style, frontend-design, agent-native-architecture |
| `skills/deploy-docs/SKILL.md` | Agent/skill counting globs (now needs recursive find) |
| `skills/release-docs/SKILL.md` | Agent/skill counting globs (now needs recursive find) |
| `commands/soleur/help.md` | Agent listing patterns |

**2.2 Counting pattern updates:**

```bash
# Old (won't match nested structure)
ls plugins/soleur/agents/*.md | wc -l

# New (recursive)
find plugins/soleur/agents -name "*.md" -not -name "README.md" | wc -l
```

Apply to all files that count agents, commands, or skills.

**2.3 AGENTS.md validation globs:**

```bash
# Old
grep -E '`(references|assets|scripts)/[^`]+`' skills/*/SKILL.md

# New (recursive)
grep -rE '`(references|assets|scripts)/[^`]+`' skills/ --include="SKILL.md"
```

**2.4 Full stale-path scan:**

After fixing known references, run a comprehensive grep to catch anything missed:

```bash
# Check for any reference to old agent paths (not under engineering/)
grep -r "agents/review/" plugins/soleur/ --include="*.md" | grep -v "engineering/review/"
grep -r "agents/design/" plugins/soleur/ --include="*.md" | grep -v "engineering/design/"

# Check for any reference to moved skills not under engineering/
for skill in agent-native-architecture agent-native-audit andrew-kane-gem-writer atdd-developer deploy-docs dhh-rails-style dspy-ruby frontend-design release-docs reproduce-bug resolve-parallel resolve-pr-parallel resolve-todo-parallel test-browser xcode-test; do
  grep -r "skills/$skill" plugins/soleur/ --include="*.md" | grep -v "engineering/$skill"
done
```

### Phase 3: Docs + Version Bump + Verify

**3.1 `plugins/soleur/AGENTS.md`:**

Update directory structure diagram:

```text
agents/
  research/        # Cross-domain research agents (5)
  workflow/        # Cross-domain workflow agents (2)
  engineering/
    review/        # Engineering code review agents (14)
    design/        # Engineering architecture agents (1)

commands/
  soleur/          # Core workflow commands (8)

skills/
  <skill-name>/    # Cross-domain skills at root (20)
  engineering/     # Engineering-specific skills (15)
```

Add section: "Adding a new domain: create `agents/<domain>/`, `skills/<domain>/` directories. The plugin loader discovers components recursively. Commands stay under `commands/soleur/` as they are domain-agnostic workflow orchestrators."

Update validation globs per Phase 2.3.

**3.2 `plugins/soleur/README.md`:**

Reorganize tables with domain sections (cross-domain vs engineering).

**3.3 `knowledge-base/overview/constitution.md`:**

Update agent organization convention to: "Organize agents by domain first (engineering/, etc.), then by function (review/, design/). Cross-domain agents stay at root level (research/, workflow/)."

**3.4 Version bump (MAJOR):**

- `plugins/soleur/.claude-plugin/plugin.json` -- bump version, update description counts
- `plugins/soleur/CHANGELOG.md`:

```markdown
## [Unreleased]

### Changed
- **BREAKING**: Directory structure reorganized by domain
- Engineering-specific agents moved to `agents/engineering/` (15 agents: 14 review + 1 design)
- Engineering-specific skills moved to `skills/engineering/` (15 skills)
- Cross-domain components remain at root (7 agents, 8 commands, 20 skills)
- Counting globs updated for recursive discovery
- README tables include domain classification

### Removed
- Flat `agents/review/`, `agents/design/` directories (now under `agents/engineering/`)
```

- Root `README.md` -- update version badge
- `.github/ISSUE_TEMPLATE/bug_report.yml` -- update version placeholder

**3.5 Verification:**

```bash
# 1. Stale path audit
grep -r "agents/review/" plugins/soleur/ --include="*.md" | grep -v "engineering/review/"
grep -r "agents/design/" plugins/soleur/ --include="*.md" | grep -v "engineering/design/"

# 2. Moved skill audit
for skill in agent-native-architecture agent-native-audit andrew-kane-gem-writer atdd-developer deploy-docs dhh-rails-style dspy-ruby frontend-design release-docs reproduce-bug resolve-parallel resolve-pr-parallel resolve-todo-parallel test-browser xcode-test; do
  hits=$(grep -r "skills/$skill" plugins/soleur/ --include="*.md" | grep -v "engineering/$skill" | wc -l)
  [ "$hits" -gt 0 ] && echo "STALE: skills/$skill referenced without engineering/ prefix ($hits hits)"
done

# 3. File counts
echo "Agents: $(find plugins/soleur/agents -name '*.md' -not -name 'README.md' | wc -l) (expected: 22)"
echo "Commands: $(find plugins/soleur/commands -name '*.md' -not -name 'README.md' | wc -l) (expected: 8)"
echo "Skills: $(find plugins/soleur/skills -name 'SKILL.md' | wc -l) (expected: 35)"

# 4. Old directories removed
ls -d plugins/soleur/agents/review/ 2>/dev/null && echo "FAIL: old review/ still exists"
ls -d plugins/soleur/agents/design/ 2>/dev/null && echo "FAIL: old design/ still exists"

# 5. Relative path check
grep -r '\.\.\/' plugins/soleur/agents/ plugins/soleur/commands/ --include="*.md"

# 6. Version consistency
grep -o '"version": "[^"]*"' plugins/soleur/.claude-plugin/plugin.json
```

## Dependencies & Risks

- **BLOCKER: Plugin loader recursion** -- Phase 0 tests this. If it fails, plan is void.
- **Risk: Runtime skill mount paths** -- Verify `.claude/skills/<name>/` still resolves for skills in `engineering/` subdirectory.
- **Risk: Missed references** -- Phase 2.4 comprehensive grep + Phase 3.5 verification audit catches these.

## Rollback Plan

```bash
git revert <commit-sha>  # Single atomic commit
```

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-12-domain-directory-restructure-brainstorm.md`
- Spec: `knowledge-base/specs/feat-domain-directory-restructure/spec.md`
- Issue: [#53](https://github.com/jikig-ai/soleur/issues/53)
- PR #60: Commands consolidated into skills (changes component counts)
- Plan review: DHH, Kieran, Simplicity -- drop `shared/`, drop placeholders, root = shared
