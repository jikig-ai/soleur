---
title: GitHub Actions SHA Pinning Workflow
date: 2026-02-27
category: security
module: ci-cd
tags: [github-actions, supply-chain-security, sha-pinning]
next_review: 2026-08-27
---

# Learning: GitHub Actions SHA Pinning Workflow

## Problem

4 workflow files in this repo used mutable version tags (`@v4`, `@v2`, `@v1`) for GitHub Actions. Mutable tags are a supply-chain risk: an attacker who compromises an action publisher's account can force-push the tag to point at a malicious commit. Real-world precedent: the tj-actions/changed-files compromise (March 2025) affected 23,000+ repositories via exactly this vector.

The risk is not theoretical. During this session's audit, the `@v4` tag for `actions/checkout` had already silently moved from v4.2.2 (the SHA used in the 2 already-pinned workflows) to v4.3.1 since those pins were set — confirming that mutable tags drift without any notification.

## Solution

**Audit process:**

1. Grep all workflow files for `uses:` lines to find every action reference:
   ```
   grep -rn "uses:" .github/workflows/
   ```
2. Separate already-pinned (40-char SHA) from mutable-tag entries. Note the version comment on pinned ones to detect drift.
3. For each mutable action, resolve the current SHA via the GitHub API:
   ```
   gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object.sha'
   ```
   If the tag points to an annotated tag object (type `tag`), a second call dereferences to the commit:
   ```
   gh api repos/<owner>/<repo>/git/tags/<sha> --jq '.object.sha'
   ```
4. Replace every mutable reference with the pinned format:
   ```
   uses: actions/checkout@<40-char-sha> # vX.Y.Z
   ```
   The version comment is essential — it is the only human-readable indicator of what version is pinned.

**Consistency upgrade:** Any already-pinned workflow that references an older SHA for the same action should be updated to the current SHA so all workflows stay in sync. In this session, 2 workflows were upgraded from v4.2.2 to v4.3.1 for `actions/checkout`.

**Complete audit scope:** Check every `.github/workflows/*.yml` file, including those added in recent PRs. This session discovered a 4th unpinned workflow (`auto-release.yml`) during the audit that was not in the original issue scope.

**Actions pinned in this session:**

| Action | Tag | Pinned SHA | Version |
|---|---|---|---|
| `actions/checkout` | `@v4` | `11bd71901bbe5b1630ceea73d27597364c9af683` | v4.2.2 (upgraded to v4.3.1 in 2 files) |
| `actions/checkout` | `@v4` (v4.3.1) | `f43a0e5ff2bd294095638e18286ca9a3d1956744` | v4.3.1 |
| `actions/github-script` | `@v7` | `60a0d83039c74a4aee543508d2ffcb1c3799cdea` | v7.0.1 |
| `peter-evans/create-or-update-comment` | `@v4` | `71345be0265236311c031f5c7866d64462f08b4` | v4.0.0 |
| `softprops/action-gh-release` | `@v2` | `c062e08bd532815e2082a85e87e3ef29c3e6d191` | v2.2.1 |
| `dawidd6/action-download-artifact` | `@v6` | `bf251b5aa9c2f7eeb574a96ee720e24f801b7c28` | v6.0.0 |

## Key Insight

Pinning is not a one-time task — it requires periodic re-audit. Actions release new versions, and the pinned SHA becomes stale over time. The version comment (`# vX.Y.Z`) is the mechanism for detecting drift: if the live SHA for a tag no longer matches the comment's version, an update is needed. A cron-based Dependabot or manual quarterly audit should cover this.

The generalizable rule: every mutable reference in a trust boundary (workflow files, Dockerfiles, lock files) should be pinned to an immutable identifier with a human-readable comment tracking the version.

## Session Errors

**1. Security hook rejections (4 instances)**

The `security_reminder_hook.py` pre-tool hook blocked the first `Edit` call on each workflow file with a security warning, requiring a retry on each. This is expected behavior for workflow edits — the hook fires once per file to ensure the author acknowledges the security context. It is not a bug. Cost: 4 wasted tool calls (one per file).

How to avoid: on subsequent workflow-editing sessions, expect the first Edit on each `.github/workflows/*.yml` file to be blocked and plan for a retry. The hook does not block the second attempt.

**2. Ralph loop setup script path miss**

The one-shot loop setup was invoked with the wrong path:
- Tried: `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` (does not exist)
- Correct: `./plugins/soleur/scripts/setup-ralph-loop.sh`

The skill directory for `one-shot` does not contain a `scripts/` subdirectory — setup scripts live at the plugin root `scripts/` level. Check `ls ./plugins/soleur/scripts/` before invoking setup scripts rather than guessing the path from the skill name.

## Tags
category: security
module: ci-cd
