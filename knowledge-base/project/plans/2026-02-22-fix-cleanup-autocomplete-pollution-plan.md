# fix: Clean up plugin loader autocomplete pollution

## Enhancement Summary

**Deepened on:** 2026-02-22
**Sections enhanced:** 4 (Root Cause, Solution, Path Updates, Risk Assessment)
**Research sources:** Claude Code plugin reference docs, existing skill `references/` patterns, codebase grep analysis

### Key Improvements
1. Confirmed approach is proven by 8 existing skills with `references/` directories (none pollute autocomplete)
2. Added exact line numbers and grep-verified path references for all 10 occurrences
3. Added verification that none of the reference files have YAML frontmatter (pure content files -- no name/description to confuse the loader)
4. Clarified that the `/bug_report` issue is likely a separate Claude Code platform behavior, not caused by the plugin

## Problem

The Claude Code plugin loader discovers unwanted entries in the `/` autocomplete menu:

1. **`/soleur:soleur:references:*`** -- 10 reference `.md` files in `commands/soleur/references/` are recursively discovered as commands. The plugin name `soleur` + path `soleur/references/<name>` creates double-prefixed names like `/soleur:soleur:references:brainstorm-brand-workshop`.

2. **`/bug_report`** and similar -- GitHub issue template files (`.github/ISSUE_TEMPLATE/bug_report.yml`, `feature_request.yml`) or other repo-level files may be surfacing in autocomplete through Claude Code's discovery mechanisms.

The intended autocomplete surface is exactly 3 commands (`/soleur:go`, `/soleur:sync`, `/soleur:help`) plus the 52 skills.

## Root Cause

