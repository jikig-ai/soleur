# Adoption note — R3 collect at `/var/tmp/s4-r3-20261108/`

What actually happened on 2026-11-08, in UTC (local file mtimes display one hour ahead):

- **~21:32 UTC** a sibling session (worktree `.worktrees/s4-r3-replay`, detached at `4fba0d512e`)
  launched the R3 collect as four chunk processes
  (`python3 -I scripts/ci-pr-affected-replay.py collect --out /var/tmp/s4-r3-20261108
  --commits 300 --base origin/main --chunk N/4`, N=1..4) plus, ~21:28 UTC, the matching
  ejections pass (`ejections --since 2026-10-29T16:42:32Z --until 2026-11-08T20:07:13Z`,
  the bounds of the same rev-list window). The sibling session then died mid-flight, but
  its processes — orphaned to systemd — kept running and kept writing.
- **~22:08 UTC** this session's predecessor, believing the sibling fully dead, launched a
  second 4-chunk restart against the same `--out` from this worktree (PGID 454997).
- **~22:12 UTC** the Phase-0 inventory found BOTH sets alive — two concurrent collects on
  one directory, the configuration the plan forbids (`aggregate`/`load_units` raises on a
  duplicate `(kind, sha)` and the append-only files do not dedupe across writers).
- **Resolution.** Verified the two worktrees' selector inputs were byte-identical
  (`ci-pr-affected-replay.py`, `test-all.sh`, `suite-durations{,-heavy}.tsv`,
  `suite-shard-legs.tsv`, `lib/test-relevance-paths.sh` — all SAME), so a unit computed by
  either writer is equivalent. The sibling's original collect had ~37 minutes of work;
  the restart had written nothing yet. The duplicate restart (PGID 454997: the 4 collect
  processes and their in-flight `--print-selection` children) was terminated ~22:14 UTC.
  First post-kill scan (key-level): zero duplicate `(kind, sha)` keys, zero unparseable
  lines.
- **Contamination found and repaired ~23:35 UTC.** A deeper per-idx verification after
  chunk 4 finished showed its file held **77** units, not 75: idx 3 and idx 7 each appeared
  twice with DIFFERENT shas. The restart's `rev-list -n 300 origin/main` resolved at ~22:08
  UTC — after `origin/main` had moved from `4fba0d512e` to `404e4c626f` — so its window was
  shifted by one and its `(kind, sha)` keys did not collide with the original's (why the
  first scan missed them; `check_complete` tests idx contiguity, not sha-vs-window, so
  aggregate would not have caught it either). Its chunk-4 writer appended the two
  `runner-changed` units for ITS window's idx 3 (`057f1e5acc`) and idx 7 (`e0f1a29fd4`)
  before the kill — fast-path units needing no selector call. Both lines were removed; a
  full re-verification (`sha == rev_list(4fba0d512e)[idx]` for every commit unit, all four
  files) now holds with **zero stale units, zero duplicate shas**. The two dropped units are
  recorded here verbatim for the audit trail: `(idx=3, sha=057f1e5acc…, clean,
  runner-changed)`, `(idx=7, sha=e0f1a29fd4…, clean, runner-changed)`.
- **Adopted evidence base:** the sibling's original processes, sole writers from ~22:14 UTC:
  collect chunks 1..4 of 4 (PIDs 169176/169430/169604/169793, launched 21:32 UTC) and the
  ejections pass (PID 4022354, launched ~21:28 UTC). This is the Phase-0 adopt-or-restart
  gate's "alive → adopt" arm, applied to the original rather than the restart.

## Window the units describe

- Commit population: the 300 first-parent commits reachable from `4fba0d512e` (the sibling's
  rev-list tip; committer time `2026-11-08T20:07:13Z`), back to `c6cd57f31d` (committer time
  `2026-10-29T16:42:32Z`).
- Ejections window: `2026-10-29T16:42:32Z..2026-11-08T20:07:13Z` — identical bounds, so the
  two populations describe the same window by construction.
- `origin/main` has since advanced (to `780a717666` at ~22:41 UTC): the window is the fresh
  300-commit window **as of collect start**, which is what the schedule comment asked for.
  Re-running `ejections --commits 300 --base origin/main` after the move would have produced
  a *wider* window than the commit population's — adopting the running pass preserves
  coherence.

## Deviation from the brief's expected narrative

The brief anticipated "sibling died mid-flight; resumed by this session's 4-chunk restart".
In fact the sibling's processes never died — only the session did — so the adopted collect is
the ORIGINAL 21:32 UTC run, and this session's restart was the artifact removed, not the
artifact adopted. The restart's chunk logs (`/tmp/r3-chunk{1..4}.log`) were empty at takeover
(python's buffered stdout — expected, not a stall signal). No `--out` file was deleted; the
sibling's worktree `.worktrees/s4-r3-replay` is untouched.
