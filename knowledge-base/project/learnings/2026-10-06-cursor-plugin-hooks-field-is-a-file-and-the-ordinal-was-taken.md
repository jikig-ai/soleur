# Learning: a Cursor plugin hooks field is a file, and ADR-272 was already taken

## Problem

The Cursor CLI adapter plan first treated `hooks` as a directory that would replace discovery, and it reserved ADR-272. Both were wrong on measurement. A directory does not replace discovery. The plugin reference types `hooks` as a path to a config file or an inline object, and an omitted field loads `hooks/hooks.json`. ADR-272 was already the filename on two origin branches, and on one local branch that origin did not have.

## Solution

Slice 1 sets the manifest `hooks` field to `./cursor/hooks-empty.json` whose body is `{ "hooks": {} }`. The provisional ordinal was ADR-273. The merge-edit census found `origin/main` holding `ADR-273-schema-constrained-handler-side-publication.md`, so the Cursor record landed as ADR-274. The spec directory and tasks file had no ordinal 273 citation to rename.

## Key Insight

A new harness manifest field is whatever the vendor page types, fetched again after the plan drafts it. An ADR ordinal is free only on the refs you just listed, not on the number one past `origin/main`.

## Session Errors

1. **The plan reserved ADR-272.** Recovery: a `git ls-tree` census of decision filenames. Prevention: re-run that census over local heads and origin heads immediately before the ADR file is added.
2. **The first hooks design was a directory.** Recovery: re-fetch the plugin reference and point `hooks` at an empty config file. Prevention: when a manifest field is documented as a path or an object, do not ship a directory and call it the registry.
3. **`git grep` across `git ls-remote` output returned no ADR numbers.** Recovery: walk each ref with `git ls-tree`. Prevention: an empty grep of a ref list is not evidence that the numbers are absent.
4. **Research Insights said to leave `behindSyncInstructions("cursor")` on the default.** That default runs the Claude plugin-root script. Recovery: the review replaced that sentence with the refusal arm. Prevention: a "current fallthrough" bullet that also says "leave it" has to match the later implementation section.
5. **`skills/help/SKILL.md` was grouped with the other skills.** It is a Devin shim, same as `go` and `sync`. Recovery: the generator points `soleur-help` at `commands/help.md`. Prevention: the do-not-edit list that names `{go,help,sync}` is the set the generator must special-case.

## Tags

category: workflow-issues
module: plugins/soleur
