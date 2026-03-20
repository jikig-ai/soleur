# Learning: Claude Code tmpfs task output can exhaust system RAM

## Problem
A stale Claude Code session left a 16 GB task output file in `/tmp/claude-<uid>/`. Because `/tmp` is typically a tmpfs (RAM-backed filesystem), this single file consumed over half of a 30 GB system's memory, leaving only 4.4 GB free. The user perceived the system as "almost out of memory" despite only running Warp and Claude.

The file was `bmdjeb18h.output` inside a session's `tasks/` directory. Claude stores task/subagent output in `/tmp/claude-<uid>/<project-path>/<session-uuid>/tasks/`. When a task produces unbounded output (e.g., a runaway subagent or a large file read piped to output), the file grows without limit on tmpfs.

## Solution
Added a `cleanup_claude_tmp` function to `worktree-manager.sh` that:

1. Enumerates all session directories under `/tmp/claude-<uid>/`
2. Identifies active Claude sessions by reading `/proc/<pid>/cmdline` for running `claude` processes and extracting `--resume <session-id>`
3. For stale (non-running) sessions, removes task output files larger than 1 MB
4. Cleans up empty session and project directories

The function is called automatically from `cleanup_merged_worktrees` (which runs at every session start and after every PR merge) and is also available as a standalone `cleanup-tmp` command.

## Key Insight
Claude Code's tmpfs usage is invisible to typical memory debugging (it doesn't show as process RSS in `ps aux`). The `Shmem` line in `/proc/meminfo` and `du -sh /tmp/claude-*` are the diagnostic tools. Since `cleanup-merged` already runs at session boundaries, hooking tmpfs cleanup into it ensures the problem self-heals without manual intervention.

## Tags
category: runtime-errors
module: worktree-manager
