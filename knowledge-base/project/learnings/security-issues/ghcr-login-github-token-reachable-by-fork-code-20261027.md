---
title: docker/login-action materializes GITHUB_TOKEN where fork-reachable pull_request code can read it
category: security-issues
tags:
  - github-actions
  - security
  - ci-cd
  - ghcr
  - fork-pull-request
module: infrastructure
date: 2026-10-27
synced_to: [security-sentinel]
---

# Learning: `docker/login-action` materializes `GITHUB_TOKEN` where fork-reachable `pull_request` code can read it

## Problem

PR #11295 added `docker/login-action` to the `rls-fuzz` job (#10868 — GHCR anonymous-bucket throttling). `pull_request` is fork-reachable and that workflow's `paths:` filter includes fork-editable code (`apps/web-platform/scripts/supabase-local.sh`, `package.json`, the fuzz test tree). `docker/login-action` writes the token into the runner's Docker client config (`<runner-home>/.docker/config.json`) for the entire job lifetime — so any in-scope fork PR could `cat` or exfiltrate a live `GITHUB_TOKEN` carrying `contents: read` + `packages: read`, without touching the workflow file itself. Pre-change, the token was only reachable via workflow-expression edits.

`logout: true` (the default post-step cleanup, correctly preserved) only fires after the job — it does not bound within-job exposure.

## Solution

Gate every credential-writing step (and any probe that depends on it) to same-repo refs:

```yaml
- name: Log in to GHCR (authenticated pulls)
  if: ${{ github.event_name == 'workflow_dispatch' || github.event.pull_request.head.repo.full_name == github.repository }}
  uses: docker/login-action@<full-sha>
  ...
```

Fork PRs then ride the anonymous path plus whatever resilience the job already has — which in #11295's case is exactly the `ghcr-pull-with-retry.sh` throttle-gated retry the login complements.

## Key Insight

A step-level `if:` gate is cheaper than `pull_request_target` and strictly safer: `pull_request_target` would run the *base* code with the token (safe for this use, but escalates the token's blast radius to every step unconditionally); the per-step gate keeps the token scoped to refs that can't carry attacker code, while fork PRs still run and still get the retry path. The guard test pins both the `if:` expression's presence on the credential steps AND `pull_request_target`'s absence.

Companion pattern from the same PR: grep-assertions over workflow files must anchor on YAML key shapes (`^\s+uses:`, `^\s+run:`) — whole-file fixed-string greps are satisfied by comments and corrupted by `head -1` ordering collisions (documented in `cq-assert-anchor-not-bare-token`; the review panel found four distinct forgery vectors in one suite).

## Tags

github-actions, security, ci-cd, ghcr, fork-pull-request
