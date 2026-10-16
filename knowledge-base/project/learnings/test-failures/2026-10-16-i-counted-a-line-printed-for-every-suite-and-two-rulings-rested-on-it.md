---
title: "I counted a line the runner prints for every suite, and two CTO rulings and a public comment rested on the count"
date: 2026-10-16
category: test-failures
module: scripts/test-all.sh --print-selection + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217, 10447]
---

# A selection probe read as "present" instead of "selected": 98 of 98 became 47 of 98

## Problem

Item G of the `grep -q` pipe-guard series asked whether the local affected gate selects `.claude/hooks/grep-q-pipe-guard.test.sh` when a producer
file or owner suite changes. The first CTO ruling split a possible gap into a follow-up issue. A full-population measurement then reported **98 of 98
producers and 97 of 97 owner suites selected**; a second CTO ruling withdrew the follow-up, the guard header was "corrected" to say so, and a comment
saying "zero gap" was posted on the tracker (#9217).

The measurement was wrong. `bash scripts/test-all.sh --print-selection --paths=<path>` prints one `AFFECTED_SELECTED` line for **every** suite (about
630 lines). The selected bit is its **third tab-separated field**. The script counted the lines that named the guard, which is 1 for every path. The
first 8-path sample did the same with `grep -c 'grep-q-pipe-guard'`. A bogus-path negative control (`bogus/not-a-path.txt`) printed the guard line with
bit 0 and exposed it, found while verifying a re-measure recipe I was writing, after a 3-seat review had passed the numbers.

Corrected, over the guard's own pairs: selected for 47 of 98 producers and 64 of 97 owner suites, **not selected for 51 and 33**. The first ruling was
restored, the follow-up is #10447, the header's false parts were fixed, and the tracker comment carries a dated correction.

## Solution

- Read the field the verdict lives in (`awk -F'\t' '$1=="AFFECTED_SELECTED" && $2==".claude/hooks/grep-q-pipe-guard.test.sh" {print $3}'`), and run a
  known-bit-0 and a known-bit-1 control before reading any count. The recipe in the spec's `selection-measurement.md` does both.
- When a seat is asked to "verify" a measurement, brief it to **re-run a sample with controls**, not to re-check the artifact's arithmetic. The pattern
  seat verified that 47+51=98 and that the table matched the regex; both were true of a table whose last column was meaningless.

## Key Insight

An instrument that has never produced a negative has not returned a positive either. The documented rule ("run every instrument against a known-positive
AND a known-negative") was in the review skill and I did not apply it to my own measurement script. Authorship makes it worse: a script I wrote to
confirm a ruling feels like bookkeeping, and a 100% result on a population that large is itself the tell (a probe that finds zero exceptions across 195
heterogeneous paths deserves a control before a ruling).

## Session Errors

1. **Counted line presence instead of the selected bit (twice: the 8-path sample and the 84-path run).** Recovery: bogus-path control, corrected 86-path
   run with parsed bit and two controls, CTO re-ruling. **Prevention:** controls first; parse the verdict field; treat a uniform result across a
   heterogeneous population as unproven until a control that should fail does fail.
2. **A review seat verified the artifact, not the claim.** The claim-verification seat confirmed the table's arithmetic and the regex counts, and its two
   `--print-selection` probes were on regex-matched paths that really were selected. **Prevention:** brief claim-verification seats with "include one
   path you expect to FAIL and report its bit".
3. **A recipe I wrote for the evidence file used a pipe-fed `grep -q` and a presence check.** Caught on the same pass (and it is the defect class this
   series fights). **Prevention:** none beyond the series guard; the recipe now captures output and reads the bit.
4. **`tmp` scratch vanished between turns** (`/tmp/soleur-run.*` dirs from earlier measurements). Recovery: the data had been committed to the spec dir
   and `/var/tmp`. **Prevention:** already documented (`/var/tmp` or the worktree, never `/tmp`).
5. **A scripted batch edit aborted on a stale count assertion (`8` vs `7` newlines) before writing.** The assertion did its job; I re-ran it and checked
   the file changed (`git status`). **Prevention:** keep the landing assertion; confirm the artifact changed after any scripted edit.
6. **Technical-ruling gate rejected a decision row that began `Void.`** (`bad-ruling-shape`); markdownlint flagged hard tabs and heading spacing in two new
   files. One-off format slips fixed in the same session. **Prevention:** run the ruling gate and markdownlint before the first commit of a new decision file.
7. **The Stop hook twice flagged a closing line naming an action not yet taken.** Recovery: do the corrective step in the same turn (correcting the
   tracker comment) and end with a `Paused:` line. **Prevention:** none needed; the hook worked.

## Triage

| item | recurring? | disposition |
|---|---|---|
| 1 uncontrolled count | recurring class, already documented | covered by existing rule; the miss was non-compliance. The durable fix is the control-bearing recipe now committed, so no new rule |
| 2 artifact-not-claim verification | recurring | one-line prevention above; no new rule (would be a restatement of the known-negative rule) |
| 3-7 | one-off | note only |

## Tags

category: test-failures
module: scripts/test-all.sh --print-selection
