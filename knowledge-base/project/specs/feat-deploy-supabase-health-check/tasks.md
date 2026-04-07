# Tasks: Add Supabase Connectivity Check to Deploy Health Verification

## Phase 1: Implementation

### 1.1 Modify deploy health verification step

- [x] Edit `.github/workflows/web-platform-release.yml` "Verify deploy health and version" step
- [x] Add `SUPABASE_STATUS` extraction via `jq -r '.supabase // empty'` after version match check
- [x] Add conditional: if `SUPABASE_STATUS != "connected"`, log and continue retrying
- [x] Update success message to include "supabase connected" confirmation
- [x] Update final error message to mention "supabase connected" expectation

### 1.2 Validate YAML syntax

- [x] Run `gh workflow view web-platform-release.yml` to verify the workflow parses correctly
- [x] Verify no heredocs or multi-line strings drop below YAML base indentation (AGENTS.md constraint)

## Phase 2: Testing

### 2.1 Verify workflow syntax

- [ ] Push branch and confirm GitHub Actions parses the workflow file without "workflow file issue" errors

### 2.2 Post-merge integration verification

- [ ] After merge, trigger a manual `workflow_dispatch` of `web-platform-release.yml`
- [ ] Verify the supabase check appears in the deploy verification logs
- [ ] Verify the deploy succeeds with "supabase connected" in output
