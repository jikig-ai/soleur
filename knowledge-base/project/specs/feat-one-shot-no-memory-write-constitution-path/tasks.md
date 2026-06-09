---
title: Tasks — Fix stale constitution path in no-memory-write hook
lane: single-domain
date: 2026-06-07
plan: knowledge-base/project/plans/2026-06-07-fix-no-memory-write-constitution-path-plan.md
---

# Tasks — Fix stale constitution path in no-memory-write hook

## 1. Core Implementation

- [x] 1.1 Edit `.claude/hooks/no-memory-write.sh` line 55: change the middle remediation
      bullet inside the `permissionDecisionReason` string from
      `knowledge-base/overview/constitution.md (architecture + style)` to
      `knowledge-base/project/constitution.md (architecture + style)`. Change only the
      `overview` → `project` token; preserve indentation, the trailing
      ` (architecture + style)`, and the rest of the `jq -n` payload verbatim.

## 2. Verification

- [x] 2.1 (AC1) `grep -c "knowledge-base/project/constitution.md (architecture + style)" .claude/hooks/no-memory-write.sh` → `1`.
- [x] 2.2 (AC2) `grep -rl "overview/constitution" .claude/hooks/` → empty (no live ref left).
- [x] 2.3 (AC3) `bash .claude/hooks/no-memory-write.test.sh` → `0 failed`, exit 0 (suite green, no test edit).
- [x] 2.4 (AC5) `git diff --name-only` lists only `.claude/hooks/no-memory-write.sh` (+ plan/tasks);
      `kb-domain-allowlist-guard.sh`, dated `knowledge-base/project/{plans,specs,brainstorms,learnings}/`
      files, `apps/web-platform` `overview/` refs, and `MEMORY.md` are all untouched.

## 3. Optional (default: skip)

- [x] 3.1 (AC4) Add regression assertion to T1 in `no-memory-write.test.sh`:
      `&& [[ "$reason" == *"knowledge-base/project/constitution.md"* ]]`. Only if explicitly
      desired — keeps the default diff to a single line otherwise.
