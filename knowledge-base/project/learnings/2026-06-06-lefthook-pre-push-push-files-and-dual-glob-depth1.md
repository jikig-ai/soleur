# Learning: lefthook pre-push uses `{push_files}` (not `{staged_files}`), and `dir/**/*` silently skips depth-1 files

## Problem

Adding a new lefthook gate (`client-pii-grep`, #3703) to BOTH `pre-commit` and a
new `pre-push` section shipped two silent no-op bugs that green tests did NOT
catch — both found at multi-agent review, verified e2e against lefthook 2.1.6:

1. **`{staged_files}` in a `pre-push` command resolves to EMPTY.** `{staged_files}`
   is a pre-commit-only template — nothing is staged at push time. lefthook
   reported `client-pii-grep (skip) no files for inspection` and the push
   succeeded carrying a real violation. The entire pre-push gate did nothing.
2. **Bare `dir/**/*.{ts,tsx}` globs skip depth-1 files.** gobwas (lefthook's
   matcher) treats `**` as **1+** intermediate directories, NOT 0+. So
   `apps/web-platform/app/**/*.tsx` does NOT match `app/global-error.tsx`
   (depth-1) — and `global-error.tsx` was one of the actual client Sentry
   call sites the gate was built to cover. Three of the four named real sites
   were silently skipped at pre-commit.

## Solution

- **pre-push file set → `{push_files}`.** Use `{push_files}` in `pre-push`
  commands (the push range), never `{staged_files}`. (The no-arg tree-scan
  fallback does NOT save you — lefthook skips the command *before* `run`
  executes when the file template resolves empty.)
- **Dual-glob for every scoped lefthook glob** — list BOTH the single-star and
  double-star forms so depth-1 AND deeper files match:
  ```yaml
  glob:
    - "apps/web-platform/lib/*.{ts,tsx}"
    - "apps/web-platform/lib/**/*.{ts,tsx}"
  ```
  This mirrors the `gdpr-gate-advisory` / `kb-structure-guard` precedents in the
  same file. The array-vs-scalar distinction is irrelevant — the `**`-only
  segment is the trap.

## Key Insight

The dual-glob trap already had a learning
(`2026-03-21-lefthook-gobwas-glob-double-star.md`) — yet the **plan prescribed
the bare `dir/**/*` form anyway**, and it shipped through implementation green
(unit tests exercise the script directly, never the lefthook glob). A learning
only prevents recurrence if it fires at the moment the wrong form is written.
When a plan or implementation adds a lefthook `glob:`, the cheapest gate is:
"does every entry have BOTH a `*` and a `**` variant?" — and for a `pre-push`
command, "is the file template `{push_files}`, not `{staged_files}`?" Neither
is catchable by the gate's own unit tests (which run the script, not lefthook);
only an e2e `git commit`/`git push` against a depth-1 fixture, or review,
catches them.

## Session Errors

- **`pre-push` command used `{staged_files}` → vacuous no-op.** Recovery:
  `{push_files}`. Prevention: this learning (novel — not previously documented).
- **Bare `dir/**/*` globs skipped depth-1 files** (3 of 4 named real sites).
  Recovery: dual-glob. Prevention: reinforces
  `2026-03-21-lefthook-gobwas-glob-double-star.md` — cite it at PLAN time when
  prescribing lefthook globs, not just at review.

## Tags
category: build-errors
module: lefthook
