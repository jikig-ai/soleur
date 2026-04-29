# Learning: Subagents launched from a worktree can read stale files even when the parent agent reads correctly

## Problem

During the brainstorm for #3024 (in-chat conversation rail), the parent agent verified `apps/web-platform/app/(dashboard)/layout.tsx` from inside the worktree (`.worktrees/feat-command-center-conversation-nav/...`) and read 531 lines, 3 NAV_ITEMS (Command Center / Knowledge Base / Settings), with `useSidebarCollapse` imported on line 8.

The CTO subagent — spawned via the Agent tool with `subagent_type: soleur:engineering:cto` while the parent was in the worktree — opened the same logical file and reported **134 lines, 2 NAV_ITEMS (Dashboard + Knowledge Base, no Settings), no `useSidebarCollapse` import anywhere in `apps/web-platform`**. It even built its assessment around the absence of the hook ("does not appear anywhere in `apps/web-platform`").

The subagent's recommendations were still sound (chat-segment layout, per-user Realtime filter as the load-bearing risk), but its premises were wrong, and the parent agent had to verify-and-correct in front of the user before synthesizing.

## Solution

The parent agent re-verified directly with `wc -l` and `grep` on the worktree-absolute path, found the contradiction, and explicitly called it out in the synthesis ("CTO read stale code; its load-bearing insight stands; verified actual state"). The brainstorm doc captured the verified state, not the subagent's reading.

Going forward, subagent prompts launched from a worktree must:

1. Pass **absolute worktree paths** (`/home/jean/.../.worktrees/feat-<name>/apps/...`), not repo-relative paths like `apps/...`.
2. Optionally pin context with the worktree's HEAD SHA so the subagent can verify it's reading the right tree (e.g., `git rev-parse HEAD` in the worktree before spawning).
3. The parent agent should sanity-check load-bearing premises in subagent output (file sizes, identifier names, line counts) before treating them as ground truth — especially when the subagent's recommendation hinges on the absence of something.

## Key Insight

AGENTS.md `hr-when-in-a-worktree-never-read-from-bare` targets the foreground agent. It does NOT propagate to subagents — a subagent spawned via the Agent tool starts with its own CWD resolution, and if the brainstorm/plan/review skill prompt does not explicitly anchor the subagent to the worktree path, the subagent can land in the bare repo root (where `apps/web-platform/app/(dashboard)/layout.tsx` resolves to a stale synced copy from before the latest collapsible-navs PR merged).

This is the same class of bug as `2026-03-13-bare-repo-stale-files-and-working-tree-guards.md` (layer 2: stale on-disk files at the bare root) but surfaces in a place existing prevention does not cover: **subagent reads, not parent-agent reads**.

## Session Errors

- **CTO subagent reported wrong premises about the dashboard layout.** Recovery: parent agent re-verified with `wc -l` + `grep`, called out the contradiction, and built the synthesis on the verified state. **Prevention:** brainstorm Phase 0.5 (and plan, review) subagent prompts should always include the absolute worktree path for any file the subagent is asked to assess.
- **`AskUserQuestion` tool received `questions` as a JSON-serialized string instead of an array.** Recovery: re-issued with proper array shape. **Prevention:** harness convention; not actionable as a project rule.
- **Brainstorm Phase 3.6 commits artifacts before compound runs**, in tension with AGENTS.md `wg-before-every-commit-run-compound-skill`. Recovery: ran compound at Phase 4 as the brainstorm skill prescribes. **Prevention:** track as a skill-instruction clarification — brainstorm Phase 3.6's commit step is an exception to the compound-before-commit gate, OR the artifact commit should move to Phase 4 after compound. File as a skill-edit issue rather than an AGENTS.md change (domain-scoped per `cq-agents-md-tier-gate`).

## Tags

category: integration-issues
module: subagents
related: 2026-03-13-bare-repo-stale-files-and-working-tree-guards.md
related: 2026-03-18-worktree-manager-bare-repo-false-positive.md
