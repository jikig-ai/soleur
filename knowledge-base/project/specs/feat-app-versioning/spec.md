# Spec: Independent App Versioning and Releases

**Issue:** #739
**Date:** 2026-03-19
**Branch:** feat-app-versioning
**Brainstorm:** [2026-03-19-app-versioning-brainstorm.md](../../brainstorms/2026-03-19-app-versioning-brainstorm.md)

## Problem Statement

Only `plugins/soleur/` has versioning and release automation. The two deployable apps (`apps/web-platform/`, `apps/telegram-bridge/`) have no release tracking, no version-tagged Docker images, and no deployment automation on merge. Deployed containers are identified only by git short-SHA, making rollback and audit difficult.

## Goals

1. Each app gets independent semver versioning with its own tag namespace
2. Docker images are tagged with version, SHA, and latest
3. Merging to main automatically builds, deploys, and announces app releases
4. `/ship` detects which components changed and applies appropriate labels
5. Monorepo PRs that touch multiple components produce separate releases for each

## Non-Goals

- Changing the plugin's existing versioning or release workflow behavior
- Adding app version files to the repository (follows existing tag-only architecture)
- Implementing rollback automation (version tags enable it; automation is future work)
- Adding staging/preview environments

## Functional Requirements

- **FR1:** A reusable release workflow (`reusable-release.yml`) accepts component configuration as inputs and performs: path change detection, PR label extraction, semver bump computation, GitHub Release creation, Docker image build+push (optional), Discord notification. Deploy is handled by caller workflows (structurally different per app).
- **FR2:** Per-app caller workflows (`web-platform-release.yml`, `telegram-bridge-release.yml`) invoke the reusable workflow with app-specific configuration and handle deploy steps
- **FR3:** The existing plugin release workflow remains unchanged (refactoring deferred to follow-up PR)
- **FR4:** `/ship` skill detects changes in `apps/web-platform/**` and `apps/telegram-bridge/**`, applying `app:web-platform` and/or `app:telegram-bridge` labels alongside existing `semver:*` labels
- **FR5:** A single PR touching multiple components produces independent releases (up to 3)
- **FR6:** Docker images receive three tags: version (`:v0.1.0` — component prefix stripped from git tag), commit SHA, and `:latest`
- **FR7:** Each release posts a Discord notification via the releases webhook

## Technical Requirements

- **TR1:** Version is derived from git tags via `git fetch --tags` + `git tag --list '<prefix>*' --sort=-version:refname | head -1` (semver-aware sort, avoids `gh release list` creation-date ordering)
- **TR2:** All GitHub Actions are pinned to commit SHAs with version comments
- **TR3:** All values written to `$GITHUB_OUTPUT` are sanitized with `printf` + `tr -d '\n\r'`
- **TR4:** PR extraction uses `gh api commits/{sha}/pulls`, not commit message parsing
- **TR5:** Each component has its own concurrency group to avoid serializing unrelated releases
- **TR6:** Reusable workflow uses `secrets: inherit` for secret passthrough
- **TR7:** Deploy scripts use `{ ...; }` grouping for `|| true` fallbacks
- **TR8:** Idempotency: skip release creation if the computed tag already exists

## Tag Format

| Component | Tag prefix | Example | Docker image |
|-----------|-----------|---------|-------------|
| Plugin | `v` (unchanged) | `v3.22.0` | N/A |
| Web Platform | `web-v` | `web-v0.1.0` | `ghcr.io/jikig-ai/soleur-web-platform:v0.1.0` |
| Telegram Bridge | `telegram-v` | `telegram-v0.1.0` | `ghcr.io/jikig-ai/soleur-telegram-bridge:v0.1.0` |

## Label Strategy

| PR scope | Labels | Releases |
|----------|--------|----------|
| Plugin only | `semver:minor` | `v3.22.0` |
| Web only | `semver:patch`, `app:web-platform` | `web-v0.1.1` |
| Telegram only | `semver:minor`, `app:telegram-bridge` | `telegram-v0.2.0` |
| Plugin + web | `semver:minor`, `app:web-platform` | `v3.22.0` + `web-v0.1.1` |
| All three | `semver:minor`, `app:web-platform`, `app:telegram-bridge` | All three |

## Resolved Questions

1. **Semver ordering:** Use `git fetch --tags` + `git tag --sort=-version:refname` (semver-aware). Shallow clones with `fetch-depth: 2` miss older tags.
2. **Health check endpoints:** Web: `http://localhost:3000/health`. Telegram: `http://localhost:8080/health`. Both return `{"status": "ok"}`.
3. **Telegram CI build:** Deferred to separate issue (out of scope for #739).
4. **SSH secrets:** Web: `WEB_PLATFORM_HOST`, `WEB_PLATFORM_SSH_KEY` (exist). Telegram: `TELEGRAM_BRIDGE_HOST`, `TELEGRAM_BRIDGE_SSH_KEY` (create via `gh secret set`).
