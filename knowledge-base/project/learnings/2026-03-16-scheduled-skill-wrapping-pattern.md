# Learning: Scheduled Workflow Pattern — Wrapping Skills for Autonomous CI Execution

## Problem

Soleur skills are designed for interactive use with user approval gates (AskUserQuestion). Scheduled GitHub Actions workflows run unattended — no human to click "Accept." How do you safely run interactive skills in CI without modifying their core behavior or bypassing safety checks?

## Solution

Three-layer pattern:

**Layer 1 — Workflow authorization (YAML).** Each scheduled workflow includes an explicit AGENTS.md override ("You are authorized to commit to main") and follows a standard scaffold: checkout → setup-node → npm ci → label pre-creation → claude-code-action → Discord failure notification.

**Layer 2 — Headless mode convention (Skill SKILL.md).** Skills detect `--headless` in `$ARGUMENTS` and set `HEADLESS_MODE=true`. Interactive gates auto-resolve: auto-accept on PASS citations, auto-abort on FAIL citations. The skill works identically without the flag — headless is additive, not destructive.

**Layer 3 — Review-driven simplification.** The original plan had 6 phases and 4 workflows including a 60-turn KPI remediation cascade. Three parallel reviewers (DHH, Code Simplicity, Architecture) independently agreed to kill the cascade and two supporting phases. Final: 3 batches, 3 workflows, 1 skill modification.

## Key Insight

**Skills should compose, not orchestrate.** Instead of building a mega-workflow that re-implements three skills in a single 60-turn cascade, ship three independent workflows that each invoke one skill. If you need coordination (KPI miss → trigger all three), add a 5-line `gh workflow run` dispatcher — not a 60-turn agent session.

## Session Errors

1. **Worktree nested inside another worktree** — `git worktree add` was run from within `.worktrees/feat-web-platform-ux/` instead of the bare repo root, creating `.worktrees/feat-web-platform-ux/.worktrees/feat-cmo-autonomous-execution/`. Fix: backup files, remove nested dir, prune, recreate at correct path.
2. **`worktree-manager.sh feature` failed on bare repo** — "fatal: this operation must be run in a work tree" because the script runs `git fetch` which requires a work tree. Workaround: manually run `git worktree add` from another worktree.
3. **Architecture reviewer made factual errors** — Claimed `weekly-analytics.sh` and social-distribute headless mode don't exist (both verified present). Lesson: always verify reviewer claims against actual file system before accepting.

## Prevention

- Always run `git worktree add` from a worktree or verify CWD is not a bare repo root
- When reviewers make factual claims about file existence, verify with grep/ls before accepting
- The headless mode pattern (`$ARGUMENTS` contains `--headless`) is now documented in two skills (social-distribute, content-writer) — use as reference for future skills

## Related Learnings

- `2026-03-03-headless-mode-skill-bypass-convention.md` — Original headless convention
- `2026-03-03-scheduled-bot-fix-workflow-patterns.md` — Bot-fix cascade patterns
- `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md` — All persistence inside agent prompt
- `2026-03-15-env-var-post-guard-defense-in-depth.md` — Defense-in-depth for autonomous actions
- `2026-03-14-content-publisher-channel-extension-pattern.md` — Multi-channel content automation

## Tags

category: ci-cd
module: scheduled-workflows, marketing-automation
