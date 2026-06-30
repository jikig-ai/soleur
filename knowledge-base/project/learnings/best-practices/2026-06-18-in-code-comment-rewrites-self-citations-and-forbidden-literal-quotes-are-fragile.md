---
title: In-code comment rewrites — self-relative line citations and forbidden-literal quotes are fragile against the same edit
date: 2026-06-18
category: best-practices
tags: [comments, line-citations, verification-grep, terraform, infra, drift]
issue: 5515
pr: 5516
---

# Learning: rewriting a heavily-cited in-code comment has two self-inflicted traps

## Problem

PR #5516 (fix #5515) rewrote the `terraform_data.deploy_pipeline_fix` comment block in
`apps/web-platform/infra/server.tf` to explain a new `depends_on` ordering edge. The
rewrite hit two distinct self-inflicted defects that a static-string suite + AC greps
caught only because they were checked explicitly:

1. **Self-relative line citation invalidated by its own insertion.** The new comment
   cited `server.tf:637` for the push `provisioner "local-exec"`. That cite was correct
   against `origin/main` — but the SAME comment-block rewrite inserted ~28 lines ABOVE
   the local-exec, shifting it to `:665`. The comment self-invalidated its own citation
   the moment it grew. (Caught by `architecture-strategist` at review, P2.) A sibling
   cite `server.tf:529` survived only because it sat ABOVE the insertion point.

2. **Verification grep false-match on a quoted forbidden literal.** The plan's AC2 was
   `grep -n "deliberately NO depends_on" server.tf` returns nothing (the old comment's
   phrase should be gone). The rewrite, while EXPLAINING that it was correcting that old
   rationale, quoted the literal phrase verbatim — so the absence-grep matched the new
   comment and the AC tripped. (Caught at AC-verify; reworded the quote.)

Adjacent one-offs the same edit produced: a duplicate `#1570` AppArmor note (re-added
inside the new block while the original line above remained), and an off-by-one cite
`:105-112` → `:106-112`.

## Solution

1. **Prefer a stable structural anchor over a self-file line number** when the comment
   you are writing lives in the same block whose size you are changing. Use
   `` the push's `provisioner "local-exec"` below `` instead of `server.tf:637`.
   Line numbers in a comment that cites OTHER files (or sits above all your insertions)
   are fine; a number that points DOWN past your own insertion is guaranteed to rot.

2. **Never quote, verbatim, a literal that a verification grep checks for ABSENCE.**
   When AC says `grep "<phrase>"` must return nothing, paraphrase the old phrase in the
   rewrite (`the earlier "no edge" rationale`), don't reproduce it. Same class as
   `[[2026-06-17-grep-assertion-over-script-body-false-matches-own-comments]]` (a body-grep
   sees comments too) — here it's the comment quoting the very token the grep forbids.

3. After rewriting any line-number-citing comment block, re-grep the cited lines
   (`grep -n 'provisioner "local-exec"'`) and confirm each citation still resolves.

## Key Insight

A comment block that both (a) cites line numbers in its own file and (b) is being grown
is a moving target that invalidates its own forward references. And a rewrite that
narrates the decision it replaces will trip any absence-grep that guards the old wording.
Both are cheap to prevent at write-time (stable anchors + paraphrase) and cheap to catch
(re-grep the cites + run the AC), but invisible to `tsc`/`terraform validate`/fmt.

## Session Errors

- **IaC-routing guard false-positives on `systemctl restart webhook` in plan prose** (forwarded from session-state) — Recovery: `<!-- iac-routing-ack -->` opt-out + reword. Prevention: existing ack mechanism; one-off per plan.
- **Worktree-cwd `ls` false-negative on `inngest-inventory.sh`** (forwarded) — Recovery: read from the worktree cwd. Prevention: one-off; always resolve paths from the worktree root.
- **AC2 absence-grep false-match on quoted forbidden literal** — Recovery: reworded the quote. Prevention: see Solution #2.
- **Duplicate `#1570` AppArmor note** — Recovery: removed the redundant line. Prevention: one-off; check the lines immediately above the block start before re-adding context.
- **Stale self-citation `server.tf:637`** — Recovery: stable anchor. Prevention: see Solution #1.
- **Off-by-one cite `:105-112` → `:106-112`** — Recovery: corrected. Prevention: one-off.

## Tags
category: best-practices
module: apps/web-platform/infra
