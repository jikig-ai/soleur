---
title: "SAFE_TOOLS allowlist bypass: LS and NotebookRead skipped path validation"
date: 2026-03-20
category: security-issues
module: web-platform/agent-runner
tags:
  - path-traversal
  - allowlist-audit
  - defense-in-depth
  - tool-path-validation
severity: high
related_issues:
  - 891
---

# Learning: SAFE_TOOLS allowlist bypass -- LS and NotebookRead skipped path validation

## Problem

`apps/web-platform/server/agent-runner.ts` maintained a `SAFE_TOOLS` array of tool names that bypass `isPathInWorkspace` entirely. LS and NotebookRead were classified as safe, but both accept user-controlled path arguments. An agent could craft a path argument to read or list files outside the workspace boundary, bypassing the application-layer sandbox.

The root cause was category confusion: "safe" was used to mean "no security-sensitive inputs," but LS and NotebookRead have path parameters that are security-sensitive. They were likely added to SAFE_TOOLS because they are read-only, conflating "read-only" with "no path escape risk."

## Solution

1. **Extracted tool classification into a dedicated module** (`apps/web-platform/server/tool-path-checker.ts`) with three explicit categories:
   - `FILE_TOOLS` -- tools with path arguments that must pass `isPathInWorkspace` (Read, Write, Edit, Glob, Grep, Bash, **LS, NotebookRead, NotebookEdit**)
   - `SAFE_TOOLS` -- tools with genuinely no path-sensitive inputs (WebSearch, WebFetch, TodoRead, TodoWrite)
   - `UNVERIFIED_PARAM_TOOLS` -- parameter names not yet mapped to an extraction rule, triggering a runtime warning

2. **Moved LS and NotebookRead from SAFE_TOOLS to FILE_TOOLS**, so their path arguments are validated against the workspace boundary.

3. **Added NotebookEdit to FILE_TOOLS** for defense-in-depth -- it was not previously listed at all, which would have caused it to silently skip validation.

4. **Added a runtime warning** for unrecognized parameter names, ensuring new tools cannot silently bypass path validation without an explicit classification decision.

5. **30 test cases** (`apps/web-platform/test/tool-path-checker.test.ts`) covering classification, path extraction, negative-space invariants, completeness guards, adversarial inputs (null bytes, `..` sequences, protocol handlers), and integration with `isPathInWorkspace`.

## Key Insight

Every entry in a SAFE_TOOLS allowlist is an explicit bypass of the security perimeter. When auditing security boundaries:

1. **Enumerate the allowlist.** For each member, verify it genuinely has no security-sensitive inputs. "Read-only" is not the same as "safe" -- a read-only tool with a path argument is a path-traversal vector.

2. **Require explicit classification.** Tools should not default to "allowed" when unrecognized. The safe default is "denied" or "warned" -- make the developer opt a new tool into the bypass list with a conscious decision.

3. **Defense-in-depth at the application layer.** Even when an OS-level sandbox (containers, seccomp, chroot) provides containment, validate paths at the application layer. Sandboxes can be misconfigured, and application-layer checks catch bugs before they reach the sandbox boundary.

4. **Completeness guards in tests.** A test that asserts `FILE_TOOLS + SAFE_TOOLS covers all known tools` prevents future tools from silently falling through. Without this, adding a new tool to the runtime without updating the classification creates the same vulnerability class.

## Session Errors

1. **`npx vitest` failed with rolldown native binding error** -- the worktree had no `node_modules`. Fix: run `npm install` in the app directory before running tests. Worktrees do not share `node_modules` with the main checkout.

2. **`cd` changed working directory silently** -- subsequent commands ran in the wrong directory. Fix: always verify `pwd` before file writes or git commands, especially after `cd` in a prior step.

3. **Two review agents hallucinated a `settingSources` removal** -- they claimed agent-runner.ts had a deleted import that was never present. Fix: always verify agent claims against actual `git diff` state before acting on review feedback.

## Related

- `2026-02-16-inline-only-output-for-security-agents.md` -- security data exposure patterns (complementary: that learning covers output, this covers input validation)
- `2026-03-05-github-output-newline-injection-sanitization.md` -- same category (security-issues), similar pattern of untrusted input bypassing validation
- `2026-02-21-github-actions-workflow-security-patterns.md` -- broader security audit methodology for CI/CD surfaces
- Issue #877 / commit `37009b4` -- `fs.realpathSync` for symlink escape defense-in-depth (same security boundary, different attack vector)

## Tags
category: security-issues
module: web-platform/agent-runner
