---
title: "test-all exits 1 with every shown suite green — the failure is in the middle, and the fix loop costs hours under lock contention"
date: 2026-09-26
category: workflow-issues
module: scripts/test-all.sh
issues: ["#8868"]
pr: 8868
tags: [test-all, lefthook, pre-commit, lock-contention, affected-gate, debugging]
---

# Learning: exit 1 behind a green summary — grep the captured log, don't re-run to diagnose

## Problem

The lefthook `pre-commit` battery (`bun-test` = `test-all.sh --affected`) exited 1
three times while every hook line ended `✔️` and the only visible failure was
`🥊 bun-test`. The visible tail showed `3701 pass, 0 fail` for the plugin suite —
a green wall that is *not* the verdict. The actual verdict line is the epilogue:

```
=== 519 suites: 231 passed, 2 failed, 0 killed, ... ===
```

and the failed suites are named inline as `[FAIL] <path>` entries scattered
through ~25k lines of suite output — never near the bottom. Three distinct
failure classes hid this way across the three attempts:

1. `test/eslint-config.test.ts` — a scratch-looking file + one genuinely unused
   `res` binding pushed `@typescript-eslint/no-unused-vars` to 75 > baseline 74.
   The finding text itself says "Check `git status`" — it enumerates lint-set
   drift, not just new violations.
2. `test/plugin-root-anchoring.test.ts` — a `:-` default arm written into
   `go.md` (`${CLAUDE_PLUGIN_ROOT:-${GROK_PLUGIN_ROOT:-}}/…`). The corpus is
   pinned: payload docs may only write the bare `${CLAUDE_PLUGIN_ROOT}` token;
   the harness substitutes it, and `GROK_PLUGIN_ROOT` fallback lives in
   resolution arms, never in producer operands. Portability prose must say
   "no-op on harnesses that export neither" rather than spelling a shell
   fallback.
3. `scripts/lint-shell-trace-credential-refusal-repo` + `fixture-cd-containment` —
   a new script touching a live credential needs BOTH the xtrace refusal
   (`case "$-" in *x*) … exit 78`) and `curl --disable --noproxy '*'` with
   `--disable` FIRST; and a test's `( cd "$R2"; parallel-emits & wait )` needs
   `cd "$R2" && { … & wait; }` — `&&` without the brace group only guards the
   first background job.

Compounding cost: each `git commit` re-ran the whole battery, and `test-all`'s
advisory lock serialized behind sibling worktree runs — ~2 h per attempt,
mostly queue. The diagnosis (grep one file) took seconds; the verification
(another commit) took hours. Verify fixes cheaply per-suite *before* re-committing.

## Solution

- After any `test-all`/`bun-test` failure, go to the lefthook-captured output
  (devin overflow file / the run's own log) and grep:
  `grep -nE '\[FAIL\]|Failed Tests|suites:.*passed' content.txt` — then read
  ±30 lines around each `[FAIL]`. Do not re-run the battery to "see" the
  failure; it is already recorded.
- Per-suite verification before the next commit: `bunx vitest run <file>`,
  `python3 scripts/lint-shell-trace-credential-refusal.py <script>`,
  `bash plugins/soleur/test/fixture-cd-containment.test.sh`. Each took <1 min
  where the gate took ~2 h.
- Credential-handling shell scripts: copy the pinned shape verbatim —
  xtrace refusal right after `set -uo pipefail`, and credentialed curl as
  `curl --disable --noproxy '*' …` (position is load-bearing: `--disable` first
  aborts `~/.curlrc`; `--noproxy '*'` blocks ALL_PROXY/HTTPS_PROXY redirect
  with the destination pin intact). Model: `scripts/supabase-logs-query.sh`.
- `${CLAUDE_PLUGIN_ROOT}` in plugin payload docs: bare, quoted token only.
  No `:-`, `:?`, `-`, `:=`, `$(printenv …)`, unbraced `$CLAUDE_PLUGIN_ROOT`, or
  `!`-indirection — the anchoring corpus rejects all of them. Grok porting is
  the *resolution layer's* job (`ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"`
  arm in go.md fences), and producer lines on harnesses without a root var
  fail open by design.
