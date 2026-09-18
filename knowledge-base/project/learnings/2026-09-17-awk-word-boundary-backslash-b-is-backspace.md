---
date: 2026-09-17
category: machinery
module: shell-regex-portability
related:
  - .github/workflows/scheduled-devin-docs-drift.yml
  - scripts/devin-docs-drift-check.test.sh
  - scripts/lint-shell-capture-exit.py
---

# Learning: `\b` means BACKSPACE in awk regex, not word boundary — a silently dead pattern arm

## Problem

A keyword-matching arm in a workflow `run:` body was written as:

```awk
if (low ~ /\bhooks?\b|\bsubagents?\b|postcompaction|requiredplugins|\bplugins?\b/ && low ~ /cloud/)
```

The `\b` was added deliberately — `webhook` must not satisfy the `hook`
anchor (measured false-positive). The arm then silently matched NOTHING:
in POSIX awk (gawk, mawk, the `awk` on ubuntu-24.04 runners), `\b` in a
regular expression is the BACKSPACE character, not a word boundary. No
error, no warning — the pattern is just never true. A "word boundary" fix
applied to make matching *stricter* instead made the whole arm *dead*,
which is the worst direction for a guard: it fails silent and green.

grep and awk disagree here, which is the trap's recurrence mechanism:
`\b` IS a word boundary in GNU `grep -E` / `rg`, so the identical regex
works in the sibling `grep` arm of the same step and fails only in awk.
Regexes get copied between the two tools constantly.

## Solution

In awk, spell the boundary on the already-normalized buffer:

```awk
low ~ /(^|[^a-z])hooks?([^a-z]|$)|subagent|postcompaction|requiredplugins|plugin/
```

`(^|[^a-z])…([^a-z]|$)` is the portable word boundary once the input is
lowercased. Only `hook` needed it — `plugin`/`subagent` have no common
false-positive superstring, so they stay substrings (prefix forms like
`plugins`/`subagents` are intended hits). gawk's `\y` also works but is
not portable to mawk, which is what `awk` resolves to on Ubuntu runners.

## Why it was caught

`scripts/devin-docs-drift-check.test.sh` extracts the check step's `run:`
body verbatim and drives it against synthesized fixtures — including a
recent changelog entry that MUST produce `capability_entry`. It didn't.
A presence-grep or a docs-eyeball review would never have seen it; the
regex arm was load-bearing and had zero executable coverage until that
suite existed. This is the recurring pattern behind the repo's
fixture-suite convention: guards whose triggers live outside the repo
(third-party doc text here) can only be verified by driving them.

## Prevention

- When porting a regex from grep/rg to awk, re-check metacharacter
  semantics per-tool: `\b`, `\y`, `\<`/`\>`, and `{m,n}` intervals all
  differ across the three.
- For a conditional arm that must distinguish "fires" from "silent",
  a negative+positive fixture pair is the minimum viable check —
  asserted-then-verified, never grep-the-source.
