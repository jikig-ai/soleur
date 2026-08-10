---
name: git-worktree
description: "This skill should be used when managing Git worktrees for isolated parallel development. It handles creating, listing, switching, and cleaning up worktrees with a simple interactive interface."
---

# Git Worktree Manager

This skill provides a unified interface for managing Git worktrees across your development workflow. Whether you're reviewing PRs in isolation or working on features in parallel, this skill handles all the complexity.

## What This Skill Does

- **Create worktrees** from main branch with clear branch names
- **List worktrees** with current status
- **Switch between worktrees** for parallel work
- **Clean up completed worktrees** automatically
- **Interactive confirmations** at each step
- **Automatic .gitignore management** for worktree directory
- **Automatic .env file copying** from main repo to new worktrees
- **Write guard enforcement** via PreToolUse hook (`.claude/hooks/worktree-write-guard.sh`) -- blocks Write/Edit to main checkout when worktrees exist

## CRITICAL: Always Use the Manager Script

**NEVER call `git worktree add` directly.** Always use the `worktree-manager.sh` script.

The script handles critical setup that raw git commands don't:

1. Copies `.env`, `.env.local`, `.env.test`, etc. from main repo
2. Ensures `.worktrees` is in `.gitignore`
3. Creates consistent directory structure
4. Detects bare repos (`core.bare = true`) and derives `GIT_ROOT` via `--absolute-git-dir` instead of `--show-toplevel`
5. Sources the shared `plugins/soleur/scripts/resolve-git-root.sh` helper -- all scripts that need `GIT_ROOT` should source this helper instead of inlining their own detection logic

**After creating a worktree**, run `npm install` if the project has a `package.json` — worktrees do not share `node_modules/` with the main working tree, and build commands (`npx @11ty/eleventy`, etc.) will silently hang instead of erroring.

```bash
# ✅ CORRECT - Always use the script
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh create feature-name

# ❌ WRONG - Never do this directly
git worktree add .worktrees/feature-name -b feature-name main
```

## When to Use This Skill

Use this skill in these scenarios:

1. **Code Review (`soleur:review`)**: If NOT already on the target branch (PR branch or requested branch), offer worktree for isolated review
2. **Feature Work (`soleur:work`)**: Always ask if user wants parallel worktree or live branch work
3. **Parallel Development**: When working on multiple features simultaneously
4. **Cleanup**: After completing work in a worktree

## How to Use

### In Claude Code Workflows

The skill is automatically called from the `soleur:review` and `soleur:work` skills:

```
# For review: offers worktree if not on PR branch
# For work: always asks - new branch or worktree?
```

### Manual Usage

You can also invoke the skill directly from bash:

```bash
# Create a new worktree (copies .env files automatically)
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# List all worktrees
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh list

# Switch to a worktree
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Copy .env files to an existing worktree (if they weren't copied)
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh copy-env feature-login

# Clean up completed worktrees
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

## Commands

### `create <branch-name> [from-branch]`

Creates a new worktree with the given branch name.

**Options:**

- `branch-name` (required): The name for the new branch and worktree
- `from-branch` (optional): Base branch to create from (defaults to `main`)

**Example:**

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh create feature-login
```

**What happens:**

