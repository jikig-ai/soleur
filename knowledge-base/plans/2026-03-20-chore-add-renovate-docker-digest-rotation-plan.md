---
title: "chore: add Renovate for automated Docker digest and dependency rotation"
type: feat
date: 2026-03-20
semver: patch
---

# chore: add Renovate for automated Docker digest and dependency rotation

## Overview

Both Dockerfiles (`apps/telegram-bridge/Dockerfile`, `apps/web-platform/Dockerfile`) pin base images to SHA256 digests for supply-chain security. All 25 GitHub Actions workflow files pin action references to commit SHAs (52 total pins). Both Dockerfiles also pin `@anthropic-ai/claude-code` to a specific npm version. None of these pinned references receive upstream security patches unless manually updated.

This plan adds a Renovate configuration to automatically create PRs when upstream images, actions, or packages publish new versions/digests.

## Problem Statement / Motivation

Digest-pinned Docker images and SHA-pinned GitHub Actions are immutable references -- they never change. This is the correct security posture, but it means the project will silently fall behind on security patches unless someone manually monitors upstream registries and updates every pin. With 2 Docker digest pins, 52 GitHub Actions SHA pins, and 2 npm version pins, manual tracking is unsustainable.

## Proposed Solution

Add Renovate Bot (GitHub App) with a `renovate.json` configuration file at the repository root. Renovate will:

1. Detect Docker digest pins in both Dockerfiles and open PRs when upstream tags publish new digests
2. Detect GitHub Actions SHA pins in all 25 workflow files and open PRs when actions publish new versions
3. Detect npm version pins in Dockerfiles (the `npm install -g @anthropic-ai/claude-code@2.1.79` pattern) and open PRs for new releases
4. Auto-merge digest-only updates (no version change, just a new digest for the same tag) after CI passes

### Why Renovate over Dependabot

| Criteria | Renovate | Dependabot |
|----------|----------|------------|
| Docker digest updates | First-class support with `docker:pinDigests` preset | Supported but less configurable |
| GitHub Actions SHA pins | `helpers:pinGitHubActionDigests` preset, preserves version comments | Supported |
| npm in Dockerfiles | Detects `npm install -g pkg@version` inside Dockerfiles | Does not detect npm pins inside Dockerfiles |
| Auto-merge | Built-in `automergeDigest` preset | Requires separate GitHub Actions workflow |
| Grouping | Native `group:` rules | Supported but less flexible |
| Config-as-code | Single `renovate.json` | `.github/dependabot.yml` |
| Update scheduling | Cron-granular scheduling | daily/weekly/monthly only |

Renovate wins on npm-in-Dockerfile detection and built-in auto-merge. Both tools are free for open-source repos.

## Technical Considerations

### Renovate GitHub App Installation

