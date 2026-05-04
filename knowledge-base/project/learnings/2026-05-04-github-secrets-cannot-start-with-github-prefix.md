---
title: GitHub repo secrets cannot start with `GITHUB_` prefix
date: 2026-05-04
category: integration-issues
related_issues: [3183]
related_prs: [3181]
tags: [github-actions, secrets, naming, gh-cli, ci-config]
---

# Learning: GitHub repo secrets cannot start with `GITHUB_` prefix

## Problem

While provisioning a workflow secret per the PR #3181 plan, `gh secret set` returned HTTP 422:

```bash
$ printf 'Iv23li9p88M5ZxYv1b7V' | gh secret set GITHUB_CLIENT_ID_PROBE
failed to set secret "GITHUB_CLIENT_ID_PROBE": HTTP 422: Secret names must not start with GITHUB_.
(https://api.github.com/repos/jikig-ai/soleur/actions/secrets/GITHUB_CLIENT_ID_PROBE)
```

GitHub reserves the `GITHUB_*` prefix for built-in environment variables (`GITHUB_TOKEN`, `GITHUB_ACTOR`, `GITHUB_REPOSITORY`, etc.). The reservation is enforced server-side at the secrets API layer — there's no override flag. Plans that prescribe `GITHUB_*`-prefixed secret names (e.g., `GITHUB_CLIENT_ID_PROBE`, `GITHUB_APP_PRIVATE_KEY`) are unimplementable as-written and force a mid-PR rename.

## Solution

Rename to a descriptive non-`GITHUB_` prefix. For OAuth probes:
`GITHUB_CLIENT_ID_PROBE` → `OAUTH_PROBE_GITHUB_CLIENT_ID`. The semantic prefix
(`OAUTH_PROBE_`) survives the constraint and reads better at the call site
(`secrets.OAUTH_PROBE_GITHUB_CLIENT_ID`).

Surface the rename rationale in code comments where the secret is consumed:

```yaml
env:
  # Prefix is OAUTH_PROBE_ because GitHub rejects repo secrets starting
  # with GITHUB_ (HTTP 422 from the secrets API).
  OAUTH_PROBE_GITHUB_CLIENT_ID: ${{ secrets.OAUTH_PROBE_GITHUB_CLIENT_ID }}
```

Otherwise the next operator reading the workflow file wonders why the prefix
isn't `GITHUB_` and may try to "fix" it.

## Key Insight

Treat plan-prescribed external-system identifiers (workflow secret names,
GitHub App callback URLs, Stripe webhook endpoints, Cloudflare Worker names,
etc.) as **proposals**, not commands. Verify the receiving system accepts
them BEFORE locking the plan. Cheapest verification per surface:

| Surface | Verification command |
|---|---|
| GitHub repo secret name | `gh secret set TEST_NAME --body x` (then delete) |
| GitHub workflow secret read | `gh api /repos/{owner}/{repo}/actions/secrets/<NAME>` (404 OK; 422/400 = invalid) |
| Stripe API key shape | `stripe products list -k <key>` (401 = bad key, 200 = OK) |
| Cloudflare Worker name | `wrangler kv:namespace list` (auth check) |
| Doppler secret name | `doppler secrets get <NAME> -p <prj> -c <cfg> --plain` |

Plans that prescribe identifiers should include the verification command
inline so the implementer doesn't have to derive it under time pressure.

## Tags

category: integration-issues
module: github-actions
