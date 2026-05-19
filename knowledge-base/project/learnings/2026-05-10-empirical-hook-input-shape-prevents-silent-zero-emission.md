---
date: 2026-05-10
category: best-practices
issue: 3494
pr: 3495
tags: [hooks, claude-code, telemetry, tdd, empirical-verification]
---

# Empirical Hook-Input-Shape Verification Prevents Silent Zero-Emission

## Problem

The PR #3495 plan and spec hypothesized a Claude Code PostToolUse(Task) hook input field path of `tool_response.usage.total_tokens` (snake_case, nested under `usage`) without empirical inspection of an actual hook payload. Had the production hook been written against that hypothesis, every Task envelope would have emitted `total_tokens=0` because the field does not exist at that path. The aggregator's orphan-gate (which checks for envelope presence and structural validity, not nonzero cost) would still pass. Every unit test against synthesized fixtures — fixtures derived from the same hypothesized shape — would still pass. The regression would only have surfaced at Phase 5 step 5 of the work plan (live integration on a real session), by which point the hook code, the aggregator code, the dashboard surface, and the fixtures would all be in committed history reinforcing the wrong shape.

## Solution

Phase 1 task 1.2 of the work plan was an explicit empirical-verification gate: **inspect a real hook input payload BEFORE writing the production hook**, citing precedent in `.claude/hooks/skill-invocation-logger.sh:13-22` where a date-stamped header comment records the empirical shape observed at hook authorship time. The plan's Sharp Edges section made this load-bearing with the line "The hook input shape inspection MUST happen before writing the hook." That gate was honored.

The verification was implemented via a stub PostToolUse(Task) hook that wrote raw stdin to a temp file under `/tmp/`. Because `.claude/settings.json` hook configuration only reloads at session start, the capture had to be triggered from a child `claude -p` session — registering the stub in the parent and then invoking a Task in the parent produced no output. Two empirical captures were taken via sequential Agent calls in the child session. The actual shape was `tool_response.totalTokens` (camelCase, top-level — not nested under `usage`), with siblings `tool_response.totalToolUseCount`, `tool_response.totalDurationMs`, and `tool_response.agentType`. None of the originally hypothesized field paths existed in the real payload. The production hook, fixtures, and aggregator were all written against the verified shape.

## Key Insight

Empirical inspection of hook, SDK, and API input is non-negotiable when the consumer's logic depends on field names. Documented field shapes drift across releases without changelog entries, and field paths reconstructed from training data or LLM recall are unreliable for any vendor that ships weekly. The skill-invocation-logger's date-stamped header comment recording the observed shape at authorship is a load-bearing pattern that every new hook in this repo should follow — it both documents the contract the hook depends on and creates a paper trail when upstream drifts the shape later. Without Phase 1.2, the fail-soft hook (which silently absorbs malformed input by design, so it cannot crash a user session) would have produced zero-cost envelopes indistinguishable from "no Task spawned" envelopes, and every layer downstream — orphan-gate, unit tests, dashboard charts — would have green-lit the regression all the way to merge.

## Session Errors

**Error 1.** Attempted to write a transient capture file to `.git/review-changed.txt` inside a worktree. In a worktree, `.git` is a regular file (a pointer to the bare repo's `worktrees/<name>` directory), not a directory, so the write failed.

**Recovery:** Redirected the capture to `/tmp/` instead.

**Prevention:** Treat `.git` as opaque infrastructure regardless of worktree vs. main checkout. Never write transient files under `.git/`; use `/tmp/` or a worktree-local scratch directory outside any git-managed path.

**Error 2.** Registered a stub PostToolUse hook in `.claude/settings.json` mid-session and expected it to fire on the next Task invocation in the same session. It did not.

**Recovery:** Spawned a child `claude -p` session, which loaded settings.json fresh at startup; the stub fired in the child and wrote the raw stdin to `/tmp/` where the parent could read it.

**Prevention:** Treat `.claude/settings.json` hooks as session-immutable. Any hook-development workflow that needs to capture or modify hook behavior must drive captures from a fresh `claude -p` child session, not from the parent.

**Error 3.** The plan and spec asserted the hook input field as `tool_response.usage.total_tokens` (snake_case, nested under a `usage` object).

**Recovery:** Phase 1.2 empirical capture revealed the real path is `tool_response.totalTokens` (camelCase, top-level). Spec, plan, fixtures, and hook were all corrected before any production code was written against the wrong shape.

**Prevention:** Never accept a hypothesized field path as authoritative. Phase 1.2 (empirical capture before production code) is the gate; the date-stamped header-comment pattern from skill-invocation-logger.sh is the artifact.

**Error 4.** A test fixture used `cat <<EOF | <hook-script>` to feed a synthesized envelope into a hook that has an early-exit kill-switch path. The kill-switch closed stdin before the heredoc finished writing, producing a SIGPIPE in the parent shell.

**Recovery:** Restructured the test to write the heredoc to a temp file first, then `<hook-script> < tmpfile`, so the producer is fully drained before the hook reads.

**Prevention:** Any hook with an early-exit kill-switch must be tested via file-redirected input, not pipe-fed input. Document the kill-switch's stdin behavior in the hook header comment so test authors know which IO pattern is safe.

**Error 5.** A test fixture passed `subagent_type="malicious xxx"` (with a space) into a `read` builtin without overriding IFS. The default IFS split the value across two fields, corrupting the assertion.

**Recovery:** Quoted the variable on both producer and consumer sides and explicitly set `IFS=` for the `read` invocation in the test harness.

**Prevention:** Any bash test that reads delimited input where field values may contain whitespace must explicitly set `IFS` (typically `IFS=$'\t'` or `IFS=`), or use `read -r` with a single-field consumer and parse downstream.

**Error 6.** While drafting a regex character class for a test, the Edit tool silently rewrote literal U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR) characters into ASCII space (0x20). The intended class `/[\x00-\x1f\x7f<U+2028><U+2029>]/g` became `/[\x00-\x1f\x7f  ]/g`, which then stripped all spaces from sanitized content.

