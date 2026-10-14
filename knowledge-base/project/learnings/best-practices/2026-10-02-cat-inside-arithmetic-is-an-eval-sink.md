---
title: "`$(cat file)` inside `$((...))` evaluates the file — sanitize reads that feed arithmetic"
date: 2026-10-02
category: best-practices
module: scripts/test-all-runtime-ceiling.test.sh
tags: [bash, arithmetic-injection, test-harness, sandbox-seam, epochseconds]
issue: 9402
pr: 9407
---

# Learning: a bare `$(cat …)` inside `$((…))` is an eval sink AND a syntax-error on empty

## Problem

The `SOLEUR_TC_BUMP_FILE` seam in the ceiling-test sandbox spliced this into
the sandboxed `_elapsed_s` computation:

```bash
_elapsed_s=$(( "${EPOCHSECONDS:-0}" - _RUN_START_EPOCH + $(cat "${SOLEUR_TC_BUMP_FILE:-/dev/null}" 2>/dev/null || echo 0) ))
```

Two latent defects, both verified live by review seats (security-sentinel
demonstrated the exec; test-design demonstrated the syntax error):

1. **The `|| echo 0` fallback never fires on the paths it documents.** `cat
   /dev/null` exits **0** with empty output — and so does `cat` of an empty
   bump file — leaving `… + )`, a bash arithmetic **syntax error**, not a +0.
   Under the sandboxed runner's `set -e` that aborts the run mid-suite with a
   cryptic `operand expected`. The comment claimed absent/unreadable → +0;
   only the nonexistent-file path actually did that.
2. **The file's bytes are evaluated as an expression, not read as a number.**
   Content `x[$(touch /tmp/pwned)]` executes the `touch` — bash runs array
   subscripts through the full evaluator inside `$((…))`. Content `10/0`
   aborts on division-by-zero; `abc` silently reads as 0. Harmless in this
   fixture (sandbox-only, per-arm mktemp path) — P3 here — but the same idiom
   in a production script is remote-eval-on-file-content.

## Solution

Sanitize before the arithmetic sees it:

```bash
_elapsed_s=$(( "${EPOCHSECONDS:-0}" - _RUN_START_EPOCH + $(b="$(cat "${SOLEUR_TC_BUMP_FILE:-/dev/null}" 2>/dev/null)"; [[ $b =~ ^[0-9]+$ ]] && printf %s "$b" || printf 0) ))
```

The `[[ =~ ^[0-9]+$ ]]` gate makes unset/absent/empty/non-numeric all read +0
with no shell error and no expression evaluation of file bytes. `$(…) `
command substitution also strips the trailing newline (`echo 120 >` writes
`120\n`), so the read survives the file's real shape.

## Key Insight

Two mistakes compounded on one line: an `|| fallback` guarding the wrong
failure mode (exit status of a successful-but-empty read), and a
content-to-`$((…))` path that treats file bytes as program text. Whenever a
file read feeds arithmetic — or any eval-adjacent context (`$((…))`, `[[ ]]`,
`let`) — gate the content with a format check first; never trust `cat`'s exit
code to mean "produced output".

**Prevention:** grep your own diffs for `$(cat` inside `$((` — any hit needs a
`^[0-9]+$` (or stricter) gate. Same rule as untrusted input into `test -n`:
the consumer's grammar is wider than the channel suggests.
