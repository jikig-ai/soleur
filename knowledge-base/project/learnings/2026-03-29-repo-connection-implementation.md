---
title: Repository connection feature -- GitHub App auth, sandboxed clone, best-effort sync
date: 2026-03-29
category: integration-issues
tags: [github-app, credential-helper, session-sync, state-machine, subagent-delegation]
---

# Learning: Repository Connection Feature Implementation

## Problem

Implementing a full-stack GitHub repository connection flow for the Soleur web platform onboarding. The feature needed to handle GitHub App installation, repository selection or creation, workspace provisioning with a cloned repo, and ongoing session sync -- all within a sandboxed server environment where persistent Git credentials are not available.

## Solution

The architecture chains four layers:

1. **GitHub App JWT auth** -- RS256 JWT signed with Node `crypto` (no external JWT library). The App JWT is exchanged for a short-lived installation token scoped to the specific repos the user granted access to.
2. **Installation token exchange** -- API routes under `app/api/repo/` handle the GitHub App callback, list accessible repos, create new repos, and trigger workspace setup. The `github_installation_id` stored on the user row enables token refresh on every sync cycle.
3. **Shallow clone with credential helper** -- `provisionWorkspaceWithRepo()` writes a temp credential helper script to `/tmp` (outside the sandbox), runs `git clone --depth 1` with `GIT_ASKPASS` pointing to that script, overlays Soleur plugin files and KB scaffold, then cleans the helper in a `finally` block.
4. **Best-effort session sync** -- `syncPull` (rebase from origin) and `syncPush` (auto-commit dirty state, push) run at session start/end, gated on `repo_status === 'ready'`. Failures are logged but never block the agent session. Rebase conflicts trigger `git rebase --abort` and continue.

The frontend uses a 9-state state machine (`choose`, `create_project`, `github_redirect`, `select_project`, `no_projects`, `setting_up`, `ready`, `failed`, `interrupted`) to handle all onboarding flows including error recovery and interrupted installations.

Database changes add columns to the existing `users` table rather than a separate junction table, since the MVP is one repo per workspace.

## Key Insight

Building GitHub integrations in sandboxed environments requires treating credentials as ephemeral, scoped, and file-system-bound. The credential helper pattern (write a temp script that outputs the token, point `GIT_ASKPASS` at it, clean up in `finally`) avoids storing tokens in `.gitconfig` or environment variables that persist beyond the operation. Combined with GitHub App installation tokens (which expire in 1 hour and scope to specific repos), this creates a security model where no long-lived credential touches disk and every operation is scoped to exactly the repos the user authorized.

The corollary for sync is that "best-effort, never-blocking" is the correct default. A failed sync is recoverable (retry next session); a blocked session is not (the user is waiting). This informed every error-handling decision in `session-sync.ts`.

## Session Errors

### Glob tool path resolution in worktrees

**Error:** Glob tool returned no results for files in `.worktrees/feat-repo-connection/` even though the files existed on disk.
**Recovery:** Used direct `ls` commands via Bash tool instead of Glob.
**Prevention:** When using Glob in worktrees, verify results with a direct `ls` if the result set is empty. The Glob tool may have issues resolving paths through the `.worktrees/` symlinked or indirect directory structure. Always have a fallback search strategy.

### Subagent side effects creating lockfiles

**Error:** A backend subagent ran a package manager command that created `bun.lock` as a side effect, which would have been committed as an unintended change.
**Recovery:** Manually deleted the file before staging and committing.
**Prevention:** When delegating implementation to subagents, explicitly instruct them to avoid running `bun install`, `npm install`, or any package manager command that mutates lockfiles. Use `--dry-run` flags or inspect `package.json` directly to check dependency presence. If a subagent must install, require it to clean up generated lockfiles.

### Copy deviations when delegating UI work to subagents

**Error:** The frontend subagent received a summary of the CMO-approved copy document rather than the verbatim text. The result had drifted copy: card descriptions were paraphrased, the setup step count changed from 5 to 4, and trust signals were reworded. All deviations required manual correction in the main context.
**Recovery:** Compared rendered output against the copy document line by line and corrected each deviation.
**Prevention:** When delegating UI implementation to subagents, include the full verbatim copy document content in the agent prompt -- not a summary or description of what the copy says. Copy documents are authoritative artifacts produced by specialist agents (copywriter, CMO). Paraphrasing introduces semantic drift that compounds across multiple sections. The subagent prompt should explicitly state: "Use the following copy exactly as written. Do not paraphrase, reword, or adjust any text."

## Tags

category: integration-issues
module: web-platform
symptoms: github app auth, credential helper, session sync, state machine, subagent copy drift
