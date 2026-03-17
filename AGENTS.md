# Agent Instructions

This repository contains the Soleur Claude Code plugin. Detailed conventions live in `knowledge-base/project/constitution.md` -- read it when needed. This file contains only rules the agent will violate without being told on every turn.

## Hard Rules

- Never commit directly to main [hook-enforced: guardrails.sh Guard 1]. Create a worktree: `git worktree add .worktrees/feat-<name> -b feat/<name>`. If one exists for the task, use it.
- Never `--delete-branch` with `gh pr merge` [hook-enforced: guardrails.sh Guard 3]. Use `gh pr merge <number> --squash --auto`, then poll with `gh pr view <number> --json state --jq .state` until MERGED, then run `cleanup-merged`.
- Never edit files in the main repo when a worktree is active [hook-enforced: worktree-write-guard.sh]. Run `pwd` before every file write or git command to verify you're in `.worktrees/<name>/`.
- Never `git stash` in worktrees. Commit WIP first, then merge.
- Never `rm -rf` on the current directory, a worktree path, or the repo root [hook-enforced: guardrails.sh Guard 2].
- MCP tools (Playwright, etc.) resolve paths from the repo root, not the shell CWD. Always pass absolute paths to MCP tools when in a worktree.
- When a command exits non-zero or prints a warning, investigate before proceeding. Never treat a failed step as success.
- Before merging any PR, merge origin/main into the feature branch [hook-enforced: pre-merge-rebase.sh] (`git fetch origin main && git merge origin/main`).
- Always read a file before editing it. The Edit tool rejects unread files, but context compaction erases prior reads -- re-read after any compaction event.
- When a plan specifies relative paths (e.g., `source "$SCRIPT_DIR/../../..."`), trace each `../` step to verify the final target before implementing. Plans have prescribed wrong paths that were implemented verbatim and only caught by review agents.
- PreToolUse hooks block: commits on main, rm -rf on worktrees, --delete-branch with active worktrees, writes to main repo when worktrees exist, commits with conflict markers in staged content. Work with these guards, not around them.
- The host terminal is Warp. Do not attempt automated terminal manipulation via escape sequences (cursor position queries, TUI rendering, and similar sequences are intercepted by Warp's tmux control mode and silently fail).
- The Bash tool runs in a non-interactive shell without `sudo` access. Do not attempt commands requiring elevated privileges -- provide manual instructions instead.
- Exhaust all automated options before suggesting manual steps to the user. The founder is a solo operator -- every manual step is a context switch. If credentials, APIs, or CLI tools exist to complete a task programmatically (Discord API, `gh` CLI, `curl`, etc.), use them. Only fall back to manual instructions when automation is genuinely impossible (e.g., no API exists, requires browser-only OAuth consent).
- Never label a browser task as "manual" without first attempting Playwright MCP. Account signups, credential generation, settings configuration, and form submissions are all automatable via Playwright. The only genuinely manual browser steps are CAPTCHA solving and interactive OAuth consent screens — and even those should be driven to the CAPTCHA/consent step via Playwright, then handed to the user for that single interaction. Plans and task lists that say "manual — browser" are a code smell.

## Workflow Gates

- Zero agents until user confirms direction. Present a concise summary first, ask if they want to go deeper, only then launch research. Exception: passive domain routing (see below).
- Before every commit, run compound (`skill: soleur:compound`). Do not ask whether to run it -- just run it.
- Never bump version files in feature branches. Version is derived from git tags — CI creates GitHub Releases with `vX.Y.Z` tags at merge time via semver labels. Set labels with `/ship`. Do NOT edit `plugin.json` version (frozen sentinel) or `marketplace.json` version.
- Use `/ship` to automate the full commit/push/PR workflow. It enforces review and compound gates.
- After marking a PR ready, run `gh pr merge <number> --squash --auto` to queue auto-merge, then poll `gh pr view <number> --json state --jq .state` until MERGED, then `cleanup-merged`. Never stop at "waiting for CI" -- actively poll and merge in the same session.
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists, run `git worktree list` from the bare root to verify.
- When an audit identifies pre-existing issues, create GitHub issues to track them before fixing. Don't just note them in conversation -- file them.
- When creating PRs that resolve a GitHub issue, include `Closes #N` in the PR **body** (not just the title). Parenthetical `(#N)` in titles creates a link but does NOT trigger auto-close.
- After merging a PR that adds or modifies a GitHub Actions workflow, trigger a manual run (`gh workflow run <file>.yml`), poll until complete (`gh run view <id> --json status,conclusion`), and investigate failures before moving on. New workflows must be verified working, not just syntactically valid.

## Passive Domain Routing

- When a user message contains a clear, actionable domain signal unrelated to the current task (expenses, legal commitments, marketing mentions, sales leads, etc.), read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` and spawn the relevant domain leader as a background agent (`run_in_background: true`) using the Assessment Question to detect relevance and the Task Prompt to delegate. Continue the primary task without waiting.
- Do not route on trivial messages ("yes", "continue", "looks good") or when the domain signal IS the current task's topic (e.g., do not route to CTO during an engineering brainstorm about architecture).

## Communication

- Challenge reasoning instead of validating. No flattery. If something looks wrong, say so.
- Delegate verbose exploration (3+ file reads, research, analysis) to subagents. Keep main context for edits and user-facing iteration.
