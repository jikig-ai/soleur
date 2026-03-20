# Tasks: Add Renovate for Docker Digest Rotation

## Phase 1: Setup

- [ ] 1.1 Create `renovate.json` at repository root with the configuration from the plan MVP section
  - Extends: `config:recommended`, `docker:pinDigests`, `helpers:pinGitHubActionDigests`, `default:automergeDigest`
  - Package rules: group Docker digests, group GitHub Actions digests, disable auto-merge for version bumps
  - Schedule: weekly on Monday mornings

## Phase 2: CLA Compatibility

- [ ] 2.1 Review `.github/workflows/cla.yml` for bot exemption handling
  - Check if Renovate bot (`renovate[bot]`) is exempt from CLA requirements
  - If not, add bot exemption to prevent CLA blocking Renovate PRs
- [ ] 2.2 Verify `ci.yml` triggers on Renovate PRs (no path or actor filters that would exclude bot PRs)

## Phase 3: Manual Steps (Post-Merge)

- [ ] 3.1 Install Renovate GitHub App on `jikig-ai/soleur` (requires org admin -- genuinely manual, no API)
  - Navigate to https://github.com/apps/renovate and install for `jikig-ai/soleur`
- [ ] 3.2 Review and merge the Renovate onboarding PR (auto-created after app installation)
- [ ] 3.3 Verify first automated digest update PR is created and auto-merges after CI

## Phase 4: Testing

- [ ] 4.1 Validate `renovate.json` schema (JSON schema validation against Renovate schema)
- [ ] 4.2 Verify grouping rules produce expected PR grouping in onboarding PR dependency list
- [ ] 4.3 Confirm auto-merge behavior: digest PRs auto-merge, version bump PRs do not
