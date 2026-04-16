---
title: "fix: resolve scheduled-ux-audit.yml failures (push event, Doppler flag)"
type: fix
date: 2026-04-16
issue: 2376
related: [2341, 2342, 2346, 2371, 2373, 2392]
branch: feat-fix-ux-audit-sdk-crash
worktree: .worktrees/feat-fix-ux-audit-sdk-crash/
---

## Enhancement Summary

**Deepened on:** 2026-04-16
**Sections enhanced:** 3 (Fix 2 edge cases, Implementation verification, Test Scenarios)
**Research sources:** Workflow run logs (5 runs analyzed), `claude-code-action` source (v1.0.75 + v1.0.97), Doppler learnings, CI shell behavior analysis

### Key Improvements

1. Confirmed `grep -E` filter is safe under `bash -e` without `pipefail` (GitHub Actions default for user `run:` blocks) -- `while read` is the last pipeline command and exits 0 even when grep finds no matches
2. Added edge case: if Doppler `prd` config loses any of the 4 expected secrets, grep silently produces no output -- added diagnostic `echo` to surface this
3. Identified that `claude-code-action` v1.0.97 (latest) still does not support `push` events, confirming removal is the only viable path without an upstream PR

### Relevant Institutional Learnings Applied

- `2026-03-29-doppler-service-token-config-scope-mismatch.md`: Confirms the workflow correctly uses `DOPPLER_TOKEN_PRD` (config-specific secret name) -- no scope mismatch risk
- `2026-02-21-github-actions-workflow-security-patterns.md`: All actions in the workflow are already SHA-pinned -- no changes needed
- `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`: Pattern of pre-validating command output before parsing applies to the grep filter (though less critical here since grep output is plain text, not JSON)
- Constitution `set -euo pipefail` audit vector: `grep` in pipelines returns exit 1 on no match, which `-o pipefail` would propagate -- but user `run:` blocks use `bash -e` only (no `pipefail`), so the `while read` command's exit code (0) governs the pipeline

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

### Research Insights (Fix 2)

**Shell pipeline behavior under `bash -e`:**

GitHub Actions user `run:` blocks use `bash -e` without `-o pipefail` (confirmed from run logs: `shell: /usr/bin/bash -e {0}`). In a `cmd1 | cmd2` pipeline under `bash -e`:

- Only the **last** command's exit code determines step success/failure
- `grep -E` returning exit 1 (no matches) does NOT fail the step because `while read` (exit 0) is the pipeline's last command
- If `pipefail` were enabled, `grep` exit 1 would propagate -- but it is not

**Edge case -- missing secrets in Doppler `prd` config:**

If any of the 4 expected secrets (`SUPABASE_URL`, etc.) are missing from the Doppler `prd` config, `grep` silently produces no output for that key. The downstream steps (`bot-fixture.ts seed`, `bot-signin.ts`) would then fail with missing env vars, but the error message would be opaque ("Missing SUPABASE_URL" at runtime, not at the Doppler injection step).

**Mitigation (optional, low priority):** Add a diagnostic count after the `while` loop:

```bash
count=$(doppler secrets download --project soleur --config prd --no-file --format env-no-quotes \
  | grep -cE "^($allowed)=" || true)
if [ "$count" -lt 4 ]; then
  echo "::warning::Expected 4 Doppler prd secrets, got $count"
fi
```

This is optional because the 4 secrets have been stable in `prd` since the workflow was created (#2346), and a missing secret would surface clearly in the seed/signin steps. Adding the diagnostic is a defense-in-depth improvement, not a required fix.

**Pattern: `grep -E "^(A|B|C)="` prevents substring matches.**

The `^` anchor + `=` delimiter ensure `SUPABASE_URL_BACKUP=...` does NOT match `SUPABASE_URL` -- the regex requires the key to start at the beginning of the line and end with `=` immediately after the key name.

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

### Research Insights (Verification)

**Verification must happen post-merge, not on the feature branch.** The `claude-code-action` step installs the plugin from `https://github.com/jikig-ai/soleur.git` (the default branch). Running `gh workflow run scheduled-ux-audit.yml --ref feat-fix-ux-audit-sdk-crash` would use the feature branch's workflow YAML (fixing the `push` trigger and `--only-secrets` issues) but the claude-code-action would install the plugin from `main`. Since the fixes are workflow-level only (not plugin code), this is fine -- the feature branch YAML is what gets tested.

**Expected run outcome:** The two successful `workflow_dispatch` runs (24472727054: success, 24469469972: success) prove that once the `push` event and `--only-secrets` errors are eliminated, the workflow runs to completion. The expected outcome for verification is either `success` or `error_max_turns` (the agent hitting 60-turn limit, which is acceptable in dry-run mode -- the findings artifact is still uploaded).

**Cost awareness:** Each successful run costs approximately $3.55 in Anthropic API usage (from run 24474065455). The verification run is necessary but should be limited to one dispatch.

## Acceptance Criteria

- [ ] `push` trigger is removed from `scheduled-ux-audit.yml`
- [ ] `--only-secrets` flag is replaced with `grep -E` filter restricting to 4 named secrets
- [ ] Workflow header comment documents the `push` trigger removal with rationale
- [ ] Manual `workflow_dispatch` run succeeds past the Doppler and `claude-code-action` steps

## Test Scenarios

- Given a `workflow_dispatch` trigger, when the workflow runs, then the Doppler step outputs no `Error: unknown flag` and the `claude-code-action` step does not throw `Unsupported event type`.
- Given the grep filter in the prd Doppler step, when secrets are downloaded, then only `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `NEXT_PUBLIC_SITE_URL` are injected into `$GITHUB_ENV`.
- Given a push to main touching `apps/web-platform/app/**`, when the push event fires, then the `scheduled-ux-audit.yml` workflow does NOT trigger (push trigger removed).

### Research Insights (Test Scenarios)

**Verification command sequence (post-merge):**

```bash
# 1. Trigger a manual run
gh workflow run scheduled-ux-audit.yml

# 2. Get the run ID (wait a few seconds for it to appear)
RUN_ID=$(gh run list --workflow=scheduled-ux-audit.yml --limit 1 --json databaseId --jq '.[0].databaseId')

# 3. Check the Doppler step output for the --only-secrets error
gh run view "$RUN_ID" --log 2>&1 | grep -c "unknown flag: --only-secrets"
# Expected: 0 (no matches)

# 4. Check for the Unsupported event type error
gh run view "$RUN_ID" --log 2>&1 | grep -c "Unsupported event type"
# Expected: 0 (no matches)

# 5. Verify the claude-code-action step reached SDK execution
gh run view "$RUN_ID" --log 2>&1 | grep "Running Claude Code via SDK"
# Expected: match found (SDK started)
```

**Negative test -- push trigger removal:** After merging, push a trivial change to `apps/web-platform/app/` (e.g., whitespace in a comment). Verify via `gh run list --workflow=scheduled-ux-audit.yml --limit 3` that no new run was triggered by the push event.

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
