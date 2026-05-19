---
date: 2026-05-12
category: integration-issues
component: tool-orchestration
problem_type: parallel_tool_batching
severity: low
tags:
  - gh-cli
  - parallel-tools
  - file-staging
related_issues:
  - 2721
---

# Learning: `gh issue edit --body-file` against a parallel-write file races to a stale no-op

## Problem

While appending a "Bundled scoping" section to GitHub issue #2721 during the brainstorm Phase 3.6 artifact-linking step, the following sequence was batched into a single tool-call message:

1. `Write /tmp/issue-2721-body.md` — to overwrite the temp file with the appended scoping block.
2. `Bash: gh issue edit 2721 --body-file /tmp/issue-2721-body.md` — to push the updated body to GitHub.

The `Write` call failed (its contract requires a prior `Read` on any existing file), but the `gh issue edit` call had already started in parallel against the unchanged file. GitHub returned 200 and the issue URL; the body on GitHub remained unchanged. The append silently no-op'd.

## Solution

Sequence file-update + `gh issue edit --body-file` operations. The corrected pattern:

1. `Read <path>` to satisfy any subsequent Edit/Write contract.
2. `Edit <path>` (or `Write <path>`) to apply the change.
3. ONLY THEN `Bash: gh issue edit <N> --body-file <path>` in a separate tool-call batch.

Equivalent for files freshly created via Bash redirect:

```bash
# Step 1 (Bash):
gh issue view N --json body --jq .body > /tmp/body.md
# Step 2 (Read tool): Read /tmp/body.md
# Step 3 (Edit tool): Edit /tmp/body.md ... append the new section
# Step 4 (Bash, separate batch): gh issue edit N --body-file /tmp/body.md
```

## Key Insight

The Write tool's read-first contract protects against *one* parallel-write hazard (clobbering unread state), but it does NOT serialize sibling Bash calls in the same batch. A failed Write does not cancel a parallel Bash. The hazard is the *gap* between intended-write and downstream-consumer in the same parallel batch.

Same class as `cm-delegate-verbose-exploration-3-file` in spirit (sequential dependencies must be sequenced, not batched), but on the file-staging axis rather than the agent-spawning axis. The narrower rule: **any tool that consumes a file via path must run after the file-write tool that produces that content, in a separate batch.**

## Prevention

- When staging a temp file as input to `gh issue edit --body-file` (or `gh pr edit --body-file`, `gh release create --notes-file`, `git commit -F`, etc.), separate the write and the consumer into adjacent but non-parallel tool-call batches.
- When auditing a multi-tool batch before sending, scan for any pair of (file-producer, file-consumer-of-same-path) and split them.
- Verify the result with `gh issue view <N> --json body --jq .body | tail -<N-lines>` after the edit lands — the issue body itself is the source of truth, not the gh CLI return code.

## Session Errors

- **Parallel `gh issue edit --body-file` raced an unsuccessful Write on the same path** — Recovery: Read → Edit-append → re-run `gh issue edit` in a separate batch. Prevention: as documented above. Verified by reading the post-edit body via `gh issue view --json body`.

## Tags

category: integration-issues
module: tool-orchestration
