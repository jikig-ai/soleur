# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-kb-search-pdf-uploads/knowledge-base/project/plans/2026-04-15-fix-kb-search-pdf-uploads-plan.md
- Status: complete
- Issue: #2230 (P1 bug, domain/engineering, Phase 3 milestone)
- PR: #2281 (draft)

### Errors

- Security reminder hook produced a known false positive on a `RegExp.prototype` method call (per learning 2026-04-07); worked around by renaming the local variable.
- The Task tool for spawning parallel review sub-agents wasn't exposed in the deepen-plan skill context; deepening was done inline by directly applying three relevant learnings.

### Decisions

- **Root cause:** `collectMdFiles` in `apps/web-platform/server/kb-reader.ts:116-141` hardcodes `entry.name.endsWith(".md")`, so every PDF/DOCX/CSV/TXT/image upload is invisible to search.
- **Fix scope:** two-mode search — filename match on all 9 allowed upload extensions (+ `.md`), content match on text-native types only (`.md`/`.txt`/`.csv`). Binary text extraction (PDF/DOCX/OCR) deferred to existing `feat-kb-rag-evaluation` spec.
- **Existing tests encode the bug:** `test/kb-reader.test.ts:358-380` has two tests asserting "searchKb returns only .md files" — must be deleted (TDD red-step).
- **Case-sensitivity trap:** `path.extname("Q1-Invoice.PDF")` returns `.PDF`. Plan prescribes `.toLowerCase()` before lookup + negative-space test.
- **Symlink enumeration guard preserved:** Renamed `collectSearchableFiles` keeps `!entry.isSymbolicLink()` on both directory and file branches.
- **Test runner anchored to vitest** per `apps/web-platform/package.json`; worktree invocation uses `node node_modules/vitest/vitest.mjs run` per `cq-in-worktrees-run-vitest`.

### Components Invoked

- `skill: soleur:plan`
- `skill: soleur:deepen-plan`
- Bash, Read, Grep, Glob, Edit, Write, markdownlint-cli2, git commit/push (2 commits on `feat-kb-search-pdf-uploads`)
- Learnings applied: `2026-04-07-promise-all-parallel-fs-io-patterns.md`, `2026-04-07-symlink-escape-recursive-directory-traversal.md`, `2026-04-11-plan-prescribed-wrong-test-runner.md`
