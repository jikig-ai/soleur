---
title: CodeQL flags VERBOSE-mode regex comments as character classes — reword, don't dismiss
date: 2026-11-03
category: engineering
tags: [codeql, regex, false-positive, python, ci]
symptoms: [py/overly-large-range alert on a re.VERBOSE literal whose pattern contains no range, Alert message says "Suspicious character range that is empty" with no visible range in the pattern]
module: code-scanning
component: codeql-python-regex-model
problem_type: external-tool-false-positive
resolution_type: cosmetic-reword
severity: low
---

# CodeQL flags VERBOSE-mode regex comments as character classes — reword, don't dismiss

## Problem

CodeQL alert #222 (`py/overly-large-range`, medium) fired on
`scripts/lint-anthropic-content-position.py` `POSITIONAL` — a
`re.VERBOSE` triple-quoted literal whose *pattern* contains no character
class with a range. The alert location (line 33, columns 181-184) maps,
once the literal is flattened, to the trailing comment
`# [0] / [x.y.length-1]`: parsed as a char class, `x.y.length-1` yields
the range `h-1` — h (0x68) > 1 (0x31) — an **empty** range, matching the
alert's "Suspicious character range that is empty." message exactly.

CodeQL's Python regex model does not strip `re.VERBOSE` `#` comments
before parsing, so comment text that happens to look like `[x-1]` is
scored as pattern. `git blame` shows this class of alert is recurring
(alert #300 flagged `\x0a-\x1f` in the same scan).

## Fix

- **Comment-shaped text in VERBOSE literals must avoid `[...]`-shaped
  spans containing `<char>-<char>`**. Reword `# [0] / [x.y.length-1]` to
  `# literal index / x.y.length-1 index` — no brackets, no range parse,
  alert self-resolves on the next scan. Cheaper than a dismissal and
  keeps the "no operator sign-off needed" property.
- **Genuine ranges**: enumerate the set instead (`"".join(chr(c) for c
  in range(0x20) if c != 0x09)`) — byte-identical match set, nothing for
  the range query to flag. Mutant anchors in the covering suite must be
  re-anchored to the new constant shape or they report `edit-failed`.
- **Anchors**: `js/regex/missing-regexp-anchor` accepts `^...$` even in
  a deliberately-weakened fixture regex; anchoring per-alternative keeps
  the fixture's RED-row role.

## Prevention

When writing or reviewing `re.VERBOSE` literals in this repo, keep
bracket-shaped examples out of trailing comments — write `index
x.y.length-1`, not `[x.y.length-1]`.
