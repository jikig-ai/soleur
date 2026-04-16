---
module: System
date: 2026-04-16
problem_type: integration_issue
component: development_workflow
symptoms:
  - "claude-code-action throws 'Unsupported event type: push' on push-triggered workflow runs"
  - "Doppler CLI prints error for invalid --only-secrets flag but exits 0, leaking all prd secrets into GITHUB_ENV"
  - "Issue #2376 misdiagnosed the error as an SDK/Ajv crash when it was minified source context around a credit balance error"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [claude-code-action, github-actions, doppler, workflow, misdiagnosis]
---

# Troubleshooting: claude-code-action unsupported push event and Doppler --only-secrets flag

## Problem

The `Scheduled: UX Audit` workflow failed on all push-triggered runs with two root causes, both in the workflow YAML. The issue report (#2376) misdiagnosed the primary failure as an SDK/Ajv crash, when in reality the minified Ajv code was source context around a "Credit balance is too low" error -- not the error itself.

## Environment

- Module: System (CI/CD)
- Affected Component: `.github/workflows/scheduled-ux-audit.yml`
- Date: 2026-04-16
- claude-code-action versions tested: v1.0.75 (pinned), v1.0.97 (latest)
- Doppler CLI version: v3.75.3

## Symptoms

- Push-triggered workflow runs fail with `Unsupported event type: push` before SDK/schema validation runs
- Doppler step prints `Error: unknown flag: --only-secrets` but exits 0 (non-blocking)
- All prd secrets leak into `$GITHUB_ENV` instead of just the 4 intended ones
- Issue report described "SDK/Ajv crash" that was actually minified source context

## What Didn't Work

**Attempted Solution 1:** PR #2371 fixed an invalid setup-bun SHA

- **Why it failed:** Addressed a different problem; the push event and --only-secrets issues remained

**Attempted Solution 2:** PR #2373 fixed Doppler `IFS='='` trailing-`=` loss

- **Why it failed:** Fixed a real parsing bug but did not address the unsupported event type or invalid flag

**Attempted Solution 3:** Investigating Ajv schema validation (as described in issue #2376)

- **Why it failed:** Misdiagnosis. Two successful `workflow_dispatch` runs (24472727054, 24469469972) proved the SDK, plugin schemas, and Ajv validation work correctly. The "Ajv crash" was minified source context around line 19 of `sdk.mjs`.

## Solution

Two changes to `.github/workflows/scheduled-ux-audit.yml`:

**Fix 1: Remove push trigger**

```yaml
# Before (broken):
on:
  push:
    branches: [main]
    paths:
      - 'apps/web-platform/app/**'
      - 'apps/web-platform/components/**'
  schedule:
    - cron: '0 9 1 * *'
  workflow_dispatch: {}

# After (fixed):
on:
  schedule:
    - cron: '0 9 1 * *'
  workflow_dispatch: {}
```

**Fix 2: Replace --only-secrets with grep filter**

```yaml
# Before (broken):
doppler secrets download --project soleur --config prd --no-file --format env-no-quotes \
  --only-secrets SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,NEXT_PUBLIC_SUPABASE_ANON_KEY,NEXT_PUBLIC_SITE_URL | while IFS= read -r line; do

# After (fixed):
allowed="SUPABASE_URL|SUPABASE_SERVICE_ROLE_KEY|NEXT_PUBLIC_SUPABASE_ANON_KEY|NEXT_PUBLIC_SITE_URL"
doppler secrets download --project soleur --config prd --no-file --format env-no-quotes \
  | grep -E "^($allowed)=" \
  | while IFS= read -r line; do
```

## Why This Works

1. **Push event unsupported:** `claude-code-action`'s `parseGitHubContext()` only handles: `issues`, `issue_comment`, `pull_request`, `pull_request_target`, `pull_request_review`, `pull_request_review_comment`, `workflow_dispatch`, `repository_dispatch`, `schedule`, `workflow_run`. Push events hit the `default` case and throw. Removing the push trigger eliminates the unsupported event entirely. Monthly cron + manual dispatch are sufficient while dry-run mode is permanent.

2. **--only-secrets does not exist:** The flag was never part of the Doppler CLI (v3.75+). The `grep -E "^($allowed)="` filter restricts secrets to the 4 intended keys. The `^` anchor + `=` delimiter prevent substring matches (e.g., `SUPABASE_URL_BACKUP` cannot match `SUPABASE_URL`). Under GitHub Actions' `bash -e` (no `pipefail`), `grep` exit 1 on no matches does not fail the step because `while read` (exit 0) is the pipeline's last command.

## Prevention

- Before using a CLI flag in a workflow, verify it exists in the tool's `--help` output or documentation -- don't assume flags from memory or other tools
- Check `claude-code-action`'s supported event list before adding new trigger types to workflows that use it
- When debugging minified error output, look for the actual error message in surrounding lines rather than focusing on the minified code fragment that happens to be displayed

## Related Issues

- See also: [claude-code-action-token-revocation](../2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md) -- another claude-code-action integration issue
- See also: [doppler-service-token-config-scope-mismatch](../2026-03-29-doppler-service-token-config-scope-mismatch.md) -- Doppler service token scoping
- See also: [ux-audit-calibration-miss-path](../2026-04-15-ux-audit-calibration-miss-path.md) -- why dry-run mode is permanent
- Ref: #2376 (this fix), #2346 (original workflow), #2371, #2373, #2392 (prior fix attempts)
