# Tasks: Add Renovate for Docker Digest Rotation

## Phase 1: Setup

- [ ] 1.1 Create `renovate.json5` at repository root with the configuration from the plan MVP section
  - File: `renovate.json5` (JSON5 format to support comments)
  - Extends: `config:recommended`, `docker:pinDigests`, `helpers:pinGitHubActionDigests`, `default:automergeDigest`, `schedule:weekly`
  - Timezone: `Europe/Paris`
  - Package rules: group Docker digests, group GitHub Actions digests, disable auto-merge for version bumps
  - Custom regex manager for `npm install -g @scope/package@version` patterns in Dockerfiles
  - Labels: `["dependencies"]`

## Phase 2: Validation

- [x] 2.1 CLA compatibility -- ALREADY RESOLVED
  - `renovate[bot]` is already in CLA allowlist at `.github/workflows/cla.yml:34`
  - No changes needed
- [ ] 2.2 Verify `ci.yml` triggers on Renovate PRs (no path or actor filters that exclude bot PRs)
- [ ] 2.3 Validate `renovate.json5` schema against Renovate JSON schema

## Phase 3: Manual Steps (Post-Merge)

- [ ] 3.1 Install Renovate GitHub App on `jikig-ai/soleur` (requires org admin -- genuinely manual, no API)
  - Navigate to https://github.com/apps/renovate and install for `jikig-ai/soleur`
  - Since `renovate.json5` is already committed, the onboarding PR will be skipped
- [ ] 3.2 Verify Renovate opens grouped digest update PRs on next scheduled run
- [ ] 3.3 Verify first digest-only PR auto-merges after CI passes
- [ ] 3.4 Verify custom regex manager detects `@anthropic-ai/claude-code` in both Dockerfiles

## Phase 4: Testing

- [ ] 4.1 Confirm auto-merge behavior: digest PRs auto-merge, version bump PRs do not
- [ ] 4.2 Verify version comment preservation on GitHub Actions SHA updates (e.g., `# v4.3.1`)
- [ ] 4.3 Monitor Claude Code Review API credit usage on Renovate PRs -- add author filter if excessive
