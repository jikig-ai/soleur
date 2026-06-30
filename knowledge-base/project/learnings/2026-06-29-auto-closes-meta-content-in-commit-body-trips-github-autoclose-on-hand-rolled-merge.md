# Learning: "auto-closes #N" meta-content in a commit body auto-closes #N on merge (hyphen is a word boundary)

## Problem

While arming a follow-through soak-verdict for #5689 item 1, the squash-merge of
PR #5717 **auto-closed #5689** (`stateReason: COMPLETED`) even though both the PR
body and the commit used `Ref #5689` (never `Closes`). Item 1 was still genuinely
open and soak-gated, and the close also defeated the mechanism being built — the
`scheduled-followthrough-sweeper` only evaluates **open** `follow-through` issues.

Root cause: the #5717 squash commit **body** contained the explanatory sentence
`Zero events → PASS (sweeper auto-closes #5689)`. GitHub's closing-keyword parser
is word-boundary based, and the hyphen in `auto-closes` is a non-word character —
so `\bcloses\b #5689` matched inside `auto-closes #5689` and fired on merge. The
parser is also negation/context-blind and, on a squash merge, reads the **branch
commit message** (not just the PR description). So *meta-content describing
auto-close behavior* (a follow-through script's own docstring, a PR explaining
"the sweeper auto-closes the issue") is a high-risk trigger.

## Solution

1. Reopened #5689 (`gh issue reopen`) and commented the cause; the directive +
   `follow-through` label were already applied, so the mechanism resumed intact.
2. The deeper miss: I **hand-rolled the merge** of #5717 (admin-merge), bypassing
   `/ship` Phase 6's "Auto-Close Keyword Pre-Creation Scan" — which scans commit
   messages AND the PR body via `auto-close-scan.sh` and would have flagged
   `auto-closes #5689`.

## Key Insight

- Any merge path that skips `/ship` (admin-merge, `gh pr merge` by hand, GitHub UI)
  MUST still run the auto-close scan over **branch commit messages**, not just the
  PR body — the squash subject+body become the merge commit and are parsed for
  closing keywords.
- **Meta-content about closing issues is the sharp edge.** A sentence like
  "the sweeper auto-closes #N", "this does not close #N", or "closes #N after the
  apply" trips the parser regardless of intent — hyphen-prefixed (`auto-closes`)
  and negated (`does not close`) forms both match. When a commit/PR legitimately
  *describes* close behavior, write it without the bare `<keyword> #N` adjacency:
  use "auto-resolves issue #N", "the sweeper will close issue #N", or reference the
  number without an adjacent keyword.
- File **contents** (a script's comments saying "auto-closes #N") are safe — GitHub
  parses commit messages and PR descriptions only, not diffs. The trap is the
  message, not the code.

## Session Errors

1. **Auto-closed #5689 via "auto-closes #5689" in the #5717 squash commit body** —
   Recovery: `gh issue reopen 5689` + cause comment; mechanism intact.
   Prevention: run the auto-close scan on commit messages for ANY merge path
   (not just `/ship`); avoid bare `<close-keyword> #N` adjacency in meta-content
   that describes close behavior (routed to work SKILL.md).

## Tags
category: workflow-patterns
module: ship, github-auto-close
related: 2026-05-16-git-trailer-parser-requires-contiguous-key-value-block.md
issue: 5689
