---
title: "Source-grep regression test breaks on symbol extraction; only the full-suite exit gate catches it"
date: 2026-06-15
category: test-failures
module: apps/web-platform/server/cc-dispatcher
issue: 5388
tags: [refactor, source-grep-test, full-suite-exit-gate, symbol-rename, cc-dispatcher]
---

# Source-grep regression test breaks on symbol extraction; only the full-suite exit gate catches it

## Problem

While fixing #5388 (the spurious `edit_c4_diagram` unregistered-tool Sentry mirror),
a review-fix refactor extracted the inline owner/repo parse + the `CC_GITHUB_NAME_RE`
regex out of `cc-dispatcher.ts` into a shared `parseConnectedRepo` helper
(`github-repo-parse.ts`), so the factory's c4-build gate and `resolveC4Eligible`'s
c4-advertise gate parse owner/repo identically (making the AC2 false-suppression
parity structural instead of comment-enforced).

Removing the `CC_GITHUB_NAME_RE` const broke `cc-dispatcher-connected-repo-context.test.ts`,
which is a **source-text regression test**: it `readFileSync`s `cc-dispatcher.ts`
and asserts `expect(comment).toMatch(/CC_GITHUB_NAME_RE/)` to prove the
injection-safety reasoning stays adjacent to the prompt builder. The symbol it
greps for no longer existed.

## Key Insight

A `readFileSync(src) + expect(src).toMatch(/SYMBOL/)` regression test couples a
test to a **source identifier**, not to behavior. Renaming or extracting that
identifier breaks the test even when behavior is unchanged — and the breakage is
invisible to the **touched-file test loop** (the test file imports nothing from
the changed module; it only reads its text). Only the **full-suite exit gate**
(`bun test` / full `vitest run`) surfaces it, because that gate exists precisely
to discover sibling/orphan suites the touched-file set never sees.

## Prevention

Before a rename/extract refactor that removes or moves a named symbol, grep the
test tree for source-text assertions on that symbol:

```bash
git grep -nE 'readFileSync|toMatch|toContain' apps/web-platform/test/ | grep -i <SYMBOL>
# or directly:
git grep -n <SYMBOL> apps/web-platform/test/
```

If a source-grep test asserts on the symbol, update its assertion in the SAME
edit cycle to point at the new identifier (here: `/CC_GITHUB_NAME_RE/` →
`/parseConnectedRepo/`), and update the test's title/docstring for accuracy. The
test's *intent* (injection-safety reasoning stays adjacent to the builder) is
still valid — only the symbol name changed.

This is the source-text-coupling sibling of the existing `cq-ref-removal-sweep`
guidance: a `replace_all`/extract sweep must include source-grep TESTS, not just
production call sites.

## Session Errors

- **CWD drift → `ugrep: No such file or directory`** — ran worktree-relative `grep`
  after the Bash CWD had moved into `apps/web-platform` from a prior `cd`.
  Recovery: prefix `cd <worktree-abs> && <cmd>`. Prevention: already covered by the
  work-skill rule "chain `cd <worktree-abs-path> && <cmd>` in a single Bash call."
- **`live-repo-badge.test.tsx` full-suite flake** — timed out at 10107ms under
  full-suite concurrency; passed 5/5 in isolation; unrelated to the diff.
  Recovery: re-ran in isolation to confirm. Prevention: the documented
  discriminate-flake-from-regression check (does the diff touch the failing test?
  does the changed surface pass? is the failure at goto/timeout vs a real
  assertion?) — CI's containerized run is authoritative.
- **`cc-dispatcher-connected-repo-context.test.ts` broke on `CC_GITHUB_NAME_RE`
  removal** — the subject of this learning. Recovery: updated the source-grep
  assertion to `/parseConnectedRepo/`. Prevention: grep `test/` for a symbol
  before extracting/renaming it (above).
