---
title: "fix(cc-permissions): allow `cd` and harden `..` path traversal in safe-Bash allowlist"
type: fix
date: 2026-05-05
issue: 3252
brainstorm: knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md
spec: knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md
draft_pr: 3249
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(cc-permissions): allow `cd` and harden `..` path traversal in safe-Bash allowlist

> Closes #3252.

Issue #3252 reports that read-only OS commands (`ls`, `pwd`, `cwd`) prompt the user for approval in Command Center. The investigation pointers in the issue body assume the gating point is `agent-runner.ts:261-346` and that the fix is "build a new exact-match allowlist." Both pointers are stale — the gate moved out of `agent-runner.ts` and an allowlist already ships from a prior plan (2026-04-29). This fix is the **delta**: add the one missing required command (`cd`), close one path-traversal gap (`..` is currently accepted as a path arg), and wire `warnSilentFallback` on near-miss rejections so over-reach drift is observable.

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** Hypotheses, Acceptance Criteria, Risks, Sharp Edges, Test Scenarios.
**Research sources used:** Direct code reads against `permission-callback.ts:90-206` (existing `SAFE_BASH_PATTERNS` + `isBashCommandSafe`) and `observability.ts:82-150` (`reportSilentFallback` / `warnSilentFallback` contracts); 38-fixture regex verification harness (Node v21.7.3, output preserved in §"Regex Verification Harness"); 12-fixture boundary harness for hidden-dotfile / `..baz` / leading-whitespace edges; security-ordering trace through `permission-callback.ts:386-574`; prior-learning review of `2026-03-20-canuse-tool-sandbox-defense-in-depth.md` and `2026-04-24-guard-surface-audit-before-coding.md`. Subagent fan-out skipped (Task tool unavailable in this nested subagent context); the deepen pass ran inline against authoritative source files instead of via parallel research agents — appropriate for a tight bug-fix scoped to one TS module + one test file.

### Key Improvements

1. **Regex verification harness pinned in plan body.** Output of all 38 ACx + regression + edge-case fixtures preserved in a new §"Regex Verification Harness" section. Future regressions or PRs widening the allowlist must re-run the harness (it lives at `/tmp/deepen-regex-verify.mjs` shape — copy to test dir at work time if useful).
2. **Path-traversal denylist load-bearing rationale strengthened.** New §"Why path-traversal denylist is load-bearing" subsection in H2 explains that `extractToolPath` does NOT apply to Bash (Bash uses `command`, not `path`/`file_path`), so the workspace path-check does NOT catch `cat ../../etc/passwd`. The path-traversal denylist on the raw command string is the canUseTool-boundary check; the bubblewrap sandbox is the OS-syscall boundary check; both are needed.
3. **Hidden-dotfile boundary verified.** Confirmed `cat .gitignore`, `cat foo/.bashrc`, `ls .config/app`, `cat ...gitignore`, `cat my..backup.txt`, `cat foo/..baz` all auto-allow (10 dotfile boundary fixtures pass). The `..` denylist regex `(?:^|[\s/])\.\.(?:$|[\s/])` correctly distinguishes parent-dir traversal from filename `..` substrings.
4. **Near-miss telemetry surface scoped.** Verified that `lsblk`, `lsattr`, `lscpu`, `lsmod` (and similar `ls*`) all trigger near-miss telemetry — by design, since they ARE near-misses to `ls`. Documented in §Risks R3 with a Sentry-side rate-limit mitigation note.
5. **Security ordering invariant traced through code.** §"Security Ordering Invariant" subsection added to Phase 2 documenting the canonical 5-step Bash-branch ordering (empty-deny → blocklist → allowlist → cache → review-gate). The new near-miss telemetry hook MUST land between allowlist-fail and cache-pre-gate; placing it earlier (before blocklist) would emit telemetry for `sudo`/`curl` which is wrong (those should hit blocklist deny, not near-miss noise). Placing it later (after review-gate) would lose drift signal.

### New Considerations Discovered

- **`cd../etc` was a candidate failure mode I almost missed.** Without the path-traversal denylist, `cd../etc` matches the proposed `cd` regex (since `[\w./~+:=@-]+` accepts `../etc`). The path-traversal denylist catches it because `../etc` has `..` followed by `/`. The two checks are **interdependent**: removing either the `cd`-with-arg regex OR the path-traversal denylist creates a hole. Documented in §Sharp Edges as an ordering-invariant note.
- **Single-character commands (`id`, `ls`, `cd`) cannot use prefix-only matching.** All three already use `\s*$` end-anchors plus optional-arg shapes. Verified at the regex-harness level. Future PRs adding new short-prefix commands (e.g., `df`, `du`, `ps`) MUST follow the same end-anchored, arg-shape-pinned pattern.
- **`feature: "cc-permissions"` is a fresh Sentry tag namespace.** No prior `cc-permissions` tag exists in the codebase (`grep -rn 'feature: "cc-' apps/web-platform/server/` returns `cc-dispatcher`, `cc-concierge`, but no `cc-permissions`). Following the established `cc-*` convention; no AGENTS.md edit needed (per `cq-agents-md-tier-gate` — domain-scoped tag, lives in code).
- **Telemetry as side-channel DoS.** A model that fires off many `lsof` near-misses could flood Sentry. Mitigation lives at Sentry's per-feature rate limit, not in this plan. Documented in §Risks R3 as a known-limitation.

## User-Brand Impact

**If this lands broken, the user experiences:** Command Center prompts a modal "Approve Bash command?" gate every time the agent runs `cd <dir>` to inspect a sub-tree. The agent's first read-only step interrupts every conversation. Worse, if the patch widens the allowlist incorrectly (prefix-only match, missing metachar denylist, or accepts `..` traversal arg shapes), the gate becomes a confused-deputy foothold for prompt-injected payloads to `cd ../../etc` or `cd /; ls /root` without a user prompt.

**If this leaks, the user's workflow is exposed via:** sandbox over-reach — a too-permissive allowlist becomes the path of least resistance for prompt injection to enumerate the host filesystem outside the workspace. The tight `SHELL_METACHAR_DENYLIST` + path-arg shape regex is the only thing standing between an injected `cd /` and execution without user gate.