Per the [Claude Code plugin reference](https://code.claude.com/docs/en/plugins-reference), the `commands/` directory is scanned for `.md` files. The official docs state "each .md file in the commands/ directory becomes a slash command." The 10 reference files were placed in `commands/soleur/references/` during the v3.0.2 context window optimization (PR #281), which extracted conditionally-loaded content from command bodies into separate files. The plugin loader discovers these recursively, treating them as commands.

### Research Insights

**Plugin loader command discovery behavior (verified via official docs):**
- The `commands/` directory uses `.md` files as the discovery format
- The loader appears to recurse into subdirectories, namespacing by path segments (same as agents)
- None of the 10 reference files have YAML frontmatter -- they are pure content files with no `name:` or `description:` fields, yet the loader still discovers them as commands based on file extension and location alone
- This contrasts with the `skills/` loader, which only discovers `skills/<name>/SKILL.md` at one level of nesting (documented in learning `2026-02-12-plugin-loader-agent-vs-skill-recursion.md`)

**Precedent:** 8 existing skills already use `references/` subdirectories without autocomplete pollution:
- `agent-native-architecture/references/` (14 files)
- `skill-creator/references/` (4 files)
- `deploy/references/` (1 file)
- `dhh-rails-style/references/`, `dspy-ruby/references/`, `every-style-editor/references/`, `compound-capture/references/`, `andrew-kane-gem-writer/references/`

For `/bug_report`: This is likely a separate Claude Code platform behavior (discovering `.github/ISSUE_TEMPLATE/*.yml` files). The `.github/ISSUE_TEMPLATE/` directory contains `bug_report.yml`, `feature_request.yml`, and `config.yml` -- all `.yml` files, not `.md`. Since the plugin loader only discovers `.md` files, this autocomplete entry is probably not from the plugin loader at all. It may be from Claude Code's own awareness of the repo structure. This should be verified empirically after the reference move but is out of scope for this fix.

## Solution

Move the 10 reference files from `commands/soleur/references/` to `references/` directories within each corresponding skill. Skills support `references/` directories natively (per skill-creator spec), and the skill loader does NOT recurse into subdirectories -- only `skills/<name>/SKILL.md` is discovered.

### File Moves

| Source (commands/soleur/references/) | Destination (skills/\<name\>/references/) |
|--------------------------------------|------------------------------------------|
| brainstorm-brand-workshop.md | skills/brainstorm/references/brainstorm-brand-workshop.md |
| brainstorm-domain-config.md | skills/brainstorm/references/brainstorm-domain-config.md |
| brainstorm-validation-workshop.md | skills/brainstorm/references/brainstorm-validation-workshop.md |
| plan-community-discovery.md | skills/plan/references/plan-community-discovery.md |
| plan-functional-overlap.md | skills/plan/references/plan-functional-overlap.md |
| plan-issue-templates.md | skills/plan/references/plan-issue-templates.md |
| review-e2e-testing.md | skills/review/references/review-e2e-testing.md |
| review-todo-structure.md | skills/review/references/review-todo-structure.md |
| work-agent-teams.md | skills/work/references/work-agent-teams.md |
| work-subagent-fanout.md | skills/work/references/work-subagent-fanout.md |

### Path Updates in SKILL.md Files

Each skill's `SKILL.md` contains `Read` instructions referencing the old path (`plugins/soleur/commands/soleur/references/<file>.md`). These must be updated to the new path. The `Read` instructions use absolute plugin-relative paths (e.g., `plugins/soleur/...`), which is how skills reference files at runtime via the Read tool.

**Exact lines to update (verified by grep):**

| Skill SKILL.md | Line | Old Path | New Path |
|----------------|------|----------|----------|
| skills/brainstorm/SKILL.md | 66 | `plugins/soleur/commands/soleur/references/brainstorm-domain-config.md` | `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` |
| skills/brainstorm/SKILL.md | 79 | `plugins/soleur/commands/soleur/references/brainstorm-brand-workshop.md` | `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` |
| skills/brainstorm/SKILL.md | 83 | `plugins/soleur/commands/soleur/references/brainstorm-validation-workshop.md` | `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` |
| skills/plan/SKILL.md | 120 | `plugins/soleur/commands/soleur/references/plan-community-discovery.md` | `plugins/soleur/skills/plan/references/plan-community-discovery.md` |
| skills/plan/SKILL.md | 124 | `plugins/soleur/commands/soleur/references/plan-functional-overlap.md` | `plugins/soleur/skills/plan/references/plan-functional-overlap.md` |
| skills/plan/SKILL.md | 204 | `plugins/soleur/commands/soleur/references/plan-issue-templates.md` | `plugins/soleur/skills/plan/references/plan-issue-templates.md` |
| skills/review/SKILL.md | 277 | `plugins/soleur/commands/soleur/references/review-todo-structure.md` | `plugins/soleur/skills/review/references/review-todo-structure.md` |
| skills/review/SKILL.md | 371 | `plugins/soleur/commands/soleur/references/review-e2e-testing.md` | `plugins/soleur/skills/review/references/review-e2e-testing.md` |
| skills/work/SKILL.md | 143 | `plugins/soleur/commands/soleur/references/work-agent-teams.md` | `plugins/soleur/skills/work/references/work-agent-teams.md` |
| skills/work/SKILL.md | 149 | `plugins/soleur/commands/soleur/references/work-subagent-fanout.md` | `plugins/soleur/skills/work/references/work-subagent-fanout.md` |

**Search-and-replace pattern:** In each file, replace `commands/soleur/references/` with `skills/<skill-name>/references/`. This is a simple string substitution -- no surrounding text changes needed.

### Bug Report Investigation

After the reference move, verify whether `/bug_report` and `/feature_request` still appear in autocomplete. If they do:

1. Check if Claude Code discovers `.github/ISSUE_TEMPLATE/*.yml` files
2. If so, check if there is a `user-invocable: false` equivalent for non-plugin discovered items
3. If not fixable at plugin level, document as a Claude Code platform limitation

### Cleanup

After moving, remove the empty `commands/soleur/references/` directory.

### Learning Update

Update `knowledge-base/learnings/2026-02-22-context-compaction-command-optimization.md` to note that the references were subsequently moved from `commands/soleur/references/` to skill `references/` directories to prevent autocomplete pollution.

## Acceptance Criteria

- [x] Zero entries in autocomplete besides the 3 commands and 52 skills
- [x] `commands/soleur/references/` directory removed
- [x] All 10 reference files moved to their respective skill `references/` directories
- [x] All `Read` path references updated in 4 SKILL.md files
- [x] `git mv` used for all moves (preserves history)
- [x] Verify no broken references by searching for old paths across all plugin `.md` files
- [ ] Version bump (PATCH -- bug fix)

## Files Modified

**Moved (10 files):**
- `plugins/soleur/commands/soleur/references/*.md` -> `plugins/soleur/skills/<name>/references/*.md`

**Edited (4 files):**
- `plugins/soleur/skills/brainstorm/SKILL.md`
- `plugins/soleur/skills/plan/SKILL.md`
- `plugins/soleur/skills/review/SKILL.md`
- `plugins/soleur/skills/work/SKILL.md`

**Deleted (1 directory):**
- `plugins/soleur/commands/soleur/references/`

**Version bump (3 files):**
- `plugins/soleur/.claude-plugin/plugin.json`
- `plugins/soleur/CHANGELOG.md`
- `plugins/soleur/README.md`

## Risk Assessment

**Low risk.** The reference files are loaded via `Read` tool at runtime -- the skill instructions say "Read \`path\` now." Updating the path in the instruction is sufficient. No code logic changes. The skill loader ignores `references/` subdirectories within skills (confirmed by 8 existing skills with `references/` directories, including `agent-native-architecture/references/` with 14 files, none appearing as commands).

### Edge Cases Considered

1. **Relative vs. absolute paths:** The `Read` instructions in SKILL.md use plugin-relative paths like `plugins/soleur/...`. These are resolved by Claude Code relative to the project root, not the skill directory. The path update is a straightforward string replacement of the middle segment.

2. **Files with no frontmatter:** All 10 reference files lack YAML frontmatter. They are pure content documents. This means no `name:` or `description:` fields need updating in the moved files themselves -- only the paths in the referring SKILL.md files.

3. **Other references to old paths:** Grep confirms the old path `commands/soleur/references` appears in exactly 4 active SKILL.md files plus 3 knowledge-base docs (plan, tasks, and a learning). The knowledge-base files are historical records and do not need path updates.

4. **`go.md` command router:** The `go.md` entry point does not reference any of these files -- it only routes to skills via the Skill tool. No changes needed.

5. **Git history preservation:** Using `git mv` for all moves ensures `git log --follow` tracks the file history across the rename.

## Implementation Notes

**Execution order matters:**
1. Create `references/` directories first (4 `mkdir -p` calls)
2. Move files with `git mv` (10 moves)
3. Update paths in SKILL.md files (10 string replacements across 4 files)
4. Remove empty directory (1 `rmdir` -- will fail safely if not empty)
5. Verify with grep for old paths

**Verification command:**
```text
grep -rn 'commands/soleur/references' plugins/soleur/
```
Must return zero results after all changes.

## Out of Scope

- Restructuring the 3 commands themselves (go.md, sync.md, help.md)
- Adding `user-invocable: false` frontmatter to reference files (moving them out of `commands/` is the correct fix)
- Changes to `.github/ISSUE_TEMPLATE/` files (these are GitHub config, not plugin files)
- The `/bug_report` autocomplete entry (likely a Claude Code platform behavior, not plugin-caused)
