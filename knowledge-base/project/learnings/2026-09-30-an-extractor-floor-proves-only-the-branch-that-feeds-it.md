---
title: An extractor floor proves only the branch that feeds it
date: 2026-09-30
category: test-failures
module: apps/web-platform/infra (inngest-bootstrap.sh, inngest.test.sh)
tags: [guard, anti-vacuity, mutation-testing, prose-accuracy, inngest]
issue: 9219
---

# Learning: an extractor floor proves only the branch that feeds it

## Problem

#9219 removed dead `inngest pause`/`resume` calls from `inngest-bootstrap.sh`. They had been
measured absent on v1.19.4 and v1.45.1. The replacement guard in `inngest.test.sh` extracts
CLI verbs with a three-branch alternation (`$INSTALL_PATH`, `${INSTALL_PATH}`,
`/usr/local/bin/inngest`). It asserts they are a subset of `start|version`, with `start` as an
anti-vacuity floor. The author's 6-row battery reported every row caught.

Review showed the floor proved only ONE branch. `start` is extracted from the unit's
`ExecStart=/usr/local/bin/inngest start`, which is the absolute-path branch. The two
`$INSTALL_PATH` branches are exactly the spelling the removed calls used, and no line in the
pristine bootstrap feeds them. Cutting the regex to the absolute branch alone left the suite
414/414 green with the verbatim historical `pause` line restored. The battery never saw this
because every row mutated SUT content, never the extractor.

## Solution

- Put the extractor in a function and self-test it on an inline fixture with one line per
  spelling, plus a comment line. Assert the exact set, so dropping any branch reds.
- Add a check that bans `pause`/`resume` as words anywhere in the code. It catches the
  spellings the extractor cannot see (bare `inngest pause`, an alias variable, a
  backslash-continued line, a `--flag` before the verb). The allowlist still catches NEW
  unmeasured verbs.
- Raise the floor 414 → 416. Mutation-proved: branch-drop, bare `inngest pause`, the verbatim
  historical line, an alias `resume`, and deleting the ban assertion (caught by the floor) all
  red.

## Key Insight

A floor that asserts "the extractor found X" certifies only the alternation branch that
produced X. For each branch of a multi-branch extractor, ask which input in the real file
feeds it. A branch fed by nothing is covered only by the fixture you write for it.

## Session Errors

1. **Plan-write guard blocked the first plan write** (literal systemd-restart wording).
   Recovery: rephrased. Prevention: none needed; the hook worked as designed.
2. **Research agents asserted false facts** (a default for `UPGRADE_FROM`; v1.1.43 "not on
   main" from a stale local ref). Recovery: checked against code and fresh `origin/main`.
   Prevention: already covered (work/SKILL.md: a planning subagent's summary is a claim about a
   file).
3. **Foreground mutation battery hit the 120 s tool limit** and was backgrounded. Recovery:
   read its output file. Prevention: run batteries longer than 2 minutes with
   `run_in_background` or under `setsid` from the start.
4. **Mutation row 2 (empty file) never reached the guard line** because the suite aborts
   earlier. Recovery: added row 2b, which removes only the `start` source. Prevention: build
   each row so the rest of the program stays well-formed and only the mechanism under test is
   removed (work/SKILL.md, dispatch-mutant rule).
5. **SC2034 on a variable referenced only inside an eval'd condition string.** Recovery:
   interpolated `'$VAR'` the way sibling asserts do. Prevention: diff shellcheck counts against
   `origin/main` before committing a test edit.
6. **A pre-existing unescaped `||` in a code span split a GFM table cell**, so appended text
   would have rendered as discarded. Recovery: escaped as `\|\|`. Prevention: already covered
   (work/SKILL.md: pipe-count check after any table-row edit).
7. **Comments and runbook prose I added carried unmeasured or false claims**: "override via env"
   (sudo `--preserve-env` omits it), "the restart loaded the new binary" (a refused restart
   continues), "killed" (it is SIGTERM plus retry), "keeps accepting work" (Redis restarts
   mid-window), and a runbook in-place path that is not the live flip. Recovery: every sentence
   corrected after review. Prevention: already covered (review/SKILL.md: "A COMMENT a fix PR
   adds is review surface"). The gap was applying it at write time: name the falsifying
   command for each causal sentence before writing it.
8. **My battery mutated one axis (SUT content)**, so the extractor-branch vacuity survived.
   Recovery: see Solution. Prevention: already covered (review/SKILL.md: audit a battery's
   axes, not its count).
9. **A review agent reported an implausible commit date.** Recovery: ignored; the date bore on
   no finding. Prevention: none needed.
10. **The stop hook blocked the turn from ending on an unkept "I'll implement" line** while I
    waited on a background agent. Recovery: an explicit `<stop>BLOCKED: …</stop>`.
    Prevention: close a waiting turn with the stop tag, not a forward-looking sentence.

## Tags

category: test-failures
module: apps/web-platform/infra
