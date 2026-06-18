---
title: "Plan-prescribed cross-file drift guards must verify each file's actual token usage"
date: 2026-06-18
category: best-practices
tags: [drift-guard, infra, plan-vs-codebase, verify-commands, bash, acceptance-criteria]
modules: [apps/web-platform/infra]
issue: 5553
pr: 5556
---

# Plan-prescribed cross-file drift guards must verify each file's actual token usage

## Problem

The #5553 plan prescribed a cross-file drift-guard test asserting that **all three**
ExecStart-durability parsers (`ci-deploy.sh`, `inngest-wiped-volume-verify.sh`,
`inngest-inventory.sh`) reference **all four** load-bearing tokens (`--postgres-uri`,
`--redis-uri`, `inngest-redis.service`, `inngest-server.service`). AC5 listed three of
those tokens with the same "all three parsers" framing.

Grepping the actual files before writing the guard showed the prescription was wrong:
`inngest-wiped-volume-verify.sh` references only `--postgres-uri` + `inngest-server.service`
(0 occurrences of `--redis-uri` and `inngest-redis.service`). Its gate deliberately checks
"is postgres configured → refuse to wipe" and never parses redis. A guard requiring the full
4-token set on all 3 files would have **false-failed** on a correct codebase.

## Solution

Scope the guard per-file to the tokens each file genuinely shares:

- The **full** postgres+redis+active rule is shared only by the source-of-truth
  (`ci-deploy.sh`) and the new mirror (`inngest-inventory.sh`) → assert all 4 tokens on those.
- `inngest-wiped-volume-verify.sh` is a **secondary** family member → assert only the
  `{--postgres-uri, inngest-server.service}` subset it actually uses.

The tripwire intent (rename a flag in the source-of-truth → guard trips, forcing a re-look)
is preserved, and the guard no longer false-fails. Verified non-vacuous by mutation
(renaming `--redis-uri` trips it) — confirmed by the pattern-recognition reviewer.

## Key Insight

A plan is authoritative for **intent**, never for the **exact token/file set** of a drift
guard (same class as `hr-when-a-plan-specifies-relative-paths-e-g`). Before writing any
"all N files reference all M tokens" assertion, run `grep -cF -- "$tok" "$file"` for every
(file, token) pair and let the matrix define the guard. A family of parsers is rarely
homogeneous — secondary members share a subset.

Corollary — **plan-quoted verify commands are preconditions, not facts.** Two AC verify
commands in this plan produced false signals against a correct implementation:
- **AC10** (`git diff origin/main | grep -c 'ssh '` == 0): returned 5 — all non-code:
  self-referential prose in the plan/tasks (the AC text contains "ssh") + a branch-divergence
  artifact (origin/main edited a runbook the plan *cites* but does not edit). Scope the grep
  to the actual changed code files to get the real answer (0).
- **AC6** (`actionlint` exits 0): exits non-zero on pre-existing `SC2016:info` that is also
  present on `main` and is unsuppressible in actionlint's harness — and actionlint is not a
  CI gate here. Assert the *substance* (no errors/warnings; output written) not the literal
  exit code.

## Session Errors

1. **Plan Edit "File has been modified since read"** — a `sed` checkbox-flip mutated the file
   between the `Read` and a later `Edit`. Recovery: re-read the region, re-apply.
   **Prevention:** after any bulk `sed`/scripted edit to a file, re-Read before the next `Edit`.
2. **Workflow Edit matched 2 occurrences** — `EXISTING=$(gh issue list ... --search "$ISSUE_SEARCH" ...)`
   is shared verbatim with the pre-existing `inngest-down` issue step. Recovery: add a following
   line of context to target only the new step. **Prevention:** when editing one of several
   parallel issue-lifecycle steps in a workflow, anchor on a step-unique neighboring line.
3. **SOLEUR-DEBT Edit `old_string` not found** — the comment block contained unicode (`…`, `→`).
   Recovery: re-Read, anchor on an ASCII-only line. **Prevention:** prefer ASCII anchors when
   the target may contain smart-quotes/arrows, or copy the exact bytes from a fresh Read.

All three are one-off tool-interaction missteps with no recurrence vector beyond the
preventions noted; none warrant a hook.