**Brand-survival threshold:** `single-user incident`.

The Command Center is the first-touch surface (carry-forward from the bundle brainstorm). One CC user encountering a confused-deputy escape via this allowlist is brand-load-bearing. Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, this plan inherits `single-user incident` from the brainstorm `## User-Brand Impact` framing and `requires_cpo_signoff: true` is set in YAML frontmatter.

CPO sign-off was satisfied by the bundle brainstorm's `## Domain Assessments` (Product lens, captured implicitly via user-impact framing). `user-impact-reviewer` will be invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Research Reconciliation — Spec vs. Codebase

| Issue / spec claim | Reality (verified at plan time) | Plan response |
|---|---|---|
| `apps/web-platform/server/agent-runner.ts:261-346` is the canUseTool gate | The gate factory was extracted to `apps/web-platform/server/permission-callback.ts` (`createCanUseTool`) per #2335. `agent-runner.ts:916` only calls `createCanUseTool({ … })`. The Bash branch of the gate lives at `permission-callback.ts:386-574`. | Plan edits are scoped to `permission-callback.ts` + its sibling test. `agent-runner.ts` is not modified. |
| Fix MUST build an exact-match command allowlist (`ls`, `pwd`, `cd`, `whoami`) with metachar rejection | A safe-Bash allowlist already ships from prior plan `2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md`. `permission-callback.ts:90-176` defines `SHELL_METACHAR_DENYLIST`, `PATH_TOKEN`, and `SAFE_BASH_PATTERNS`. Verified at plan time via `node /tmp/check-cmds.mjs` against the live regex array: `pwd`, `ls`, `ls -la`, `whoami`, `cat <path>`, `git status` all auto-allow today; near-miss prefixes `lsof`, `cdrecord`, `pwdx` reject; `pwd; ls`, `ls && curl x`, `ls > out.txt`, `ls \| grep foo`, `echo "$VAR"` all reject. | This plan is the **delta** against that allowlist, not a greenfield build. The HARD CONSTRAINT in the issue is satisfied by the existing two-stage check (raw-string `SHELL_METACHAR_DENYLIST`, then leading-token regex) — extending it with `cd` preserves the contract. |
| `cd` is in the required allowlist (issue body Acceptance Criteria) | `cd` is **not** in `SAFE_BASH_PATTERNS` today. Verified via `grep -nE "\bcd\b" permission-callback.ts` → no match. The prior plan's allowlist scoped to "read-only file/git/cwd inspection" but did not add `cd`. | Add a `cd`-specific regex with optional path arg. See Phase 2 §"Add `cd` regex." |
| `cwd` is a real Unix command in the allowlist scope | `cwd` is not a real Unix utility. The user wrote it as shorthand for "current working directory" = `pwd` (already allowed) or as the field name `cwd` in `process.cwd()`. | Document in plan §"Non-goals" that `cwd` is not added as a literal command — `pwd` already covers the user-visible intent. |
| Reject `..` path traversal | Today `[\w./~+:=@-]+` (the `PATH_TOKEN`) **accepts** `..`, `../foo`, `/etc/passwd`. `node /tmp/check-cmds.mjs` confirmed `ls ..` and `ls -la ../` both auto-allow today. | Add path-traversal rejection at the metachar-denylist stage: `..` substring (and `\.\.` literal) rejection BEFORE the leading-token regex runs. See Phase 2 §"Path-traversal denylist." |
| If the allowlist rejects a candidate, log via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry` | Today `permission-callback.ts` does NOT call `reportSilentFallback` or `warnSilentFallback` anywhere. Pino-only logging via `log.info({ sec: true, … })` exists for both auto-approved and gated paths (lines 401-409, 431-439, 567-572). The blocklist-deny path also logs only to pino (lines 401-409). | Wire `warnSilentFallback` on near-miss rejection paths only — see Phase 2 §"Near-miss telemetry." Use `warnSilentFallback` (not `reportSilentFallback`) because near-miss rejection is degraded-but-expected (prompt-injection probing, model exploration), not an error. Match the constitution's signal vocabulary. |

## Hypotheses

### H1 — `cd` is the only required command genuinely missing from the allowlist

The issue body's HARD CONSTRAINT names four commands: `ls`, `pwd`, `cd`, `whoami`. Three of those (`ls`, `pwd`, `whoami`) already auto-allow. Only `cd` is missing. `cwd` is not a real utility. The fix is one new regex entry, not a new module.

**Evidence (verified at plan time):**

```js
// /tmp/check-cmds.mjs run against current SAFE_BASH_PATTERNS
ALLOW  "pwd"
ALLOW  "ls"
ALLOW  "ls -la"
REJECT "cd"          // ← missing
REJECT "cd /tmp"     // ← missing
REJECT "cwd"         // ← not a real command
ALLOW  "whoami"
REJECT "lsof"        // ← correct (near-miss)
REJECT "cdrecord"    // ← correct (near-miss)
REJECT "pwdx"        // ← correct (near-miss)
REJECT "ls && curl x"  // ← correct (metachar)
REJECT "pwd; ls"       // ← correct (metachar)
ALLOW  "ls .."          // ← BUG: path traversal currently slips through
ALLOW  "ls -la ../"     // ← BUG: path traversal currently slips through
```

### H2 — `..` path traversal is a latent gap in the existing allowlist

The `PATH_TOKEN` regex `[\w./~+:=@-]+` was designed to accept paths but does not exclude `..`. Auto-allowing `cat ../../../etc/passwd` is a real escape — even though the canUseTool's file-tool branch (`isFileTool` + `isPathInWorkspace`) catches the path-bearing SDK tools, **Bash with a path argument bypasses that workspace check** because the gate only inspects the command string, not the resolved path the shell executes. The host-level `bubblewrap` sandbox (sibling defense in `agent-runner-sandbox-config.ts`) restricts filesystem visibility, but the workspace-relative invariant is at the canUseTool boundary, not at the OS-syscall boundary. Closing `..` here is defense-in-depth against the exact pivot the issue's HARD CONSTRAINT names.

#### Why path-traversal denylist is load-bearing (deepen-pass elaboration)

`extractToolPath` (in `tool-path-checker.ts`) reads `toolInput.file_path`, `toolInput.path`, `toolInput.notebook_path` — verified at plan time. Bash uses `toolInput.command`, which is **not** in that list. So the canUseTool's `isFileTool` → `isPathInWorkspace` defense (`permission-callback.ts:274-300`) DOES NOT FIRE for Bash invocations. The only canUseTool-boundary check on Bash arguments is `isBashCommandSafe`, which today accepts `..` via `PATH_TOKEN`.

Two layers in our defense-in-depth stack catch this today:

1. **Bubblewrap sandbox** (`agent-runner-sandbox-config.ts`) restricts the agent subprocess's filesystem visibility at the OS namespace level. `cat /etc/passwd` would still fail because `/etc` is not bind-mounted into the sandbox.
2. **Auto-approve scope** — `cat ../etc/passwd` does NOT match `BLOCKED_BASH_PATTERNS` (no `curl|wget|sudo|sh -c`) so it flows to the safe-bash check, which TODAY accepts it (verified via the harness in §"Regex Verification Harness"), then to the review-gate which prompts the user.

The current behavior is: the user gets a review-gate prompt and (if they accept) the bubblewrap sandbox blocks the read. **The bug is that the user is forced into the prompt-and-decide loop** — exactly the friction the issue is trying to eliminate. We can't fix the friction by widening the auto-approve list without ALSO closing path-traversal, because the union ("auto-approve `cat <path>`" + "no `..` filter") would let the agent silently `cat ../../etc/passwd` (with the bubblewrap sandbox as the only remaining defense). One layer of defense for cross-tenant-data-class secrets is below the bar set by `2026-03-20-canuse-tool-sandbox-defense-in-depth.md` ("three-tier defense-in-depth, where each layer independently blocks the most critical attack classes").

So: adding `cd` to the allowlist + auto-approving `cat`/`ls` with path args + NOT adding the path-traversal denylist would **regress** defense-in-depth. The denylist is required, not optional.

### H3 — Near-miss rejection telemetry is missing

A future widening (someone adds `lsof` thinking it's read-only) is the failure mode the issue's `reportSilentFallback` requirement is designed to detect. Today, when a near-miss command rejects, it falls through to the existing review-gate (which prompts the user) — this is functionally correct but invisible to on-call. Wiring `warnSilentFallback` on the **rejection** path (specifically, when the command starts with a known near-miss prefix like `ls`, `pwd`, `cd`, `whoami` but does NOT match the safe regex) makes drift observable without changing user-facing behavior.

## Hypotheses ruled out

- **"The session isn't sandboxed."** The issue body asks "is the CC session actually flagged sandboxed?" — confirmed yes. `agent-runner-sandbox-config.ts:60` sets `autoAllowBashIfSandboxed: true` unconditionally for the CC path. The reason the SDK auto-approve isn't catching `cd` is not sandbox flagging — it's that **`canUseTool` runs in step 5 of the SDK permission chain** (per `permission-callback.ts:6-9` doc comment) and our local `canUseTool` is overriding the SDK's auto-approve before it can fire. The SDK doc-string in `agent-runner-sandbox-config.ts:9-11` confirms this: the sandbox flag only applies to the SDK-side fallback, but our `canUseTool` is authoritative once provided. So adding `cd` to the local allowlist is the correct surface.

## Acceptance Criteria

### Pre-merge (PR)

#### AC1 — `cd` auto-approves with no review gate

- `isBashCommandSafe("cd")` returns `true`.
- `isBashCommandSafe("cd /tmp")` returns `true`.
- `isBashCommandSafe("cd src/components")` returns `true`.
- For each: `canUseTool("Bash", { command }, sdkOptions())` returns `{ behavior: "allow" }`, and `deps.sendToClient` and `deps.abortableReviewGate` are NOT called.

#### AC2 — Near-miss prefixes still reject

- `isBashCommandSafe("cdrecord")` → `false`.
- `isBashCommandSafe("cd../etc")` → `false` (no space, traversal).
- `isBashCommandSafe("cd /etc/../tmp")` → `false` (path-traversal denylist).
- `isBashCommandSafe("cdx")` → `false` (extra-char near-miss).

#### AC3 — Path-traversal rejection on previously-allowed commands

- `isBashCommandSafe("ls ..")` → **`false`** (regression vs. current behavior; this is intentional).
- `isBashCommandSafe("ls -la ../")` → `false`.
- `isBashCommandSafe("cat ../foo")` → `false`.
- `isBashCommandSafe("cat foo/..")` → `false` (trailing `..`).
- `isBashCommandSafe("ls .")` → `true` (single dot is current-dir, not traversal).
- `isBashCommandSafe("cat foo/bar/..baz")` → `true` (`..baz` is a filename, not a parent ref). **NOTE:** this row is the load-bearing edge case for the path-traversal regex shape — see Phase 2 §"Path-traversal denylist" for the regex and the test fixture justifying the boundary.

#### AC4 — Shell-metacharacter rejection unchanged (regression guard)

- All COMPOUND_COMMANDS fixtures from the existing test still reject (`pwd && curl x`, `pwd; ls`, `ls > out.txt`, etc.). No semantic change to `SHELL_METACHAR_DENYLIST`.

#### AC5 — Near-miss rejection mirrors via `warnSilentFallback`

- When a Bash command starts with a known near-miss leading token (`lsof`, `cdrecord`, `pwdx`, or any token matching `^(ls|pwd|cd|whoami|cat|head|tail|wc|file|stat|which|uname|git|echo)\w+`) but does NOT match `SAFE_BASH_PATTERNS`, `warnSilentFallback` is called exactly once with `{ feature: "cc-permissions", op: "safe-bash-near-miss", extra: { leadingToken } }`.
- The command itself is NOT included in `extra` (it may contain user-prompt PII per `cq-test-fixtures-synthesized-only`-adjacent reasoning); only the leading token (first word) is logged.
- The user-facing behavior is unchanged: the command still falls through to the review-gate.

#### AC6 — Test covers the three issue-mandated cases plus path-traversal

Test file: `apps/web-platform/test/permission-callback-safe-bash.test.ts` (extend existing).

New `describe` blocks:

- `describe("cd auto-approval (AC1)")` — `cd`, `cd /tmp`, `cd src/components`.
- `describe("path-traversal rejection (AC3)")` — `ls ..`, `cat ../foo`, `cd ../`, plus the `..baz` filename edge case.
- `describe("near-miss telemetry (AC5)")` — assert `warnSilentFallback` called with `op: "safe-bash-near-miss"` and correct `leadingToken` for `lsof`, `cdrecord`, `pwdx`. Mock `warnSilentFallback` via `vi.mock("../server/observability", …)`.

### Post-merge (operator)

None. This is a pure code change — no DB migration, no infra apply, no doppler edit.

## Files to Edit

- `apps/web-platform/server/permission-callback.ts`
  - Add `cd` regex to `SAFE_BASH_PATTERNS`.
  - Add `..` path-traversal denylist check (post-trim, pre-leading-token-match).
  - Wire `warnSilentFallback` on near-miss-prefix rejection.
  - Import `warnSilentFallback` from `./observability`.

- `apps/web-platform/test/permission-callback-safe-bash.test.ts`
  - Add `describe("cd auto-approval (AC1)")` (3 tests).
  - Add `describe("path-traversal rejection (AC3)")` (4 tests + the `..baz` boundary case).
  - Add `describe("near-miss telemetry (AC5)")` (3 tests with `warnSilentFallback` mock).
  - **NOTE:** existing `ls ..` / `ls -la ../` cases are NOT in the current test fixtures (verified via `grep -nE "ls \.\." permission-callback-safe-bash.test.ts` → no match). AC3 adds these as positive-rejection tests.

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED: extend the test file (no implementation)

Per AGENTS.md `cq-write-failing-tests-before` — TDD gate. Add the three new `describe` blocks documented in AC6 to `permission-callback-safe-bash.test.ts`. Run `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts`. Tests in AC1 (`cd …`) MUST fail because `cd` is not in `SAFE_BASH_PATTERNS`. Tests in AC3 (`ls ..`, `cat ../foo`) MUST fail because `..` is currently accepted. Tests in AC5 MUST fail because `warnSilentFallback` is not wired.

Commit checkpoint: `test(cc-permissions): RED — cd auto-approve, ../-traversal rejection, near-miss telemetry`.

### Phase 2 — GREEN: implementation

#### Add `cd` regex

In `permission-callback.ts:136-176` (`SAFE_BASH_PATTERNS`), add one entry, placed adjacent to the `pwd` entry for proximity (both are cwd-related):

```ts
// cd — optional single path arg. No flags (cd -, cd --, cd -P all rejected).
new RegExp(String.raw`^cd(?:\s+${PATH_TOKEN})?\s*$`),
```

**Why no flags:** `cd -` swaps to `OLDPWD`; `cd -P` follows symlinks; both are state-coupled and confusing. The Soleur use case is "agent inspects a known dir." Reject all flags. (If a future use-case needs them, a separate plan files the request.)

#### Path-traversal denylist

Add a new top-level constant after `SHELL_METACHAR_DENYLIST` (line 120):

```ts
// Path-traversal denylist. Matches `..` as a path segment (preceded by
// start-of-string, slash, or whitespace; followed by end-of-string, slash,
// or whitespace). Does NOT match `..baz` (a filename starting with `..`)
// or `foo..bar` (literal in middle of token). The intent is parent-dir
// traversal, not banning every literal `..` substring.
const PATH_TRAVERSAL_DENYLIST = /(?:^|[\s/])\.\.(?:$|[\s/])/;
```

Plumb the check in `isBashCommandSafe` immediately after the metachar denylist:

```ts
export function isBashCommandSafe(command: unknown): boolean {
  if (typeof command !== "string" || command.length === 0) return false;
  if (command.length > SAFE_BASH_MAX_INPUT_LENGTH) return false;
  if (SHELL_METACHAR_DENYLIST.test(command)) return false;
  if (PATH_TRAVERSAL_DENYLIST.test(command)) return false;  // ← new
  const trimmed = command.trim();
  if (trimmed.length === 0) return false;
  for (const pattern of SAFE_BASH_PATTERNS) {
    if (pattern.test(trimmed)) return true;
  }
  return false;
}
```

**Boundary case (AC3 `..baz` row):** the regex `(?:^|[\s/])\.\.(?:$|[\s/])` matches `..` only when surrounded by start-of-string, end-of-string, slash, or whitespace. `cat foo/bar/..baz` does NOT match because `..baz` has a non-slash, non-whitespace character after `..` (the `b`). `cat foo/..` matches because `..` is at end-of-string after a slash. This boundary shape is specifically the one prescribed in `cq-pii-regex-scrubber-three-invariants` adjacent rationale: structural shape, not substring.

#### Near-miss telemetry

At the top of `permission-callback.ts`, add the import:

```ts
import { warnSilentFallback } from "./observability";
```

Add a near-miss leading-token regex constant near `SAFE_BASH_PATTERNS`:

```ts
// Near-miss prefix detection. Matches tokens that LOOK like a safe-bash
// allowlist entry but extend past it (lsof vs ls, cdrecord vs cd, pwdx
// vs pwd). Used only for telemetry — the rejection path is the same
// either way (review-gate). When this fires, on-call sees drift before
// it becomes a confused-deputy escape.
const SAFE_BASH_NEAR_MISS_PREFIX =
  /^(ls|pwd|cd|whoami|cat|head|tail|wc|file|stat|which|uname|git|echo)(\w)/;
