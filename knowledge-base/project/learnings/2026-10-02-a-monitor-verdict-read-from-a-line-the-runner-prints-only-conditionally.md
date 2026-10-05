# Learning: a monitor verdict read from a runner line that is printed only conditionally

## Problem

#8112 ("CI: main branch tests failing") was open for 19 days with 76 "still not passing" comments while main's
tests were green. The main-health-monitor was misreporting twice over:

1. Its filer treated a bare `^\[FAIL\]` line as the verdict. Seven `[FAIL]` lines in the body were EXPECTED
   positive controls printed by suites that exercise their own `fail()` helper, and the same capture's runner
   breakdown said `0 failed`.
2. The real failing signal was budget exhaustion: the tests step was killed by its own 40-minute ceiling on
   every run (2411-2413 s, 60 of 60 listed runs). Every earlier ceiling derivation had read a CENSORED duration.

## Solution

- Verdict = the runner's own output: a `RED`/`UNACCOUNTED` line, or a printed `=== N suites: ... F failed ...`
  breakdown with `F >= 1`. `[FAIL]` became display-only, labelled "unconfirmed" when nothing corroborates it.
- One uncensored dry run (ceilings temporarily raised, dispatched from the branch) measured tests 4228 s and
  infra 2326 s, and each suite step now records its own `elapsed_s` so the next derivation needs no dry run.
  Ceilings re-derived: tests 110, infra 60, job 185; Sentry `max_runtime_minutes` and `checkin_margin_minutes`
  re-aligned and pinned by a parity row.
- Review then found the design's own blind spot (below), which is the generalizable part.

## Key Insight

**A verdict parsed out of another program's output is only as good as that program's EMISSION CONDITION, and the
shape of the line says nothing about when it is printed.** The plan, the deepen pass and the author all
validated the breakdown regex against a captured line (`=== 549 suites: 547 passed, 1 failed, ...`) and
derived the regex from the runner's `echo`. None read the `if` around that `echo`. `scripts/test-all.sh`
prints the breakdown only when something was killed, skipped, declined or observed; a plain failing run prints
`[FAIL] <suite>` and the terminal `=== P/N suites passed ===` and nothing else. On such a run the new
classifier would have titled a genuinely failing main "did not complete" and told the operator not to revert:
the inverse of the original bug, and invisible today only because the infra runner is declined on main
(`not_in_diff` counts as `skipped`), a coincidence of an empty diff.

Companion lessons from the same review:

- A check that proves a wiring by token presence (`tests_elapsed_s=` appears in the Record step) is satisfied by
  a deleted producer, a mis-mapped `env:` line and a half-guarded consumer. Pin each EDGE: producer writes,
  output name, env mapping to the right step's output in every consumer, numeric guard per variable, and
  execute the consumer's real body with hostile values.
- Fixtures that sit inside the `tail -30` window cannot prove a dedicated append is needed. Put a 34-line
  epilogue after every evidence line, and match labels as whole lines, since arm prose quotes the same phrases.
- An explanatory sentence an action list adds is a claim: "a printed figure near the ceiling means the step ran
  out of time" had the semantics inverted (a killed step prints no figure) and was a cause the job did not
  measure (ADR-166).

## Session Errors

1. **Unverified plan premise about the runner's emission condition** — Recovery: review's architecture and
   structural seats; added a `[FAIL]` + short-terminal-marker fallback gated on no printed breakdown and no
   parent-death line, with five rows (including the exact #8112 capture staying arm 4). **Prevention:** when a
   plan keys a classifier on an emitter's output line, read the emitter's guarding condition and record when the
   line is NOT printed; fixture the case where it is absent.
2. **Wiring asserted as token presence** — Recovery: static (8k) rewritten per edge; Record step body extracted
   and executed (R0-R4); infra and comment-path rows (B19c/B19d). **Prevention:** for any added data path,
   name the mutation that deletes the producer or the mapping and confirm a row reds; keep injection-only rows
   from standing in for the real env mapping.
3. **Arm-4 action 2 inverted** — Recovery: reworded, with the `gh run view` command and the seconds-vs-minutes
   conversion. **Prevention:** re-read each new instruction against the producer's behaviour before shipping
   (the figure is absent on a kill).
4. **`${{ }}` inside a double-quoted bash string** (in a test row description) aborted with "bad substitution" and
   showed up as an accounting FATAL (PASS+FAIL != CASES). **Prevention:** keep workflow-expression literals out
   of double-quoted shell strings; the accounting check pointed straight at the silent row.
5. **A scripted edit batch that did nothing** — a second Python call carried a trailing `if False else None`, so
   three comment edits to the infra runner silently did not land; only a follow-up `grep` showed it.
   **Prevention:** after any scripted multi-edit, grep the new anchor (already a documented class; the
   instrument is the check, not the script's success message).
6. **Forward-looking sentence at turn end** triggered the unkept-promise stop hook. **Prevention:** end a
   waiting turn with a declarative `<stop>BLOCKED: ...</stop>` that names what is awaited, or do the action.
7. **Background wait capped at 2 h** while 4 h was requested; the timer died and was re-armed. **Prevention:**
   size clock waits under the 2 h cap and re-arm, or watch the condition rather than the clock.
8. **`pgrep -f` rejected by hook** while checking for a running suite. **Prevention:** read the task output file
   or use the captured PID.
9. **Spelling-pinned rows broke on a flag order** — `grep -a -E` missed row (10)'s `grep -E` exemption, and `-a`
   on the display filter would have broken (13)'s extraction. **Prevention:** put new flags where the pinned
   spelling tolerates them, and prefer rows that pin the effect over the spelling.
10. **Dry run planned from a branch that lacked the merged apt fix** — Recovery: merged `origin/main` before
    dispatch so the infra step was measured undisturbed. **Prevention:** before a measurement dispatch, check
    which merged fixes the measured steps depend on.
11. **Playwright MCP failed to connect during planning** (not needed). One-off.
12. **A probe `cd` into a sibling worktree changed the session cwd.** **Prevention:** `cd <abs> && cmd` in a
    subshell or use `git -C`.

## Tags
category: workflow-issues
module: main-health-monitor, ci-classifier
