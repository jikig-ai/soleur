# Tasks: sec: secure tmp paths in release workflow

## Phase 1: Implementation

### 1.1 Add secure temp file creation step

Add a new step `Create secure temp files` (id: `tmpfiles`) after checkout and before "Find merged PR" in `.github/workflows/version-bump-and-release.yml`. The step creates four temp files via `mktemp` and exports their paths via `GITHUB_OUTPUT`.

**File:** `.github/workflows/version-bump-and-release.yml`

- [ ] Add step with `id: tmpfiles`
- [ ] Create `pr_body`, `release_notes`, `current_tag`, `gh_err` via `mktemp`
- [ ] Export all four paths to `$GITHUB_OUTPUT`

### 1.2 Update "Find merged PR" step

Replace all `/tmp/pr_body.txt` references with the secure path from `steps.tmpfiles.outputs.pr_body`.

**File:** `.github/workflows/version-bump-and-release.yml`

- [ ] Pass `PR_BODY_FILE: ${{ steps.tmpfiles.outputs.pr_body }}` via `env:`
- [ ] Update `give_up()` function to use `$PR_BODY_FILE` instead of `/tmp/pr_body.txt`
- [ ] Update `workflow_dispatch` branch to use `$PR_BODY_FILE`
- [ ] Update PR metadata write to use `$PR_BODY_FILE`
- [ ] Update `body_file=` output to reference the env var

### 1.3 Update "Compute next version" step

Replace `/tmp/current_tag` and `/tmp/gh_err` with secure paths.

**File:** `.github/workflows/version-bump-and-release.yml`

- [ ] Pass `CURRENT_TAG_FILE: ${{ steps.tmpfiles.outputs.current_tag }}` via `env:`
- [ ] Pass `GH_ERR_FILE: ${{ steps.tmpfiles.outputs.gh_err }}` via `env:`
- [ ] Update `gh release view` redirect to use `$CURRENT_TAG_FILE` and `$GH_ERR_FILE`
- [ ] Update `grep` and `sed` commands to reference the new paths

### 1.4 Update "Extract changelog" step

Replace `/tmp/pr_body.txt` and `/tmp/release_notes.txt` with secure paths.

**File:** `.github/workflows/version-bump-and-release.yml`

- [ ] Pass `BODY_FILE: ${{ steps.tmpfiles.outputs.pr_body }}` via `env:` (replace hardcoded assignment)
- [ ] Pass `RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}` via `env:`
- [ ] Update `BODY_FILE=` assignment to use the env var
- [ ] Update release notes write to use `$RELEASE_NOTES_FILE`

### 1.5 Update "Create GitHub Release" step

Replace `/tmp/release_notes.txt` with secure path.

**File:** `.github/workflows/version-bump-and-release.yml`

- [ ] Pass `RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}` via `env:`
- [ ] Update `--notes-file` to reference `$RELEASE_NOTES_FILE`

### 1.6 Update "Post to Discord" step

Replace `/tmp/release_notes.txt` with secure path.

**File:** `.github/workflows/version-bump-and-release.yml`

- [ ] Pass `RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}` via `env:`
- [ ] Update `cat` command to reference `$RELEASE_NOTES_FILE`

## Phase 2: Verification

### 2.1 Grep verification

- [ ] Run `grep -n '/tmp/' .github/workflows/version-bump-and-release.yml` -- must return zero results
- [ ] Run `grep -c 'tmpfiles.outputs' .github/workflows/version-bump-and-release.yml` -- must return count matching all temp path references

### 2.2 YAML validation

- [ ] Verify workflow YAML is valid (no syntax errors from the edits)
- [ ] Verify all `steps.tmpfiles.outputs.*` references match the keys defined in the tmpfiles step