Renovate runs as a GitHub App, not a GitHub Actions workflow. The org admin must install the Renovate app from [github.com/apps/renovate](https://github.com/apps/renovate) and grant it access to `jikig-ai/soleur`. This is a one-time manual step -- Renovate cannot be installed programmatically (requires OAuth consent).

After installation, Renovate will:
1. Open an onboarding PR with the detected dependency inventory
2. Begin opening update PRs according to `renovate.json` configuration

### Configuration Design

```json
// renovate.json (repo root)
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "docker:pinDigests",
    "helpers:pinGitHubActionDigests",
    "default:automergeDigest"
  ],
  "packageRules": [
    {
      "description": "Group all Docker digest updates into one PR",
      "matchDatasources": ["docker"],
      "matchUpdateTypes": ["digest"],
      "groupName": "docker-digests",
      "automerge": true
    },
    {
      "description": "Group all GitHub Actions digest updates into one PR",
      "matchManagers": ["github-actions"],
      "matchUpdateTypes": ["digest"],
      "groupName": "github-actions-digests",
      "automerge": true
    },
    {
      "description": "Do not auto-merge version bumps (only digests)",
      "matchUpdateTypes": ["major", "minor", "patch"],
      "automerge": false
    }
  ],
  "schedule": ["before 7am on Monday"]
}
```

Key design choices:
- **Extends `config:recommended`**: Sensible defaults, enables minor/patch updates
- **`docker:pinDigests`**: Ensures new Dockerfile images get pinned
- **`helpers:pinGitHubActionDigests`**: Keeps Actions SHA pins current
- **`default:automergeDigest`**: Digest-only updates auto-merge after CI passes (low risk -- same tag, just newer build)
- **Grouping**: Docker digest updates grouped into one PR, Actions digest updates grouped into another -- reduces PR noise
- **Version bumps require review**: Major/minor/patch version changes are NOT auto-merged -- they may contain breaking changes
- **Weekly schedule**: Monday mornings, before work begins -- batches a week of upstream changes

### Interaction with Existing CI

Renovate PRs trigger the existing CI workflow (`.github/workflows/ci.yml`) which runs `bun test`. This provides the safety gate for auto-merge. No CI changes needed.

### Interaction with Branch Protection

Auto-merge is already enabled on the repo (`allow_auto_merge: true`). Renovate uses GitHub's native auto-merge feature, so it respects branch protection rules and required status checks.

### Interaction with CLA Workflow

The CLA workflow (`.github/workflows/cla.yml`) triggers on `pull_request_target` with `issue_comment`. Renovate bot PRs will need CLA exemption. The existing CLA workflow should be checked for bot exemptions.

### npm Pins in Dockerfiles

Renovate's Dockerfile manager can detect `RUN npm install -g @anthropic-ai/claude-code@2.1.79` and propose version updates. This covers both:
- `apps/telegram-bridge/Dockerfile:9`
- `apps/web-platform/Dockerfile:4`

These updates will NOT be auto-merged (they are version bumps, not digest rotations).

## Non-goals

- **Replacing SHA-pinning with tag-only references**: The current pinning strategy is correct; Renovate automates rotation, not removal
- **Managing Terraform provider versions**: Out of scope for this issue
- **Managing Bun/Node.js runtime versions**: Could be added later but not part of this PR
- **Self-hosted Renovate**: The hosted GitHub App is sufficient for an open-source repo

## Acceptance Criteria

- [ ] `renovate.json` exists at repository root with Docker digest, GitHub Actions, and auto-merge configuration
- [ ] Renovate GitHub App is installed on `jikig-ai/soleur` (manual step by org admin)
- [ ] Renovate onboarding PR is opened and merged after installation
- [ ] Digest-only updates auto-merge after CI passes
- [ ] Version bump PRs require manual review (not auto-merged)
- [ ] Docker digest updates are grouped into a single PR per schedule window
- [ ] GitHub Actions digest updates are grouped into a single PR per schedule window
- [ ] CLA workflow does not block Renovate bot PRs

## Test Scenarios

- Given the Renovate config exists and the app is installed, when `node:22-slim` publishes a new digest on Docker Hub, then Renovate opens a PR updating `apps/web-platform/Dockerfile` line 1 with the new digest
- Given the Renovate config exists, when `oven/bun:1.3.11` publishes a new digest, then Renovate opens a PR updating `apps/telegram-bridge/Dockerfile` line 1 with the new digest
- Given the Renovate config exists, when `actions/checkout` publishes a new release, then Renovate opens a PR updating the SHA pin across all workflows that reference it, preserving the version comment
- Given a digest-only Renovate PR, when CI passes, then the PR auto-merges via GitHub's native auto-merge
- Given a version bump Renovate PR (e.g., `@anthropic-ai/claude-code` 2.1.79 to 2.2.0), when CI passes, then the PR does NOT auto-merge and waits for manual review
- Given the CLA workflow, when Renovate opens a PR, then the CLA check passes or is bypassed for bot accounts

## MVP

### renovate.json

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "docker:pinDigests",
    "helpers:pinGitHubActionDigests",
    "default:automergeDigest"
  ],
  "packageRules": [
    {
      "description": "Group all Docker digest updates into one PR",
      "matchDatasources": ["docker"],
      "matchUpdateTypes": ["digest"],
      "groupName": "docker-digests",
      "automerge": true
    },
    {
      "description": "Group all GitHub Actions digest updates into one PR",
      "matchManagers": ["github-actions"],
      "matchUpdateTypes": ["digest"],
      "groupName": "github-actions-digests",
      "automerge": true
    },
    {
      "description": "Do not auto-merge version bumps (only digests)",
      "matchUpdateTypes": ["major", "minor", "patch"],
      "automerge": false
    }
  ],
  "schedule": ["before 7am on Monday"]
}
```

## Dependencies & Risks

### Dependencies

- **Renovate GitHub App installation**: Requires org admin access. This is the only manual prerequisite.
- **CI must pass on Renovate PRs**: The existing `ci.yml` workflow must work for PRs from the Renovate bot.

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CLA workflow blocks Renovate PRs | Medium | Low | Add bot exemption to CLA config or allowlist |
| Too many PRs from Renovate | Low | Low | Grouping and weekly schedule limit PR volume |
| Auto-merged digest breaks build | Very Low | Medium | CI runs before auto-merge; digest changes only affect base image layer, not app code |
| Renovate detects false positive dependencies | Low | Low | Review onboarding PR carefully; add `ignoreDeps` if needed |

## References

- Issue: #816
- `apps/web-platform/Dockerfile` -- `node:22-slim@sha256:...` (pinned in #814)
- `apps/telegram-bridge/Dockerfile` -- `oven/bun:1.3.11@sha256:...` (pinned in #801)
- `@anthropic-ai/claude-code@2.1.79` npm pin (pinned in #803)
- Learning: `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- [Renovate Docker docs](https://docs.renovatebot.com/docker/)
- [Renovate GitHub Actions manager](https://docs.renovatebot.com/modules/manager/github-actions/)
- [Renovate configuration options](https://docs.renovatebot.com/configuration-options/)
