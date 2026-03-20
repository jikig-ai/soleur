---
title: "Truncated CHANGELOG during rebase conflict resolution"
category: integration-issues
tags:
  - git-rebase
  - merge-conflicts
  - changelog
  - file-truncation
module: git-workflow
created: 2026-02-17
severity: high
---

# Learning: Write tool truncates large files during rebase conflict resolution

## Problem

During rebase of PR #117 (sync definitions feature), CHANGELOG.md had a merge conflict -- both main and the feature branch claimed version 2.12.1. When resolving the conflict by writing only the new entry + the conflicting entry (~32 lines), the remaining ~575 lines of changelog history were silently lost. The file went from ~620 lines to ~32 lines with no error.

Additionally, version references in plugin.json, root README badge, and bug_report.yml were not updated to match the new version (2.12.2), since the conflict only surfaced in CHANGELOG.md.

## Solution

When resolving merge conflicts in large files during rebase:

1. Read the FULL base file from the rebase target: `git show HEAD:<path>`
2. Write the COMPLETE file: resolved content + full prior history
3. Verify line count matches expectation after writing
4. Update ALL scattered version references (the versioning pentad), not just the conflicting file

## Key Insight

The Write tool replaces the entire file. During rebase conflict resolution, the file on disk contains conflict markers -- there is no "rest of the file" to preserve. You must explicitly reconstruct the full file by reading the base version from `git show HEAD:<path>` and appending all prior history after your resolved section. Treat rebase conflict resolution as a full file rewrite, not an edit.

## Tags

category: integration-issues
module: git-workflow
symptoms: changelog history missing after rebase, file shorter than expected, version mismatch across triad files
