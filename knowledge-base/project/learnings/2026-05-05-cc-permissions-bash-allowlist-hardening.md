---
title: "cc-permissions safe-Bash allowlist: cd + path-traversal + near-miss telemetry hardening"
date: 2026-05-05
module: cc-permissions
problem_type: security_issue
component: typescript_module
symptoms:
  - "Command Center modal-prompts every cd <dir>"
  - "Path-traversal `cat ../../etc/passwd` auto-approves at canUseTool boundary"
  - "Near-miss commands (lsof, cdrecord, pwdx) silently fall through to review-gate without drift signal"
root_cause: "missing allowlist entry + missing path-traversal denylist + missing drift telemetry"
severity: high
tags: [cc-permissions, canUseTool, bash, path-traversal, sentry, review-driven-hardening]
issue: 3252
pr: 3277
---

# cc-permissions safe-Bash allowlist: cd + path-traversal + near-miss telemetry hardening

## Problem

Issue #3252 reported that read-only OS commands (`ls`, `pwd`, `cwd`) prompted for approval in Command Center. The investigation pointers in the issue body assumed:
- The gate lived at `agent-runner.ts:261-346` — STALE (gate moved to `permission-callback.ts:createCanUseTool` per #2335)
- The fix was a "new exact-match allowlist" — STALE (a safe-Bash allowlist already shipped from a prior 2026-04-29 plan)

Three of the four named commands (`ls`, `pwd`, `whoami`) already auto-allowed. Only `cd` was missing. `cwd` is not a real Unix utility.

But surveying `permission-callback.ts:isBashCommandSafe` revealed two latent gaps:

1. `PATH_TOKEN` (the regex shape for path args) accepted `..` — `cat ../../etc/passwd` auto-allowed at canUseTool. Bubblewrap was the only remaining defense; defense-in-depth was a single layer for Bash absolute/relative paths outside the workspace.
2. No drift telemetry on near-miss rejections (`lsof`, `cdrecord`, `pwdx`). Future widening drift would be invisible.

## Solution

Three coordinated changes in `apps/web-platform/server/permission-callback.ts`:

1. **Add `cd` regex** to `SAFE_BASH_PATTERNS`:
   ```ts
   new RegExp(String.raw`^cd(?:\s+(?!-)${PATH_TOKEN})?\s*$`),
   ```
   The `(?!-)` negative lookahead rejects flag args (`cd -`, `cd -P`). PATH_TOKEN's bare permissiveness for `-` would otherwise accept them.

2. **Add `PATH_TRAVERSAL_DENYLIST`** plumbed before per-pattern allowlist:
   ```ts
   const PATH_TRAVERSAL_DENYLIST = /(?:^|[\s/])\.\.(?:$|[\s/])/;
   ```
   Matches `..` only as a parent-dir segment (boundary-anchored). Filenames like `..baz`, `my..backup.txt`, `...gitignore` remain allowed. Runs in `isBashCommandSafe` BEFORE the per-pattern loop, since `cd`/`cat`/`ls` regexes accept `../` by token shape.

3. **Wire near-miss telemetry** at step 3.5 of the Bash branch (after allowlist miss, before batched-approval cache):
   ```ts
   if (SAFE_BASH_NEAR_MISS_PREFIX.test(trimmedCmd)) {
     const leadingToken = trimmedCmd.split(/\s+/)[0].slice(0, 32);
     // ...per-ctx dedupe + 32-event budget...
     warnSilentFallback(null, {
       feature: "cc-permissions", op: "safe-bash-near-miss",
       extra: { leadingToken },
     });
   }
   ```

After parallel review surfaced additional concerns (P2 findings), a hardening pass added:
- **leadingToken length cap** (32 chars) to bound PII surface from glued tokens (`catatonic_password_dump_with_secret`).
- **Per-(canUseTool ctx) dedupe + 32-event budget** via WeakMap to bound Sentry flood under prompt-injected loops.
- **Single source of truth** (`SAFE_BASH_VERBS` array) deriving both `SAFE_BASH_PATTERNS` documentation and `SAFE_BASH_NEAR_MISS_PREFIX` to eliminate verb-list drift.
- **Inline `isBashCommandNearMiss`** at the call site (was exported but used once, not directly tested).
- **Extend `SHELL_METACHAR_DENYLIST`** to `[\x00-\x1f\x7f]` to seal C0/NUL/DEL log-injection surface.

## Key Insight

**For canUseTool boundary checks against Bash, `extractToolPath` does NOT apply.** Bash uses `toolInput.command`, not `toolInput.file_path`/`toolInput.path`. The `isFileTool → isPathInWorkspace` defense-in-depth pattern is silent for Bash invocations. The path-traversal denylist on the raw command string is the only canUseTool-boundary check against parent-dir traversal; the bubblewrap sandbox (`agent-runner-sandbox-config.ts`) is the OS-syscall-boundary check. Both are required per `2026-03-20-canuse-tool-sandbox-defense-in-depth.md`.

**Telemetry on rejection paths needs PII guards AND flood guards from day one.** Three independent defenses:
1. Length cap on logged token (caps glued-no-space PII leakage)
2. Per-conversation dedupe (caps repeat-token cost)
3. Per-conversation budget (caps unique-token flood)

WeakMap keyed by ctx is the right shape — state auto-clears when conversation ends, no manual reset needed.

**Verb lists in security-relevant code should derive from a single source.** `SAFE_BASH_NEAR_MISS_PREFIX` initially hardcoded a verb list that diverged from `SAFE_BASH_PATTERNS` (missing `id`, `date`, `hostname`). Single `SAFE_BASH_VERBS` array consumed by both — adding a verb stays one-edit.

## Prevention

- When adding ANY new arg-taking allowlist verb that uses `PATH_TOKEN`, pin a `-` flag-rejection test (PATH_TOKEN accepts leading `-` due to its char class).
- When adding telemetry on a rejection path, include from day one: length cap on logged content, per-conversation dedupe, per-conversation budget.
- When introducing a verb-derived security regex, derive from a `const VERBS = [...] as const` array, not a hand-edited alternation literal.
- For Bash canUseTool checks, do NOT rely on `extractToolPath`/`isPathInWorkspace` — those are file-tool-only. Add explicit traversal/path defenses at the command-string level.

## Session Errors

1. **`cd -` regex false-allow** — initial `cd` regex `^cd(?:\s+${PATH_TOKEN})?\s*$` accepted `cd -` because PATH_TOKEN's char class `[\w./~+:=@-]+` includes `-`. **Recovery:** RED test fired; added `(?!-)` negative lookahead. **Prevention:** When adding any new arg-taking allowlist verb that uses `PATH_TOKEN`, pin a `-` flag-rejection test fixture.
2. **Pre-existing vitest parallel flake on unrelated test files** — `ws-protocol`, `ws-usage-update`, `with-user-rate-limit`, `ws-abort` fail intermittently in full-suite parallel runs but pass in isolation. **Recovery:** confirmed via 4-file isolation (59/59 pass); this PR did not introduce it. **Prevention:** file a tracking issue for the cross-file vitest flake; do not normalize a red full-suite run.
3. **Background `vitest --no-file-parallelism` slow** — the no-parallelism full app run did not complete within usable timeout. **Recovery:** killed; re-confirmed via parallel run + isolation. **Prevention:** avoid `--no-file-parallelism` for full app runs; isolate the suspected files instead.
4. **Forwarded from session-state.md: Task tool unavailable in nested subagent (deepen-plan)** — deepen ran inline rather than fanning out to research subagents. **Recovery:** appropriate for tight bug-fix scope. **Prevention:** environmental; deepen handles this gracefully.
5. **Forwarded from session-state.md: Initial Node regex syntax error in deepen harness** — caught at write time. **Recovery:** fixed before final results. **Prevention:** self-discoverable via runtime error.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-05-fix-cc-readonly-os-commands-plan.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md`
- Bundle spec: `knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md`
- Prior allowlist plan: `knowledge-base/project/plans/2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md`
- Defense-in-depth invariant: `knowledge-base/project/learnings/security-issues/2026-03-20-canuse-tool-sandbox-defense-in-depth.md` (referenced; verify path)
- AGENTS.md rules invoked: `cq-silent-fallback-must-mirror-to-sentry`, `cq-write-failing-tests-before`, `hr-weigh-every-decision-against-target-user-impact`
- PR #3277, Issue #3252, Sibling bundle: #3250 (P1), #3251 (P2), #3253 (P3)
