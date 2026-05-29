# Learning: developing a command-detection hook recursively self-intercepts; review catches commit-shape gaps plan+work miss

## Problem

Fixing #4600 — `.claude/hooks/pre-merge-rebase.sh` (a PreToolUse gate that
intercepts `gh pr merge`) false-fired on plain `git commit`s whose message
*documented* the merge verb. The fix derives a `SCAN` string with quoted/heredoc
bodies blanked, then runs the existing anchor regex against `SCAN`.

Two non-obvious things surfaced:

1. **The hook intercepts the very commands you write to test it.** Running an
   ad-hoc Bash matrix that contained a literal `git push && gh pr merge 7`
   (a real chained-merge pattern *outside* quotes) caused the active hook to
   classify my own tool call as a merge and deny it ("BLOCKED: Uncommitted
   changes detected" — the worktree held the in-progress hook edit). The hook
   you are editing is live against your own shell.

2. **The quote-strip fix (plan + work) missed a commit shape that
   `test-design-reviewer` caught.** The issue documented `git commit -m
   "$(cat <<EOF … EOF)"` (heredoc *inside* quotes — handled by blanking the
   `"…"` span). But a *bare* `git commit -F - <<EOF … gh pr merge … EOF`
   heredoc has an unquoted body, so the verb at a line-start still tripped the
   `^` anchor. The branch was literally named `…-heredoc-fp`, yet the first
   implementation only covered the quoted-heredoc shape.

## Solution

1. **Test a command-detection hook only through committed fixture files.**
   Put every input containing the detected literal inside a `*.test.sh` file
   and invoke it as plain `bash .claude/hooks/<hook>.test.sh` — that command
   string carries no trigger pattern, so the hook does not fire on it. Never
   put the unquoted trigger literal in an ad-hoc Bash tool call.

2. **Blank heredoc bodies before quoted spans in the SCAN derivation**, using a
   perl `-0777` backreference that preserves the markers and everything after
   the closing delimiter (where a real chained merge lives):
   `s/(<<-?\s*["']?)(\w+)(["']?)(.*?)(\n[ \t]*\2\b)/$1$2$3$5/gs` then the
   double/single-quote strips. Fails toward firing (a real merge after the
   terminator still matches). Covered by T-FP4 (bare heredoc ⇒ no-intercept)
   and T8 (merge-after-heredoc ⇒ still fires).

## Key Insight

- A guard hook that pattern-matches a command literal is **live against the
  agent's own shell while you develop it** — keep the literal out of unquoted
  ad-hoc commands; drive tests through committed fixtures.
- For a "documents-the-verb" false-positive class, enumerate *every* commit
  message-carrying shape: `-m "…"`, `-m '…'`, multi-line `-m`, `-m "$(cat
  <<EOF)"` (heredoc-in-quotes), AND bare `-F - <<EOF` (heredoc-no-quotes). The
  issue text named the first four; the fifth is the gap `test-design-reviewer`
  reliably surfaces by reconstructing the pre-fix hook and replaying each shape.

## Session Errors

1. **Command-detection hook self-intercepted a test probe.** An inline Bash
   matrix with an unquoted `git push && gh pr merge 7` was denied by the live
   `pre-merge-rebase.sh`. — Recovery: route all trigger-literal test inputs
   through committed `*.test.sh` files run via plain `bash …test.sh`. —
   Prevention: never place a command-detection hook's trigger literal, unquoted,
   in an ad-hoc Bash command while developing/testing that hook.
2. **Plan-file Edit failed with "File has been modified since read"** after an
   earlier `sed -i` on the AC checkboxes mutated the file post-read. — Recovery:
   re-Read the section, retry the Edit. — Prevention: re-Read a file after any
   `sed -i` / external mutation before the next Edit.
3. **Edit "String to replace not found"** on the PR_NUMBER comment — assumed a
   `|| true` suffix that did not exist and the line had shifted after prior
   edits. — Recovery: grep the exact current line, re-Read, retry. — Prevention:
   grep/Read exact current content before constructing `old_string` once a file
   has had several edits.

## Tags
category: integration-issues
module: .claude/hooks
issue: 4600
