---
title: "fixture: hostile-but-legal YAML whose correct answer is NON-empty"
date: 2026-08-10
branch: "feat-quoted-branch"
---

# Positive control

The frontmatter quotes `branch:`, which is idiomatic in this corpus (`title:` is quoted two lines
above it). A reader that cannot unquote returns `"feat-quoted-branch"` with the quotes, which
compares unequal to the branch name and silently degrades to "no plan found".

This fixture's correct answer is non-empty, so it is the control that stops every other assertion
in the suite from passing against a reader that always returns empty.

## Acceptance Criteria

- Present so this fixture reads as a FINISHED plan under the completion predicate.
