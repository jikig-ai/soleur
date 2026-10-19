# PR1 step 0 spike (Ref #9729, Ref #10448)

Pinned tree: `89d2b7799970fa09b79799569f3b5c1f5ea45768` (this branch's HEAD when the spike ran; 19,367 tracked files, 643 registered suites).
Machine: 16 cores, shared with other sessions (load average 14-25 during the runs; an earlier run at load 25-44 took about 4 minutes of wall time, not timed).

## (a) Cold cost of one nested `--print-selection` walk

Shape: the audit's own `run_selector` invocation, `env -u CI -u TEST_GROUP bash scripts/test-all.sh --print-selection --paths=README.md`,
on a fresh `git clone --no-hardlinks` of the repository at the pinned HEAD (no derive cache, so the walk is cold; the first line of
output is `AFFECTED_DERIVE_CACHE state=on hits=0 misses=643 derived=0`). rc 0, 643 `AFFECTED_SELECTED` rows, `fallback=none`.

| Measure | Value |
|---|---|
| wall (real) | 180.1 s |
| user | 146.7 s |
| sys | 33.0 s |

Against the CTO ceiling (ruling 4 / round 2 A): 180 s billed per full-battery run, 300 s suite timeout. The walk alone is
180.1 s, 0.1 s over the billed ceiling and 60 percent of the suite timeout, before the ratchet does any scan. CPU time (user plus sys,
179.7 s) is the less noisy figure and it is also on the line. Implication: there is no headroom, so ruling 4's fallback applies:
the ratchet takes `--rows FILE` with one walk shared inside one leg (the PR3 design must not run a second real walk), and PR3
step 3.5 must re-measure on a CI runner before the ratchet is registered.

## (b) Throwaway prototype of the component-boundary match with per-file memoisation

Prototype: a trie of the tracked paths by component, candidate starts found by one compiled regex over the 48 top-level names with a
word-character lookbehind, extension component by component until the first absent prefix, per-file memo of the scan result across suites,
one-hop library texts read once. Timed over the audit's 526 file-backed suites (12.4 MB of suite text, 547 distinct files scanned).

| Measure | Value |
|---|---|
| prototype scan (all 526 suites) | 1.4 s to 1.8 s (3 runs), 670,006 trie operations |
| old `f in blob` scan, same process, same load | 53.1 s |
| old scan inside the differential runs (heavier load) | 76.7 s to 86.6 s |
| refs found | prototype 2,173 (word-character rule only) versus 2,176 old; the 3 missing were printf `\t` escapes, kept in the committed rule, which then matches the old scan exactly (receipts/audit-differential.tsv) |

Target: 30 s or less. Met with a factor of about 17 to 21 (target over new); the old scan was about 29 to 38 times slower than the new one. Implication: memoisation plus the component index alone meets the target, so
the left/right boundary rule is NOT needed for speed and is, apart from the left boundary this PR already ships, the conditional precision PR (PR2, right boundary only). The PR1 dry run of PR2's right
boundary (next character not `[A-Za-z0-9_-]`) on the new gap pairs drops 4 pairs (2 of them only because the dry run ignores the printf
escape rule), against the threshold of 30: PR2 is not opened; those pairs become declared edges or accept rows in PR4 and PR5.

## Differential and recorder (task 1.3)

`audit-differential.tsv` (same directory): old `f in blob` scan versus the committed scan on the pinned tree, same selector rows.
Result: 526 file-backed suites, 2,176 refs in both, 1,108 gap pairs in both, ZERO dropped refs. Three mentions
(`printf '...\t<path>...'` fixture records in `.claude/hooks/devin-matcher-parity.test.sh` and `scripts/ci-pr-selection.test.sh`) would be dropped by a
plain word-character rule because the source text has the letter `t` before the path; the running program has a tab there, so
the committed rule treats a printf escape as a boundary and the receipt lists those three lines as `kept-escape`. With nothing dropped, the
recorder has no dropped reference to look for; as corroboration it was run (`record --mode check --cover-from-selection --max-load 100`;
the default `--max-load 4.0` refused both suites with `load_refused` at host load 33 to 37) over the two suites that hold the kept lines:
`.claude/hooks/devin-matcher-parity.test.sh` was recorded (verdict `uncovered`, 44 files opened, `plugins/soleur/hooks/stop-hook.sh` not among
them); `scripts/ci-pr-selection` came out `unreliable reason=contaminated` (the suite writes `.soleur/` into the private checkout), so it
yielded no observation.

## Live audit after the change (task 1.6)

Before: `SOLEUR_PR_AFFECTED_AUDIT suites=643 always_on=116 audited=526 unaudited=1 gap_suites=195 gap_refs=1108 accepted=0` (125 s wall).
After:  `SOLEUR_PR_AFFECTED_AUDIT suites=643 always_on=116 audited=527 unaudited=0 gap_suites=196 gap_refs=1244 accepted=0 stale=0` (80 s wall).
The directory suite `plugins/soleur` now carries 136 gap refs (its bun test files read paths outside `plugins/soleur/`); every other suite is unchanged
(1,244 minus 136 is 1,108). Re-split trigger (PR4/PR5 re-split by directory if the added refs exceed half of 1,108, i.e. 554): 136 added, 12 percent, NOT triggered.
