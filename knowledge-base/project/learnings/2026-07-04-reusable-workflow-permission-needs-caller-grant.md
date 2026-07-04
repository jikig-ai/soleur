# Learning: a permission added to a reusable workflow must be granted by every caller (startup_failure)

## Problem

PR #5977 (#5933 Item 4) added cosign keyless signing to `.github/workflows/reusable-release.yml` (an `on: workflow_call` reusable workflow), which needs `id-token: write` (OIDC → Fulcio). I added `id-token: write` to the reusable workflow's job `permissions:`. `actionlint` was clean and CI passed, so it merged.

On the first release after merge, `web-platform-release.yml` (the caller) failed with **`startup_failure`** — "This run likely failed because of a workflow file issue." No job logs, no build failure: the workflow never started. This broke the release/deploy pipeline for every future merge (a silent-outage class — prod would stay on the old version).

## Root cause

**A reusable workflow can only USE permissions its CALLER grants.** `web-platform-release.yml` declared workflow-level `permissions: contents: write, packages: write` — no `id-token: write`. The `release` job inherited those and called the reusable workflow, which requested `id-token: write`. GitHub rejects a reusable-workflow call that requests a permission the caller did not grant → `startup_failure` at dispatch time.

`actionlint` and CI validate each workflow file in isolation; neither checks the cross-file caller↔reusable permission contract. It is invisible until a real dispatch.

## Solution

Grant the scope at the caller, scoped to the **calling job** (least privilege), not workflow-wide (a workflow-level `id-token: write` would let every job mint an OIDC token):

```yaml
jobs:
  release:
    uses: ./.github/workflows/reusable-release.yml
    permissions:
      contents: write   # a job-level block REPLACES inherited perms,
      packages: write    # so re-declare what the reusable workflow needs
      id-token: write
    secrets: inherit
```

Fixed in PR #5981.

## Key Insight

Two compounding lessons:

1. **Cross-file workflow contracts (permissions, `secrets: inherit`, `with:` inputs) are not validated by `actionlint`/CI.** When you add a `permissions:` scope to a reusable workflow, `git grep -l 'uses:.*<reusable-basename>\.yml' .github/workflows/` and grant the scope at each caller (calling job, least privilege).
2. **Live validation catches what tests and CI structurally cannot.** In this same session, both the `startup_failure` AND a separate gap — the app image is *private*, so the cosign verifier container can't fetch the signature without ghcr auth (→ #6005) — were invisible to a green CI and a 103/103 bash test suite. Only `gh workflow run` (watch for `startup_failure`) + a real `cosign verify` against the freshly-signed image surfaced them. For release-pipeline / supply-chain / OIDC changes, **drive the real dispatch** — don't trust the green checkmark.

## Session Errors

1. **Unpushed worktree reaped mid-edit.** Creating the worktree for THIS learning without immediately running `draft-pr` left an unpushed branch that a concurrent `cleanup-merged` reaped between the file read and the edit (the race AGENTS.md `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` warns about). Recovery: recreate + `draft-pr` FIRST. Prevention: always `draft-pr` immediately after `worktree-manager.sh feature` before any file write.

## Tags
category: workflow-patterns
module: ship, github-actions
related: #5933, #5977, #5981, #6005, reusable-release.yml, web-platform-release.yml
