---
module: System
date: 2026-04-11
problem_type: best_practice
component: tooling
symptoms:
  - "Branch names with special characters reach git/GitHub API producing cryptic errors"
  - "Single regex cannot express all 10 git ref format rules without catastrophic backtracking"
root_cause: missing_validation
resolution_type: code_fix
severity: medium
tags: [git, branch-validation, security, extraction-pattern, defense-in-depth]
---

# Learning: Git Ref Format Validation Requires Multi-Check Approach

## Problem

The `push-branch.ts` and `create_pull_request` tool handlers accepted any string as a branch name, relying on git/GitHub API to reject invalid refs. This produced cryptic error messages and missed defense-in-depth validation.

A single regex was initially proposed but cannot express all 10 git `check-ref-format` rules. Component-level rules (`.lock` suffix, `.` prefix per path segment) and the `@{` sequence require either catastrophic backtracking or separate checks.

## Solution

Created `branch-validation.ts` as a standalone module with zero heavy dependencies, following the established security extraction pattern (`sandbox.ts`, `error-sanitizer.ts`, `tool-path-checker.ts`).

The `validateBranchFormat()` function uses a series of sequential checks, each mapping to one git ref format rule:

1. Empty/length check (max 255)
2. Single `@` rejection (rule 9)
3. Leading/trailing `/` (rule 6)
4. Trailing `.` (rule 7)
5. `..` anywhere (rule 3)
6. `//` consecutive (rule 6)
7. `@{` sequence (rule 8)
8. Banned characters regex: control chars, space, `~^:?*[]\` (rules 4+5+10)
9. Component-level: starts with `.` or ends with `.lock` (rule 1)

Integrated at two call sites:
- `push-branch.ts`: called before `validateBranchName` (protected-branch check)
- `agent-runner.ts` `create_pull_request`: validates both head and base, plus rejects head === base

## Key Insight

When validating against a spec with component-level rules (per path segment, per suffix), a single regex becomes unmaintainable. A series of O(n) checks with descriptive error messages per rule is clearer, faster, and easier to test. Each check maps to one rule in the spec, making audits trivial.

The security extraction pattern (standalone module, zero heavy deps) enables unit testing in milliseconds without mocking SDK/Supabase, and makes the validation reusable across tool handlers.

## Session Errors

**1. Worktree branched from stale main** -- The worktree was created from a `main` that predated PR #1925 (CI/CD integration merge). All source files were missing until `git merge origin/main`. **Recovery:** Ran `git merge origin/main` after discovering files were absent. **Prevention:** The worktree-manager script should `git fetch origin && git merge origin/main` before branching. Consider adding a freshness check to worktree creation.

**2. Git add with wrong CWD** -- Ran `git add apps/web-platform/server/...` from `apps/web-platform/` directory, causing "pathspec did not match" because paths were relative to repo root. **Recovery:** Used paths relative to current directory. **Prevention:** Always verify CWD before `git add` or use absolute paths. The Bash tool's CWD persists between calls — track it explicitly.

## Related

- `knowledge-base/project/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` (sandbox.ts extraction pattern)
- `knowledge-base/project/learnings/integration-issues/mcp-adapter-pure-function-extraction-testability-20260329.md` (pure function extraction for testability)
- `knowledge-base/project/learnings/2026-04-10-cicd-mcp-tool-tiered-gating-review-findings.md` (mock URL assertion pattern)

## Tags

category: best-practices
module: System
