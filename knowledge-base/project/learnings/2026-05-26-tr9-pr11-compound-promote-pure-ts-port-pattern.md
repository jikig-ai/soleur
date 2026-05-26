---
title: "TR9 PR-11 — compound-promote is pure-TS (PR-6 pattern), NOT claude-eval-spawn (PR-7 pattern)"
date: 2026-05-26
type: learning
pr: 4463
umbrella: 3948
tags: [tr9, inngest, cron-substrate, pure-ts, compound-promote, octokit]
---

# TR9 PR-11 — Pure-TS pattern selection for compound-promote

## Context

The GHA `scheduled-compound-promote.yml` workflow uses direct `curl` to the
Anthropic API + inline `gh` CLI for PR creation. It does NOT use
`claude-code-action` (ADR-027 chose this shape to avoid token revocation).

## Decision

Port as pure-TS handler (PR-6 `cron-strategy-review.ts` pattern), NOT the
claude-eval-spawn pattern (PR-7 `cron-roadmap-review.ts`). Key factors:
- No claude binary spawn needed (direct Anthropic fetch)
- All GH ops via Octokit (gh CLI absent from Hetzner Dockerfile)
- Per-cluster gates (allowlist, byte-cap, branch-name shape) are TS logic, not prompt guards

## Key Insight

The PR-6/PR-7 decision tree for future TR9 children:
- Source uses `claude-code-action`? → PR-7 claude-eval-spawn
- Source uses direct API + shell logic? → PR-6 pure-TS Octokit port

## Review Findings Applied

1. **Promise.race wall-clock guard (I3)** — must wrap heavy steps with `withTimeout` helper
2. **redactToken must mutate `e.message` in-place** — `reportSilentFallback` passes the Error object to Sentry, which serializes `.message` directly (not the `options.message` field)
3. **PII-check LLM output before posting as PR comments** — corpus input is PII-filtered but LLM output is not; apply PII_REGEX before posting conflict-guard comments
4. **spawnGitChecked for commit/push path** — unchecked git exit codes in the apply loop can silently push to wrong branch

## Session Errors

1. **Planning subagent hit weekly API limit** — Recovery: recovered from partial artifact (plan file on disk). Prevention: budget-aware scheduling or plan-only mode for tight budget windows.
