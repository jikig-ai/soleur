---
title: Tasks — fix(cc-permissions) cd allowlist + ../traversal + near-miss telemetry
plan: knowledge-base/project/plans/2026-05-05-fix-cc-readonly-os-commands-plan.md
issue: 3252
date: 2026-05-05
---

# Tasks — fix(cc-permissions): cd auto-approve + path-traversal + near-miss telemetry

Derived from `2026-05-05-fix-cc-readonly-os-commands-plan.md`. Three phases (RED → GREEN → REFACTOR) per AGENTS.md `cq-write-failing-tests-before`.

## Phase 1 — RED (failing tests)

- 1.1 Read existing fixture file `apps/web-platform/test/permission-callback-safe-bash.test.ts` to confirm imports, `buildContext` helper shape, `sdkOptions` helper, and `assertAllow` helper.
- 1.2 Add `describe("cd auto-approval (AC1)")` block with three commands (`cd`, `cd /tmp`, `cd src/components`, `cd ~`). Each emits two assertions: `isBashCommandSafe(cmd) === true` AND `canUseTool` returns allow with no review_gate.
- 1.3 Add `describe("cd near-miss rejection (AC2)")` block — `cdrecord`, `cdx`, `cd../etc`, `cd /etc/../tmp`.
- 1.4 Add `describe("path-traversal rejection (AC3)")` block — `ls ..`, `ls -la ../`, `cat ../foo`, `cat foo/..`, `cd ../`, `cd ..` (rejected). PLUS `cat foo/..baz` and `ls .` (allowed). The `..baz` and `.` rows are the boundary pins.
- 1.5 Add `describe("near-miss telemetry (AC5)")` block — mock `../server/observability`. Assert `warnSilentFallback` called once with `{ feature: "cc-permissions", op: "safe-bash-near-miss", extra: { leadingToken: <first-word> } }` for `lsof`, `cdrecord`, `pwdx`. Assert NOT called for `pwd`, NOT called for `curl x` (blocklist hit), AND assert `extra` does NOT contain the rest of the command (PII guard via `cat foo/..baz`-shaped fixture or `lsof -i :443`-shaped fixture asserting `:443` is absent).
- 1.5b (deepen-pass) Add TS5 — hidden-dotfile boundary block (10 fixtures). Verifies `.git`, `.gitignore`, `cat foo/.bashrc`, `cat my..backup.txt`, `cat ...gitignore` all auto-allow despite the path-traversal denylist. See plan §"Test Scenarios" TS5.
- 1.5c (deepen-pass) Add TS6 — `cd` regex + path-traversal interdependence block. Pins BOTH directions: (a) `cd ..`, `cd ../`, `cd /etc/../tmp` reject; (b) `cd`, `cd /tmp`, `cd ~`, `cd /` allow. See plan §"Test Scenarios" TS6.
- 1.5d (deepen-pass) Add TS7 — near-miss telemetry surface includes `lsblk`/`lsattr`/`lscpu`/`lsmod`/`lspci`/`lsusb`. Pins per-Risk R5. See plan §"Test Scenarios" TS7.
- 1.6 Run: `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts`. Confirm new tests in 1.2/1.4/1.5/1.5b/1.5c/1.5d fail (cd not allowed; ../ allowed; warnSilentFallback never called; lsblk-class not detected — though TS5 hidden-dotfile cases SHOULD already pass since dotfiles are not path-traversal). Expect: AC1, AC3, AC5, TS6, TS7 RED; TS5 likely already GREEN (sanity check).
- 1.7 Commit: `test(cc-permissions): RED — cd auto-approve, ../-traversal rejection, near-miss telemetry`.

## Phase 2 — GREEN (implementation)

### 2.1 Add `cd` regex

- 2.1.1 In `apps/web-platform/server/permission-callback.ts`, in the `SAFE_BASH_PATTERNS` array (currently lines 136-176), add `new RegExp(String.raw`^cd(?:\s+${PATH_TOKEN})?\s*$`)` adjacent to the `pwd` entry.
- 2.1.2 Run: `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts -t "cd auto-approval"`. AC1 tests now pass.

### 2.2 Path-traversal denylist

