---
date: 2026-07-01
category: test-failures
module: testing
issue: 5754
tags: [grep, ugrep, ci-vs-local, bre, bash-tests, portability]
---

# Learning: the host `grep` is ugrep — use `grep -F` for literal-match test assertions, or CI's GNU grep fails what passed locally

## Problem

`scripts/domain-model-drift.test.sh` passed 40/40 locally and 131/131 in the local
`TEST_GROUP=scripts` shard, but the CI `test-scripts` required check **failed** on exactly two
assertions:

```
FAIL: T13b: leading ## not neutralized
FAIL: T13c: pipe not escaped
```

Both asserted the SUT's markdown-escaped output with a **BRE regex** grep:

```bash
grep -q '\#\# injected' "$reg"   # T13b
grep -q 'left \| right' "$reg"    # T13c
```

The escaping was correct — `cat -A` confirmed the file contained the literal bytes
`\#\# injected heading` and `left \| right`. Only the *assertions* were the problem.

## Root cause

The interactive/agent host aliases `grep` to **ugrep** (`grep --version` → `ugrep 7.5.0`).
CI (GitHub Ubuntu runners) uses **GNU grep**. The two diverge on how BRE interprets
backslash-escaped punctuation: `\#` and `\|` in a Basic-Regexp pattern are handled
differently (ugrep matched the literal-ish form; GNU grep did not), so a `grep -q` assertion
that matches under ugrep can fail under GNU grep and vice-versa. Local green is therefore NOT
authoritative for these patterns — the CI `test-scripts` gate is.

## Solution

Assert literal escaped output with **`grep -qF`** (fixed-string), which is POSIX-deterministic
and identical across ugrep and GNU grep:

```bash
grep -qF '\#\# injected' "$reg"   # matches the exact bytes, no regex interpretation
grep -qF 'left \| right' "$reg"
```

## Key Insight

When a bash test asserts a string the SUT produced that **contains regex-significant
punctuation** (`\`, `|`, `#`, `.`, `*`, `[`, `(`, `$`), reach for `grep -F` (or `grep -qF`)
unless you specifically need a regex. Reserve regex grep for genuine patterns, and when you do
use it, prefer `grep -E` (ERE, more consistent across implementations) over default BRE for
anything with backslash-escapes. A green local run under ugrep does not prove the assertion
passes under CI's GNU grep — the divergence is silent and only surfaces at the CI required
check. Cheapest guard: default test assertions over literal SUT output to `-F`.

## Tags
category: test-failures
module: testing