**Recovery:** Rewrote the character class using ` ` / ` ` escape notation. This is the documented case for AGENTS.md rule `cq-regex-unicode-separators-escape-only`; this session is a confirming instance.

**Prevention:** Always use `\uXXXX` escape notation for non-ASCII characters in regex character classes. Treat the Edit tool's input pipeline as ASCII-lossy for any character that visually renders as whitespace.

**Error 7.** Wrote `printf "x%.0s" {1..120}` inside a bash double-quoted string context where the outer quotes were already escaped. The escaped inner double-quotes caused bash to emit 120 separate `"x"` literal strings instead of 120 `x` characters.

**Recovery:** Replaced with `printf 'x%.0s' {1..120}` using single quotes for the format string, sidestepping the escaping interaction.

**Prevention:** When `printf` format strings appear inside an already-quoted shell context, use single quotes for the format string. Avoid layering double-quote escapes — they compose unpredictably with `printf`'s own format-spec parsing.

**Error 8.** Test 10 in the test harness invoked an inner bash subprocess that loaded the Claude Code shell snapshot. The snapshot referenced `$ZSH_VERSION` under `set -u`, which is unbound under bash, causing the subprocess to error out before reaching the test body.

**Recovery:** Isolated the inner subprocess with an `env -i` invocation that did not source the snapshot, and skipped snapshot-dependent setup for that test.

**Prevention:** Tests that spawn fresh shell subprocesses should not inherit the Claude Code shell snapshot path. Use `env -i bash -c '...'` or explicitly unset `BASH_ENV` / `ENV` before the subprocess fires.

**Error 9.** Test T4 in `rule-metrics-aggregate.test.sh` fails on the PR branch. Investigation showed it also fails on main with the same signature.

**Recovery:** Filed issue #3507 to track the pre-existing failure with reproduction steps. Did not block PR #3495 on a regression that predates the branch.

**Prevention:** Per AGENTS.md `wg-when-tests-fail-and-are-confirmed-pre`, every confirmed pre-existing failure must produce a tracking issue in the same session it is observed. The issue is the workflow gate, not a verbal note.

**Error 10.** Initial `.gitignore` patterns for transient hook capture files matched the base filename but missed rotation suffix variants (`.1`, `.2`, `.gz`, `.YYYY-MM-DD`).

**Recovery:** Extended the gitignore globs to cover the suffix space explicitly and verified with `git check-ignore` against synthesized rotation filenames.

**Prevention:** When ignoring a file that any rotating writer may produce, enumerate the rotation suffix conventions of every consumer (logrotate, hand-rolled rotators, gzip post-processing) and add explicit globs. `git check-ignore <synthesized-path>` is the verification step.

## Related

- Sibling empirical-shape learning: [`2026-05-10-claude-code-posttooluse-task-hook-input-shape.md`](./2026-05-10-claude-code-posttooluse-task-hook-input-shape.md) — catalogs the verified field shape itself.
- Issue #3493 — Empirical-shape catalog (parent of the sibling learning).
- Issue #3494 — Token-efficiency analysis parent issue (this PR).
- Issue #3497 — Aggregator tuning follow-up.
- Issue #3507 — T4 pre-existing failure in `rule-metrics-aggregate.test.sh`.
- Issue #3508 — Rotation scope-out (deferred from this PR).
- Issue #3509 — Drops handling scope-out (deferred from this PR).
- AGENTS.md rule `cq-regex-unicode-separators-escape-only` — Error 6 above is a confirming instance.
- Precedent: `.claude/hooks/skill-invocation-logger.sh:13-22` — date-stamped empirical-shape header comment, the artifact pattern this learning argues every new hook must adopt.
