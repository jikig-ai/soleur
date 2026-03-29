# Feature: Project Repo Connection

## Problem Statement

The cloud platform workspace is an empty shell -- `provisionWorkspace()` runs `git init` on an empty directory, scaffolds empty `knowledge-base/` subdirectories, and symlinks the Soleur plugin. Agents operate in a vacuum with no codebase context, no institutional memory, and limited domain leader effectiveness. Every other Phase 1 feature (multi-turn conversations, tag-and-route) delivers marginal value without a real codebase underneath.

## Goals

- Founders connect their GitHub repository during onboarding (after API key setup, before dashboard)
- Founders without a repo get one auto-created via the GitHub App with scaffolded `knowledge-base/` structure
- Agent sessions run against the real codebase with full read/write access
- Soleur plugin is installed (symlinked) and all agents + skills are available
- Bidirectional sync: pull on session start, push on session end
- Git credentials never exposed to the agent sandbox

## Non-Goals

- GitLab or Bitbucket support (GitHub only for P1)
- Continuous webhook-based sync (boundary-based sync only)
- Conflict resolution UI (fail-safe approach for P1: skip pull on conflict, warn founder)
- Private repo OAuth flow beyond GitHub App installation tokens
- PR-based workflow for agent changes (direct commit for P1)
- Deep clone with full git history (`--depth 1` only)
- Per-user disk quotas (monitoring only for P1)

## Functional Requirements

### FR1: GitHub App Registration

Register a Soleur GitHub App on GitHub with the following permissions:

- `contents:read+write` (clone, push)
- `metadata:read` (list repos)
- Repository creation scope (for auto-create flow)

The App's OAuth callback URL points to the web platform. The App generates short-lived installation tokens (1hr expiry) for git operations.

### FR2: Onboarding Repo Connection Page

A new page in the onboarding flow between API key setup and dashboard. The page:

- Offers "Connect existing repo" (GitHub OAuth consent to install the App)
- Offers "Create new repo" (auto-creates a GitHub repo with KB scaffold)
- Offers "Skip for now" (proceeds with empty workspace, connect later from settings)
- Shows repo selection after App installation (list founder's repos)

### FR3: Workspace Provisioning with Clone

`provisionWorkspace()` is extended to accept a `repoUrl` parameter:

- If `repoUrl` provided: `git clone --depth 1 <url>` into workspace, then overlay plugin symlink and `.claude/settings.json`
- If no `repoUrl`: current empty-workspace behavior (backwards compatible)
- Clone runs outside the agent sandbox (server-side, in `provisionWorkspace`)
- Async provisioning with status polling (clone may take 30+ seconds for large repos)

### FR4: Plugin Overlay After Clone

After cloning, the Soleur plugin is symlinked into the workspace:

- Create `<workspace>/plugins/soleur` -> `/app/shared/plugins/soleur`
- If the cloned repo already has a `plugins/` directory, create the symlink alongside existing content
- If the repo already has `plugins/soleur/`, the platform symlink takes precedence (platform-managed version)
- Scaffold `knowledge-base/` directories if they don't exist in the cloned repo
- Write `.claude/settings.json` with empty permissions (sandbox enforcement)

### FR5: Auto-Create Repo

When the founder chooses "Create new repo":

- Use the GitHub App installation token to create a new repository via GitHub API
- Repository name derived from founder input or defaulted
- Initialize with `knowledge-base/` directory structure, `CLAUDE.md`, and initial commit
- Clone the newly created repo into the workspace (same as FR3)

### FR6: Session Sync

Before each agent session starts:

- Server generates a fresh GitHub App installation token (1hr expiry)
- Server runs `git pull --rebase` in the workspace using the token via git credential helper
- If pull fails (conflicts, network), skip pull and log a warning -- session proceeds on stale state

After each agent session ends:

- Server runs `git push` using a fresh installation token
- If push fails (conflicts, force-push needed), log a warning and retain local commits -- next session will retry

### FR7: Credential Isolation

Git credentials (installation tokens) are never exposed to the agent process:

- Tokens are injected via a server-side git credential helper that the agent cannot read
- The `buildAgentEnv()` allowlist is NOT modified -- no git tokens in agent env
- Git push/pull operations happen server-side, not agent-initiated
- The bash sandbox regex layer provides defense-in-depth against credential probing

### FR8: Database Schema

New migration (`011_repo_connection.sql`) adds to the `users` table:

- `repo_url text` -- connected repository URL (nullable)
- `repo_provider text default 'github'` -- git provider
- `github_installation_id bigint` -- GitHub App installation ID (nullable)
- `repo_status text default 'not_connected' check (repo_status in ('not_connected', 'cloning', 'ready', 'error'))` -- connection status
- `repo_last_synced_at timestamptz` -- last successful sync timestamp

## Technical Requirements

### TR1: Security -- Sandbox Integrity

The three-tier sandbox model (bubblewrap + canUseTool + disallowedTools) must remain intact. Cloning a real repo introduces symlink escape vectors (CWE-59) and path traversal risks (CWE-22) -- the existing `isPathInWorkspace()` using `fs.realpathSync()` handles this. No changes to the sandbox for P1.

### TR2: Security -- Credential Helper Architecture

A git credential helper script runs outside the sandbox. It reads the installation token from a server-managed location (e.g., `/tmp/git-cred-<session-id>`) that is not within the workspace path and is not readable by the bubblewrap sandbox. The helper is configured via `GIT_CONFIG_GLOBAL` or workspace-level `.gitconfig`.

### TR3: Disk Management

Shallow clone (`--depth 1`) minimizes disk usage. The 20GB Hetzner volume is shared across all users. Add monitoring for disk usage (alert at 80% capacity). Volume expansion via Terraform variable if needed.

### TR4: Async Provisioning

Clone operations may take 30+ seconds. The workspace API route must support async provisioning:

- `POST /api/workspace` returns immediately with `status: 'cloning'`
- Client polls `GET /api/workspace` until `status: 'ready'`
- Loading UI shows progress messaging ("Setting up your AI organization...")

### TR5: Git Identity

Per-workspace git config sets the founder's name and email for commits:

- `git config user.name "<founder name>"` (from user profile)
- `git config user.email "<founder email>"` (from auth)
- Overrides the container-level global config ("Soleur")

### TR6: Migration Safety

The `011_repo_connection.sql` migration must be idempotent and safe on both empty and populated databases. All new columns are nullable or have defaults. No data loss for existing users.
