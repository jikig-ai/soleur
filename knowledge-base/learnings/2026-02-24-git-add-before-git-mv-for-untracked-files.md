# Learning: Always git add before git mv in skill instructions

## Problem
`git mv` fails with `fatal: not under version control` when archiving knowledge-base files created during the current session but never committed. This broke compound-capture archival and any skill that archives KB artifacts.

## Solution
Prepend `git add <source-file>` before every `git mv` in skill instructions. `git add` on an already-tracked file is a no-op, so this is safe to run unconditionally. This avoids the error entirely rather than catching it after the fact.

## Key Insight
When skill markdown files instruct LLMs to run `git mv`, the instruction must account for files that exist on disk but are not yet tracked by git. Proactively staging with `git add` before `git mv` is simpler and more token-efficient than a try/catch/retry pattern, because it avoids generating error output that consumes context.

## Tags
category: build-errors
module: skills
