# Learning: Cron-based tmpfs guard for mid-session runaway output

## Problem

On 2026-03-28, a Claude Code subagent task produced a 16 GiB `.output` file (`bnjkmjai1.output`) in `/tmp/claude-1001/`. This filled the entire 16 GiB tmpfs mount (RAM-backed), crashing all Claude Code sessions and degrading bash on the machine.

The existing `cleanup_claude_tmp()` function in `worktree-manager.sh` (from the 2026-03-20 incident) only runs at **session boundaries** — session start and post-merge. It cannot catch a file that grows to 16 GiB **during an active session**, because by definition the session is still running and the function skips active sessions.

## Solution

Three-layer defense-in-depth:

### Layer 1: Cron job (`scripts/tmpfs-guard.sh`)

Runs every 5 minutes via user crontab. Removes `.output` files > 200 MB from `/tmp/claude-$(id -u)/`. Respects active file handles (`fuser`) at < 90% usage; at 90%+ usage, removes even active files to prevent system lockup. Sends `notify-send` critical alerts and logs via `logger`.

```bash
*/5 * * * * /home/jean/git-repositories/jikig-ai/soleur/scripts/tmpfs-guard.sh
```

### Layer 2: AGENTS.md hard rule

Added rule requiring all subagent commands with uncertain output size to pipe through `| head -n 500` or `| tail -n 200`. This prevents the problem at the source rather than cleaning up after.

### Layer 3: tmpfs resize (manual, needs sudo)

Reduce tmpfs from 16 GiB (50% of 32 GiB RAM, kernel default) to 4 GiB so a runaway file can't consume all system memory. Add to `/etc/fstab`:

```
tmpfs /tmp tmpfs defaults,nosuid,nodev,size=4G 0 0
```

Apply immediately: `sudo mount -o remount,size=4G /tmp`

## Session Errors

**markdownlint package name mismatch** — Used `npx markdownlint` instead of `npx markdownlint-cli2`. Self-corrected. Prevention: The correct command is documented in AGENTS.md and constitution.md.

## Key Insight

Session-boundary cleanup is necessary but not sufficient for tmpfs protection. A runaway subagent can fill tmpfs in minutes, but session-boundary cleanup only fires when sessions start or end. The cron job fills this timing gap by running independently of session lifecycle. The three layers form a defense chain: the AGENTS.md rule prevents the problem (weakest — requires agent compliance), the cron job catches it within 5 minutes (medium — system-level), and the tmpfs resize caps blast radius (strongest — kernel-enforced).

## Tags

category: runtime-errors
module: claude-code-infrastructure