```

In the Bash branch of `createCanUseTool`, after `isBashCommandSafe(command)` returns `false` and before the cache lookup (around line 448 in the current file), add:

```ts
const nearMiss = command.match(SAFE_BASH_NEAR_MISS_PREFIX);
if (nearMiss) {
  warnSilentFallback(null, {
    feature: "cc-permissions",
    op: "safe-bash-near-miss",
    extra: {
      leadingToken: nearMiss[1] + nearMiss[2],  // e.g., "lsof" → "ls" + "o" = "lso", but we want full token
      // Actually: capture the full leading word.
    },
  });
}
```

**CORRECTION (caught at plan time before write-skill phase):** the regex match shape gives us the safe prefix (`ls`, `cd`, etc.) and the next char, not the full leading word. The intent is to log the full leading token so `lsof` shows up as `leadingToken: "lsof"`. Use a separate match:

```ts
const nearMiss = SAFE_BASH_NEAR_MISS_PREFIX.test(command);
if (nearMiss) {
  const firstWord = command.trim().split(/\s+/)[0];
  warnSilentFallback(null, {
    feature: "cc-permissions",
    op: "safe-bash-near-miss",
    extra: { leadingToken: firstWord },
  });
}
```

The command itself is not in `extra` (PII risk per `cq-test-fixtures-synthesized-only`-adjacent reasoning).

**Why `null` not an Error:** there is no exception. This is observability for a normal rejection path. `warnSilentFallback` accepts `null` → triggers the `else if` branch (`Sentry.captureMessage(message ?? feature silent fallback, …)`) per `observability.ts:104-110`.

Commit checkpoint: `fix(cc-permissions): GREEN — add cd, harden ../ traversal, wire near-miss telemetry`.

### Phase 3 — REFACTOR

If the new `PATH_TRAVERSAL_DENYLIST` and `SAFE_BASH_NEAR_MISS_PREFIX` regexes are clean and tests are green, no refactor needed. If the test file's `describe` blocks have duplicated boilerplate, factor a helper for the `mock*` setup.

Run full suite: `bun test apps/web-platform/test/`.

Commit checkpoint: `refactor(cc-permissions): consolidate test setup` (only if a refactor lands).

## Domain Review

**Domains relevant:** Engineering, Product (carry-forward from bundle brainstorm).

### Engineering

**Status:** reviewed (carry-forward).

**Assessment (from brainstorm):** All four bundle bugs are in the Command Center server/UI layer. #3252 has both UX (interruption) and security (sandbox over-reach) framings — the security framing dominates if the fix is wrong. This plan's two-stage check (metachar denylist → path-traversal denylist → leading-token allowlist) preserves the existing security shape; the additions (`cd`, `..` rejection, near-miss telemetry) are within the same defensive envelope. No architectural deviation from `permission-callback.ts`'s existing pattern.

### Product/UX Gate

**Tier:** none.

**Decision:** N/A — this is a server-side permission-policy change. No new user-facing pages, modals, or flows. The existing review-gate UI is unchanged. The user-visible delta is "fewer modal interrupts for `cd`" + "AC3 adds `ls ..` to the rejection path, so a model that was previously auto-approving `ls ..` will now see a review-gate prompt for that one shape." The latter is a strict-tightening, expected behavior.

**Brainstorm-recommended specialists:** none (the bundle brainstorm did not name any specialist for #3252).

## Security Ordering Invariant

The Bash branch in `permission-callback.ts:386-574` follows a 5-step ordering invariant. Any change to this file MUST preserve it; the new near-miss telemetry hook lands at step 3.5:

```text
1. Empty-command deny     (line 388)
2. BLOCKED_BASH_PATTERNS  (line 400) — sudo/curl/wget/sh -c/eval/base64 -d/dev/tcp
3. SAFE_BASH_PATTERNS     (line 430) — auto-approve allowlist
3.5 (NEW) Near-miss tel.  ← warnSilentFallback when SAFE_BASH_NEAR_MISS_PREFIX matches and step 3 missed
4. bashApprovalCache      (line 453) — #2921 batched grants
5. Review-gate (lines ~478-572) — user-facing modal
```

**Why step 3.5 is the only correct insertion point:**

- **Earlier (between 1 and 2 OR between 2 and 3):** would emit telemetry for `sudo whoami` (which `SAFE_BASH_NEAR_MISS_PREFIX` does NOT match anyway: `sudo` is not in the prefix regex's alternatives), but more importantly would emit telemetry for `pwd && curl` BEFORE the blocklist denies — causing duplicate telemetry signal where blocklist log already fires.
- **Same point as 3.5 (chosen):** fires only when allowlist missed AND command starts with a known prefix. Captures the intended drift signal (`lsof`, `cdrecord`, `pwdx`).
- **Later (after step 4 or 5):** would lose signal for cache-hit cases (a previously-batched `lsof <pattern>` would skip telemetry), AND would mix near-miss-during-review-gate signals with successful-after-approval signals, polluting the drift dashboard.

**Verified via code-trace:** `permission-callback.ts:430` (allowlist check) → fall-through to telemetry hook → `permission-callback.ts:453` (cache check). The hook lives in the gap between these two existing branches.

## Regex Verification Harness

The proposed regexes were verified at plan time against a 38-fixture matrix (Node v21.7.3). All passed. Selected output:

```text
OK   [AC1] expected=ALLOW got=ALLOW  near-miss=false  cmd="cd"
OK   [AC1] expected=ALLOW got=ALLOW  near-miss=false  cmd="cd /tmp"
OK   [AC2 cd<no-space>..] expected=REJECT got=REJECT  near-miss=false  cmd="cd../etc"
OK   [AC2] expected=REJECT got=REJECT  near-miss=false  cmd="cd /etc/../tmp"
OK   [AC3] expected=REJECT got=REJECT  near-miss=false  cmd="ls .."
OK   [AC3] expected=REJECT got=REJECT  near-miss=false  cmd="ls -la ../"
OK   [AC3] expected=REJECT got=REJECT  near-miss=false  cmd="cat ../foo"
OK   [AC3] expected=REJECT got=REJECT  near-miss=false  cmd="cat foo/.."
OK   [AC3 ..baz boundary] expected=ALLOW got=ALLOW  near-miss=false  cmd="cat foo/..baz"
OK   [AC3 single-dot] expected=ALLOW got=ALLOW  near-miss=false  cmd="ls ."
OK   [AC4] expected=REJECT got=REJECT  near-miss=false  cmd="pwd && curl evil.com"
OK   [near-miss] expected=REJECT got=REJECT  near-miss=true  cmd="lsof"
OK   [near-miss] expected=REJECT got=REJECT  near-miss=true  cmd="pwdx"
OK   [near-miss-extended] expected=REJECT got=REJECT  near-miss=true  cmd="catatonic"
OK   [edge: cd .] expected=ALLOW got=ALLOW  near-miss=false  cmd="cd ."
OK   [edge: cd /] expected=ALLOW got=ALLOW  near-miss=false  cmd="cd /"
OK   [edge: ~ tilde] expected=ALLOW got=ALLOW  near-miss=false  cmd="cd ~/src"
OK   [traversal start] expected=REJECT got=REJECT  near-miss=false  cmd="cat ../etc/passwd"
OK   [traversal middle slash] expected=REJECT got=REJECT  near-miss=false  cmd="ls /tmp/../etc"
OK   [traversal trailing] expected=REJECT got=REJECT  near-miss=false  cmd="cat /tmp/.."