- `cd` in tests: `cd "$dir" && { … }`, and wrap multi-command bodies in `{ }`
  so `&&` scopes over all of them — `cd x && a & b & wait` backgrounds `b`
  unguarded from the parent cwd.

## Key Insight

The suite-verdict line (`=== N suites: … failed …`) is the only honest summary;
hook summaries and per-file tails are not. When the failure log is already on
disk, diagnosis is a `grep`, not a re-run — under a serialized advisory lock a
re-run to *observe* is indistinguishable from a re-run to *fix*, and it costs
hours.

## Session Errors

1. **Killed a lock-queue child of the gate run itself** (pid misidentified as a
   stray duplicate `test-all`). The run survived — the queue child respawned —
   but the kill targeted a process I had not inspected.
   **Prevention:** inspect the process tree (`/proc/<pid>/task/*/children`,
   `ps -o ppid=`) before any kill; a test-all in queue sleeps on `sleep 60`
   loops that look orphaned.
2. **Wrote a credentialed curl without the repo's pinned shape** — no xtrace
   refusal, no `--disable --noproxy '*'`. Caught by
   `lint-shell-trace-credential-refusal-repo`, fixed in place.
   **Prevention:** the lint exists and fired; when adding a credential-touching
   script, copy `scripts/supabase-logs-query.sh`'s shape rather than writing
   curl flags from memory.
3. **Spelled a `:-` fallback arm on `${CLAUDE_PLUGIN_ROOT}` in go.md** — the
   one form the anchoring corpus structurally forbids. Caught by
   `plugin-root-anchoring.test.ts` P1 + W1, reverted to the bare token.
   **Prevention:** same class as #2 — the corpus is pinned and its test names
   the accepted spellings; check it before editing any producer line.
4. **An unused `res` binding in a new test pushed the eslint baseline over** —
   `no-unused-vars` is pinned repo-wide at a number, not a zero-tolerance per
   file. Caught by `eslint-config.test.ts` Guard 2.
   **Prevention:** run `npx eslint` on every touched file before staging;
   baseline counters make "one unused var in a test" a blocking finding.
5. **First fix for the cd-containment violation was itself a violation class.**
   `cd "$R2" && bash a & bash b & wait` leaves `b` unguarded in the parent cwd.
   Recovery: `cd "$R2" && { bash a & bash b & wait; }`.
   **Prevention:** when a guard rule fires, read the rule's fixture corpus
   (`fixture-cd-containment.test.sh` shows the exact guarded spellings it
   accepts) instead of inventing a near-miss.
6. **An Edit removed the `--selfcheck` block of emit-decision.sh** (old_string
   overlapped it). Caught on re-read; restored.
   **Prevention:** after an Edit anchored on a preamble, re-read the whole
   function region — prefix-anchored replacements silently swallow trailing
   blocks.
7. **A thenable test-mock's `then` didn't satisfy `PromiseLike`, and the first
   fix attempt introduced a syntax error** (generic arrow in an object
   literal). Recovery: method shorthand + explicit casts.
   **Prevention:** when mocking `await`-ables, copy the repo's existing
   thenable-mock shape instead of writing `then` freehand.
8. **`git commit --dry-run` with a real hook battery** spent output; hooks do
   not run on dry-run, so it told nothing about the gate.
   **Prevention:** one-off; the battery only runs on the real commit.
9. **Believed `--repo-scan` existed** on lint-shell-trace-credential-refusal.py
   (it does not; `--census` and positional paths do).
   **Prevention:** one-off; `--help` first.
10. **Misdiagnosed the first exit-1 as "c4 hook modified the index"** instead
    of grepping the captured log for `[FAIL]` — a hypothesis before evidence.
    **Prevention:** exit≠0 with all-hook ✔️ ⇒ the verdict is a per-suite
    `[FAIL]` line in the middle of the log, not the summary; grep first.

## Related

- `plugins/soleur/skills/review/SKILL.md` — the 11-seat panel that produced
  the fixes these commits carried.
- Issue #7797 (xtrace/credential refusal), #6789 (test-all contention model),
  #7453 + ADR-179 A18/A20 (plugin-root anchoring corpus), #1383 (project-tree
  sentinel regression this branch fixed).
