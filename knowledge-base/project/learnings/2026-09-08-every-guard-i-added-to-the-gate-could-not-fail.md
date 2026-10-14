---
title: "Every guard I added to a vacuity gate could not fail, and my battery certified them"
date: 2026-09-08
category: test-failures
module: plugins/soleur/test
issue: 7466
tags: [mutation-testing, vacuity, bash, ansi, security]
---

# Every guard I added to a vacuity gate could not fail

## Problem

`preflight-check10-suite-integrity.test.sh` is the gate whose thesis is *"a suite that
asserts nothing is indistinguishable from one that passed."* Its bun-summary parser
anchored four greps at `^[[:space:]]*`, which cannot cross the ESC that begins a
colour-coded summary line, and its failure-count arm printed `[ok]` on a count it had
never read (#7466).

The parser fix was ~40 lines and correct. A nine-agent review then found **eight P1s**,
and only one was pre-existing in spirit. The rest were in the guards and the prose I
added while fixing it.

## What the review found

Four independent agents each found a different instance of ONE property: *a guard that
cannot fail is indistinguishable from one that passed* — the file's own thesis, violated
four ways inside its own repair.

- **A forged counter.** `$LOG` is bun's stdout AND stderr, so it carries every byte the
  suites print. Measured: 132 assertion-free tests plus one
  `console.log(" 999999 expect() calls")` cleared the assertion floor and scored a clean
  green. The source-pattern and manifest controls both passed, because the test *names*
  were intact. Second placement: `bun test >"$LOG" 2>&1` hands fd 1 to every child a test
  spawns, so a child can poll for the terminator and append forged counters AFTER bun
  exits, where `tail -1` prefers them.
- **`^[0-9]+$` is not an integer guard for `[[ ]]`.** Arithmetic evaluation reads a
  leading zero as octal, so `08` satisfies the regex and then makes every comparison abort
  and return false. All three floors bypassed — while the integer check I had just added
  printed `[ok] every counter is an integer at the point of comparison` on the exact value
  breaking the comparison. `2^63` survives it too, by wrapping.
- **Conservation is a SUM, so it cannot see a misroute.** `fail() { PASS=$((PASS + 1)); … }`
  — one token — printed `[FAIL]` lines and still reported `25 passed, 0 failed`, exit 0.
  `cases` never moved and the sum was conserved.
- **Absence was an inference, not a measurement.** `summary_measured` reads `pass` and
  `fail`; the other three were normalised from `-` to `0`, so a parse failure confined to
  skip/todo printed `skip=? todo=?` directly above `[ok] no tests skipped or todo'd`.

## Solution

One anchor closed three of them: bun's `Ran N tests across M file.` line is both the
terminator that bounds the trusted region and the unconditional total that turns the
absence-inference into `pass + fail + skip + todo == ran`. Plus `10#` normalisation at the
producer, an append-only `VERDICTS` transcript read by a directional routing check, a
second instrument probe for the comparator that had none, and runtime dispatch counters.

## Key insight

**A battery measures the mutations its author imagined, and the reason given for skipping
an axis is worth checking before the axis is skipped.** Mine reported 19/19 clean. Its
stated justification for not mutating the verdict helpers — *"already covered by
`scripts/guard-vacuity-floor.test.sh`"* — was FALSE: that guard constructs a NEUTERED
helper (verdict lost, conservation fires), never a MISROUTED one. Run against the real
mutation it reports 23/23 green and names this file zero times. That single false sentence
excused the axis both dispatch P1s came from.

The corollary is sharper: **on a fix PR, the new assertions are the least-audited surface
in the diff.** They are written while holding the old bug in mind, so they pin the shape of
that bug rather than the property. Review them before the fix.

## Session Errors

1. **The first mutation battery's own harness was broken.** Nested shell heredoc quoting
   mangled the Python, so M1 built a `strip_ansi` that emitted nothing and scored S1 RED —
   when S1 staying GREEN *is* the proof the REDs came from colour. **Recovery:** rebuilt
   with one quoted-heredoc script per row. **Prevention:** build mutations as standalone
   `.py` files; assert the mutation landed via `diff -q` against a pristine copy AND that
   the intended construct changed, not merely that the file did.
2. **Two comments collided with the plan's own grep ACs** — prose quoting `\x1b` beside the
   word `sed`, and quoting `: "${n_pass:=0}"` verbatim. **Recovery:** reworded the comments,
   not the assertions. **Prevention:** after writing a comment that documents a construct an
   assertion greps for, run that assertion.
3. **A block replacement silently deleted V1–V4 and the N2 probe**, leaving `assert_measured`
   defined and called zero times — four verdicts gone, with `cases` and conservation both
   still consistent because the calls vanished together with their counts. **Recovery:**
   caught by grepping for call sites. **Prevention:** shipped — runtime dispatch counters.
   Note the first attempt at that guard counted call sites textually and scored the
   DEFINITION as one, so it was vacuous; only running the mutation exposed it.
4. **A broken `sed` extraction reported as a result.** The range split `strip_ansi` across a
   line continuation, so every "parsed" value came from a nonexistent function — and two
   lines printed a confident `TRUE (floor fires)` from an empty variable. **Prevention:**
   verify the instrument (`declare -F`, a known-positive) before reading any measurement.
5. **Reasoned past a measurement already on screen.** Chose `[ok] assertion count` as the
   discoverability anchor while the table above it showed that string matching all three
   failing runs. **Recovery:** built the complementary case and reverted. **Prevention:**
   when the falsifying data is already printed, read it before writing the conclusion.
6. **Nearly shipped a CI toolchain-skew risk.** Every capture was on bun 1.3.11; CI installs
   1.3.14 from `.bun-version`, and this change made the parse newly dependent on a terminator
   format never observed on CI's version. **Recovery:** installed 1.3.14 in a scratch dir and
   verified identical. **Prevention:** before basing a format-dependent parse on local
   captures, diff the local toolchain against the pinned one.
7. **The first scratch install failed silently** (postinstall not run) and printed empty
   results that read as evidence about 1.3.14. **Prevention:** gate on a version assertion
   before using a scratch toolchain.
8. **`mutation-verdicts.md` asserted a false coverage claim** (see Key insight).
   **Prevention:** verify a "covered elsewhere" claim by running the other guard against the
   actual mutation.
9. **Ended a turn on a forward-looking sentence** — "Continuing to compound → ship" — and
   abandoned the pipeline; the operator had to ask why I stopped. **Prevention:** already
   named in `review/SKILL.md`; nothing enforces it.
10. **A `/tmp` "No space left on device"** mid-session (tmpfs 65%, ~2 GB of stale sandboxes
    from sibling sessions). One-off for this diff; recurring for the machine. **Prevention:** `test-all.sh --capacity` reports `tmp_avail_mb` against its floor in ~3s — read it before launching any battery, and write long-lived logs to `/var/tmp`.
