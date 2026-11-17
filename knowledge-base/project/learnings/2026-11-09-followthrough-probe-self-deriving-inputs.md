# Learning: followthrough probes must self-derive inputs; fixture schemas must mirror the real producer

## Problem

PR #12495's new soak probe shipped three convergent defects that made it dead-on-arrival: (1) it required `SOLEUR_FT_TRACKER`/`SOLEUR_FT_FLIP_MERGED`/`SOLEUR_FT_P50_FLOOR` env values, but the sweeper's `secrets=` mechanism forwards secret NAMES into `env -i`, not `NAME=value` pairs, and `SOLEUR_FT_*` is a reserved prefix — the inputs were undeliverable by construction; (2) its tracker-body parser was written against an invented 8-column schema (p50 at $4, a window column at $6) while the real emitter writes n/p50/p90 at $4/$5/$6 in seconds with no window column — the fixture suite passed 8/8 against the fiction; (3) the suite was never registered in `test-all.sh`, and when registered it was placed after the enumerate exit/drain where `run_suite` verdicts are silently dropped.

## Solution

Derive inputs inside the probe: tracker via the watch's own find-or-file (exact title + github-actions author), flip timestamp via `git log -1 --first-parent -G'<anchored assignment regex>'` (not `-S`, which counts occurrences and misses value-only swaps), floor via a defaulted env override. Parse the real schema, use `Report refreshed:` as the postdate carrier (there is no per-row window). Keep env vars as optional fixture overrides. Register suites inside `want_scripts` before the enumerate terminator, and treat `run_suite` placement as part of the contract — verify with `bash scripts/test-all.sh --enumerate scripts | grep <label>`.

## Key Insight

For convention-gated surfaces (sweeper env, tracker body, run_suite registration), read the PRODUCER (sweeper launcher, watch emitter, enumerate stream) before writing the consumer — a self-consistent fixture suite certifies fiction. Ordering matters in HCL parsing too: comment-strip the whole file BEFORE block-windowing, or a `/* */`-wrapped stale block wins `head -1`.

## Tags

category: workflow-patterns
module: scripts/followthroughs, scripts/test-all.sh
issue: #12269
