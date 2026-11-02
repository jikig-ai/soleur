# Learning: a resume brief's "next link" can already be shipped, and a saved .pen trips gitleaks

## Problem

Brainstorm for epic #9601 slice 2 (#4672 approval queue). Two things cost time:

1. The operator's resume brief said "#4671 is the next link, run brainstorm/plan for it". `gh` showed #4671 already had two merged PRs (#10192 WebFetch annotator, ADR-287; #11075 GitHub-text framing) plus open follow-ups (#10194, #10195, #10196, #11076, #11077). Routing on the brief would have re-planned shipped work.
2. After the wireframe agent saved `approval-request.pen`, the commit was blocked by the gitleaks PreToolUse hook: the file's top-level `"fileToken"` UUID matched `generic-api-key`. The hook blocks the entire Bash command, so the other steps bundled with the commit (taste-profile write, doc edits) did not run either.

## Solution

1. Verified each cited issue with `gh issue view --json state,comments` and `gh pr list --search` before routing, then asked the CTO agent to rule on the real next link (#4672, #10443 folded in). Refreshed the epic body from verified state.
2. Removed the `fileToken` key in place (fixing the trailing comma, re-parsing as JSON), then staged and committed as separate calls.

## Key Insight

A brief written from memory carries the author's last-known state; `gh` is the source of truth, and "X is next" is a claim to verify, as is "X is unstarted". A Pencil document id is not a secret but looks like one to gitleaks, and a blocked hook voids every step bundled into the same command, so stage and commit alone.

## Session Errors

1. **Resume brief treated #4671 as unstarted** — Recovery: `gh` verification before routing; CTO re-ruled — **Prevention:** `soleur:go` already says "verify each with gh before acting"; kept as a brief-author habit, no new rule.
2. **`worktree-manager.sh feature` exceeded the 120 s tool timeout and moved to background** — Recovery: waited for the completion notification — **Prevention:** one-off (long worktree hydration); none.
3. **`sleep 45 && …` was blocked by the harness** — Recovery: read the output file / polled with a plain command — **Prevention:** use a background task notification, not a foreground sleep (already enforced by the harness).
4. **Redirect to a scratchpad file failed because the directory did not exist** — Recovery: `mkdir -p` — **Prevention:** one-off.
5. **gitleaks blocked the commit over the `.pen` `fileToken`, which also skipped the bundled steps** — Recovery: scrub in place, restage, commit separately — **Prevention:** added a sentence to `plugins/soleur/agents/product/design/ux-design-lead.md` Step 3 item 1 to drop `fileToken` after the final save.
6. **Shell cwd drifted to the repo root after a `cd … && gh` call** — Recovery: explicit `cd` into the worktree on later calls — **Prevention:** one-off; always `cd` to the worktree absolute path per call.

## Tags
category: workflow-issues
module: brainstorm, ux-design-lead, gitleaks hook
