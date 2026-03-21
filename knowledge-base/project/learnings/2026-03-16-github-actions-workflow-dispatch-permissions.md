# Learning: GitHub Actions workflow_dispatch permissions with GITHUB_TOKEN

## Problem

Needed to dispatch other workflows from within a GitHub Actions workflow using `gh workflow run`. The workflow already declared explicit `permissions` (contents, pull-requests, statuses), which meant all unlisted permissions defaulted to `none`.

## Solution

1. Add `actions: write` to the workflow's `permissions` block — this is the minimum required for `gh workflow run`
2. Use `GH_TOKEN: ${{ github.token }}` in the step's `env` (not a PAT)
3. Use `|| echo "::warning::Failed to dispatch ..."` per call for independent failure isolation

Key facts confirmed via research:

- `GITHUB_TOKEN` can trigger `workflow_dispatch` since Sep 2022 (explicit GitHub exception to the recursive prevention rule)
- When a workflow declares explicit `permissions`, omitting `actions: write` causes HTTP 403
- `gh` CLI has a known panic issue (cli/cli#10519) on unexpected HTTP codes — the `||` fallback absorbs any non-zero exit

## Key Insight

When a GitHub Actions workflow already uses explicit `permissions`, you must explicitly add every new permission needed. The "default permissions" only apply when no `permissions` block exists. This is a common gotcha when extending existing workflows.

## Session Errors

- One-shot skill referenced wrong Ralph Loop script path (`skills/one-shot/scripts/` vs `scripts/`)

## Tags

category: integration-issues
module: github-actions
