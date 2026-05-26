---
date: 2026-05-25
pr: 4423
issue: 4425
umbrella: 3948
tags: [tr9, inngest, claude-code, cron, pattern-reuse]
---

# TR9 PR-7 — Roadmap review claude-code-spawn pattern reuse

## Context

PR-7 (#4425, draft PR #4423) ports `.github/workflows/scheduled-roadmap-review.yml` to `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` as the seventh substrate application in the TR9 umbrella (#3948). This is the **second** handler ported via the claude-code-spawn pattern; PR-5 (#4377 cron-bug-fixer) was the first. PR-6 (#4412 cron-strategy-review) took the alternate pure-TS Octokit-walker path.

## What landed

A ~550-line `cron-roadmap-review.ts` that is structurally near-verbatim with `cron-bug-fixer.ts` minus the bug-fix-specific branches:

| Helper / block | Reuse status |
|---|---|
| `mintInstallationToken` | verbatim (REPO_OWNER/REPO_NAME constants identical) |
| `buildAuthenticatedCloneUrl` | verbatim |
| `redactToken` | verbatim |
| `spawnSimple` | verbatim |
| `setupEphemeralWorkspace` | verbatim — only `mkdtemp` prefix changes (`soleur-cron-roadmap-review-`) |
| `teardownEphemeralWorkspace` | verbatim — only `feature` tag changes (`cron-roadmap-review`) |
| `resolveClaudeBin` | verbatim |
| `buildSpawnEnv` | verbatim |
| `spawnClaudeEval` | shape verbatim — drops `issueNumber` arg, passes static `ROADMAP_REVIEW_PROMPT` (not factory) |
| `postSentryHeartbeat` | verbatim — only `SENTRY_MONITOR_SLUG` changes |
| Handler shape | 4 step.run blocks (mint-token → setup-workspace → claude-eval → sentry-heartbeat) — strips the bug-fixer's detect-pr / auto-merge-gate / notify-ops-email / select-issue / precreate-labels steps |
| Inngest registration | verbatim — only `id`, `cron`, `event` change |

Spawn-call count in `cron-roadmap-review.ts`: **2** (one in `spawnSimple` for `git clone`, one in `spawnClaudeEval` for the agent loop). Matches PR-5.

## Reusability claim

**Any future TR9 child that originated as a `claude-code-action` GHA workflow is now a near-verbatim port of `cron-bug-fixer.ts` or `cron-roadmap-review.ts`.** The decision tree is:

1. Does the prompt operate over a per-N entity (issue, user, span)? → PR-5 shape: factory prompt (`fixIssuePrompt(n)`), select-N step, detect-PR step, optional gates.
2. Does the prompt operate over global live state (roadmap, milestones, all issues)? → PR-7 shape: static prompt constant, no select step, no detect step, 4-step handler.

Both shapes preserve:
- Ephemeral workspace with plugin symlink + `.claude/settings.json` overlay
- `--` separator before the prompt positional arg (load-bearing per #4017)
- 50-min `AbortController` envelope with SIGTERM→SIGKILL escalation
- Installation-token mint with `minRemainingMs` floor
- stdout/stderr redaction through `redactToken`
- Single-step Sentry heartbeat at end of handler
- try/finally teardown of ephemeral workspace

## Prompt-as-string-constant convention

Both PR-5 and PR-7 embed prompts as `const` template literals near the top of the file. The convention is:

1. **Extract verbatim from the YAML** via `awk 'NR>=A && NR<=B {sub(/^<leading-ws>/, ""); print}'` — the leading-whitespace pattern is the YAML's block-scalar indent (12 spaces for the roadmap-review workflow, verified live; the plan's claim of 10 spaces was off by 2).
2. **Verify zero backticks** (`grep -c '`' /tmp/prompt-body.txt`) and zero `${` sequences before embedding — both characters need escaping inside a JS template literal. Roadmap-review prompt had neither.
3. **Pin verbatim discipline** with canary tests on anchor strings ("Part 1: Issue-to-Milestone Alignment", "MILESTONE RULE:", etc.) — full SHA equality is fragile to whitespace; substring anchors catch silent paraphrasing across plan→work cycles without false positives.
4. **Do NOT factor the prompt into a separate file.** Inline keeps the spawn argv, prompt content, and tool-allowlist co-located for reviewer inspection.

## Pitfalls observed

- The plan's prompt-dedent recipe (10 spaces) was off — the actual YAML block-scalar body indent is 12 spaces. The `awk` pattern was corrected at work time. Future YAML→template-literal extractions should run `awk 'NR>=START {print "[" $0 "]"; exit}'` first to count leading whitespace before piping into `sub()`.
- The advisory `security_reminder_hook.py` PreToolUse hook fires on any GHA workflow edit (including adding a static `-target=` line). It's an advisory warning, not a block — retry the edit if it surfaces; the hook does not actually prevent the write.
- `terraform validate` emits deprecation warnings for `sentry_issue_alert` resources (unrelated to PR-7). Exit 0 is the success indicator; warnings are pre-existing.

## What this unlocks

Future TR9 children using `claude-code-action` (group-(c) agent-loop crons remaining in `.github/workflows/scheduled-*.yml`) can be ported by:

1. Copy `cron-roadmap-review.ts` (for global-state prompts) or `cron-bug-fixer.ts` (for per-entity prompts) as the template.
2. Rename `SENTRY_MONITOR_SLUG`, `mkdtemp` prefix, `feature` tag, handler/function exports, function `id`, cron trigger, manual-trigger event.
3. Extract the prompt verbatim from the YAML (verify leading-whitespace count first).
4. Update `CLAUDE_CODE_FLAGS` to mirror the workflow's `claude_args`.
5. Add a `sentry_cron_monitor` resource in `cron-monitors.tf` + a `-target=` line in `apply-sentry-infra.yml`.
6. Register in `apps/web-platform/app/api/inngest/route.ts` (alphabetical insertion).
7. `git rm` the GHA YAML in the same commit.

The "reviewer's burden reduces to: does each named diff match the workflow's documented semantics?" observation from the plan (§6.5) holds: with two precedent shapes in tree, every remaining `scheduled-*` migration is a precedent-diff exercise rather than a fresh architectural decision.

## Follow-ups

PR-8 (#4439) reused this pattern verbatim — 5 helpers + handler shape unchanged; only opus-4-7 model + cap-enforcement-already-in-prompt differ from PR-7.

PR-9 (#4442) reused this pattern — 4th handler now (PR-5, PR-7, PR-8, PR-9). Substrate-extraction backlog grows.

PR-10 (#4448) — 5th handler. Adds WebSearch+WebFetch+Task tools cohort sibling to PR-7; bridges to the cohort that also creates follow-up PRs (vs PR-8/PR-9 issue-only).
