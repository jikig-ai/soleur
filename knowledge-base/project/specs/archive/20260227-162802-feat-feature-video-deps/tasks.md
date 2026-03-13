# Tasks: Feature Video Dependency Check

**Plan:** `knowledge-base/plans/2026-02-27-fix-feature-video-silent-failure-plan.md`
**Issue:** #325
**Branch:** feat-feature-video-deps

## Phase 1: Create check_deps.sh

- [x] 1.1 Create `plugins/soleur/skills/feature-video/scripts/` directory
- [x] 1.2 Write `check_deps.sh` (agent-browser hard check, ffmpeg/rclone soft checks, rclone remote config check)
- [x] 1.3 Make script executable (`chmod +x`)

## Phase 2: Modify SKILL.md

- [x] 2.1 Update frontmatter `description:` to reflect optional video capability
- [x] 2.2 Update Prerequisites to mark ffmpeg and rclone as optional
- [x] 2.3 Add Phase 0 dependency check section calling `check_deps.sh`
- [x] 2.4 Add link to script: `[check_deps.sh](./scripts/check_deps.sh)`
- [x] 2.5 Ensure `mkdir -p tmp/screenshots` runs unconditionally before recording
- [x] 2.6 Add conditional to skip ffmpeg commands in Steps 4-5 when absent
- [x] 2.7 Add conditional to skip rclone commands in Step 6 when absent/unconfigured
- [x] 2.8 Step 7: adapt PR description based on actual output
- [x] 2.9 Step 8: only delete screenshots if they were converted to video

## Phase 3: Version Bump & Finalize

- [x] 3.1 Bump PATCH version in plugin.json
- [x] 3.2 Add CHANGELOG.md entry
- [x] 3.3 Bump marketplace.json version
- [x] 3.4 Update root README.md version badge
- [x] 3.5 Update bug_report.yml version placeholder
