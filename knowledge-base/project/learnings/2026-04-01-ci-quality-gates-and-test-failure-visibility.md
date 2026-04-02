---
title: "CI Quality Gates and Test Failure Visibility"
date: 2026-04-01
category: ci-infrastructure
tags: [ci, testing, branch-protection, quality-gates, github-actions]
---

# Learning: CI Quality Gates and Test Failure Visibility

## Problem

50 failing tests on main went unnoticed across multiple PR merges. The question "how did this happen?" revealed five compounding gaps:

1. **CI on main was red** (run 23840983070) -- `plugins/soleur` changelog tests and `blog-link-validation` suite failed due to GitHub API 403 rate limiting because `GITHUB_TOKEN` was not passed to the test step.
2. **No tracking issue existed** for the main-branch CI failure. Nobody knew it was broken.
3. **Branch protection allowed stale PRs to merge** -- `strict_required_status_checks_policy` was `false`, so PRs could merge even when main was red and their status checks were based on an outdated base.
4. **Bare repo root produced phantom failures** -- running tests from the bare repo root used stale files (pre-PR #1228) that diverged from HEAD, producing 8 phantom test failures that do not exist in CI or any worktree.
5. **A prior agent session fabricated a rationalization** -- it claimed "50 failing dashboard page tests with `document not defined` -- a JSDOM issue." There are zero dashboard UI tests and zero jsdom dependencies in the project. The agent hallucinated both the test count and the failure mode.

## Investigation

Key findings during the investigation:

- **Rate limiting was the root cause of CI failure.** The `github.js` test helper checks for `GITHUB_TOKEN` in the environment and uses it for authenticated API calls when present. The CI workflow's test step did not pass it, so all GitHub API calls hit the unauthenticated rate limit (60 req/hr) and returned 403.
- **Bare repo stale files are a distinct problem from CI failures.** The bare repo root contains a checkout frozen at some prior state. Files deleted or moved in recent PRs still exist there. Running `test-all.sh` from the bare root exercises dead code paths and produces failures that have nothing to do with actual HEAD.
- **The hallucinated rationalization was the most dangerous failure.** It provided a plausible-sounding explanation ("JSDOM environment mismatch") that would have sent any investigator down a wrong path. The fabricated detail ("50 dashboard page tests") had no basis in the codebase -- zero files match `dashboard*.test.*` and `jsdom` appears nowhere in any `package.json`.

## Solution

Five gates were implemented to close each gap:

- **Gate 1: Strict status checks.** Enabled `strict_required_status_checks_policy: true` on the CI Required ruleset via GitHub API. Updated `scripts/setup-branch-protection.sh` to set this flag. PRs must now be up-to-date with main before merging -- stale green checks no longer satisfy the gate.

- **Gate 2: test-all.sh exit code.** Verified that `test-all.sh` already exits non-zero on any test failure. No change needed.

- **Gate 3: Main health monitor.** Created `.github/workflows/main-health-monitor.yml` -- runs the full test suite every 6 hours on a cron schedule. On failure, it auto-creates a P1 GitHub issue with the `ci/main-broken` label, linking to the failed run. On success, it auto-closes any open `ci/main-broken` issue. This ensures main-branch failures are surfaced within 6 hours even if no PRs are in flight.

- **Gate 4: GITHUB_TOKEN in CI.** Added `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` to the CI workflow's test step environment. The `github.js` helper already uses this token when present -- it just was never provided.

- **Gate 5: Bare repo guard.** Added a check at the top of `test-all.sh` that detects when it is running from a bare repo root (via `git rev-parse --is-bare-repository`) and exits with an explanatory error message directing the user to run from a worktree instead.

Filed GitHub issue #1357 to track the current main-branch CI failure.

## Key Insight

CI failures on main are invisible without active monitoring. Branch protection status checks only gate PRs -- they say nothing about post-merge health. A project needs both: (1) strict status checks so PRs cannot merge against a stale base, and (2) a scheduled health monitor that creates tracking issues when main goes red. Without the monitor, a single broken merge silently degrades the entire pipeline, and subsequent PRs inherit the failure without anyone noticing.

The secondary insight is about agent hallucinations in debugging contexts. When an agent produces a specific, technical-sounding explanation for a failure (exact test count, named error pattern, attributed root cause), verify every claim against the codebase before acting on it. Fabricated rationalizations are more dangerous than "I don't know" because they redirect investigation effort toward nonexistent problems.

## Session Errors

**1. CI on main failing since latest push -- undetected until this investigation.**

- **Prevention:** Gate 3 (main-health-monitor) now auto-creates a P1 issue within 6 hours of any main-branch test failure. Gate 1 (strict status checks) prevents PRs from merging against a stale base, so a red main blocks all new merges until fixed.

**2. Bare repo stale files caused 8 phantom test failures locally.**

- **Prevention:** Gate 5 (bare repo guard) now refuses to run `test-all.sh` from a bare repo root. The error message explains why and directs users to run from a worktree. This is also documented in AGENTS.md: "The repo root is a bare repository -- never run git pull, git checkout, or other working-tree commands from the bare root."

**3. Agent hallucinated "50 failing dashboard page tests with document not defined" -- zero such tests exist.**

- **Prevention:** When an agent produces a specific failure diagnosis (test count, error message, root cause), verify each claim: (a) search for the test files (`dashboard*.test.*`), (b) search for the dependency (`jsdom` in `package.json`), (c) reproduce the failure and compare actual output to the claimed output. Do not propagate a diagnosis without evidence. This is a restatement of the AGENTS.md rule: "When a command exits non-zero or prints a warning, investigate before proceeding."

**4. `priority/p1-critical` label did not exist -- issue creation failed on first attempt.**

- **Prevention:** Before using a GitHub label in `gh issue create` or workflow YAML, verify it exists with `gh label list --search "<name>"`. The actual label was `priority/p1-high`. Alternatively, create the label first with `gh label create` if the desired label genuinely does not exist.

**5. `ci/main-broken` label did not exist -- had to create before the health monitor workflow could use it.**

- **Prevention:** When a workflow or script references a GitHub label, include a setup step that creates the label if it does not exist (`gh label create "ci/main-broken" --description "..." --color "..." 2>/dev/null || true`). The main-health-monitor workflow now handles this inline.

## Tags

category: ci-infrastructure
module: github-actions, scripts
