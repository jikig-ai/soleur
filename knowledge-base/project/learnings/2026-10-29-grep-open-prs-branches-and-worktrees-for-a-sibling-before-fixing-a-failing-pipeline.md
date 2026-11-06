# Learning: grep open PRs, remote branches and worktrees for a sibling before fixing a failing pipeline

## Problem

When the infra apply pipeline went red on the web-2 host key, three parallel attempts at the same re-pin were opened by separate sessions (the fix that merged was the web-2 host-key re-pin). A red shared pipeline attracts every session that sees it, and each one assumes it is the only one looking.

## Solution

Before opening a PR for a failing-pipeline fix, search for a sibling: open PRs (`gh pr list --state open --search "<issue or symptom>"`), remote branches (`git branch -r | grep -i <issue>`), and local worktrees (`git worktree list`). If one exists and is live (recent commits), leave it alone and offer review, not a duplicate. The same check applies before starting any issue-keyed work; it found two live sessions on #11194 and none on #11128 in this session.

## Key Insight

A failing shared pipeline is the highest-duplication case, because the signal is public and the fix is small. The search costs three commands; a duplicate costs a merge race and a wasted CI budget.

## Session Errors

1. Three parallel PRs fixed the same web-2 host-key re-pin. **Prevention:** grep open PRs, remote branches and worktrees for a sibling before opening a PR for a failing-pipeline fix.

## Tags

category: workflow-patterns
module: ci, parallel-sessions
