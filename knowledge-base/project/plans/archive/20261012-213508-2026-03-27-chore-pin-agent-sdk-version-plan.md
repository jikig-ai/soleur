---
title: "chore: pin Agent SDK to exact version (0.2.80)"
type: chore
date: 2026-03-27
---

# chore: pin Agent SDK to exact version (0.2.80)

The `apps/web-platform/package.json` uses `^0.2.80` (caret range) for `@anthropic-ai/claude-agent-sdk`. A minor SDK update could silently change `canUseTool` callback behavior or hook types, compromising the security sandbox that enforces workspace isolation. Pinning to the exact version ensures deterministic installs and deliberate upgrade reviews.

**Source:** CTO review, #1045
**Roadmap:** Phase 1, item 1.9

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 2 (Context, Implementation)
**Research sources:** 4 institutional learnings checked, 1 applied

### Key Findings from Learnings

- **Renovate is scoped to exclude npm** (`enabledManagers` does not include `npm`; see learning `2026-03-20-renovate-enabled-managers-scoping.md`). The exact pin will not be overridden by automated dependency PRs. Upgrades require a deliberate manual change.
- **Consistent with project supply-chain posture:** GitHub Actions use SHA pinning (`2026-02-27-github-actions-sha-pinning-workflow.md`), Docker images use digest pinning (`2026-03-19-docker-base-image-digest-pinning.md`), and npm global installs use version pinning (`2026-03-19-npm-global-install-version-pinning.md`). This change completes the pattern for project-level npm dependencies in the security-critical path.
- **No new edge cases discovered.** The change is mechanical (single character removal) with a well-understood lockfile regeneration step.

## Acceptance Criteria

- [x] `apps/web-platform/package.json` declares `"@anthropic-ai/claude-agent-sdk": "0.2.80"` (no caret)
- [x] `apps/web-platform/package-lock.json` updated to reflect the exact version pin
- [x] No other dependencies are changed

## Test Scenarios

- Given `apps/web-platform/package.json`, when inspecting the `@anthropic-ai/claude-agent-sdk` dependency, then the version string is `"0.2.80"` with no range prefix (`^`, `~`, `>=`)
- Given the updated `package-lock.json`, when running `npm ls @anthropic-ai/claude-agent-sdk`, then it resolves to exactly `0.2.80`
- Given the lockfile diff, when reviewing changes, then only `@anthropic-ai/claude-agent-sdk` version entries changed (no unrelated dependency updates)

## Implementation

### 1. Edit `apps/web-platform/package.json`

Change line 14:

```json
"@anthropic-ai/claude-agent-sdk": "^0.2.80",
```

to:

```json
"@anthropic-ai/claude-agent-sdk": "0.2.80",
```

### 2. Regenerate lockfile

**Note:** The issue mentions `bun install` but the app uses `package-lock.json` (npm lockfile v3). Run `npm install` from `apps/web-platform/` to regenerate the lockfile consistently:

```bash
cd apps/web-platform && npm install
```

This updates `package-lock.json` to reflect the exact version pin without introducing a conflicting `bun.lock`.

### 3. Verify

```bash
cd apps/web-platform && npm ls @anthropic-ai/claude-agent-sdk
```

Expected output: `soleur-web-platform@0.0.1 -- @anthropic-ai/claude-agent-sdk@0.2.80`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- The `canUseTool` callback is the security boundary for workspace isolation (see learning: `2026-03-16-agent-sdk-spike-validation.md`)
- The SDK was validated at v0.2.76 during the spike and upgraded to v0.2.80; the callback behavior is sensitive to SDK internals
- The lockfile discrepancy (issue says `bun install`, codebase uses `package-lock.json`) should be resolved by using `npm install` to match the existing lockfile format

### Supply-Chain Pinning Pattern

This pin is the fourth surface in the project's supply-chain hardening posture:

| Surface | Mechanism | Learning |
|---------|-----------|----------|
| GitHub Actions | SHA pinning (`@sha # vX.Y.Z`) | `2026-02-27-github-actions-sha-pinning-workflow.md` |
| Docker images | Digest pinning (`tag@sha256:...`) | `2026-03-19-docker-base-image-digest-pinning.md` |
| npm global installs | Version pinning (`@X.Y.Z`) | `2026-03-19-npm-global-install-version-pinning.md` |
| Agent SDK (this change) | Exact version (`"0.2.80"`) | `2026-03-16-agent-sdk-spike-validation.md` |

## References

- GitHub issue: #1045
- Related learning: `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md`
- Target file: `apps/web-platform/package.json:14`
- Lockfile: `apps/web-platform/package-lock.json`
