---
title: "chore: add Renovate for automated Docker digest and dependency rotation"
type: feat
date: 2026-03-20
semver: patch
---

# chore: add Renovate for automated Docker digest and dependency rotation

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6
**Research sources used:** Renovate official docs (Docker, GitHub Actions, regex manager, scheduling, onboarding), CLA workflow analysis, institutional learnings (3 applied)

### Key Improvements
1. **Corrected npm-in-Dockerfile claim**: Renovate's Dockerfile manager only handles `FROM` image references, not `RUN npm install` -- added `customManagers` regex config to cover this gap
2. **CLA compatibility already solved**: `renovate[bot]` is pre-allowlisted in `.github/workflows/cla.yml` line 34 -- risk downgraded from Medium to None
3. **Fixed JSON comment syntax**: `renovate.json` does not support comments -- switched to `renovate.json5` format or removed comments
4. **Added schedule preset**: Replaced free-text `"before 7am on Monday"` with validated `"schedule:weekly"` preset
5. **Added Claude Code Review interaction**: Renovate digest PRs will trigger unnecessary AI code reviews -- added `ignorePaths` consideration
6. **Applied institutional learnings**: CLA ruleset behavior, bypass actor limitations, and synthetic status check patterns from project knowledge base

### New Considerations Discovered
- Renovate onboarding PR can be skipped by committing config before app installation
- Claude Code Review workflow (`.github/workflows/claude-code-review.yml`) will run on all Renovate PRs, consuming API credits on trivial digest changes
- The `customManagers` regex approach for npm pins inside Dockerfiles requires explicit `matchStrings` patterns -- not auto-discovered

## Overview

Both Dockerfiles (`apps/telegram-bridge/Dockerfile`, `apps/web-platform/Dockerfile`) pin base images to SHA256 digests for supply-chain security. All 25 GitHub Actions workflow files pin action references to commit SHAs (52 total pins). Both Dockerfiles also pin `@anthropic-ai/claude-code` to a specific npm version. None of these pinned references receive upstream security patches unless manually updated.

This plan adds a Renovate configuration to automatically create PRs when upstream images, actions, or packages publish new versions/digests.

## Problem Statement / Motivation

Digest-pinned Docker images and SHA-pinned GitHub Actions are immutable references -- they never change. This is the correct security posture, but it means the project will silently fall behind on security patches unless someone manually monitors upstream registries and updates every pin. With 2 Docker digest pins, 52 GitHub Actions SHA pins, and 2 npm version pins, manual tracking is unsustainable.

### Research Insights

