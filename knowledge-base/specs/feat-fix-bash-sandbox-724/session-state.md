# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/fix-bash-sandbox-724/knowledge-base/plans/2026-03-20-fix-bash-sandbox-canuse-tool-plan.md
- Status: complete

### Errors
None

### Decisions
- **SDK built-in sandbox over string-matching**: Agent SDK has native `sandbox` option using `bubblewrap` on Linux for OS-level filesystem/network isolation, replacing fragile regex-based Bash command parsing.
- **Three-tier defense-in-depth**: Tier 1 = SDK sandbox (OS-level), Tier 2 = `canUseTool` with deny-by-default policy, Tier 3 = `disallowedTools` for hard deny.
- **Env var spread is a separate vulnerability**: `env: { ...process.env }` leaks all server secrets to the agent process. Plan narrows to minimal env set.
- **`.claude/settings.json` bypass**: Provisioned `permissions.allow` bypasses `canUseTool` workspace path validation. Must be emptied.
- **Dockerfile must install `bubblewrap socat`**: Required for SDK sandbox on Linux.

### Components Invoked
- soleur:plan
- soleur:deepen-plan
- WebFetch (Agent SDK docs)
- GitHub CLI
- File reads (agent-runner.ts, workspace.ts, ws-handler.ts, etc.)