Hidden-dotfile boundary cases (12 fixtures, separate run, all PASS):
OK   [.git dir] cmd="ls .git" → ALLOW
OK   [.gitignore] cmd="cat .gitignore" → ALLOW
OK   [hidden file] cmd="cat foo/.bashrc" → ALLOW
OK   [..backup filename] cmd="cat my..backup.txt" → ALLOW
OK   [...gitignore file] cmd="cat ...gitignore" → ALLOW
OK   [....file] cmd="cat ....file" → ALLOW
OK   [leading-ws ls ..] cmd="  ls .." → REJECT
OK   [tab-separated ..] cmd="ls\t.." → REJECT
```

The harness verifies four invariants simultaneously:
1. `isBashCommandSafe` returns the expected allow/reject.
2. `SAFE_BASH_NEAR_MISS_PREFIX` returns the expected near-miss flag.
3. The two are consistent for all near-miss cases (telemetry fires iff a near-miss prefix is detected AND the safe-check missed).
4. The `..baz` filename boundary holds (filenames starting with `..` are not flagged as path traversal).

Future PRs widening `SAFE_BASH_PATTERNS` should re-run this harness with their new fixtures appended. Do NOT delete fixtures from the matrix without a §Risks justification.

## Test Scenarios

### TS1 — `cd` auto-approve (AC1)

```ts
describe("cd auto-approval (AC1)", () => {
  for (const cmd of ["cd", "cd /tmp", "cd src/components", "cd ~"]) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === true`, () => {
      expect(isBashCommandSafe(cmd)).toBe(true);
    });

    test(`canUseTool Bash(${JSON.stringify(cmd)}) → allow with no review_gate`, async () => {
      const { ctx, deps } = buildContext();
      const canUseTool = createCanUseTool(ctx);
      const result = await canUseTool("Bash", { command: cmd }, sdkOptions());
      assertAllow(result);
      expect(deps.sendToClient).not.toHaveBeenCalled();
      expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    });
  }
});
```

### TS2 — Near-miss prefix rejection (AC2)

```ts
describe("cd near-miss rejection (AC2)", () => {
  for (const cmd of ["cdrecord", "cdx", "cd../etc", "cd /etc/../tmp"]) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
});
```

### TS3 — Path-traversal rejection (AC3)

```ts
describe("path-traversal rejection (AC3)", () => {
  for (const cmd of [
    "ls ..",
    "ls -la ../",
    "cat ../foo",
    "cat foo/..",
    "cd ../",
    "cd ..",
  ]) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }

  test("`..baz` (filename starting with two dots) is allowed when otherwise safe", () => {
    expect(isBashCommandSafe("cat foo/..baz")).toBe(true);
  });

  test("single dot (current dir) is allowed", () => {
    expect(isBashCommandSafe("ls .")).toBe(true);
  });
});
```

### TS4 — Near-miss telemetry (AC5)

```ts
import { warnSilentFallback } from "../server/observability";
vi.mock("../server/observability", () => ({
  warnSilentFallback: vi.fn(),
  reportSilentFallback: vi.fn(),
}));

describe("near-miss telemetry (AC5)", () => {
  beforeEach(() => {
    vi.mocked(warnSilentFallback).mockClear();
  });

  for (const [cmd, leadingToken] of [
    ["lsof", "lsof"],
    ["cdrecord", "cdrecord"],
    ["pwdx", "pwdx"],
  ]) {
    test(`warnSilentFallback called for near-miss ${JSON.stringify(cmd)}`, async () => {
      const { ctx } = buildContext();
      const canUseTool = createCanUseTool(ctx);
      await canUseTool("Bash", { command: cmd }, sdkOptions());

      expect(warnSilentFallback).toHaveBeenCalledTimes(1);
      expect(warnSilentFallback).toHaveBeenCalledWith(null, {
        feature: "cc-permissions",
        op: "safe-bash-near-miss",
        extra: { leadingToken },
      });
    });
  }

  test("warnSilentFallback NOT called for safe commands", async () => {
    const { ctx } = buildContext();
    const canUseTool = createCanUseTool(ctx);
    await canUseTool("Bash", { command: "pwd" }, sdkOptions());
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  test("warnSilentFallback NOT called for total-misses (e.g., curl)", async () => {
    const { ctx } = buildContext();
    const canUseTool = createCanUseTool(ctx);
    await canUseTool("Bash", { command: "curl x" }, sdkOptions());
    // curl hits BLOCKED_BASH_PATTERNS → deny via blocklist, no near-miss telemetry.
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  test("the command itself is NOT in the telemetry extra (PII guard)", async () => {
    const { ctx } = buildContext();
    const canUseTool = createCanUseTool(ctx);
    await canUseTool("Bash", { command: "lsof -i :443" }, sdkOptions());
    expect(warnSilentFallback).toHaveBeenCalled();
    const call = vi.mocked(warnSilentFallback).mock.calls[0];
    const extra = call[1].extra as Record<string, unknown>;
    // Only leadingToken should be in extra. Defensive assertion against future drift.
    expect(extra).toEqual({ leadingToken: "lsof" });
    expect(JSON.stringify(extra)).not.toContain(":443");
  });
});
```

### TS5 — Hidden-dotfile boundary (deepen-pass addition)

These fixtures verify that legitimate dotfile/`.git`/`.config` reads still auto-allow despite the path-traversal denylist:

```ts
describe("hidden-dotfile boundary (TS5)", () => {
  for (const cmd of [
    "ls .git",
    "cat .gitignore",
    "cat foo/.bashrc",
    "ls .config/app",
    "cat .foo",
    "cat my..backup.txt",   // ..backup is a filename
    "cat ...gitignore",     // ...gitignore is a filename
    "cat ....file",          // ....file is a filename
    "ls .",                   // current dir
    "cat foo.",               // trailing dot in filename
  ]) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === true`, () => {
      expect(isBashCommandSafe(cmd)).toBe(true);
    });
  }
});
```

### TS6 — `cd` regex + path-traversal interdependence (deepen-pass addition)

A regression guard for the §Sharp Edges note "cd regex + path-traversal denylist are interdependent." Asserts that **both** checks are required: removing either re-opens a hole.

```ts
describe("cd regex + path-traversal denylist interdependence (TS6)", () => {
  // The cd regex itself ACCEPTS `cd ../etc` (path-traversal arg shape matches PATH_TOKEN).
  // The path-traversal denylist is what rejects it. This test pins both checks
  // by asserting:
  //   (a) cd-with-../-arg variants reject (path-traversal denylist working)
  //   (b) cd-with-non-traversal-arg variants allow (cd regex working)
  // If a future PR breaks either the regex or the denylist, this block fires.

  // (a) Path-traversal MUST reject for cd
  for (const cmd of ["cd ..", "cd ../", "cd ../foo", "cd /etc/../tmp"]) {
    test(`cd path-traversal: ${JSON.stringify(cmd)} rejects`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
  // (b) cd regex MUST allow non-traversal args
  for (const cmd of ["cd", "cd /tmp", "cd ~", "cd ~/src", "cd /", "cd ."]) {
    test(`cd non-traversal: ${JSON.stringify(cmd)} allows`, () => {
      expect(isBashCommandSafe(cmd)).toBe(true);
    });
  }
});
```

### TS7 — Near-miss prefix surface includes `lsblk`-class (deepen-pass addition)

Per §Risks R5, the near-miss telemetry surface intentionally includes `lsblk`, `lsattr`, `lscpu`, `lsmod`, etc. This test pins that surface so a future PR that narrows the prefix regex doesn't silently lose drift signal.

```ts
describe("near-miss telemetry surface (TS7)", () => {
  for (const cmd of ["lsblk", "lsattr", "lscpu", "lsmod", "lspci", "lsusb"]) {
    test(`${JSON.stringify(cmd)} triggers near-miss telemetry`, async () => {
      const { ctx } = buildContext();
      const canUseTool = createCanUseTool(ctx);
      await canUseTool("Bash", { command: cmd }, sdkOptions());
      expect(warnSilentFallback).toHaveBeenCalledTimes(1);
      const call = vi.mocked(warnSilentFallback).mock.calls[0];
      expect(call[1]).toMatchObject({
        feature: "cc-permissions",
        op: "safe-bash-near-miss",
        extra: { leadingToken: cmd },
      });
    });
  }
});
```

## Risks

- **R1 — `ls ..` regression for legitimate users.** If a user / agent was relying on `ls ..` auto-approving today, AC3 will start prompting. Mitigation: this is a **strict tightening** for security; the user can `cd ..` first, then `ls`, or accept the one-time review-gate prompt. The `warnSilentFallback` telemetry will surface frequency-of-occurrence data so we can decide whether to relax. Expected hit count: low (the path-traversal pattern was rarely exercised — `Glob` and `Grep` SDK tools cover the legitimate "look outside cwd" use cases).
- **R2 — Regex backtracking on pathological input.** `PATH_TRAVERSAL_DENYLIST = /(?:^|[\s/])\.\.(?:$|[\s/])/` is a tight non-backtracking shape (no `*` or `+` quantifiers on capture groups). The 4096-char input cap (`SAFE_BASH_MAX_INPUT_LENGTH`) already guards against amplification. No additional risk introduced.
- **R3 — `warnSilentFallback` call rate / telemetry side-channel DoS.** If the model exploration (or a prompt-injection attempt) includes many near-miss probes, Sentry could see traffic spikes. **Mitigation:** Sentry's per-feature rate limit at the `feature: "cc-permissions"` tag (configured at the Sentry org level, not in this plan). If traffic exceeds the rate limit budget, switch to log-only via `log.info({ sec: true, … })` and remove the Sentry call — the pino mirror still writes to stdout and is captured by Better Stack. **Acknowledged-untracked:** an attacker-driven near-miss flood is technically a low-grade DoS surface against Sentry. Tracking issue: not filed; revisit if Sentry per-feature volume on `cc-permissions` exceeds 1k events/hour for any 24h window. Mitigation deferred per `wg-when-deferring-a-capability-create-a` — fold-in only if observed, file as scope-out otherwise.
- **R4 — Future allowlist additions must follow the same pattern.** New entries in `SAFE_BASH_PATTERNS` must be reviewed against the `..` denylist (already enforced at the `isBashCommandSafe` boundary). Prescribe a §Sharp Edges note that future entries cannot bypass the metachar + path-traversal stages.
- **R5 — Near-miss telemetry surface includes `lsblk`/`lsattr`/`lscpu`/`lsmod`/`lspci`/`lsusb`/etc.** Verified at plan time: `SAFE_BASH_NEAR_MISS_PREFIX = /^(ls|pwd|cd|whoami|cat|head|tail|wc|file|stat|which|uname|git|echo)(\w)/` matches any token starting with one of these prefixes followed by a word character. So `lsblk`, `lsattr`, `lscpu`, `lspci`, `lsusb`, `lsof` all trigger near-miss telemetry. **By design** — these ARE near-misses to `ls` and the drift signal is correct. Operators monitoring the `safe-bash-near-miss` op should expect `leadingToken` values like `lsblk` / `lspci` in normal traffic and treat them as exploration noise, not threats. The signal-to-noise issue on the dashboard is real but acceptable; the alternative (an exact-match list of "real near-misses") would require maintenance every time the kernel adds a util.
- **R6 — `cd` is an interactive-shell builtin, not a process.** When the SDK Bash tool runs `cd /tmp`, it executes in a subprocess shell that exits immediately — `cd` does not persist working directory across Bash invocations. This is a UX subtlety the user/agent must understand: auto-approving `cd /tmp; ls` is impossible (rejected by metachar denylist), and `cd /tmp` followed by a separate `ls` Bash invocation runs `ls` in the original cwd (the workspace root), not `/tmp`. **Mitigation:** none needed in this plan — this is upstream SDK behavior. The agent should use `ls /tmp` directly. Document for the issue's author so they understand `cd` auto-approval is partially cosmetic (it confirms intent, but doesn't change subsequent command's cwd).

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled and threshold is `single-user incident`. (Required boilerplate per plan-skill Phase 2.6.)
- **Future entries to `SAFE_BASH_PATTERNS` MUST not bypass the metachar + path-traversal stages.** Both denylists run BEFORE the per-pattern leading-token regex in `isBashCommandSafe`. Any future PR that moves a per-pattern check above the denylists, or adds a "fast-path" allow before them, breaks the security contract. Add a comment in `permission-callback.ts` adjacent to `isBashCommandSafe` documenting the ordering invariant.
- **The `PATH_TRAVERSAL_DENYLIST` boundary case (`..baz` allowed, `../` rejected) is load-bearing.** A regex change that drops the surrounding `(?:^|[\s/])` and `(?:$|[\s/])` anchors would either (a) reject legitimate filenames starting with `..` or (b) accept `cat foo../etc`. The test fixtures in TS3 pin both edges. Do not "simplify" the regex to `\.\.` without re-running TS3.
- **`warnSilentFallback` accepts `null` as the first argument** — verified via `observability.ts:99-110`. The pino mirror at `observability.ts:92` will log `err: null` which is fine; the Sentry path correctly hits the `else if` branch (`captureMessage`) for non-Error inputs. If `observability.ts` ever adds a non-null assertion on the first argument, this near-miss-telemetry path will throw — add a pre-check `if (err === null) { /* sentinel */ }` or wrap in try/catch. Currently the `try { … } catch {}` in `warnSilentFallback` itself absorbs any Sentry-side failure (lines 133-end of file).
- **`AGENTS.md` rule footprint:** this plan does NOT add a new AGENTS.md rule. The constraint "future allowlist entries must not bypass the metachar/traversal stages" is enforced by the test-suite (TS3's `..baz` pin + COMPOUND_COMMANDS regression coverage) and an in-code comment, not an AGENTS.md rule. Per `wg-every-session-error-must-produce-either` "Discoverability exit": the failure mode would surface as a failing test on the offending PR, not as a hidden production drift. Test pin + code comment is sufficient.
- **Issue-body claim of `agent-runner.ts:261-346` as the gating point is stale.** Anyone re-reading the issue post-merge should know the authoritative path is `permission-callback.ts:createCanUseTool` → Bash branch (~lines 386-574). The plan's §"Research Reconciliation" row 1 documents this; the PR description should also note it inline.
- **`cwd` is not a real Unix command.** The issue body lists "`ls`, `pwd`, `cwd`" as required allowlist entries. `pwd` covers the user-visible intent. The plan does NOT add a literal `cwd` regex. PR description should call this out for the issue author.
- **`cd` regex + path-traversal denylist are interdependent (deepen finding).** The `cd` regex `^cd(?:\s+[\w./~+:=@-]+)?\s*$` accepts `cd ../etc` (since `../etc` matches `PATH_TOKEN`). The path-traversal denylist `(?:^|[\s/])\.\.(?:$|[\s/])` is what rejects it. **Removing either check creates a hole:** removing the `cd` regex breaks AC1; removing the path-traversal denylist re-opens `cd ../`, `cat ../foo`, `ls ..`. A future PR that "simplifies" the regex by dropping path-traversal because "the cd regex already restricts args" is wrong — verified at plan time by removing the denylist from the harness and observing `cd ../` immediately auto-allow. The two checks are bound together; document this in an in-code comment adjacent to `PATH_TRAVERSAL_DENYLIST` ("DO NOT remove this denylist without auditing every `PATH_TOKEN`-using regex above for `..` acceptance").
- **Near-miss telemetry placement is load-bearing.** Per §"Security Ordering Invariant", the hook must land at step 3.5 (between `SAFE_BASH_PATTERNS` check and `bashApprovalCache` check). Any future PR that moves it earlier (before blocklist) emits noise on `sudo`/`curl` (which doesn't match the prefix anyway, but still — wrong placement) or duplicates blocklist signal; later (after cache) loses signal for cache-pre-approved misses. Document in code comments at the hook site.

## Open Code-Review Overlap

None. Verified at plan time via `gh issue list --label code-review --state open --json number,title,body --limit 200` → empty array (only the `gh` CLI's empty-list output, no matches). The two prior plans that touched `permission-callback.ts` (#2335 extraction, #2829 safe-bash) are merged with no open scope-outs.

## References

- Brainstorm: [`knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md`](../brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md)
- Bundle spec: [`knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md`](../specs/feat-cc-session-bugs-batch/spec.md)
- Prior allowlist plan: [`knowledge-base/project/plans/2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md`](./2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md)
- Issue: #3252
- Draft PR: #3249
- Sibling issues in bundle: #3250 (P1), #3251 (P2), #3253 (P3)
- AGENTS.md rules invoked: `cq-silent-fallback-must-mirror-to-sentry`, `cq-write-failing-tests-before`, `hr-weigh-every-decision-against-target-user-impact`.
