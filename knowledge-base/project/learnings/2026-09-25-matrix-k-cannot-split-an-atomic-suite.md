# Learning: a shard-matrix K bump has a structural floor — the heaviest single registration

## Problem

Asked to "shard the `test-scripts` CI job", the premise was stale on two
axes: the sharding already existed (K=6 manifest matrix, #8585/#8612/#8665),
and the residual gap was leg *rebalancing*, not implementation. After a
measured regen, the worst leg proved to be a **single atomic suite**
(`lint-orphan-test-suites-mutations`, 588.8 s) alone on leg 5 — at which
point no K can help: worst leg ≥ duration of the largest indivisible item.

A second floor worth naming beside it: the plan's predicted K=7 outcome
(~8.5 min worst leg) did not survive contact with the actual regen
(leg 5 = 588.8 s + ~0.4 setup ≈ ~10.2 min wall). The AC had to be amended
post-review with an atomic-floor carve-out pointing at the real remedy
(suite-internal split / heavy-group move), not the matrix.

## Solution

- Regenerate the manifest first and read its *predicted leg table* before
  choosing K: the regenerator's dry run shows immediately whether the worst
  leg is an LPT imbalance (K helps) or an atomic item (K is exhausted).
- In this repo: `python3 scripts/regenerate-shard-manifest.py --run <id>`
  (the default latest-green lookup 404'd — always pass `--run`).
- When the floor is an atomic suite, the remedies live outside the matrix:
  `--rows`-split the suite (precedent: `shard-totality-mutations`) or move
  it to `want_scripts_heavy`. Both edit `scripts/test-all.sh` — check the
  open-PR surface for the registration region first (this session's edit
  was frozen by AC5 against #8763).
- Sweep discipline: after bumping K, grep `six legs`, `489`, `K=6`, `/6`
  across *all* touched files' comments, not only the anchor lines —
  the review panel caught three stale literals in files the diff already
  edited.

## Key Insight

A shard rebalancing plan should open with "is the worst leg one suite or a
load imbalance?" — the answer decides whether the work is a matrix edit,
a suite-internal change, or a `test-all.sh` registration edit, and those
three have entirely different collision surfaces and merge risk.

## Session Errors

1. Persistent-shell heredoc hung silently (workflow YAML scan); killed and
   reran in a fresh shell. **Prevention:** prefer short one-shot execs for
   scan scripts on busy shell sessions.
2. `gh issue create` refused twice (missing `--milestone`, then missing
   user-visible-consequence) — the filing-gate contract wants
   `--milestone "Post-MVP / Later"` + `meta/machinery` label for
   machinery findings. **Prevention:** apply the three exits (machinery
   label / User-Impact+Fix-Size / Mandated-By) before the first attempt.
3. `regenerate-shard-manifest.py` default latest-green lookup returned
   HTTP 404. **Prevention:** always pass `--run <id>`; if no fresh green
   run carries `suite-timings-*` artifacts, use the branch's own CI run.
4. K-bump literal sweep missed same-file sibling comments (`six legs`,
   `489 labels`) that the review panel caught. **Prevention:** grep the
   subject noun (`legs`, suite counts) across each touched file, not only
   the lines the plan enumerated.

## Tags

ci, sharding, test-all, manifest, regen, k-bump, atomic-floor, premise-staleness
