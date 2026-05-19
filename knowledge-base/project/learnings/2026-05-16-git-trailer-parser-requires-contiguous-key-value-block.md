---
module: System
date: 2026-05-16
problem_type: best_practice
component: development_workflow
symptoms:
  - "`Allowlist-Widened-By:` trailer present in commit body but `git interpret-trailers --parse` returns empty"
  - "`apps/web-platform/scripts/allowlist-diff.sh` ack mechanism reads `git log --format='%(trailers:key=Allowlist-Widened-By,valueonly)'` and sees nothing despite the line being in the commit message"
  - "Co-Authored-By renders correctly but a sibling trailer added above it silently drops"
root_cause: inadequate_documentation
resolution_type: workflow_improvement
severity: low
tags: [git, trailers, commit-message, allowlist-diff, ci-gate]
synced_to: [work]
related:
  - https://github.com/jikig-ai/soleur/pull/3886
  - https://github.com/jikig-ai/soleur/issues/3877
  - https://github.com/jikig-ai/soleur/pull/3875
---

# Git trailer parser requires a contiguous `Token: value` block at the end of the commit message

## Problem

PR #3886 (the asterisk-redaction allowlist widening for `database-url-with-password`) needs a `Allowlist-Widened-By: Jean Deruelle` commit trailer for the `apps/web-platform/scripts/allowlist-diff.sh` ack mechanism. The trailer was emitted on its own line in the commit body, but:

- `git interpret-trailers --parse < <(git log -1 --format=%B)` returned only `Co-Authored-By: ...`, dropping the Allowlist-Widened-By line.
- `git log -1 --format='%(trailers:key=Allowlist-Widened-By,valueonly)'` (the exact form `allowlist-diff.sh:112` uses) returned empty.

Two distinct shapes triggered the silent drop:

**Shape 1 — Blank line between trailers.**

```
...prose body...

Allowlist-Widened-By: Jean Deruelle

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@example.com>
```

Git's parser treats only the LAST contiguous paragraph of `Token: value` lines as the trailer block. Inserting a blank line between `Allowlist-Widened-By:` and `Co-Authored-By:` makes the former part of the body, not a trailer.

**Shape 2 — Non-key:value line inside the final paragraph.**

```
Closes #3877.
Refs #3874 (path-allowlist precedent), #3888 (sibling parser refactor).
Allowlist-Widened-By: Jean Deruelle
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@example.com>
```

Git requires EVERY line in the final paragraph to be parseable as `Token: value` (or a continuation line starting with whitespace). The `Closes #3877.` and `Refs #3874 (...)` lines don't match — they have a number sign and a period, not `Closes: #3877`. The parser falls back to "no trailers detected" for the entire block; even valid `Allowlist-Widened-By:` and `Co-Authored-By:` lines below are dropped.

## Solution

Two rules for any commit that needs to be machine-readable via trailers:

1. **Keep the trailer block contiguous.** No blank lines between `Token: value` entries in the final paragraph.
2. **Put `Closes`/`Refs`/`Fixes` references in PROSE earlier in the body, not in the trailer block.** GitHub's auto-close still works from anywhere in the body; the trailer block must stay pure `key: value`.

Working shape (verified via `git interpret-trailers --parse`):

```
feat(scope): subject

...rationale prose...

Closes #3877. Refs #3874 (motivating issue), #3875 (precedent PR),
#3888 (sibling parser refactor).

...more prose, code block list, etc...

Allowlist-Widened-By: Jean Deruelle
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@example.com>
```

## Verification

Run `git interpret-trailers --parse < <(git log -1 --format=%B)` after writing any commit that depends on a trailer-based ack. Empty output = the trailer block is malformed; both lines must be in the same contiguous paragraph at the end.

For ack scripts like `allowlist-diff.sh` that use `git log --format='%(trailers:key=NAME,valueonly)'`, this format directive has the same contiguity requirement — `interpret-trailers --parse` is the canonical local pre-check.

## Prevention

- **Authoring**: when constructing commit messages that carry an ack trailer (`Allowlist-Widened-By:`, `Signed-off-by:`, `Reviewed-by:`, etc.), put `Closes/Refs/Fixes` references in mid-body prose. Reserve the FINAL paragraph for trailers only.
- **Verification**: always run `git interpret-trailers --parse < <(git log -1 --format=%B)` after authoring (or amending) a trailer-carrying commit; treat empty output for a trailer that should exist as a hard fail.
- **Issue vs PR citations**: when citing a fix as precedent, distinguish motivating issue from merge PR. `gh issue view <N> --json state,title` AND `gh pr view <N> --json state,title` disambiguates. Use both numbers in prose (`Refs #<issue> (motivating), #<PR> (precedent)`) when traceability matters.

## Session Errors

1. **Trailer dropped silently due to blank-line separation** — Recovery: `git commit --amend` with trailers contiguous — Prevention: see Authoring rule above. Always verify with `git interpret-trailers --parse`.
2. **Trailer dropped silently due to `Closes #N.` / `Refs #N.` in the final paragraph** — Recovery: second amend; moved `Closes/Refs` into mid-body prose — Prevention: keep final paragraph as pure `Token: value` block.
3. **Issue vs PR conflation (#3874 the issue treated as #3875 the precedent PR)** — Recovery: review-fix commit corrected references in plan frontmatter (`related_prs`), fixture file, and PR body — Prevention: run `gh issue view <N>` AND `gh pr view <N>` to disambiguate before writing precedent prose.
