---
name: soleur-rclone
description: "This skill should be used when uploading, syncing, or managing files across cloud storage providers using rclone. It handles transfers to S3, Cloudflare R2, Backblaze B2, Google Drive, Dropbox, or any S3-compatible storage."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/rclone/SKILL.md`, relative to the plugin root.
