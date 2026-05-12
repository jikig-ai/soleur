# Learning: `pgrep -f <pattern>` matches its own zsh shell-snapshot subprocess

## Problem

When checking whether a dev server is still alive after `kill`, `pgrep -f "dev-server.mjs"` returned a PID, then `kill -9 <pid>` returned 0, then the next `pgrep -f "dev-server.mjs"` returned a *different* PID. Looked like the process was respawning. It wasn't — the dev server was actually dead.

## Root Cause

The Bash tool wraps every command in a zsh subshell that loads `~/.claude/shell-snapshots/snapshot-zsh-<id>-<hash>.sh` and then `eval`s the user's command. The `eval` argument contains the literal pattern string, so `pgrep -f` (matches against full argv) finds the zsh transcript subprocess itself:

```
/usr/bin/zsh -c source /home/harry/.claude/shell-snapshots/snapshot-zsh-... && eval 'pgrep -fa "dev-server.mjs" ...'
```

Each invocation gets a fresh subprocess with a new PID, so consecutive `pgrep` calls return different PIDs even when no real target exists. The PIDs you see are short-lived shell wrappers, not the service.

## Solution

For service-liveness checks, use a network probe:

```bash
curl -sf --max-time 2 http://localhost:3000/ >/dev/null 2>&1 && echo alive || echo dead
```

It tests the actual contract (port bound + responding) and cannot be fooled by pattern matches on transcript text.

When PID enumeration is genuinely required (e.g., to send a signal to a known background job started with `&`), capture the PID at spawn time with `echo "PID=$!"` and store it — do not rediscover it via `pgrep -f` after the fact.

## Key Insight

Inside the Bash tool, `pgrep -f <substring>` has a built-in false-positive class: any substring that appears in your own command's argv will match the wrapping zsh subshell. The trap shows up specifically when the substring is a token you typed (a filename, a service name, an option flag) — the same token the pattern is looking for.

## Tags
category: integration-issues
module: tooling
