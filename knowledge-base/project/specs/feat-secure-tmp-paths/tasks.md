# Tasks: sec: secure tmp paths in release workflow

## Phase 1: Implementation

### 1.1 Add secure temp file creation step

Add a new step `Create secure temp files` (id: `tmpfiles`) after checkout and before "Find merged PR" in `.github/workflows/version-bump-and-release.yml`. The step creates four temp files via `mktemp` and exports their paths via `GITHUB_OUTPUT`.

**File:** `.github/workflows/version-bump-and-release.yml`

- [x] Add step with `id: tmpfiles`
- [x] Create `pr_body`, `release_notes`, `current_tag`, `gh_err` via `mktemp`
- [x] Export all four paths to `$GITHUB_OUTPUT`

### 1.2 Update "Find merged PR" step

Replace all `/tmp/pr_body.txt` references with the secure path from `steps.tmpfiles.outputs.pr_body`.

**File:** `.github/workflows/version-bump-and-release.yml`

- [x] Pass `PR_BODY_FILE: ${{ steps.tmpfiles.outputs.pr_body }}` via `env:`
- [x] Update `give_up()` function to use `$PR_BODY_FILE` instead of `/tmp/pr_body.txt`
- [x] Update `workflow_dispatch` branch to use `$PR_BODY_FILE`
- [x] Update PR metadata write to use `$PR_BODY_FILE`
- [x] Update `body_file=` output to reference the env var

### 1.3 Update "Compute next version" step

Replace `/tmp/current_tag` and `/tmp/gh_err` with secure paths.

**File:** `.github/workflows/version-bump-and-release.yml`

- [x] Pass `CURRENT_TAG_FILE: ${{ steps.tmpfiles.outputs.current_tag }}` via `env:`
- [x] Pass `GH_ERR_FILE: ${{ steps.tmpfiles.outputs.gh_err }}` via `env:`
- [x] Update `gh release view` redirect to use `$CURRENT_TAG_FILE` and `$GH_ERR_FILE`
- [x] Update `grep` and `sed` commands to reference the new paths

### 1.4 Update "Extract changelog" step

Replace `/tmp/pr_body.txt` and `/tmp/release_notes.txt` with secure paths.

**File:** `.github/workflows/version-bump-and-release.yml`

- [x] Pass `BODY_FILE: ${{ steps.tmpfiles.outputs.pr_body }}` via `env:` (replace hardcoded assignment)
- [x] Pass `RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}` via `env:`
- [x] Update `BODY_FILE=` assignment to use the env var
- [x] Update release notes write to use `$RELEASE_NOTES_FILE`

### 1.5 Update "Create GitHub Release" step

Replace `/tmp/release_notes.txt` with secure path.

**File:** `.github/workflows/version-bump-and-release.yml`

- [x] Pass `RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}` via `env:`
- [x] Update `--notes-file` to reference `$RELEASE_NOTES_FILE`

### 1.6 Update "Post to Discord" step

Replace `/tmp/release_notes.txt` with secure path.

**File:** `.github/workflows/version-bump-and-release.yml`

- [x] Pass `RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}` via `env:`
- [x] Update `cat` command to reference `$RELEASE_NOTES_FILE`

## Phase 2: Verification

### 2.1 Grep verification

- [x] Run `grep -n '/tmp/' .github/workflows/version-bump-and-release.yml` -- must return zero results
- [x] Run `grep -c 'tmpfiles.outputs' .github/workflows/version-bump-and-release.yml` -- must return count matching all temp path references (7)

### 2.2 YAML validation

- [x] Verify workflow YAML is valid (no syntax errors from the edits)
- [x] Verify all `steps.tmpfiles.outputs.*` references match the keys defined in the tmpfiles step
