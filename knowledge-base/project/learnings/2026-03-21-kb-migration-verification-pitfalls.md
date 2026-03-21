---
title: KB Migration Verification Pitfalls
date: 2026-03-21
category: workflow-issues
tags:
  - migration
  - verification
  - grep
  - git-mv
  - lefthook
  - file-extensions
  - knowledge-base
---

# Learning: KB Migration Verification Pitfalls

## Problem

During the third attempt at migrating 144 knowledge-base artifact files from deprecated top-level paths (`knowledge-base/{brainstorms,learnings,plans,specs}/`) to canonical paths (`knowledge-base/project/{brainstorms,learnings,plans,specs}/`), four distinct verification and tooling errors caused wasted work and near-misses. The migration had already regressed twice before (PRs #657 and #897), making verification correctness critical.

## Solution

### grep -v path filtering bug

When verifying stale references using `grep -rn "knowledge-base/brainstorms" . | grep -v "knowledge-base/project/"`, the second `grep -v` filters ALL output lines because every match line starts with the matched file's path — and those files live under `knowledge-base/project/`. The pattern you're trying to exclude appears at the start of every output line as the filename prefix, not just in the content.

Correct approach: grep for the stale pattern in files that are NOT under the target directory, or redirect output to a temp file and inspect it directly:

```bash
# Wrong — filters everything because output lines include the file path
grep -rn "knowledge-base/brainstorms" knowledge-base/project/ | grep -v "knowledge-base/project/"

# Correct — search for stale refs outside the canonical path, or use --include to scope
grep -rn "knowledge-base/brainstorms" . --include="*.md" --include="*.ts" | grep -v "^./knowledge-base/project/"
# Or: use absolute path anchoring so the exclusion pattern matches only the prefix
```

### git mv on untracked files

`git mv` on a directory that contains only untracked files (files never `git add`ed) fails with `fatal: source directory is empty`. Git considers the source directory empty because it tracks no files there, even if the filesystem shows files present.

Correct approach: use `mv` directly on the filesystem for untracked files, then `rm -d` the now-empty source directory:

```bash
mv knowledge-base/project/brainstorms/* knowledge-base/project/brainstorms/
rm -d knowledge-base/project/brainstorms/
```

For tracked files, `git mv` works correctly and preserves history.

### Missing file extensions in reference sweeps

An initial stale-ref sweep checked `.md`, `.ts`, `.js`, `.sh`, `.yml`, `.yaml`, and `.json` but omitted `.toml`. An architecture review agent subsequently caught 2 stale references in `bunfig.toml`. Any file that can contain path strings is a candidate for stale references.

Correct approach: when specifying `--include` globs for a reference sweep, default to all text files, or explicitly enumerate a checklist and verify it covers the project's full extension inventory:

```bash
# Safer: let ripgrep search all files, exclude binary formats explicitly
grep -rn "knowledge-base/brainstorms" . --type-add 'config:*.toml' -t config -t yaml -t json -t ts -t js -t sh -t md
# Or: omit --include entirely and let grep search all text files
grep -rn "knowledge-base/brainstorms" .
```

### Testing Lefthook guards in isolation

During guard verification, a `git commit` intended only as a guard test inadvertently committed all staged renames because Lefthook did not block it (the guard was being tested, not yet active). This required `git reset HEAD~1` to undo. Real commits are the wrong vehicle for testing hooks.

Correct approach: test Lefthook guards in isolation without creating a real commit:

```bash
lefthook run pre-commit --verbose
```

This runs the hook scripts against currently staged content and prints pass/fail output without creating a commit. Stage a violating file, run this command, verify the block, then unstage. No reset needed.

## Key Insight

Verification commands can silently return false-clean results when the exclusion pattern matches the file path prefix rather than the content. Always sanity-check verification output counts: if a grep-verify step returns 0 matches for a large codebase, confirm by sampling a few files manually before declaring success.

The broader pattern: every step in a multi-phase migration (move files, update references, verify references, test guards) has a distinct failure mode. Treat each phase's verification as adversarial — assume it can silently lie — and cross-check with a second method.

## Session Errors

1. **git mv fatal on untracked files** — `git mv` on a directory containing only untracked files fails with "source directory is empty". Manual `mv` + `rm -d` needed because git has no knowledge of files that were never staged.

2. **Buggy grep -v verification** — `grep -rn ... knowledge-base/project/ | grep -v 'knowledge-base/project/'` filters ALL output lines because file paths in grep output start with `knowledge-base/project/`. This made it appear 0 stale refs existed when there were 110.

3. **Accidental commit during guard test** — `git commit` for guard testing included all staged renames because Lefthook didn't block it (the guard was being verified, not yet enforced at that stage). Required `git reset HEAD~1`. Guard verified working separately via `lefthook run pre-commit --verbose`.

4. **Missing file type in sweep** — Initial stale-ref sweep checked `.md/.ts/.js/.sh/.yml/.yaml/.json` but missed `.toml`. Architecture review agent caught 2 stale refs in `bunfig.toml`.

## Related Learnings

- `2026-02-06-docs-consolidation-migration.md` — The original migration into `knowledge-base/`. Established the grep-verify pattern that this learning corrects.
- `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md` — Bulk migration with integrity verification; shares the "scope all edits first, then apply, then verify" workflow.
- `2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md` — Related lesson on testing hooks deterministically without relying on real commits.

## Tags

category: workflow-issues
module: knowledge-base
severity: high
problem_type: verification-error
root_cause: grep-filtering-pitfall