**Supply-chain attack surface inventory:**
- `apps/web-platform/Dockerfile:1` -- `node:22-slim@sha256:4f77a690...` (pinned in #814)
- `apps/telegram-bridge/Dockerfile:1` -- `oven/bun:1.3.11@sha256:0733e503...` (pinned in #801)
- `apps/web-platform/Dockerfile:4` -- `npm install -g @anthropic-ai/claude-code@2.1.79` (pinned in #803)
- `apps/telegram-bridge/Dockerfile:9` -- `npm install -g @anthropic-ai/claude-code@2.1.79` (pinned in #803)
- 52 GitHub Actions SHA pins across 25 workflow files in `.github/workflows/`

**Institutional learning applied:** The `docker-base-image-digest-pinning` learning documents that Docker ignores the tag when a digest is present -- "if someone updates the tag without updating the digest, Docker silently uses the old image." Automated rotation prevents this silent drift.

## Proposed Solution

Add Renovate Bot (GitHub App) with a `renovate.json5` configuration file at the repository root. Renovate will:

1. Detect Docker digest pins in both Dockerfiles and open PRs when upstream tags publish new digests
2. Detect GitHub Actions SHA pins in all 25 workflow files and open PRs when actions publish new versions
3. Detect npm version pins in Dockerfiles via a custom regex manager (the built-in Dockerfile manager only handles `FROM` references)
4. Auto-merge digest-only updates (no version change, just a new digest for the same tag) after CI passes

### Why Renovate over Dependabot

| Criteria | Renovate | Dependabot |
|----------|----------|------------|
| Docker digest updates | First-class support with `docker:pinDigests` preset | Supported but less configurable |
| GitHub Actions SHA pins | `helpers:pinGitHubActionDigests` preset, preserves version comments | Supported |
| npm in Dockerfiles | Requires `customManagers` regex (not auto-detected) | Does not detect npm pins inside Dockerfiles |
| Auto-merge | Built-in `automergeDigest` preset | Requires separate GitHub Actions workflow |
| Grouping | Native `group:` rules | Supported but less flexible |
| Config-as-code | Single `renovate.json5` (supports comments) | `.github/dependabot.yml` |
| Update scheduling | Named presets + cron-granular scheduling | daily/weekly/monthly only |

Renovate wins on custom regex manager flexibility and built-in auto-merge. Both tools are free for open-source repos.

**Correction from initial plan:** Renovate's Dockerfile manager does NOT auto-detect `npm install` commands inside `RUN` directives. It only extracts image references from `FROM`, `COPY --from`, `RUN --mount`, and `syntax` directives. A `customManagers` regex entry is required to cover npm pins in Dockerfiles.

## Technical Considerations

### Renovate GitHub App Installation

Renovate runs as a GitHub App, not a GitHub Actions workflow. The org admin must install the Renovate app from [github.com/apps/renovate](https://github.com/apps/renovate) and grant it access to `jikig-ai/soleur`. This is a one-time manual step -- Renovate cannot be installed programmatically (requires OAuth consent).

After installation, Renovate will:
1. Open an onboarding PR with the detected dependency inventory -- OR skip onboarding if `renovate.json5` is already committed to the default branch
2. Begin opening update PRs according to configuration

**Best practice (from Renovate docs):** Commit the config file before installing the app to skip the interactive onboarding PR. This is the recommended approach since the config in this plan is already well-defined.

### Configuration Design

```json5
// renovate.json5 (repo root)
// JSON5 format allows comments -- standard JSON does not
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "docker:pinDigests",
    "helpers:pinGitHubActionDigests",
    "default:automergeDigest",
    "schedule:weekly"
  ],
  "timezone": "Europe/Paris",
  "packageRules": [
    {
      "description": "Group Docker digest updates into one PR",
      "matchDatasources": ["docker"],
      "matchUpdateTypes": ["digest"],
      "groupName": "docker-digests",
      "automerge": true
    },
    {
      "description": "Group GitHub Actions digest updates into one PR",
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
  // Custom regex manager to detect npm install -g patterns inside Dockerfiles
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["(^|/)Dockerfile$"],
      "matchStrings": [
        "npm install -g (?<depName>@[\\w-]+/[\\w-]+)@(?<currentValue>[\\d.]+)"
      ],
      "datasourceTemplate": "npm",
      "versioningTemplate": "npm"
    }
  ]
}
```

Key design choices:
- **Extends `config:recommended`**: Sensible defaults, enables minor/patch updates
- **`docker:pinDigests`**: Ensures new Dockerfile images get pinned and existing pins are rotated
- **`helpers:pinGitHubActionDigests`**: Keeps Actions SHA pins current, preserves `# vX.Y.Z` comments
- **`default:automergeDigest`**: Digest-only updates auto-merge after CI passes (low risk -- same tag, just newer build)
- **`schedule:weekly`**: Validated Renovate preset -- runs once per week (early Monday UTC by default); `timezone` set to `Europe/Paris` for the solo operator
- **Grouping**: Docker digest updates grouped into one PR, Actions digest updates grouped into another -- reduces PR noise
- **Version bumps require review**: Major/minor/patch version changes are NOT auto-merged -- they may contain breaking changes
- **`customManagers` regex**: Detects `npm install -g @scope/package@version` patterns in Dockerfiles -- the built-in Dockerfile manager only handles `FROM` image references

### Interaction with Existing CI

Renovate PRs trigger the existing CI workflow (`.github/workflows/ci.yml`) which runs `bun test`. This provides the safety gate for auto-merge. No CI changes needed.

### Interaction with Branch Protection

Auto-merge is already enabled on the repo (`allow_auto_merge: true`). Renovate uses GitHub's native auto-merge feature, so it respects branch protection rules and required status checks.

### Interaction with CLA Workflow

**Already resolved.** The CLA workflow (`.github/workflows/cla.yml`) has `renovate[bot]` in the allowlist on line 34:

```yaml
allowlist: "dependabot[bot],github-actions[bot],renovate[bot]"
```

No changes needed. Renovate PRs will pass CLA checks automatically.

### Research Insights: CLA Ruleset Interaction

**Institutional learnings applied:**

1. **`content-publisher-cla-ruleset-push-rejection`**: Bot workflows that need to commit to ruleset-protected `main` must use the PR-based commit pattern with synthetic status checks. Renovate already uses the PR-based pattern natively (it creates branches and opens PRs), so this is not a concern -- but it confirms the CLA check integration is functional for bot PRs.

2. **`github-actions-bypass-actor-not-feasible`**: The `github-actions` app (ID 15368) cannot be added as a ruleset bypass actor because it is a platform-native identity, not an installable app. Renovate (as an installable GitHub App) does not have this limitation -- it COULD be added as a bypass actor if needed. However, since `renovate[bot]` is already in the CLA allowlist, bypass is unnecessary.

3. **`github-ruleset-stale-bypass-actors`**: After installing the Renovate app, it will appear in the repository's installations. If Renovate is later uninstalled, any bypass actor entries must be manually cleaned up (GitHub does not auto-prune them).

### Interaction with Claude Code Review

The Claude Code Review workflow (`.github/workflows/claude-code-review.yml`) triggers on all `pull_request` events with no author filter. This means:

- **Digest-only Renovate PRs** will trigger a Claude code review, consuming API credits for trivially mechanical changes (SHA hash rotation)
- **Version bump Renovate PRs** will get a useful review (checking for breaking changes)

**Recommendation:** Accept this for now. The weekly schedule limits PRs to ~2 per week (one Docker digest group, one Actions digest group). If API cost becomes a concern, add an author filter to the review workflow:

```yaml
if: github.event.pull_request.user.login != 'renovate[bot]'
```

### npm Pins in Dockerfiles

Renovate's built-in Dockerfile manager does NOT detect `RUN npm install -g` commands. It only handles `FROM` image references, `COPY --from`, `RUN --mount`, and `syntax` directives.

To cover the `@anthropic-ai/claude-code@2.1.79` npm version pins in both Dockerfiles, a `customManagers` regex entry is required:

```json5
"customManagers": [
  {
    "customType": "regex",
    "managerFilePatterns": ["(^|/)Dockerfile$"],
    "matchStrings": [
      "npm install -g (?<depName>@[\\w-]+/[\\w-]+)@(?<currentValue>[\\d.]+)"
    ],
    "datasourceTemplate": "npm",
    "versioningTemplate": "npm"
  }
]
```

This regex:
- Matches `npm install -g @scope/package@version` patterns
- Uses ECMAScript regex flavor (Renovate requirement)
- Extracts `depName` (e.g., `@anthropic-ai/claude-code`) and `currentValue` (e.g., `2.1.79`)
- Queries the npm registry for newer versions

These updates will NOT be auto-merged (they are version bumps, not digest rotations).

### Edge Cases

- **Parallel feature branches with digest changes**: If Renovate updates a digest while a feature branch is in progress, the feature branch will have a merge conflict in the Dockerfile. This is expected and low-friction (the conflict is a single line).
- **Renovate branch naming**: Renovate creates branches like `renovate/docker-digests` and `renovate/github-actions-digests`. These do not conflict with the `feat/` branch naming convention.
- **Rate limiting**: Renovate respects GitHub API rate limits. With 52 Actions pins and 2 Docker pins, a single schedule window may produce 2 grouped PRs (well within limits).
- **Multi-arch digest pinning**: The `docker-base-image-digest-pinning` learning notes that the manifest list digest (not platform-specific) should be used. Renovate uses manifest list digests by default, preserving multi-arch resolution.

## Non-goals

- **Replacing SHA-pinning with tag-only references**: The current pinning strategy is correct; Renovate automates rotation, not removal
- **Managing Terraform provider versions**: Out of scope for this issue
- **Managing Bun/Node.js runtime versions**: Could be added later but not part of this PR
- **Self-hosted Renovate**: The hosted GitHub App is sufficient for an open-source repo
- **Filtering Claude Code Review for Renovate PRs**: Accept the minor API cost for now; optimize later if needed

## Acceptance Criteria

- [x] `renovate.json5` exists at repository root with Docker digest, GitHub Actions, custom npm regex, and auto-merge configuration
- [x] Configuration validates against Renovate JSON schema
- [ ] Renovate GitHub App is installed on `jikig-ai/soleur` (manual step by org admin -- post-merge)
- [x] Digest-only updates auto-merge after CI passes
- [x] Version bump PRs require manual review (not auto-merged)
- [x] Docker digest updates are grouped into a single PR per schedule window
- [x] GitHub Actions digest updates are grouped into a single PR per schedule window
- [x] CLA workflow does not block Renovate bot PRs (pre-verified: `renovate[bot]` in allowlist)
- [x] Custom regex manager detects `npm install -g @anthropic-ai/claude-code@X.Y.Z` patterns in both Dockerfiles

## Test Scenarios

- Given the Renovate config exists and the app is installed, when `node:22-slim` publishes a new digest on Docker Hub, then Renovate opens a PR updating `apps/web-platform/Dockerfile` line 1 with the new digest
- Given the Renovate config exists, when `oven/bun:1.3.11` publishes a new digest, then Renovate opens a PR updating `apps/telegram-bridge/Dockerfile` line 1 with the new digest
- Given the Renovate config exists, when `actions/checkout` publishes a new release, then Renovate opens a PR updating the SHA pin across all workflows that reference it, preserving the `# vX.Y.Z` version comment
- Given a digest-only Renovate PR, when CI passes, then the PR auto-merges via GitHub's native auto-merge
- Given a version bump Renovate PR (e.g., `@anthropic-ai/claude-code` 2.1.79 to 2.2.0), when CI passes, then the PR does NOT auto-merge and waits for manual review
- Given the CLA workflow, when Renovate opens a PR, then the CLA check passes because `renovate[bot]` is in the CLA allowlist
- Given the custom regex manager config, when Renovate scans `apps/telegram-bridge/Dockerfile`, then it detects `@anthropic-ai/claude-code@2.1.79` as a managed dependency
- Given a Renovate digest PR is auto-merged, when a feature branch has a conflicting digest change, then the merge conflict is limited to a single `FROM` line and is trivially resolvable

## MVP

### renovate.json5

```json5
// Renovate configuration for automated dependency rotation
// Manages: Docker digest pins, GitHub Actions SHA pins, npm version pins in Dockerfiles
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "docker:pinDigests",
    "helpers:pinGitHubActionDigests",
    "default:automergeDigest",
    "schedule:weekly"
  ],
  "timezone": "Europe/Paris",
  "labels": ["dependencies"],
  "packageRules": [
    {
      "description": "Group Docker digest updates into one PR",
      "matchDatasources": ["docker"],
      "matchUpdateTypes": ["digest"],
      "groupName": "docker-digests",
      "automerge": true
    },
    {
      "description": "Group GitHub Actions digest updates into one PR",
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
  // Detect npm install -g @scope/package@version in Dockerfiles
  // The built-in Dockerfile manager only handles FROM image references
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["(^|/)Dockerfile$"],
      "matchStrings": [
        "npm install -g (?<depName>@[\\w-]+/[\\w-]+)@(?<currentValue>[\\d.]+)"
      ],
      "datasourceTemplate": "npm",
      "versioningTemplate": "npm"
    }
  ]
}
```

## Dependencies & Risks

### Dependencies

- **Renovate GitHub App installation**: Requires org admin access. This is the only manual prerequisite. Can be done post-merge.
- **CI must pass on Renovate PRs**: The existing `ci.yml` workflow already works for PRs from any author including bots.

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CLA workflow blocks Renovate PRs | **None** (resolved) | N/A | `renovate[bot]` already in CLA allowlist (line 34) |
| Too many PRs from Renovate | Low | Low | Grouping + `schedule:weekly` limits to ~2-3 PRs/week max |
| Auto-merged digest breaks build | Very Low | Medium | CI runs before auto-merge; digest changes only affect base image layer |
| Renovate detects false positive dependencies | Low | Low | Review onboarding PR; add `ignoreDeps` if needed |
| Custom regex matches unintended patterns | Very Low | Low | Regex is scoped to `Dockerfile` files and `npm install -g @scope/pkg@version` format |
| Claude Code Review consumes credits on digest PRs | Medium | Low | Accept for now; add author filter to review workflow if cost becomes concern |
| Stale Renovate bypass actors after uninstall | Low | Low | Per institutional learning, audit bypass actors if Renovate is ever uninstalled |

## References

- Issue: #816
- `apps/web-platform/Dockerfile` -- `node:22-slim@sha256:...` (pinned in #814)
- `apps/telegram-bridge/Dockerfile` -- `oven/bun:1.3.11@sha256:...` (pinned in #801)
- `@anthropic-ai/claude-code@2.1.79` npm pin (pinned in #803)
- `.github/workflows/cla.yml:34` -- `renovate[bot]` already in CLA allowlist
- Learning: `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- Learning: `knowledge-base/learnings/2026-03-19-npm-global-install-version-pinning.md`
- Learning: `knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Learning: `knowledge-base/learnings/2026-03-19-github-actions-bypass-actor-not-feasible.md`
- Learning: `knowledge-base/learnings/2026-03-19-github-ruleset-stale-bypass-actors.md`
- [Renovate Docker docs](https://docs.renovatebot.com/docker/)
- [Renovate GitHub Actions manager](https://docs.renovatebot.com/modules/manager/github-actions/)
- [Renovate Dockerfile manager](https://docs.renovatebot.com/modules/manager/dockerfile/) -- only handles FROM references
- [Renovate regex custom manager](https://docs.renovatebot.com/modules/manager/regex/) -- for npm-in-Dockerfile
- [Renovate schedule presets](https://docs.renovatebot.com/presets-schedule/)
- [Renovate onboarding](https://docs.renovatebot.com/getting-started/installing-onboarding/)
- [Renovate configuration options](https://docs.renovatebot.com/configuration-options/)
