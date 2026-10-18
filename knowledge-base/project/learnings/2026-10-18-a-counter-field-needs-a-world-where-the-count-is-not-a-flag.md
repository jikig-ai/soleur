# Learning: a new counter or flag field on a fixed-shape line needs a world where the count is not a flag

## Problem

The wipe host verb's exit-34 refusal printed only per-type counts, so nobody could tell which top-level entry tripped it (run 39081408368, 2026-10-18). The diagnostic PR appended three fixed-vocabulary fields (`has_hooks_d`, `lf_entries`, `offlist_n`) to that line. The first build passed 785 assertions and six purpose-written mutants, yet the review's mutation seat found four mutants that stayed green.

## Solution

Every survivor lived in a gap the fixtures shared, not in the code:

- `offlist_n` counted by an allowlisted lock file: no world held a lock file beside an off-list entry (new world A125).
- `lf_entries` as `$((ln > 0))` or capped: every world had 0 or 1 entries in `lost+found` (new world A126, two entries, one nested).
- A FIFO or an `*hooks` suffix setting the bit: only the shapes the author thought of were looped (A123 gained `fifo` and `suffix`).
- Seven older rc=34 rows had no whole-line equality, so only the grammar guarded them. All now pin the whole line, and an rc=34 row without a tail fails.

The oracle also gained two derived invariants (the hooks bit implies an off-list entry; `offlist_n` cannot exceed the top-level entries counted by type). Floors were re-measured from an unprivileged, loopback-skipped run and annotated with what each literal was measured as.

## Key Insight

For each added field, ask "which edit makes this a different quantity and keeps the old fixtures green?" A count is only pinned by a world where it differs from its flag form (>= 2), from its look-alikes (allowlisted siblings), and where it is zero while a neighbour is not. Mutants written by the author come from the author's model of the code; the survivors came from the fixtures' shared blind spots. Run the review mutation seat against the CURRENT tree and fold each survivor into a world, not a bigger regex.

## Session Errors

1. **Imprecise counts comment** ("3 dirs not on the expected list") on a public thread — Recovery: appended a correction on #6897 and #9066 — **Prevention:** state a measured count with its exact field names only; never gloss it with a category word.
2. **`gh issue create` blocked** by the hook (heredoc in the same call; then the consequence line) — Recovery: body file via Write, then tracked in place on #6897 (decision row R-8) — **Prevention:** write the body file first; prefer in-place tracking when an owner thread exists.
3. **technical-ruling gate failures** (Class cells, non-CTO rulings) — Recovery: reclassified rows, gate PASS — **Prevention:** run `technical-ruling-gate.sh` right after editing `decision-challenges.md`, not at ship.
4. **`draft-pr` with no commits ahead** — Recovery: expected, ship creates the PR — **Prevention:** none needed.
5. **Fixture setup `: > a b` creates only one file** (A125/A126) and **A127 duplicated A16** — Recovery: `touch`, dropped A127 before running — **Prevention:** use `touch` for multi-file setup; diff a new world's tree against existing rows before adding it.
6. **markdownlint MD038/MD022/MD032** on the runbook edit and the previously committed `session-state.md` — Recovery: fixed, lint clean — **Prevention:** lint every touched `.md` before committing, including generated spec files.

## Tags

category: test-failures
module: apps/web-platform/infra/git-data-wipe-assert
