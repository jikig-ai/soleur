# External-platform gate — vendor-bundle decomposition (#10230)

When a brainstorm evaluates an external product/tool BUNDLE ("can we use X?"), decompose
by insertion layer before any benefit analysis: the question is one per mechanism, and
reachability settles most of them:

- **Proxy-layer behaviors** (aux-call mocks — quota probes, titles, suggestions —
  and provider-request rewriting) are UNREACHABLE from a plugin: a plugin sees tool-call
  lifecycle events, not provider traffic.
- **Tool-result compression** cannot touch Bash/Read/Grep output: PostToolUse only
  appends `additionalContext`; `updatedMCPToolOutput` is MCP-only.
- **PreToolUse command rewriting** IS reachable (`grep-rewrite.sh`, ADR-162) — Bash-call
  output filters install here (rtk's `PreToolUse` rewrite of `git status` →
  `rtk git status`).

Then, whatever the adopt verdict, check the tool's command wrappers against OUR
machinery: a rejected tool can still bypass a guard for users who install it
independently (`rtk` vs `destructive-command-guard.sh`'s wrapper table — #10230;
the same class reached `pkill-self-match-guard.sh` and `proc.sh`).

Learning: `knowledge-base/project/learnings/2026-10-13-external-tool-adoption-evals-decompose-by-reachability-layer.md`.
