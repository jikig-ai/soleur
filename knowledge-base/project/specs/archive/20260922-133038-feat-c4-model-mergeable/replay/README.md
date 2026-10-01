# C4 artifact mergeability replay (2026-09-22, origin/main 69b08a4ee)

`replay.py` takes the 30 most recent `main` commits touching `.c4` sources and pairs each commit
A with the commit `gap` positions after it (B), for gaps 1-6, 8 and 10. That is 201 candidate
pairs, of which 152 were kept. A candidate is skipped when B's source diff does not re-apply
cleanly onto A's parent, when either side leaves the sources unchanged, or when a side fails to
render. For each kept pair:

- base = A's parent;
- side A = A's sources;
- side B = B's own source diff re-applied onto the base.

Each side is rendered with `likec4@1.50.0`, and the artifact is 3-way merged with
`git merge-file`. A clean merge is compared against a fresh render of the merged sources, so
"clean" is only counted when it is also correct. `replay.py` compares the two as JSON values.
During review, a byte-exact re-run of the `canonical` arm checked 108 of the 152 pairs: all 74
clean merges were byte-identical to a fresh render, and 34 conflicted.

| Format | Clean + correct | Conflict | Clean but WRONG |
|---|---|---|---|
| raw (before this PR) | 0 | 152 | 0 |
| indent 2, hash kept (sorted or unsorted) | 7 | 145 | 0 |
| indent 2 or 0, hash removed | 107 | 45 | 0 |
| **`canonical`: the shipped module via `c4-canonical-cli.mjs`** | **107** | **45** | **0** |

No pair's `.c4` sources conflicted, so every row above is a pair whose sources merge cleanly.

**The 45 residual conflicts** (`residual-conflicts-2026-09-22.txt`, each row labelled
`TRUE-OVERLAP` or `ADJACENCY`) are the positive control:

- **43 true overlaps.** Both sides set the same leaf to different values: Graphviz coordinates in
  a shared view (mostly `views.containers` or `views.index`), or the same relation's title. No
  text merge can be correct for these, so the conflict is the right answer.
- **2 adjacency conflicts** (`7597d25cc/9768645ad`, `1a2453d17/91c8bdccf`). No leaf differs on
  both sides, but the two sides' edits sit on neighbouring lines, so git has no unchanged line
  between the hunks.

All 45 go to `resolve-regenerable-conflicts.sh` on the local paths.

To re-run from the repo root, set `RENDER_CACHE` to a scratch directory, set `GAPS` to a
comma-separated list, and run `python3 replay.py "$PWD" <comma-separated commits>`.
