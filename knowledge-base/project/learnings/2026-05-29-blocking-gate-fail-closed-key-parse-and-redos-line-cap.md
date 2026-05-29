---
title: "Blocking gates: fail-closed key-parse + line-length cap on per-line regex rules"
date: 2026-05-29
category: security-issues
module: plugins/soleur/skills/frontend-anti-slop (tier1-scan.ts)
tags: [blocking-gate, fail-open, redos, regex, scanner, review-caught, single-source]
severity: P1
---

# Learning: making a deterministic blocking gate actually block

## Problem

PR #4646 made the frontend-anti-slop scanner's brand findings BLOCKING (exit
non-zero) so off-brand hex can't ship. Multi-agent review caught a **P1
fail-open** in the new `computeExitCode` before merge:

```ts
// selector is `${relPath}#${rule.id}` — rule.id is the LAST #-segment
const ruleId = f.selector.split("#")[1];   // ← takes the SECOND segment
```

A scanned file path legally containing `#` (e.g. `app/we#ird/x.tsx`) yields
selector `app/we#ird/x.tsx#BRAND-RAW-HEX`; `split("#")[1]` = `"ird/x.tsx"`, the
rule-id lookup misses, and the gate returns **exit 0** on a real brand/high
finding. The gate silently passes in exactly the case it exists to block.

A second review finding (P2): the brand `BRAND-WHITE-ON-GOLD` regex was O(n²) on
a long single line (minified `.css` is in-scope), so one large committed/vendored
CSS file could stall the scanner — and since the scanner now gates merges, stall
the review pipeline.

## Solution

1. **Parse a gate's decision key fail-closed.** Derive the key from the LAST
   delimiter, never a positional split, when the delimiter can appear in the
   data:
   ```ts
   const ruleId = f.selector.slice(f.selector.lastIndexOf("#") + 1);
   ```
   A malformed (no-`#`) selector then falls through to non-blocking — acceptable
   for malformed input, but the common `#`-in-path case now resolves correctly
   (verified: `#`-in-path brand/high → exit 1).
2. **Cap line length before any per-line regex `.test()`.** A scanner that runs
   `rule.pattern.test(line)` over arbitrary source must bound input so one
   pathological line can't hang it (defends ALL present + future rules):
   ```ts
   const MAX_SCAN_LINE = 2000;
   const lineToTest = line.length > MAX_SCAN_LINE ? line.slice(0, MAX_SCAN_LINE) : line;
   ```
3. **A "single source of truth" regex must gate EVERY entry point.** The path
   regex was unified for `defaultPaths()` but `expandPaths()` still used a bare
   extension filter → scope drift (it admitted `.ts` outside the declared
   `server/` scope). Fix: route `expandPaths` output through the same
   `new RegExp(DEFAULT_PATH_RE_SOURCE)`. Don't unify one caller and leave the
   sibling on a parallel definition.

## Key Insight

"Deterministic gate" is only as strong as its weakest parse. Two failure shapes
recur: (a) **fail-open key extraction** — positional `split(delim)[N]` is
fail-open whenever `delim` can appear earlier in the matched data; use
`lastIndexOf`/anchored capture and prefer fail-closed on malformed input for a
SECURITY gate (but here non-blocking-on-malformed was the accepted call since the
selector is internally constructed); (b) **unbounded per-line regex** is a DoS
surface the moment the gate consumes attacker-or-incidentally-large input — cap
line length once, centrally. Both were caught by post-implementation multi-agent
review, not by the 41 unit tests written first — the tests asserted canonical
inputs; the adversarial `#`-in-path and 300KB-line cases came from the security
lens. Reusable across any line-scanning gate (lint rules, log scrubbers,
secret scanners).

## Session Errors

1. **Blocking-gate fail-open via positional `split("#")[1]`** — Recovery:
   `lastIndexOf`-based parse; verified `#`-in-path → exit 1. Prevention: gate
   decision keys parse fail-closed, never positional split on a delimiter that
   can occur in the data.
2. **`expandPaths` scope drift past the single-source regex** — Recovery:
   post-filter through `DEFAULT_PATH_RE_SOURCE`. Prevention: a unified regex must
   gate all entry points, not one.
3. **Absence-check bash idiom false-positive** (`git diff | head -1 && echo FAIL`
   — `head -1` exits 0 on empty input, firing the FAIL branch). Recovery: re-ran
   with `grep -c … = 0`. Prevention: use a count (`grep -c`) for absence checks,
   not `head -1 &&`.
