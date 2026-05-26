---
title: test-all.sh tail-masking and Monitor exit-condition tightness
date: 2026-05-18
category: best-practices
tags: [bash, test-runner, monitor, grep, exit-codes]
related_prs: [4011]
---

# test-all.sh tail-masking and Monitor exit-condition tightness

Three session-tooling gotchas surfaced during one-shot PR #4011 (cla-evidence WORM-409 idempotency fix). All three swallowed signal that should have been load-bearing; recovery required re-running the underlying operation with stricter capture.

## 1. `bash scripts/test-all.sh 2>&1 | tail -40` masks the real exit code

**Symptom:** Background task reported `exit code 0`. Output showed `=== 59/62 suites passed ===` — 3 suites silently failed.

**Root cause:** Without `set -o pipefail` (the Bash invocation here is `bash -c '...'` from the agent harness, which does not inherit pipefail), the exit status of a pipeline is the exit status of the LAST command. `tail -40` always exits 0, so the non-zero from `bash scripts/test-all.sh` was discarded.

**Recovery:** Re-ran the script with redirect + `$?` capture:

```bash
bash scripts/test-all.sh > /tmp/test-all-full.log 2>&1; rc=$?; echo "EXIT=$rc"
```

The second run reported `EXIT=1`, and `grep '^\[FAIL\]' /tmp/test-all-full.log` named the 3 failing suites (all pre-existing, unrelated to the PR's diff scope).

**Prevention:** When running any aggregate test script whose pass/fail signal is load-bearing (`scripts/test-all.sh`, `bun test`, `npm test`, `pytest`, `go test ./...`), do NOT pipe through filtering. Either (a) redirect full output to a log and inspect `rc=$?` explicitly, OR (b) prepend `set -o pipefail` in a wrapping `bash -c`. The convenience of `| tail -40` to reduce conversation noise is not worth a false-pass. This is a manifestation of the broader rule `hr-when-a-command-exits-non-zero-or-prints` — pipeline filtering is one of the most common ways to silently swallow a non-zero exit.

The agent harness's "Bash completed with exit code 0" report is structurally identical to a real pass; the only way to distinguish is to make the underlying script's exit code reach the wrapper unmodified.

## 2. Monitor's `pgrep -f` exit condition self-matches the Monitor wrapper

**Symptom:** `Monitor` armed with `until ! pgrep -f "scripts/test-all.sh" >/dev/null; do sleep 5; done` ran past the actual exit of `bash scripts/test-all.sh` for 15+ minutes, emitting `running:` notifications forever (until the 600s timeout).

**Root cause:** The Monitor's own shell wrapper is launched as `/bin/bash -c '... until ! pgrep -f "scripts/test-all.sh" ...'` and the literal string `scripts/test-all.sh` is part of its argv. `pgrep -f` matches against the full command line of every process, so the Monitor's pgrep matches the Monitor's own bash -c invocation. The until-loop condition is always true. The underlying `bash scripts/test-all.sh` process exited 30 seconds in; the Monitor watched its own shadow for the next 15 minutes.

**Recovery:** Switched to `pgrep -fx "bash scripts/test-all.sh"` (`-x` requires whole-line exact match). The Monitor's wrapper command contains the pattern as a substring inside a much longer `bash -c '...'` argv, so `-fx` correctly excludes it.

**Prevention:** When monitoring for the absence of a specific shell-script process, use `pgrep -fx '<exact invocation>'` not `pgrep -f '<substring>'`. The substring form silently self-matches whenever the Monitor's own command line contains the script name (it always does, by construction — the Monitor invokes the watch loop via a single `bash -c '...'` whose argv is the entire script). The cheaper alternative: use a sentinel file the watched script writes on exit, and `until [[ -f /tmp/done ]]; do ...`. No process-table introspection, no self-shadowing.

## 3. `grep -c '${dup_label}'` returns 0 because `$` is a BRE EOL anchor

**Symptom:** Plan AC1 verification `grep -c 'worm-${dup_label}' apps/cla-evidence/scripts/r2-conditional-put.sh` returned 0, even though the file contains 2 occurrences of the literal `worm-${dup_label}` (visible via `grep -n`).

**Root cause:** Default `grep` uses Basic Regular Expressions (BRE). In BRE, `$` is a metacharacter meaning end-of-line. The pattern `worm-${dup_label}` parses as "the literal `worm-`, then end-of-line, then the literal `{dup_label}`" — which cannot match anywhere because nothing follows end-of-line on the same line.

**Recovery:** Re-ran with `grep -cF 'worm-${dup_label}'` (`-F` forces fixed-string match). The two occurrences matched as expected. Same class on AC11's heredoc-escape level: the plan's verification command escaped `$` for a shell expansion that didn't happen inside the literal string, producing a 0 instead of the expected 1.

**Prevention:** When writing a plan AC's `grep -c '<literal>'` verification command, AND the literal contains any of `$`, `{`, `}`, `*`, `.`, `(`, `)`, `[`, `]`, `\`, `+`, `?`, `|`: use `grep -cF` (fixed-string). The plan-quality checklist (Phase 4.5 in /soleur:plan, plan-quality sharp edges) should add this as a precondition: any AC grep over a literal containing BRE/ERE metacharacters must use `-F`. The deepen-plan reviewer should mechanically verify each AC grep command is regex-safe before deepening completes.

## Cross-cutting lesson

All three errors share a shape: **a signal got filtered through a layer that silently transformed it.** Pipeline `| tail` discards the exit code; `pgrep -f` matches the Monitor's own invocation; default `grep` interprets metacharacters in a "literal" string. The recovery in each case was to bypass the filtering layer (redirect-not-pipe, `-x` for exact match, `-F` for fixed string).

The general prevention is "when a signal is load-bearing, the cheapest layer to verify is the one closest to the source." Inspect `rc=$?` directly. Match the literal script invocation, not a substring. Use `-F` when the pattern is a literal.

## Session Errors

- **test-all.sh tail-masking** — Recovery: re-ran with `> /tmp/test-all-full.log 2>&1; rc=$?`. Prevention: never pipe a test runner whose pass/fail signal is load-bearing through `| tail` without `set -o pipefail`. Add to /soleur:work Phase 2.9 + /soleur:ship Phase 5.5 instructions.
- **Monitor pgrep-self-matching** — Recovery: switched to `pgrep -fx '<exact>'`. Prevention: document this as a sharp edge in the Monitor tool's usage notes, and prefer sentinel-file watchers over process-table introspection when the watched script's argv contains its own pattern.
- **AC grep BRE metacharacter footgun** — Recovery: switched to `grep -cF`. Prevention: deepen-plan reviewer should mechanically verify each AC `grep -c` over a literal uses `-F` when the literal contains BRE metacharacters. Add to /soleur:deepen-plan or /soleur:plan checklist.
