---
name: soleur-feature-video
description: "This skill should be used to record video walkthroughs of features for PR descriptions. Captures browser interactions via agent-browser CLI; optional GIF/MP4 via ffmpeg and upload via rclone."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/feature-video/SKILL.md`, relative to the plugin root.
