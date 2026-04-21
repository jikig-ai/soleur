---
module: docs-tooling
date: 2026-04-19
problem_type: best_practice
component: markdownlint-cli2
symptoms:
  - "`npx markdownlint-cli2 --fix` rewrites prose so `#NNNN` lands at column 0, then flags MD025 single-h1 violation"
  - "Subsequent --fix runs do not auto-recover; the file gains a phantom h1 mid-document"
  - "Verification.md gained a `# 2416 dismissed all 9 alerts...` heading where the original prose said `bulk-dismiss PR #2416. It became an orphan when PR #2416 dismissed all 9 alerts.`"
root_cause: inadequate_documentation
resolution_type: prose_pattern
severity: low
tags: [markdownlint, markdown, prose-conventions, lint-pitfalls]
related_learnings:
  - 2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md
---

# `markdownlint --fix` mangles `#NNNN` at line-start into a phantom h1

## Problem

Running `npx markdownlint-cli2 --fix` on `verification.md` (PR #2631) reflowed
prose around an issue/PR reference so `#2416` ended up as the first non-blank
character of a line. CommonMark interprets `#2416` at line-start as an
ATX heading (level depends on hash count, but a bare `#` followed by content
is h1). markdownlint then flagged MD025 (Multiple top-level headings) AND
MD022 (blanks-around-headings) on the same line. The autofix did not undo the
mangle on subsequent runs — the document was now structurally wrong from
markdownlint's view, and only manual prose rewrite recovered.

The original prose was:

```markdown
~18 hours before the bulk-dismiss PR #2416. It became an orphan when
#2416 dismissed all 9 alerts.
```

After `--fix`, the second line was treated as a heading and rewritten to:

```markdown
# 2416 dismissed all 9 alerts. The remediation in this PR adds an automated
```

…which then triggered single-h1 because the document already had a real `#`
title at line 1.

## Solution

When writing prose containing `#NNNN` references near a line wrap, prevent
`#NNNN` from ever starting a line. Three options:

1. **Reword to keep the reference mid-line.** Preferred — most readable.

   ```markdown
   …18 hours before the bulk-dismiss PR #2416. It became an orphan when PR
   #2416 dismissed all 9 alerts.   <!-- still wraps, but starts with "PR " -->

   …18 hours before the bulk-dismiss PR #2416). It became an orphan when PR
   \#2416 dismissed all 9 alerts.   <!-- escape with backslash -->
   ```

2. **Escape the hash.** `\#2416` renders as literal `#2416` and is not parsed
   as a heading. Slightly noisy but mechanical.
3. **Wrap in backticks.** `` `#2416` `` always renders as literal text in code
   font. Use when prose can tolerate the typographic shift.

## Key Insight

`markdownlint --fix` is autofix-only for whitespace/format violations — it
will NOT undo a structural change it caused. Once it interprets a line as a
heading, the document is structurally different and re-running `--fix` only
adds blank lines around the phantom heading. Prose must be defensively
written so autofix cannot re-classify a line.

## Prevention

- After `npx markdownlint-cli2 --fix`, always Read the modified file before
  trusting it. The Edit tool's "modified by linter" reminder surfaces this,
  but the prose-mangle case requires human inspection.
- For docs that cite many GitHub references, audit fenced wrap points: any
  prose line ending mid-sentence near a `#NNNN` mention is a candidate for
  re-wording.
- For author-controlled docs (learning files, plans, verification.md), prefer
  the rewording approach over escapes — escapes propagate noise into future
  edits.

## Session Errors

**Wrong issue number from user input.** User typed `#2398` (a real issue, but
not the resume target). Created a worktree+draft-PR before clarification.
Recovery: closed PR, removed worktree, resumed correct #2368 worktree.
Prevention: when `/soleur:go resume #N` finds no matching worktree, list
nearby worktrees and confirm before creating a new one.

**Markdownlint heading-mangle.** Documented as the main subject of this
learning. Recovery: reworded prose. Prevention: see Solution above.

**Frontmatter schema drift.** Initial learning frontmatter used a non-conforming
schema (`title/category/source_session`). Caught by review. Prevention: read
one existing sibling in the same `learnings/<category>/` directory before
writing a new one.

**SKILL.md heading-level inversion.** Inserted `### CodeQL alert-state precheck`
between `##` siblings with no parent `##`. Caught by review. Prevention:
validate heading hierarchy after any insertion using `grep -E '^#+' <file>`
to confirm no level-skip.

**Committed 685KB raw `gh api --paginate` snapshot.** Verification.md only
needed the filtered 27KB version. Caught by review. Prevention: before
committing JSON dumps, ask "is this load-bearing or recreatable in <5 min via
a documented command?" Recreatable artifacts go in the runbook, not in git.

**Subshell counter loss in extended workflow.** New `close-orphans` job
faithfully copied a pre-existing `| while` subshell pattern from
`check-alerts`; the counters always print 0/0/0. Caught by
pattern-recognition agent. Recovery: rewrote both jobs with `done < <(...)`
process substitution per `wg-when-fixing-a-workflow-gates-detection`
retroactive application. Prevention: when extending a workflow file by
duplicating a job's pattern, scan the source pattern for known-buggy idioms
(piped subshell loops, unquoted vars, eager `set -e`) before duplicating.
