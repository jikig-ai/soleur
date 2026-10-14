# Learning: a pipe reader that exits early flipped three CI suites, and the fix for the producer side was a stub that reads

## Problem

Five merge-queue/CI flakes on 2026-10-05 were re-investigated from the completed run logs (PR #9525, tracker #7376).
Three of them were one bash defect: a pipeline whose reader exits before its writer finishes, under `set -o pipefail`.

- `cron-egress-firewall.test.sh`: `echo "$CEN_MEMBER_SCAN" | grep -qxF "HIT …/m5.ts"` printed
  `echo: write error: Broken pipe` in the CI log, and member `m5` read as unflagged.
- `reap-archive-persistence.test.sh` assertion G: `git log … | grep -q 'chore(archive-kb)'` reported the commit missing
  while a debug copy proved it was present (3/24 and 6/32 red under 24-32 parallel copies, 0/1 serial).
- `workspaces-luks-verify-workflow.test.sh`: the probe step's `printf 'DOPPLER_TOKEN=…' | ssh …` classified
  `unavailable/unparsed` instead of `selftest`, because the test's ssh stub never read its stdin.

The tracker's leading hypothesis (shared scratch dirs, `-P` contention) was half right: contention is the trigger that
opens the scheduling gap; the cause is the pipe shape. The other two flakes in the brief were not this class: the e2e
ejections were a Turbopack Google-font compile failure and a `role=status` strict-mode collision, and
`lint-bot-statuses` was a deterministic content failure, not a flake.

## Root cause

`grep -q` exits on its first match; if the writer still has bytes to write it takes SIGPIPE (rc 141) or, where SIGPIPE is
ignored as on the CI runner, EPIPE (the builtin `printf`/`echo` returns 1). `pipefail` makes that status the pipeline's
status, so a match reads as a miss, and a negated or `&&`-chained site reads as a false PASS. Three corrections to what the
repo believed:

- **Size is not a bound.** #7005 and #7432 held that it needs more than the 64 KiB pipe buffer. It fired with a 3-line
  `git log` producer and with an `echo` of a few KB.
- **It has a producer-side form.** The luks suite's pipe is `printf | stub`; the stub exited without reading, so a late
  `printf` took the signal. No line search over the test file sees that mechanism.
- **The disposition changes the status.** Under an ignored SIGPIPE the failing status is 1, not 141, so a test that asserts
  "not 141" is wrong on the very host the flake occurs on.

## Solution

- Consumer side: `grep -q P <<<"$V"` (33 sites) and `grep -q X < <(producer)` (11 sites, keeps the one-line shape inside
  `if … \` chains). No pattern text changed; verified by an inverse transform over the changed lines only (33 segments).
- Producer side: the stub drains stdin and keeps what it read; `drive()` runs the extracted body with stdin from
  `/dev/null`; the `tar xzf` arm drains too.
- Regression rows that can fail: a handshake helper holds the single `printf` call until the stub has begun the probe call,
  one must-PASS row, and one control row (non-draining stub, probe rc 1, `unavailable/unparsed`) under an ignored SIGPIPE.
- Guard: `grep-q-pipe-guard.test.sh` pins the three suites at zero (`FILES_7376`, a dedicated `scan_pipes`, comment lines
  stripped), with probes for negated, `&&`, awk-exit, trailing-comment and unreadable-input shapes.

## Key insight

1. **A race row pinned by timing is a timing-only test.** The first version passed when the stub drained and also when it
   merely exited inside the poll window. Pin the mechanism: assert the piped text actually ARRIVED in the stub, assert the
   hand-off was released by the sentinel and not the timeout, and pin that the rewritten copy of the production body differs
   from production in exactly one line. Each was a mutant the first battery let survive.
2. **A membership check for an entry in a hand-maintained array must read that array's body, comments dropped.** The first
   parity check grepped the whole index file; the reap suite names itself in its own array there, so deleting the guard's
   entry stayed green, and a commented-out entry passed. Four review seats found the same hole independently.
3. **The producer side is invisible to a line search.** The guard header now says so, and points at the race rows that hold
   it; the structural-enumeration seat's map (category counts per suite) is the right tool for what a regex cannot see.
4. **Measure a held-open stdin by timing the suite, not the pipeline.** `sleep 600 | timeout 400 bash suite` waits for the
   sleeper regardless of how fast the suite finishes.

## Session Errors

1. **First cron rewrite regex matched 59 sites, not 33.** The flag class was too broad (it also took `grep -c`). Recovery:
   the assert-before-write stopped it; narrowed to flags containing `q`. Prevention: derive the expected count from the
   guard's own PATTERN before writing, and keep the assert ahead of the write.
2. **Three mutation attempts were not valid mutants** (a `sed` delimiter clash, an anchor in the wrong file, and deleting only
   an `ok` line, which produced a syntax error rc 2 rather than a weaker program). Recovery: re-ran with a python anchor
   assert and a syntactically valid weaker replacement (`ok …` to `:`). Prevention: a mutant must be a working, weaker
   program, and the run must report NOT LANDED when the anchor is absent.
3. **`test-all.sh --affected` degraded to the full battery (rc 4)** because the diff edits `scripts/lib/test-affected-paths.sh`
   while a sibling worktree held the gate; the scoped selector then queued behind seven tickets. Recovery: cancelled both by
   name and ran the consumer suites, guard, ratchets and orphan lint directly; CI is the full gate. Prevention: known and
   documented in the work skill; also note that editing that file makes the PR's CI run the five PR-gated batteries (about
   2,900 s of runner time, once per push), so batch fixes into one push.
4. **A pipeline-based held-open-stdin test measured the sleeper.** Recovery: stopped the task and read the suite log's own
   mtime (finished in about a minute, 316/0). Prevention: time inside the suite, or hold the pipe open with a FIFO.
5. **The parity check I added was whole-file** (see Key insight 2). Recovery: array-scoped, comment-aware, with its own probe
   (a member only in another array, a commented-out entry, a missing array). Prevention: scope any membership test to the
   container it names.
6. **Plan prose went stale as the design moved** (34 vs 35 here-string sites, "two race rows" vs five assertions, "the landing
   check counts every producer", sentinel creation in no-drain mode only). Recovery: corrected in the review commits.
   Prevention: re-derive plan-quoted counts at work start (existing rule) and update the plan in the same commit that
   changes the design.
7. **The trap-ownership lint was called with an unsupported `--base`** (rc 2). One-off; read `--help` first.
8. **`session-state.md` was written without blank lines around headings**, so markdownlint failed in a later pass. One-off;
   lint every markdown file in the commit that writes it.
9. **The stop hook blocked turn endings that named a future action.** Recovery: ended turns on a named gate
   (`<stop>BLOCKED: …`). Prevention: end a turn only on an action performed or a gate named.
10. **A sibling session's PR (#9523) edited the same reap suite and carried the e2e work I had planned as PR-2**, found only
    from a gate banner naming the sibling worktree. Recovery: read its diff, recorded merge order (this PR first), did not
    start PR-2. Prevention: at plan time list worktrees by the defect noun (existing one-shot rule).
11. **The PR's first CI cycle failed on a ratchet I had not run.** `scripts/test-affected-kb-consumers.test.sh` reads one hop
    into the scripts a registered suite names; the guard now names three suites, and their fixture strings produced six
    uncovered `knowledge-base/` references. I had run "the ratchets" from memory, not from the list. Recovery:
    `--write-baseline` (six rows, all for the guard; the guard reads none of them), re-ran 22/22, one more push.
    **Prevention:** when a diff edits `scripts/lib/test-affected-paths.sh` or makes a registered suite name another script,
    enumerate the ratchets with `grep -l 'ratchet' scripts/*.test.sh` and run each, rather than the ones the plan listed.

## Tags

category: test-failures
module: ci-infra-test-suites, grep-q-pipe-guard

## Related

- `2026-09-25-the-flake-was-sigpipe-at-4kib-and-my-fix-leaked-a-pipe-status-through-a-bare-return.md` (the consumer-side
  mechanism and the capture-once fix this builds on)
- `2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md`
- `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`
- Trackers: #7376, #7432, #9217 (repo-wide sweep), #7005, #6601; follow-ups #8785, #9170 (e2e), #8022 (live-verify)
