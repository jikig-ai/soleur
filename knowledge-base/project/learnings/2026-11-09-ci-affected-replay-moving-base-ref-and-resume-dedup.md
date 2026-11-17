# ci-pr-affected-replay: `--base` is a moving ref; killed legs resume as duplicate idx units

Date: 2026-11-09. Context: 4th S4 go/no-go re-ruling (#9729), PR #12477.

## What happened

1. `collect --base origin/main` + `ejections --base origin/main` resolve the LOCAL `origin/main` ref
   at launch. All four collect legs were killed mid-run (host reaper/OOM — no OOM in dmesg, empty
   logs, all four dead within ~15 min of a ~50-min stall) at 53 units; relaunching hours later
   enumerated a base that had drifted 3 commits past the pinned window → 3 out-of-window units,
   3 missing tail commits, and `aggregate` rc 2 integrity refusals (duplicate sha, non-contiguous idx).
2. The fix: re-collect only the missing tail (`--commits 3 --base <pinned-BASE>~297`), drop the
   out-of-window units, dedup by `sha` (duplicate units differ only in `idx`), renumber idx by
   pinned window position. `git rev-list --first-parent -n 300 <BASE> | diff - <(cut -f2
   replay-commits.tsv | tail -n +2)` is the positional proof the correction restores the window.
3. The ejections phase ran on the drifted base too — its `ejections-window.json.until` is the head
   commit's committer time, so `until` > the pin-fetch time is the tell. Edge effect is small
   (~3 commits of a 300 window) but it must be disclosed: n=444 blended two populations.

## Rules

- Always pass a PINNED SHA as `--base` to every replay phase (collect, ejections, audit), never a
  branch/ref name — #12456's window-tip pinning covers the in-tool fix; this run is the live instance.
- Unit class field is `cls`, not `class` — histogram/TSV generators reading `unit['class']` print
  all-clean silently. The commit-unit and ejection-unit shapes share `cls`.
- `aggregate`'s `saving` line uses default `--baseline-min 99.8` unless passed — pass the
  census-derived baseline or annotate the default in the receipts.
- On a heavily loaded host: 300-commit collect ≈ 4-5h (not ~40min), ejections ≈ 4h (not ~25min) —
  the gh-api corroboration + per-unit `--print-selection` children dominate.
- `verdict` computes from `--a/--b/--c/--d` args; always read `computed=` from stdout, never the
  process exit code alone, and commit the invoked form (not a template) to commands.txt.
