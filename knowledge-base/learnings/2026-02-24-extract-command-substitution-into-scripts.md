# Learning: Extract command substitution into bash scripts to eliminate permission prompts at the root

## Problem

The existing learning `command-substitution-in-plugin-markdown` documents the symptom (Claude Code permission prompts for `$()`) and a mitigation (rewriting bash blocks as prose or split commands). However, the mitigation only suppresses the symptom per-file -- when archival logic duplicated across 4+ skills needed `$(date ...)` and `$(basename ...)`, each skill had to independently avoid `$()` in its instructions, leading to fragile, duplicated workarounds.

## Solution

Extract the logic that needs `$()` into a standalone bash script. The script contains `$()` internally (where it is safe -- scripts are executed as single units), and the SKILL.md invokes the script with a plain `bash ./path/to/script.sh` command that contains no command substitution.

Pattern:

| Before | After |
|--------|-------|
| 4 SKILL.md files each with `mkdir -p ... && git add ... && git mv ...` with angle-bracket placeholders | 1 script (`archive-kb.sh`) + 4 SKILL.md files with `bash ./path/to/script.sh` |
| Each consumer must handle timestamp generation, slug derivation, untracked files | Script handles all edge cases once |

Key design decisions:

- Script generates timestamp internally (single `date` call per invocation)
- Slug derived from branch name with `tr '/' '-'` + sequential prefix stripping
- `git add` before `git mv` for untracked files (no-op if already tracked)
- `--dry-run` for preview, explicit slug argument for override
- No `!` code fences in SKILL.md (silent permission failure per `skill-code-fence-permission-flow` learning)
- `shopt -s nullglob` for safe empty glob expansion under `set -euo pipefail`

## Key Insight

When the same `$()` pattern recurs across multiple markdown files, the root fix is extraction into a script -- not per-file workarounds. Scripts are the natural boundary where shell features like command substitution, variable expansion, and pipe chains belong. Markdown instructions should invoke scripts, not replicate their logic.

## Prevention

When adding new functionality that requires `$()`, `${VAR}`, or pipe chains, default to creating a script under `skills/<name>/scripts/` rather than embedding the logic in SKILL.md. The script becomes the single source of truth, and consumer skills invoke it with a static `bash ./path` command.

## Session Errors

1. `chmod +x` on the script failed because Bash CWD was main repo root, not the worktree -- used relative path instead of absolute
2. Initial script had a dead if/else branch (both branches identical) -- caught by code review agents
3. Initial script included `--list` flag with no caller -- removed as YAGNI after simplicity review

## Tags
category: integration-issues
module: plugins/soleur/skills/archive-kb
symptoms: recurring $() permission prompts across multiple skills