- 2.2.1 In `permission-callback.ts`, after `SHELL_METACHAR_DENYLIST` (line 120), add `const PATH_TRAVERSAL_DENYLIST = /(?:^|[\s/])\.\.(?:$|[\s/])/;` with the boundary-comment per plan §"Path-traversal denylist".
- 2.2.2 In `isBashCommandSafe`, add `if (PATH_TRAVERSAL_DENYLIST.test(command)) return false;` immediately after the `SHELL_METACHAR_DENYLIST` check.
- 2.2.3 Run: `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts -t "path-traversal"`. AC3 tests pass, including `..baz` allowed and `.` allowed.
- 2.2.4 Run full suite: `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts`. Confirm AC1, AC2, AC3, AC4 pass; existing TS1/TS2/TS3/edge-cases blocks still green.

### 2.3 Near-miss telemetry

- 2.3.1 In `permission-callback.ts` imports, add `import { warnSilentFallback } from "./observability";`.
- 2.3.2 Add `const SAFE_BASH_NEAR_MISS_PREFIX = /^(ls|pwd|cd|whoami|cat|head|tail|wc|file|stat|which|uname|git|echo)(\w)/;` near `SAFE_BASH_PATTERNS` (with the comment from plan §"Near-miss telemetry").
- 2.3.3 In the Bash branch of `createCanUseTool` (around line 448 — between the `isBashCommandSafe(command)` early-return and the cache-pre-gate `deps.bashApprovalCache?.allow(command)` check, i.e., step 3.5 in the §"Security Ordering Invariant" — DO NOT move earlier or later, see plan §Sharp Edges "Near-miss telemetry placement is load-bearing"), add the near-miss detection block:
  ```ts
  if (SAFE_BASH_NEAR_MISS_PREFIX.test(command)) {
    const firstWord = command.trim().split(/\s+/)[0];
    warnSilentFallback(null, {
      feature: "cc-permissions",
      op: "safe-bash-near-miss",
      extra: { leadingToken: firstWord },
    });
  }
  ```
- 2.3.4 Run: `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts -t "near-miss telemetry"`. AC5 tests pass.

### 2.4 Type-check + full lint

- 2.4.1 `bun run --cwd apps/web-platform typecheck` — verify no new TS errors.
- 2.4.2 `bun run --cwd apps/web-platform lint:eslint` (or per `package.json scripts` — confirm at task-time, do NOT hardcode the runner per plan-skill Sharp Edge).

### 2.5 Commit

- 2.5.1 `git add apps/web-platform/server/permission-callback.ts apps/web-platform/test/permission-callback-safe-bash.test.ts`
- 2.5.2 Commit: `fix(cc-permissions): GREEN — add cd, harden ../ traversal, wire near-miss telemetry`.

## Phase 3 — REFACTOR (conditional)

- 3.1 If duplicated mock-setup boilerplate exists across the new `describe` blocks, factor a `setupBashCanUseToolTest()` helper. Otherwise skip.
- 3.2 If `PATH_TRAVERSAL_DENYLIST` and `SHELL_METACHAR_DENYLIST` could share a clearer naming pattern (e.g., both as `RAW_INPUT_DENYLISTS = […] as const`), refactor — only if it improves readability without changing semantics.
- 3.3 Run full test suite one more time: `bun test apps/web-platform/test/`. All green.
- 3.4 If a refactor landed, commit: `refactor(cc-permissions): consolidate test setup`.

## Phase 4 — Compound + ship

- 4.1 Run: `skill: soleur:compound`. Capture any new learnings about the safe-Bash regex shape, near-miss-telemetry pattern, or stale issue-body line-number references.
- 4.2 Run: `skill: soleur:ship`. Set `semver:patch` label per existing PR labels (`bug`, `priority/p2-medium`, `semver:patch` already on issue #3252).

## Acceptance verification (pre-merge)

- [x] AC1: `cd`, `cd /tmp`, `cd src/components` all auto-approve with no review_gate.
- [x] AC2: `cdrecord`, `cdx`, `cd../etc` all reject from `isBashCommandSafe`.
- [x] AC3: `ls ..`, `cat ../foo`, `cd ..` reject; `cat foo/..baz`, `ls .` allow.
- [x] AC4: All COMPOUND_COMMANDS fixtures from existing test still reject.
- [x] AC5: `lsof`, `cdrecord`, `pwdx` invocations call `warnSilentFallback` with correct `leadingToken` and no command-content leakage to `extra`.
- [x] AC6: Test file extended with three new `describe` blocks, all green.

## Acceptance verification (post-merge)

None. Pure code change.
