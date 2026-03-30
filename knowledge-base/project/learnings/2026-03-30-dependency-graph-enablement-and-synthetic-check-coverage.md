---
title: "Dependency graph enablement and synthetic check coverage"
date: 2026-03-30
category: integration-issues
module: ci-cd
tags: [github-actions, dependency-review, synthetic-checks, supply-chain-security]
related_issues: ["#1294", "#1309", "#1174"]
---

# Learning: Dependency graph enablement and synthetic check coverage

## Problem

The `dependency-review.yml` workflow (added in PR #1290) was passing vacuously --
the action reported "No snapshots found" and exited successfully without scanning
any dependencies. The GitHub Dependency Graph appeared enabled in repo settings,
but the SBOM contained only 1 package (the repo itself), meaning no actual
dependency indexing was occurring.

## Root Cause

GitHub's Dependency Graph has two layers of enablement:

1. **Repository setting** -- "Dependency graph" toggle in Settings > Code security.
   This was already on.
2. **Vulnerability alerts** -- Must be enabled separately via API
   (`gh api repos/{owner}/{repo}/vulnerability-alerts --method PUT`). Without this,
   GitHub does not perform full dependency indexing, and the SBOM remains empty.

Additionally, GitHub's dependency graph does not support `bun.lock` files. Only
`package-lock.json` is indexed for npm ecosystems. The `apps/telegram-bridge/`
directory had only `bun.lock`, so its entire dependency tree was invisible to GitHub.

A secondary issue: `npm install --package-lock-only` produces a lockfile without
`resolved` and `integrity` fields, which GitHub's dependency graph cannot fully
index. A full `npm install` is required to generate a complete lockfile.

## Solution

1. Enabled vulnerability alerts via GitHub API -- SBOM grew from 1 to 773 packages
2. Added `retry-on-snapshot-warnings: true` to `dependency-review.yml` to handle
   snapshot race conditions (dependency graph indexing is async; PRs opened
   immediately after push may not have snapshots ready)
3. Generated `apps/telegram-bridge/package-lock.json` via full `npm install` (not
   `--package-lock-only`) to ensure resolved/integrity fields are present
4. Added synthetic `dependency-review` check run to `scheduled-content-publisher.yml`
   (GITHUB_TOKEN PRs skip required checks)
5. Security review caught `scheduled-weekly-analytics.yml` was missing ALL synthetic
   checks (test, cla-check, dependency-review) -- added all three synthetics there too
6. Filed #1309 to triage the 15 Dependabot alerts surfaced by enabling the graph

## Key Insight

When adding a new required check to the CI Required ruleset, audit ALL workflows
that create PRs via `GITHUB_TOKEN` -- not just the one you are fixing. `GITHUB_TOKEN`
PRs do not trigger `on: pull_request` workflows, so every required check must be
synthetically created in those workflows. The plan claimed "only 1 workflow needs
synthetics" but there were 2 (`scheduled-content-publisher.yml` and
`scheduled-weekly-analytics.yml`). Missing even one means that workflow's PRs hang
forever waiting for checks that will never run.

The general audit query is:

```bash
grep -rl "GITHUB_TOKEN" .github/workflows/ | \
  xargs grep -l "gh pr create\|peter-evans/create-pull-request" | head -n 20
```

## Session Errors

### 1. Ralph loop script path wrong

The plan referenced `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh`
but this path did not exist. The agent attempted to run it and got a file-not-found
error.

**Prevention:** When a plan specifies a script path, verify the file exists with
`ls` or `test -f` before running it. This is already covered by the AGENTS.md rule
about tracing relative paths, but applies equally to absolute/rooted paths in plans.

### 2. Plan undercounted GITHUB_TOKEN workflows

The plan stated only `scheduled-content-publisher.yml` needed synthetic checks.
The security review agent discovered `scheduled-weekly-analytics.yml` was also
missing all required synthetic checks. The plan's grep was too narrow -- it checked
for `GITHUB_TOKEN` in PR creation but missed workflows using
`peter-evans/create-pull-request` (which implicitly uses `GITHUB_TOKEN`).

**Prevention:** When auditing for a pattern across workflows, use a broad search
that covers all variants (CLI `gh pr create`, action `create-pull-request`, manual
API calls). Verify the count matches reality by listing all results, not just
spot-checking.

### 3. `npm install --package-lock-only` produced incomplete lockfile

The first attempt used `npm install --package-lock-only` to avoid downloading
`node_modules`. This produced a `package-lock.json` without `resolved` and
`integrity` fields, which GitHub's dependency graph requires for full indexing.

**Prevention:** When generating lockfiles for dependency graph consumption (not
just local development), always use full `npm install` to ensure all metadata fields
are populated. The `--package-lock-only` flag is a development convenience, not
suitable for supply-chain tooling inputs.

## Prevention Strategy

1. **Dependency graph enablement checklist** -- When adding dependency scanning to
   a new repo, verify both layers: (a) dependency graph toggle is on, (b)
   vulnerability alerts are enabled via API, (c) SBOM contains expected package
   count (`gh api repos/{owner}/{repo}/dependency-graph/sbom | jq '.sbom.packages | length'`)

2. **Required check audit pattern** -- When adding any new required check to branch
   protection or rulesets, immediately grep for all workflows that create PRs with
   `GITHUB_TOKEN` or `create-pull-request` action and add the synthetic check to
   each one. This is a combinatorial concern: N required checks times M token-based
   workflows = N*M synthetic entries.

3. **Lockfile format awareness** -- GitHub's dependency graph requires ecosystem-native
   lockfiles (`package-lock.json`, `yarn.lock`, `Gemfile.lock`). Alternative lockfiles
   (`bun.lock`, `pnpm-lock.yaml` partially) may not be indexed. When a project uses
   a non-standard package manager, generate the native lockfile alongside it for
   supply-chain tooling. Ensure the lockfile is generated with full metadata (not
   `--package-lock-only`).

## Tags

category: integration-issues
module: ci-cd