1. Checks if worktree already exists
2. Fetches `refs/remotes/origin/<from-branch>` (the local `<from-branch>` ref is NOT touched — this lets `create` succeed even when a sibling worktree has `<from-branch>` checked out; see #3741)
3. Creates the new worktree from `origin/<from-branch>` with `--no-track` (preserves the pre-fix upstream-unset state so downstream `git push -u origin <branch>` flows are unchanged)
4. **Copies all .env files from main repo** (.env, .env.local, .env.test, etc.)
5. Shows path for cd-ing to the worktree

**Opt-in: also update local `<from-branch>`**

Pass `--update-local-main` (as a global flag, before `create`) to additionally fast-forward the local `<from-branch>` ref. Default behavior leaves the local ref untouched.

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh --update-local-main create feature-login
```

### `list` or `ls`

Lists all available worktrees with their branches and current status.

**Example:**

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh list
```

**Output shows:**

- Worktree name
- Branch name
- Which is current (marked with ✓)
- Main repo status

### `switch <name>` or `go <name>`

Switches to an existing worktree and cd's into it.

**Example:**

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh switch feature-login
```

**Optional:**

- If name not provided, lists available worktrees and prompts for selection

### `cleanup` or `clean`

Interactively cleans up inactive worktrees with confirmation.

**Example:**

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

**What happens:**

1. Lists all inactive worktrees
2. Asks for confirmation
3. Removes selected worktrees
4. Cleans up empty directories

### `sync-bare-files` or `sync`

Syncs stale on-disk files from git HEAD in a bare repo. Only needed when the repo uses `core.bare=true` — on-disk files at the bare root become stale after merges since git never updates them. Auto-called after `cleanup-merged` cleans branches in bare repo context.

**Example:**

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh sync-bare-files
```

**What it syncs:**

- `AGENTS.md`, `CLAUDE.md` (session-start instructions)
- `plugins/soleur/AGENTS.md`, `plugins/soleur/CLAUDE.md`
- `plugins/soleur/hooks/*` (plugin hooks: stop-hook, welcome-hook, hooks.json)
- `.claude/settings.json` (permission rules)
- `.claude/hooks/*.sh` (PreToolUse hooks)
- `plugins/soleur/scripts/resolve-git-root.sh`
- The `worktree-manager.sh` script itself

**Important:** Any file that Claude Code executes at runtime from the bare repo root (via `${CLAUDE_PLUGIN_ROOT}` or direct path) must be added to the sync list in `worktree-manager.sh`. Stale on-disk files cause silent regressions.

## Workflow Examples

### Code Review with Worktree

```bash
# Claude Code recognizes you're not on the PR branch
# Offers: "Use worktree for isolated review? (y/n)"

# You respond: yes
# Script runs (copies .env files automatically):
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh create pr-123-feature-name

# You're now in isolated worktree for review with all env vars
cd .worktrees/pr-123-feature-name

# After review, return to main:
cd ../..
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

### Parallel Feature Development

```bash
# For first feature (copies .env files):
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# Later, start second feature (also copies .env files):
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh create feature-notifications

# List what you have:
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh list

# Switch between them as needed:
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Return to main and cleanup when done:
cd .
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

## Key Design Principles

### KISS (Keep It Simple, Stupid)

- **One manager script** handles all worktree operations
- **Simple commands** with sensible defaults
- **Interactive prompts** prevent accidental operations
- **Clear naming** using branch names directly

### Opinionated Defaults

- Worktrees always created from **main** (unless specified)
- Worktrees stored in **.worktrees/** directory
- Branch name becomes worktree name
- **.gitignore** automatically managed

### Safety First

- **Confirms before creating** worktrees
- **Confirms before cleanup** to prevent accidental removal
- **Won't remove current worktree**
- **Clear error messages** for issues

## Integration with Workflows

### `soleur:review`

Instead of always creating a worktree:

```
1. Check current branch
2. If ALREADY on target branch (PR branch or requested branch) → stay there, no worktree needed
3. If DIFFERENT branch than the review target → offer worktree:
   "Use worktree for isolated review? (y/n)"
   - yes → call git-worktree skill
   - no → proceed with PR diff on current branch
```

### `soleur:work`

Always offer choice:

```
1. Ask: "How do you want to work?
   1. New branch on current worktree (live work)
   2. Worktree (parallel work)"

2. If choice 1 → create new branch normally
3. If choice 2 → call git-worktree skill to create from main
```

## Troubleshooting

### "Worktree already exists"

If you see this, the script will ask if you want to switch to it instead.

### "Cannot remove worktree: it is the current worktree"

Switch out of the worktree first (to main repo), then cleanup:

Navigate to the repository root directory, then run:

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

### Lost in a worktree?

See where you are:

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh list
```

### .env files missing in worktree?

If a worktree was created without .env files (e.g., via raw `git worktree add`), copy them:

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh copy-env feature-name
```

Navigate back to the repository root directory.

## Sharp Edges

- If `worktree-manager.sh` reports success but `cd` to the worktree path fails or `git branch --show-current` returns an unexpected branch, the worktree was not properly created. Fall back to `git worktree add` directly: `git worktree add .worktrees/<name> -b <name> main`. The script includes post-creation verification (#1806) but edge cases on bare repos may still produce partial directories. Tracked in #1854.
- The `draft-pr` subcommand uses `SCRIPT_DIR` for path resolution -- invoke it from inside the worktree, not from the bare repo root.
- **`fatal: this operation must be run in a work tree` in an intact worktree means `extensions.worktreeConfig` is set on the SHARED bare-repo config while `config.worktree` files are empty — it takes every worktree down at once, not just yours.** Enabling that extension makes git read `.git/worktrees/<name>/config.worktree` per worktree; when those are 0 bytes, nothing overrides `core.bare = true` from the common config, so `git rev-parse --is-inside-work-tree` returns `false` everywhere despite valid `.git`/`gitdir`/`commondir` pointers. Repair BOTH halves: `git config -f <bare>/.git/config --unset-all extensions.worktreeConfig`, **and** write `[core]\n\tbare = false` into each `config.worktree` — the second is what leaves the fleet immune to a re-add, and is what git itself writes when provisioning a bare repo's worktrees. Verify with a loop over `git worktree list` before continuing. **Why:** 2026-08-09 (#7332) — all 14 worktrees wedged mid-rebase; the key is already classed as harmful by #4826, but that heal (`apps/web-platform/server/worktree-config-seed.ts`) is scoped to Concierge workspace provisioning and never runs against an operator's local bare repo. See `knowledge-base/project/learnings/2026-08-09-one-shared-config-key-took-all-fourteen-worktrees-down-mid-rebase.md`.
- When creating worktrees manually (not via the script), always use absolute paths. Relative paths resolve from CWD, not from `GIT_DIR`, creating nested worktrees that are difficult to clean up. The script handles this correctly but manual `git worktree add` commands are susceptible.
- **A manually-added worktree holds NO LEASE and is reapable by any sibling's `cleanup-merged` — and RECOVERING an existing branch is exactly the case that forces you into the manual path.** `worktree-manager.sh create` runs `git worktree add -b "$branch"`, which fails when the branch already exists, so recovering a branch whose worktree was removed (or whose PR is mid-flight) cannot go through the script — and the lease wiring lives only in the script's `create`. After any manual `git worktree add`, acquire the lease explicitly: `source .claude/hooks/lib/session-state.sh && acquire_lease "<branch>" "<skill>" <minutes>`. Note the default grant is 240 minutes: a long review-and-fix pass outlives it, so re-acquire rather than assuming the initial grant still covers you. Recovery when it is reaped: the commit objects survive unreferenced, so `git branch <name> <sha>` pins them before gc can prune, then re-push. Tell for the whole class — a test run whose failures read `fatal: Unable to read current working directory` or `getcwd: cannot access parent directories` is reporting its own environment being deleted, not defects. **Why:** 2026-08-10 (#7278) — reaped twice in one session, once on lease expiry and once with no lease at all; 2 of 3 full-suite "failures" were the deletion landing mid-run.
- When lefthook hangs in a worktree (>60s), kill it (`pkill -f "lefthook run"`), verify checks manually, then commit with `LEFTHOOK=0 git commit`. This is a known lefthook/worktree interaction bug. (ex-`cq-when-lefthook-hangs-in-a-worktree-60s`; also guarded by `.claude/hooks/lib/incidents.sh` detect_bypass)
- **`pkill -f <shared-script-name>` is NEVER correctly scoped in this repo — it kills the identical process in every sibling worktree.** Parallel worktrees are the documented workflow, so the same [scripts/test-all.sh](../../../../scripts/test-all.sh) (or lefthook, or any shared script) runs under a byte-identical command line in each one; a `-f` pattern match cannot distinguish yours. Kill by **PID** from the process listing, or resolve `readlink /proc/<pid>/cwd` and match the worktree before killing anything. The same `/proc` resolution is the only sound liveness test — a bare `pgrep -f "<script>"` matches its OWN command line, so it always finds ≥1 process and can never report "not running". **The read-only direction of that self-match is the more dangerous one and recurred on #7109: a polling loop whose condition was `! ps -ef | grep "<script>" | grep -v grep` reported `FINISHED` while a 40-minute suite was still 3,000 lines from its terminal marker** — `grep -v grep` does not filter the poller's own `/bin/bash -c` wrapper (it is not `grep`), so the check oscillates between matching itself and matching nothing, and "nothing" reads as done. Resolve liveness by **PID** (`[[ -d /proc/$PID ]]`) plus `readlink /proc/$PID/cwd` to confirm the process is yours, and confirm completion from the runner's own terminal marker (`=== N/M suites passed ===`) — a killed run and a finished run are indistinguishable from the process table. **Why:** #7086 — `pkill -f "bash scripts/test-all.sh"` terminated a parallel session's suite 4,274 lines in (its infra/terraform results had already landed and survived; only the `test-all` rc was lost), and a `pgrep` self-match was twice read as "my run is alive" while the run had been dead for hours. **The cwd filter above is necessary and NOT sufficient, and #5454 paid for the difference:** a scan that resolved `/proc/<pid>/cwd` and killed only pids whose cwd was the current worktree still killed the SCANNING shell (exit 144) — the scanner's own cwd *is* that worktree and its command line matches its own predicate, so filtering by worktree selects it too. Neither `grep -v grep` nor a `[t]est` bracket trick excludes it, because the matching process is the `/bin/bash -c` wrapper, not `grep`. Compute self + ancestry first and skip those pids explicitly: `p=$$; while [ -n "$p" ] && [ "$p" != 1 ]; do ANC="$ANC $p"; p=$(awk '{print $4}' /proc/$p/stat 2>/dev/null); done`, then `case " $ANC " in *" $pid "*) continue ;; esac` inside the kill loop. That form killed both target processes and spared every sibling.
- Never pass `-c user.email=<fake>` / `-c user.name=<fake>` to `git commit` to bypass author-identity errors — fix the worktree's local git config instead (`worktree-manager.sh create` auto-runs `ensure_worktree_identity`). (ex-`hr-never-fake-git-author`; PR #2815 forced a destructive force-push after 4 commits were authored as `test@test` and blocked CLA; `knowledge-base/project/learnings/2026-04-24-fake-git-author-bare-repo-bot-override.md`)
- After `git worktree add` on bare repos, verify both `rev-parse --show-toplevel` (directory validity) and `git worktree list --porcelain` (registration). See learning: `knowledge-base/project/learnings/2026-04-10-worktree-registration-verification-insufficient.md`.
- In bare repos with multiple worktrees, `git fetch origin branch:branch` fails when the target branch is checked out in any worktree -- git rejects the refspec update. The fallback `git fetch origin branch` only updates `origin/branch`, NOT the local ref. Use `git update-ref refs/heads/branch origin/branch` to force-sync when the fetch refspec is rejected. As of #3741 (2026-05-14), `worktree-manager.sh create` bypasses this failure mode by default — new worktrees are based on `refs/remotes/origin/<from>` directly. The refspec-fetch path only runs when `--update-local-main` is passed.
- After creating a worktree via the script, always verify it exists in `git worktree list` before attempting to `cd` into it -- the script may report success for names that silently fail (e.g., excessively long names). A 2026-04-18 recurrence under a normal short name (#2611) confirms the silent-failure mode is not limited to edge-case names; see `knowledge-base/project/learnings/2026-04-18-worktree-manager-silent-registration-failure.md`.
- In bare repos, `git branch --show-current` from the bare root returns `main` (or empty), not the worktree's branch. Always ensure CWD is inside the target worktree before running branch-detecting git commands.
- **Never re-add a raw `git config` write to the shared config in `worktree-manager.sh`** — every shared-config mutation must route through `atomic_git_config`, which resolves the common-dir config via `rev-parse --path-format=absolute --git-common-dir` and survives a masked `config.lock` (ADR-081). A raw `git config --local`/`--file` write EEXISTs on the sandbox's char-device lock and wedges creation (RC=255).
- **A bare-vs-non-bare guard must detect layout via a pure filesystem fact, not mask-degradable `git rev-parse` (#5934).** Under the sandbox's char-device config mask, `git rev-parse --show-toplevel` returns empty (`GIT_ROOT=""`) and `--is-bare-repository` degrades to `true` because both must read the masked `.git/config` — so a genuinely NON-bare clone gets wrongly routed into bare-repo config surgery and wedges on the doomed `mv … .git/config` (EBUSY). Detect non-bare via `git_dir` being a `.git` **directory** (with a `$PWD/.git` fallback when `GIT_ROOT` resolves empty), which never reads the masked config; skip the surgery on non-bare and fail LOUD only on genuinely-bare-under-mask. Pin bare-vs-non-bare + the exact masked node via live probes (`--is-bare-repository`, `stat .git`, `stat .git/config*`) BEFORE scoping any fix. See `knowledge-base/project/learnings/2026-07-07-telemetry-blind-giveup-and-mask-degraded-nonbare-guard.md`.
- **An orphan directory the reaper could not remove is a PARTIALLY-deleted hollow shell, and it will recur every run until the residue is cleared (#7102).** `rm -rf` deletes everything it can reach before failing, so a surviving orphan is not the intact worktree it looks like — treat it as debris, never as recoverable work. The usual cause is root-owned residue: the local Supabase stack runs as root in a container and creates `apps/web-platform/supabase/snippets` via a bind-mount, leaving `root:root 755` directories inside an otherwise user-owned worktree that an unprivileged `rm` cannot unlink. Any worktree that ever started that stack leaves this behind, so the class is not specific to one branch. `cleanup_orphan_worktree_dirs` now reports it honestly instead of counting it as cleaned. It emits ONE aggregate sentinel on **stdout** (the stream agents grep) per invocation — note the field set, because greppping for a `dir=` key that does not exist is exactly the failure this whole change is about:

```text
SOLEUR_ORPHAN_UNREMOVABLE count=<n> cleaned=<n> errno=<LABEL> names=<basename,basename> reason=rm-partial hint="…"
```

`count=` is how many could not be removed, `cleaned=` how many actually were (carried here so the success counter is readable at the default `verbose=false`, where the success summary is suppressed), and `names=` is sanitized basenames only. A human-readable failure summary naming each full path goes to stderr and prints even at `verbose=false`. A separate `SOLEUR_ORPHAN_REGISTRY_UNAVAILABLE` fires when `git worktree list` fails — the reaper then refuses to reap anything rather than treat an empty registry as "everything is an orphan". To clear it, stop the local Supabase stack (`supabase stop`) so the bind-mount is released, then re-run `cleanup-merged`. **Do not reach for a containerized `rm -rf` as a privileged workaround.** `guardrails:block-rm-rf-worktrees` still matches most docker-wrapped forms (the `.worktrees/` path survives in the command line), but it is defeated by a **remapped mount** — `docker run -v <abs>/.worktrees/foo:/target alpine rm -rf /target` never names `.worktrees/` after the `rm -rf`, so it is allowed. Measured; matcher gap tracked in #7113 (which also covers `rm -rf -- <path>`, where the `--` separator defeats the same matcher). A safely-designed privileged fallback is tracked in #7112; the producer-side fix that would stop the residue being created at all is #7114.
- **Identity authority is inverted between environments (ADR-099, #6184).** On the non-bare Concierge agent workspace the LOCAL identity is the host-seeded workspace **owner** (authoritative); on the bare CLI dev repo the operator's **global** is the human, and the bare root frequently carries an inherited `github-actions[bot]` LOCAL that worktrees inherit (the #2815 CLA-reject bug). `ensure_worktree_identity` discriminates on **bot-shape** (`_identity_is_bot`: a `[bot]` marker in name/email), NOT on presence: it respects a present NON-bot local, overrides a bot-shaped local from a human `--global`, and REFUSES to ever write a bot-shaped `--global` (`reason=bot-global-refused`) so it can never misattribute a commit. Do NOT re-introduce a blanket "force global over local" (wrong on Concierge) OR a blanket "respect any present local" (wrong on the bare-dev bot-local) — neither is correct alone.

## Technical Details

### Directory Structure

```
.worktrees/
├── feature-login/          # Worktree 1
│   ├── .git
│   ├── app/
│   └── ...
├── feature-notifications/  # Worktree 2
│   ├── .git
│   ├── app/
│   └── ...
└── ...

.gitignore (updated to include .worktrees)
```

### How It Works

- Uses `git worktree add` for isolated environments
- Each worktree has its own branch
- Changes in one worktree don't affect others
- Share git history with main repo
- Can push from any worktree

### Performance

- Worktrees are lightweight (just file system links)
- No repository duplication
- Shared git objects for efficiency
- Much faster than cloning or stashing/switching
