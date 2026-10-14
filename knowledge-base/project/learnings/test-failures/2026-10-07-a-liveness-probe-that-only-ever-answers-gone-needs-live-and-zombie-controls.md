# Learning: a liveness probe that only ever answers "gone" needs live and zombie controls

## Problem

Issue #9670: the row "a real grandchild in the child's process group is reaped on exit" failed once in a
`merge_group` run (`the grandchild survived the child's exit ... expected true to be false`). The issue
said "the assertion checks once". It did not: the row already polled 3s and then probed once, so adding
a poll would have changed nothing. The product code (`process.kill(-child.pid, "SIGKILL")` in the
`exit` handler) was correct; SIGKILL delivery is asynchronous (the sleeper was still alive on the first
post-exit probe in 391 of 400 runs under load average ~40, gone within 72ms every time), so the
failure needed a longer stall than any local load reproduced.

## Solution

One test file. Replace the 3s hand-rolled loop with `vi.waitFor({ timeout: 15_000, interval: 25 })`
(above the repo's 10s contended-CI floor, #5796), raise the row timeout to 40s, fold the failure into
`expect.fail` with pid / last probe state / waited ms / loadavg so a recurrence is countable on the
issue, and harden the inline probe: `ESRCH` means gone and `EPERM` means alive, the state char is parsed
after the LAST `)`, and a `/proc/<pid>/stat` read that vanishes counts as dead only when
`/proc/self/stat` shows this pid (`procIsOurs`).

The 8-seat review's best finding came from the test-design seat: the row only ever watches the probe
answer "gone", so an always-false oracle, an `S`-is-dead oracle and a first-paren parser all passed the
file with the product kill removed. Three control rows now drive the probe on known inputs: a live
`sleep`, a live process whose comm is `x) Z y`, and an unreaped zombie. All five oracle mutants are
killed (always-false, S-is-dead, first-paren, Z-blind, `kill(0)`-only).

## Key Insight

A probe used only in the "should be gone" direction is unfalsifiable on its alive branch, so the test
that depends on it proves nothing about that half until something feeds it a live process.

Reusable recipes:

- **Unreaped zombie fixture:** `sh -c 'sleep 0 & echo $!; exec sleep 120'`. The exec'd parent never
  waits, so the `sleep 0` child stays `Z`, `kill(pid, 0)` still succeeds, and `/proc/<pid>/stat` shows
  `) Z `. Kill the parent in `finally`.
- **Comm with a paren:** copy a standalone `sleep` to a file named `x) Z y` (skip if `sleep` is a
  multicall binary). A first-paren parse of `123 (x) Z y) S ...` reads `Z`.
- **State right after exec is transient `D`/`R`:** wait for `S` instead of asserting it immediately.
- **vitest `repeats` is reported as one test and this repo's vitest config swallows `console.log`**
  from a repeated row. Count iterations with a file append and compare unique temp dirs; a printed
  "16 passed" says nothing about 50 runs.
- A surviving mutant needs a label: the EPERM branch needs a process of another uid, so it is
  equivalent for a same-uid fixture and was recorded as such rather than "fixed".

## Session Errors

1. **Session-start `cleanup-merged` ran past the 120s tool timeout** — Recovery: moved to background,
   proceeded — Prevention: none needed (already fail-open by design).
2. **Mutation-run command containing `pkill -f` blocked by the pkill-self-match hook** — Recovery:
   nothing in the command ran; re-ran without it — Prevention: hook already enforces; use
   `proc.sh kill_mine` / a captured PID.
3. **`sleep 150; echo` used as a wait, blocked by the foreground-sleep hook** — Recovery: bounded
   polling loops — Prevention: hook already enforces.
4. **`test-all.sh --affected` queued at position 6 behind sibling worktrees** — Recovery: stopped it
   with `kill_mine`, left the gate to ship Phase 4 and CI — Prevention: already documented (ADR-133 /
   review risk-tier reference); read `--capacity` first.
5. **First control row asserted `state S` immediately after exec and failed once (`state D`)** —
   Recovery: wrapped in a settle `vi.waitFor` — Prevention: see Key Insight (transient state after exec).
6. **`console.log` inside a `{ repeats: 49 }` row printed nothing, so the 50 iterations were
   unprovable from the runner output** — Recovery: file-append counter, 50 unique temp dirs —
   Prevention: see Key Insight; never trust a repeat count the runner does not itemise.
7. **Two-dot style `git diff --stat origin/main` listed 26 files because local `origin/main` was
   ahead** — Recovery: three-dot diff — Prevention: already documented in the review skill.
8. **playwright MCP server failed to connect** — not needed for a test-only change.

## Tags
category: test-failures
module: apps/web-platform/test/server/inngest
