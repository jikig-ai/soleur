# Decision Challenges — feat-one-shot-8990-extractor-mutation-rows

Recorded by the headless `soleur:plan` run (pipeline mode — no operator-attached gate).
`ship` Phase 6 renders these into the PR body and files an `action-required` issue if needed.

## 1. Scope: three committed mutation rows, not the issue's minimum one

- **Operator's stated direction:** issue #8990 prescribes "a mutation row" (singular) covering
  the extractor end-to-end.
- **Plan ships:** three rows — `ROWS-GAP` (RED), `ROWS-DROP` (RED), `ROWS-SWAP` (GREEN
  must-PASS).
- **Rationale:** the issue itself names "drops or gaps" as the two shapes worth proving (two
  distinct guard arms: `_rows_tile_check` vs the MIXED-contract check), and a RED-only addition
  cannot detect a guard that rejects everything — the must-PASS row is the same
  `MUSTPASS`-row doctrine the battery already follows. Each row costs ~24 s of serial leg time.
- **Deviation class:** additive scope within the issue's own enumerated shapes; cheap to trim
  at review (drop ROWS-DROP/ROWS-SWAP, keep ROWS-GAP, DECLARED_TOTAL 25) if the reviewer
  prefers the literal minimum.

## 2. Worktree base predated the machinery under test — self-resolved mid-session

- **Finding:** at session start, branch HEAD (`dfee49ef53`) predated `d453170127` — the
  `--rows` registrations and `_rows_tile_check` did not exist in the tree. Mid-session the
  pipeline's init commit `e0927dbd24` landed atop `6ee3acf0d8` (origin/main tip), bringing the
  branch current; both anchors now verify present.
- **Plan response:** Phase 0 is a verify-only step (grep the anchors); `git merge origin/main`
  only if it fails. Recorded because a work phase on a stale checkout would see
  `ANCHOR MISSING` on every new row.
