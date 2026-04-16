---
title: "fix: resolve scheduled-ux-audit.yml failures (push event, Doppler flag)"
type: fix
date: 2026-04-16
issue: 2376
related: [2341, 2342, 2346, 2371, 2373, 2392]
branch: feat-fix-ux-audit-sdk-crash
worktree: .worktrees/feat-fix-ux-audit-sdk-crash/
---

# fix: resolve scheduled-ux-audit.yml failures (push event, Doppler flag)

## Overview

The `Scheduled: UX Audit` workflow (`.github/workflows/scheduled-ux-audit.yml`) is failing on all `push`-triggered runs and has an invalid Doppler CLI flag. Two root causes, both in the workflow YAML:

1. **Primary**: `claude-code-action` does not support `push` events. The action's `parseGitHubContext()` only handles: `issues`, `issue_comment`, `pull_request`, `pull_request_target`, `pull_request_review`, `pull_request_review_comment`, `workflow_dispatch`, `repository_dispatch`, `schedule`, `workflow_run`. Push events hit the `default` case and throw `Unsupported event type: push`. This is confirmed in both the pinned version (v1.0.75) and the latest (v1.0.97).

2. **Secondary**: `--only-secrets` flag on line 93 does not exist in Doppler CLI v3.75+. The command prints an error but exits 0, so downstream steps still receive all secrets (not just the filtered set).

## Research Reconciliation -- Issue Description vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| SDK/Ajv crash during claude-code-action startup is the primary blocker | The Ajv `dependencies` code in the error output is minified source context around line 19 of `sdk.mjs`, not the actual error. Run 24469143935 shows the real error: "Credit balance is too low". Two successful `workflow_dispatch` runs (24472727054, 24469469972) prove the SDK, plugin schemas (`.mcp.json`, `plugin.json`), and Ajv validation work correctly. | Drop the Ajv/schema investigation entirely. The "SDK crash" is a misread of the error output format. |
| Push-triggered runs fail with SDK crash | They fail with `Unsupported event type: push` before any SDK/schema validation runs. | Fix the `push` trigger by converting it to a supported event type. |
| `--only-secrets` flag is secondary/non-blocking | Confirmed: Doppler prints error but exits 0. All secrets leak into `$GITHUB_ENV` instead of just the 4 intended ones. | Fix with grep filter approach (as described in issue). |

## Proposed Solution

### Fix 1: Convert `push` trigger to `workflow_run` (or remove it)

`claude-code-action` supports `schedule`, `workflow_dispatch`, `repository_dispatch`, and `workflow_run` as automation events. Two options:

**Option A (recommended): Remove the `push` trigger entirely.**

The workflow already has a monthly cron (`0 9 1 * *`) and manual `workflow_dispatch`. The `push` trigger was intended to catch UI changes on merge, but `UX_AUDIT_DRY_RUN` is permanently `true` (per #2392 calibration MISS outcome). Running the full audit on every push that touches `apps/web-platform/app/**` or `components/**` is expensive ($3.55/run per run 24474065455) and produces artifacts that require manual founder review. The monthly cron and manual dispatch are sufficient for the dry-run-only mode.

**Option B: Convert `push` to `workflow_run` trigger.**

Create a lightweight "trigger" workflow that runs on `push` to `main` with the same path filters, and have `scheduled-ux-audit.yml` trigger via `workflow_run` on that workflow. This preserves the event-driven path but adds complexity. Only worth doing if/when `UX_AUDIT_DRY_RUN` is flipped to `false`.

**Decision: Option A.** Remove the `push` trigger. Add a comment documenting why (link to this plan and the `Unsupported event type: push` error). When dry-run mode is disabled in the future (requires calibration pass per #2392), the `push` trigger can be re-added via the `workflow_run` pattern.

### Fix 2: Replace `--only-secrets` with grep filter

Replace the invalid `--only-secrets` flag in the "Inject Doppler secrets (prd)" step with a `grep -E` filter that restricts which secrets are injected into `$GITHUB_ENV`.

**Before (line 92-99):**

```yaml
doppler secrets download --project soleur --config prd --no-file --format env-no-quotes \
  --only-secrets SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,NEXT_PUBLIC_SUPABASE_ANON_KEY,NEXT_PUBLIC_SITE_URL | while IFS= read -r line; do
```

**After:**

```yaml
allowed="SUPABASE_URL|SUPABASE_SERVICE_ROLE_KEY|NEXT_PUBLIC_SUPABASE_ANON_KEY|NEXT_PUBLIC_SITE_URL"
doppler secrets download --project soleur --config prd --no-file --format env-no-quotes \
  | grep -E "^($allowed)=" \
  | while IFS= read -r line; do
```

## Implementation Phases

### Phase 1: Fix the workflow file (single commit)

Both fixes are in `.github/workflows/scheduled-ux-audit.yml`:

1. **Remove `push` trigger block** (lines 28-31). Keep `schedule` and `workflow_dispatch`.
2. **Replace `--only-secrets` with grep filter** (lines 92-93). Use the `allowed` variable + `grep -E` pattern.
3. **Update workflow header comment** to document the removal of the `push` trigger and the reason.

Files to modify:

- `.github/workflows/scheduled-ux-audit.yml`

### Phase 2: Verify

1. Push the branch and trigger a manual workflow run: `gh workflow run scheduled-ux-audit.yml`.
2. Verify the Doppler step no longer prints the `--only-secrets` error.
3. Verify the `claude-code-action` step runs (no `Unsupported event type` error).
4. Confirm the workflow completes (success or expected `error_max_turns`/dry-run behavior).

## Acceptance Criteria

- [ ] `push` trigger is removed from `scheduled-ux-audit.yml`
- [ ] `--only-secrets` flag is replaced with `grep -E` filter restricting to 4 named secrets
- [ ] Workflow header comment documents the `push` trigger removal with rationale
- [ ] Manual `workflow_dispatch` run succeeds past the Doppler and `claude-code-action` steps

## Test Scenarios

- Given a `workflow_dispatch` trigger, when the workflow runs, then the Doppler step outputs no `Error: unknown flag` and the `claude-code-action` step does not throw `Unsupported event type`.
- Given the grep filter in the prd Doppler step, when secrets are downloaded, then only `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `NEXT_PUBLIC_SITE_URL` are injected into `$GITHUB_ENV`.
- Given a push to main touching `apps/web-platform/app/**`, when the push event fires, then the `scheduled-ux-audit.yml` workflow does NOT trigger (push trigger removed).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Fix `claude-code-action` upstream to support `push` events | Not in our control. Even if a PR were accepted, we'd be blocked until it ships. The `push` trigger is also expensive in dry-run-only mode. |
| Use `repository_dispatch` with a separate trigger workflow | Adds complexity for no benefit while dry-run is permanent. Reconsider when calibration passes. |
| Investigate Ajv schema validation | Misdiagnosis. The SDK works fine -- two successful runs prove it. The "Ajv crash" was minified source context around a "Credit balance is too low" error. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CI workflow bug fix.

## References

- Issue: #2376
- Successful runs (workflow_dispatch): 24472727054, 24469469972
- Failed runs (push): 24478421961, 24477947551
- Failed run (credit balance): 24469143935
- `claude-code-action` supported events: `src/github/context.ts` in `anthropics/claude-code-action`
- Prior fix PRs: #2346, #2371, #2373, #2392
- Calibration MISS learning: `knowledge-base/project/learnings/2026-04-15-ux-audit-calibration-miss-path.md`
