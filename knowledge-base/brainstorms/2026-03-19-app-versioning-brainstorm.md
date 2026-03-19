# App Versioning and Releases Brainstorm

**Date:** 2026-03-19
**Issue:** #739
**Branch:** feat-app-versioning

## What We're Building

Independent versioning, release, build, and deployment pipelines for `apps/web-platform/` and `apps/telegram-bridge/`, following the tag-only versioning architecture already established for `plugins/soleur/`.

Currently, only plugin changes produce GitHub Releases (`vX.Y.Z` tags). App-only PRs merged to main produce no version bump, no release notes, no Discord notification, and no Docker image with a traceable version tag. Deployed containers are identified only by git short-SHA, making rollback and audit difficult.

## Why This Approach

### Reusable workflow + per-app callers (Approach B)

A shared `reusable-release.yml` encapsulates the bump/release/build/deploy/notify logic with parameterized inputs. Each deployable component gets a thin caller workflow (~20 lines) that passes its configuration. The existing plugin workflow is refactored into a caller too.

**Why not the alternatives:**

- **Approach A (matrix in existing workflow):** Keeps everything in one file but grows it to ~300 lines with conditional logic per component. Harder to reason about and test.
- **Approach C (JSON config-driven):** Maximum extensibility but adds indirection. Deploy steps differ per app (SSH targets, health checks), which is hard to express in a flat config file.

**Approach B wins** because each app can independently configure deploy targets, health checks, and build args while sharing the version bump, release creation, and Discord notification logic. Adding a future app means creating one ~20-line YAML file.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Version scheme | Semver (`web-vX.Y.Z`, `telegram-vX.Y.Z`) | Consistent with plugin pattern. Communicates breaking/feature/fix intent. |
| Workflow architecture | Reusable workflow + per-app callers | Clean separation, independently configurable, reusable for future apps |
| Label strategy | Shared `semver:*` labels + `app:web-platform` / `app:telegram-bridge` tags | Simpler label set. `/ship` applies semver:* (shared) + app:* (scoped). Release workflow uses both to determine what to bump. |
| Multi-component PRs | Separate releases per component | A single merge can produce up to 3 releases with independent version histories |
| Deploy scope | Full pipeline (version + build + deploy) | End-to-end automation: bump version → build Docker image with version tag → deploy to server |
| Starting version | `v0.1.0` for both apps | Signals pre-1.0 status. Apps are in production but API/behavior may change. |
| Version source of truth | Git tags via GitHub Releases API | Follows existing tag-only architecture (Learning: serialize-version-bumps-to-merge-time). No committed version files. |

## Architecture Sketch

```
PR merges to main
      │
      ▼
┌─────────────────────────────────┐
│ version-bump-and-release.yml    │  (existing, refactored to caller)
│ web-platform-release.yml        │  (new caller)
│ telegram-bridge-release.yml     │  (new caller)
└──────────┬──────────────────────┘
           │ each calls
           ▼
┌─────────────────────────────────┐
│ reusable-release.yml            │
│                                 │
│ Inputs:                         │
│   component: string             │
│   path_filter: string           │
│   tag_prefix: string            │
│   docker_image: string (opt)    │
│   deploy_host: string (opt)     │
│   deploy_script: string (opt)   │
│                                 │
│ Steps:                          │
│   1. Check if path changed      │
│   2. Find merged PR + labels    │
│   3. Determine bump type        │
│   4. Compute next version       │
│   5. Create GitHub Release      │
│   6. Build + push Docker image  │  (if docker_image provided)
│   7. Deploy to server           │  (if deploy_host provided)
│   8. Post to Discord            │
└─────────────────────────────────┘
```

### Tag format examples

| Component | Tag | Docker image |
|-----------|-----|-------------|
| Plugin | `v3.22.0` (unchanged) | N/A |
| Web Platform | `web-v0.1.0` | `ghcr.io/jikig-ai/soleur-web-platform:web-v0.1.0` |
| Telegram Bridge | `telegram-v0.1.0` | `ghcr.io/jikig-ai/soleur-telegram-bridge:telegram-v0.1.0` |

### Label behavior

| PR touches | Labels applied by `/ship` | Releases created |
|------------|--------------------------|------------------|
| Only `plugins/soleur/` | `semver:minor` | `v3.22.0` |
| Only `apps/web-platform/` | `semver:patch`, `app:web-platform` | `web-v0.1.1` |
| Only `apps/telegram-bridge/` | `semver:minor`, `app:telegram-bridge` | `telegram-v0.2.0` |
| Plugin + web | `semver:minor`, `app:web-platform` | `v3.22.0` + `web-v0.1.1` |
| All three | `semver:minor`, `app:web-platform`, `app:telegram-bridge` | `v3.22.0` + `web-v0.1.1` + `telegram-v0.2.0` |

### `/ship` changes

1. Extend diff analysis to check `apps/web-platform/**` and `apps/telegram-bridge/**`
2. Apply `app:web-platform` and/or `app:telegram-bridge` labels when those paths have changes
3. Keep existing `semver:*` label logic (analyze all changed component dirs for the highest bump level)
4. When no plugin files changed but app files changed, still apply `semver:*` (the release workflow uses the combination of `semver:*` + `app:*` to know what to bump)

### Docker image tagging

Each app's Docker image gets three tags per release:
- `:web-v0.1.0` (version — for rollback and audit)
- `:<short-sha>` (commit — for debugging)
- `:latest` (convenience — for fresh deploys)

## Learnings to Apply

- **Tag-only versioning:** No committed version files. `gh release view` with tag prefix filter to find latest version per component.
- **GITHUB_TOKEN releases don't cascade:** All steps (bump, release, build, deploy, notify) must happen in one workflow invocation.
- **Pin actions to commit SHAs:** Security hook will block first edit — plan for retry.
- **Sanitize `$GITHUB_OUTPUT`:** Use `printf` + `tr -d '\n\r'` for all untrusted values.
- **`gh api commits/{sha}/pulls`:** Use API for PR extraction, not commit message parsing.
- **Bash operator precedence:** Group `|| true` fallbacks with `{ ...; }` in deploy scripts.
- **Idempotency:** Check if release tag already exists before creating.

## Open Questions

1. **Reusable workflow secrets:** GitHub reusable workflows require `secrets: inherit` or explicit secret passthrough. Need to verify which secrets each app needs (DISCORD_RELEASES_WEBHOOK_URL, SSH keys, GHCR token).
2. **`gh release view` with prefix filtering:** The existing workflow uses `gh release view --json tagName` which returns the latest release. Per-app releases need `gh release list --exclude-drafts | grep "^web-v"` or similar to find the latest release for a specific component. Need to verify this works correctly with semver ordering.
3. **Health check after deploy:** Each app likely has a different health check endpoint. This should be a caller input.
4. **Telegram bridge CI gap:** Currently no CI workflow exists for telegram-bridge. Should the release workflow also build/test, or should a separate CI workflow be added first?
5. **Concurrency:** Each app release should have its own concurrency group to avoid serializing unrelated releases.

## Capability Gaps

None identified — all required infrastructure (GitHub Actions, GHCR, SSH deploy, Discord webhooks) is already in use.
