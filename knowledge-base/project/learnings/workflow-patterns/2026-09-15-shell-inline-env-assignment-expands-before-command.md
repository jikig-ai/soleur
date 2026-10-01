---
date: 2026-09-15
category: workflow-patterns
tags: [bash, environment, review]
---

# Shell inline environment assignments expand after the command is parsed

An invocation written as `VAR=value bash "$VAR/path/script.sh"` expands
`$VAR` before the temporary environment assignment is active. The command then
looked for `/path/script.sh` and failed even though the file existed.

Export the variable in a preceding command, or use the literal path in the
argument: `export VAR=value; bash "$VAR/path/script.sh"`. Keep this in mind
when invoking Soleur scripts whose path is carried by an environment variable.

## Session Error

The review-trailer command used the inline-assignment form and exited with
`No such file or directory`; the corrected exported form emitted the trailer.
