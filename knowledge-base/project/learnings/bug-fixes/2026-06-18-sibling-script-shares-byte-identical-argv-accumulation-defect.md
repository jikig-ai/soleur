---
title: "A shell-idiom defect's scope claim must be verified by grepping the idiom across sibling scripts"
date: 2026-06-18
category: bug-fixes
issue: 5523
pr: 5528
tags: [bash, jq, arg-max, pagination, scope-verification, infra]
---

# A shell-idiom defect's scope claim must be verified by grepping the idiom across sibling scripts

## Problem

`op=inventory` (`cutover-inngest.yml` → `inngest-inventory.sh`) failed on the live host with
HTTP 500: `jq: Argument list too long` at the eventsV2 pagination accumulation
`all_edges=$(jq -nc --argjson a "$all_edges" --argjson b "$page_edges" '$a + $b')`. Passing the
*running accumulator* as a single jq argv element overflows the kernel per-arg ceiling
(`MAX_ARG_STRLEN`, ~128 KB — NOT `getconf ARG_MAX` 2 MB, which is the total envp+argv ceiling)
once accumulated event volume crosses it. The unit tests passed because fixtures were tiny (1–2 edges).

The bug report asserted **"op=enumerate … unaffected."** That scope claim was **false**:
`inngest-enumerate-reminders.sh:126` carried the **byte-identical** accumulation idiom, paginates the
**same** eventsV2 edge set, and is a live cutover hook. Shipping only the inventory fix would have left
a known HTTP 500 on the sibling op (the re-arm safety path depends on enumerate succeeding).

## Solution

Replace the per-page argv accumulation with a `mktemp` spool file + a single post-loop
`jq -s 'add // []'` collapse (file I/O has no argv size limit), in **both** scripts. Clean the temp
file with an in-function `trap "rm -f '$edges_file'" EXIT` — **`EXIT`, not `RETURN`**: a `RETURN` trap
does not fire on `exit`, so the `exit 1` FATAL branches would leak the spool. Registering the trap
*inside* the function is safe for the sourced-by-test design because the `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`
guard means the function is never called when the script is sourced. Pattern precedent:
`plugins/soleur/skills/community/scripts/github-community.sh:294`.

## Key Insight

A feature description / bug report's "X is unaffected" scope claim is a **hypothesis, not a fact**.
When the defect is a copy-pasteable shell idiom (an argv accumulation, a `${VAR:-default}` flip, a
missing `set -e`, an unquoted expansion), **grep the byte-identical idiom across every sibling script
before trusting the scope** — `git grep -n '<exact idiom>' <dir>` returns the true work-list. Here it
returned exactly two hits (inventory + enumerate); the plan folded both into one PR. This is the
shell-script analogue of the "sweep-class fixes use grep-enumerated work-lists, not intuited ones"
rule already in `work/SKILL.md`.

## Session Errors

1. **Structural-guard grep matched its own explanatory comment.** The new `test_no_argv_accumulation`
   guard greps the script for the forbidden literal `argjson a "$all_edges"`; my in-script comment
   *describing* the old form contained that exact literal, so the guard FAILed (and AC4's
   `git grep` matched the comment too). — **Recovery:** reworded every comment to drop the bare
   literal (e.g. "the old per-page --argjson accumulation"); wrote the enumerate-side comments
   without the literal from the start. — **Prevention:** already documented as
   `test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md` — when
   adding a body-grep guard for a forbidden literal, never write that exact literal in a comment in
   the same file. One-off this session (recovered in two edits); no new rule needed.

## Tags
category: bug-fixes
module: apps/web-platform/infra
