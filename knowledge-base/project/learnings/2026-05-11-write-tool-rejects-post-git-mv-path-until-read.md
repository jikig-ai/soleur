---
date: 2026-05-11
type: tooling-quirk
component: claude-code-tools
severity: low
tags: [git-mv, write-tool, read-tracker, worktree]
related_issues: [3270]
related_prs: [3560]
synced_to: []
---

# Learning: Write tool rejects post-`git mv` destination path until it is Read

## Problem

In PR #3560, the work skill instructed me to `git mv router-flag-stickiness.test.ts router-stickiness-invariant.test.ts` and then rewrite the file content to drop two `it` blocks and reframe the header doc-comment. The natural sequence was:

```
1. git mv old.test.ts new.test.ts        # rename in-place
2. Write new.test.ts <new content>       # overwrite
```

Step 2 was rejected by the Claude Code Write tool with:

> File has not been read yet. Read it first before writing to it.

This is surprising because (a) the file at the new path was just produced by `git mv` from a file I had Read earlier in the session, (b) the inode and content are identical, and (c) the Edit tool would have worked if I had used Edit instead of Write (Edit tracks the original path's read state, not the new one).

## Root Cause

The Write tool's "must read before write" guard is keyed on the **literal path string**, not on inode identity or file content. After `git mv`, the destination path is a new string in the tool's read-tracker — even though the file content is identical. The guard exists to prevent the model from overwriting a file whose current state it has not observed; the `git mv` doesn't change content, but it does change the path the tool would track.

## Solution

After any `git mv`, **Read the destination path** before invoking Write/Edit on it:

```
1. git mv old.test.ts new.test.ts
2. Read new.test.ts                       # registers the new path with the tracker
3. Write new.test.ts <new content>        # accepted
```

Cost: one Read call (~free). Recovery from the rejection is also a single Read call.

Alternative: prefer **Edit** over **Write** when the post-mv file content is going to be a substantial rewrite. Edit's old-string match against the original (read) content from before the mv works because the file inode is unchanged. Write requires the destination path to be in the tracker.

## Prevention

- After `git mv <old> <new>`, immediately Read `<new>` if you plan to Write to it. This is one extra Read call per rename; it's cheap insurance against the rejection.
- This is a discoverable error (the error message is clear and points at the fix), so it does not require a hard rule in AGENTS.md. A single learning file is the right tier per `wg-every-session-error-must-produce-either`'s discoverability exit clause.
- If the rename is followed by a CONTENT REWRITE (not just metadata change), the natural reflex is `Write` (full replacement) rather than `Edit` (diff). Default to `Read` + `Write` in that case.

## Session Errors

**Write rejected on renamed file** — Recovery: Read the new path, then Write succeeded on the next attempt. Prevention: after `git mv`, Read the destination before invoking Write/Edit on it.

## See Also

- `2026-02-24-git-add-before-git-mv-for-untracked-files.md` — related git-mv gotcha (different symptom: untracked file disappears on `git mv`).
- AGENTS.md `hr-always-read-a-file-before-editing-it` — the load-bearing rule; this learning is a corollary specific to the post-`git mv` state.
