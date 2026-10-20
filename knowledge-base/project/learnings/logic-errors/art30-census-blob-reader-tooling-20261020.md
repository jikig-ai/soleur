---
module: Art. 30 re-verification gate
date: 2026-10-20
problem_type: logic_error
component: tooling
symptoms:
  - "A first-match reader of the PA-8 retention cell still exited 1, so rows that only asserted exit 1 stayed green"
  - "Command substitution of git cat-file dropped a NUL and joined two retention lines into one"
  - "A symlink blob is the link text, so mode 120000 could supply a passing cell"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [art-30, re-verification-trigger, census, nul, symlink]
---

# Troubleshooting: Art. 30 census graded a decoy cell

## Problem

The partial actuation gate for re-verification triggers 2, 4, and 5 could accept a review hunk that never landed in the one PA-8 retention cell. A test that only required a non-zero exit did not catch that, because the broken reader failed for a different reason.

## Environment

- Module: Art. 30 re-verification gate
- Affected Component: `scripts/lint-art30-reverification.sh` and `scripts/lint-art30-reverification.test.sh`
- Date: 2026-10-20
- Issue: #7893. This learning does not close that issue.

## Symptoms

- Rows 35–37 planted a firing `--log-opt` line and a decoy cell that still contained the base bold ids. Both the old reader and the fixed reader exited 1, so `expect_rc 1` stayed green.
- `$(git cat-file blob …)` strips NUL. Two retention lines separated by NUL became one line and the heading count stayed 1.
- `git cat-file` of a mode `120000` symlink prints the link text. A link whose text is a valid cell passed `pa8_cell_text`.
- A line-start prefix `| **(f) Retention**` missed the live reordered cell, which puts bold ids before the marker.

## What Didn't Work

**Attempted Solution 1:** Assert exit code 1 on the decoy rows.

- **Why it failed:** The decoy kept `**(2)**` and `**(4)**` aligned with the base cell, so a first-match reader still reported `fired ids 2 4` and exited 1.

**Attempted Solution 2:** Match the retention marker only at the start of the line.

- **Why it failed:** Row 34's reordered cell has the bold ids before `| **(f) Retention**`. The prefix match rejected the only real row.

**Attempted Solution 3:** Treat row 37's short symlink as the mode-`120000` oracle.

- **Why it failed:** The committed blob is the link text `decoy-register.md`, which is not a cell. A blob reader and the mode check both emit `id census rejected`. The mode oracle is the multiline link whose text is itself a valid cell.

## Session Errors

**Bare-root git exited 128.**

- **Recovery:** Run git from the feature worktree. The checkout at the repo root is bare.
- **Prevention:** Start every git command with `cd` into the worktree and confirm `git rev-parse --show-toplevel`.

**Census rows accepted any exit 1.**

- **Recovery:** `CELL_PASS` is a re-ack a first-match reader passes (`2026-10-21`, `noted-2`, `noted-4`). The rows require the text `id census rejected`.
- **Prevention:** A refusal test must use a fixture the defective reader would pass.

**A prefix match broke the reordered cell.**

- **Recovery:** Match the substring `"| **(f) Retention**"`. Prose `see (f) Retention` does not contain that marker.
- **Prevention:** Pin the live row's token order before tightening a match.

**`fix-round-seats.sh` printed `unknown-seat` for `simplicity` and `structural`.**

- **Recovery:** The leaf names are `code-simplicity` and `structural-enumeration`.
- **Prevention:** The script already warns on an unknown leaf. Pass the leaf it prints, not a shortened name.

**A reused commit-message file still held an older subject.**

- **Recovery:** Overwrite the message file in the same turn as the commit, and do not reuse `/tmp/art30-commit-msg.txt`.
- **Prevention:** Write the message immediately before `git commit -F`, and read it back.

**`fixture-dir-operand-assert` is red on this host.**

- **Recovery:** Left it. GUARD 3 treats `/home/jean/.git` as a repository (69 passed, floor 71). The failure is outside this diff.
- **Prevention:** Do not regenerate the fixture-relative baseline to absorb a host control.

**An early capacity probe printed `CAPACITY_CONTENDED`.**

- **Recovery:** A later `--capacity` probe printed `CAPACITY_OK`. The banner is the contention signal, not a suite failure.
- **Prevention:** Re-probe at the moment of launch. Do not treat an older banner as the current lock state.

**`TEST_GROUP=affected --enumerate` listed every registration.**

- **Recovery:** `bash scripts/test-all.sh --print-selection` reported `selected=324 of=655 fallback=none`.
- **Prevention:** Use `--print-selection` for the affected set. `--enumerate` lists registrations.

## Solution

Read the register from the committed blob. Require exactly one `## Processing Activity 8 ` heading and exactly one line containing `| **(f) Retention**`. Dump the blob to a file and count NUL bytes with `tr -cd '\0' | wc -c` before any command substitution. Reject mode `120000` from `git ls-tree` on HEAD and on the merge base before `pa8_cell_text`. A missing base blob stays exit 2 (`cannot read the base register`).

The passing re-ack puts the fired ids inside tokens the POSIX diff marks added (`noted-2`, `noted-4`) plus a date string absent from the removed cell text. One added token may carry both the id and a letter.

## Why This Works

The census now fails closed on the shapes that used to look like one cell: a second retention line, a second PA-8 heading, a NUL join, a symlink, and a prose mention. The token diff still decides whether the fired ids were added. Passing that diff is not Art. 5(2). The automation does not write the register entry.

Row 37 still catches a worktree `[[ -f ]]` follower, which would open the target and grade `CELL_PASS`. Row 40 is the mode oracle: without the `120000` check its link text exits 0.

## Prevention

- Grade the committed blob, not the worktree file.
- Count NULs on the raw file before `cat` or `$()`.
- Reject mode `120000` before parsing the blob as text.
- A refusal assertion must name the error text a passing decoy would not emit.
- Do not archive `knowledge-base/project/specs/feat-7893-art30-trigger-actuation/decision-challenges.md` before ship Phase 6 step 2.5 reads it. Ship Phase 6.45 is the archival point.

## Related Issues

- Ref #7893. Triggers 1, 3, 6, and 7 stay unactuated.
- No earlier learning documents this census hole.
