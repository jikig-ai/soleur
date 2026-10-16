# Escape-rate replay (S4 PR C, activation prerequisite 2, Ref #9729)

Tool: `scripts/ci-pr-affected-replay.py` (read-only; suite `plugins/soleur/test/ci-pr-affected-replay.test.sh`). Collected 2026-10-16 against a
pinned `origin/main` tree (`ee8644bded`), so the selector and index are TODAY's, applied to older diffs (a recorded limit). The queue ejections were
re-classified at review on 2026-10-16T18:00Z..18:50Z with the hardened classifier (see "Review re-run" below).
Window: the last 300 first-parent commits of `main`, committer time 2026-10-06T10:11:21Z to 2026-10-15T19:12:41Z (oldest `2cfef66506`, newest
`ee8644bded`), plus every failed `merge_group` run of `ci.yml` created in the SAME window (**53 failed of 392** `merge_group` runs, the queue
ejections; the first collection read 53 of 394 because its window had no upper bound and ran to the query time). Per-unit rows:
`replay-commits.tsv` (353 rows). Raw run records were read live; the oldest listed run is recorded in `dark-cost.md`.

## The proposed rule (stored with its hash so PR D's selector can be pinned to it)

`rule_sha256=ad9e6916307c65de162a5e151641d30449471242b4c62f11344c37d7b43d2cec`

> skip a suite iff AFFECTED_SELECTED sel=0 and reason is not always_on and AFFECTED_SUMMARY fallback=none and the diff is evaluable
> (no comma or non-printable path byte, list at most 100000 bytes)

Today's shipped rule skips nothing, so replaying it would be vacuous (CTO R2); this is the per-suite rule PR C was to gate.

## Result

| Population | n | clean | rule-irrelevant | flake-cleared | not-evaluable | attributable | unverified-as-escape (gating point) | worst case | 95% upper bound on the worst case |
|---|---|---|---|---|---|---|---|---|---|
| first-parent commits | 300 | 300 | 0 | 0 | 0 | 0 | 0 of 300 (0.00%) | 0 of 300 | 0.99% |
| commits plus ejections | 353 | 300 | 29 | 21 | 3 | 0 | 0 of 353 (0.00%) | 3 of 353 | 2.18% |

Units are replay units (a commit, or an ejected queue run); the bound is the one-sided 95% Clopper-Pearson bound on the WORST-CASE numerator
(attributable + unverified + not-evaluable). **"0 attributable" is defined as: zero units where a would-skip suite failed on at least two attempts of
the identical tree, attempt 1's jobs and logs named the same suite, and no later green run cleared it.** Routes (units per class and reason): of the
300 commits, 300 `clean` (a full-battery run on the identical tree concluded success); of the 53 ejections, **29 `rule-irrelevant`** (they failed in
jobs or suites the rule would have RUN anyway: e2e, lint, build, selected suites), **21 `flake-cleared`, every one by `identical-tree-green`** (a later
queue run of the same PR with the identical (name, blob sha) changed-file set concluded success; the multi-unit flake class, which needs 3 units from
3 distinct PRs, flipped none of them, though `scripts/test-all-orphan-log-retention` meets it), and **3 `not-evaluable`** (2 failed shards with no
`[FAIL]`/`[KILLED]` line, 1 failure with no failed job). No unit is `unverified` or `escape`.

Saving (criterion c): over the 300 commits the selector skips a mean of **52.87 suite-minutes** per commit (standard error 1.59; 245 commits
evaluated, 49 runner-changed full runs and 6 non-evaluable diffs count as 0); net of the 1.29 billed selector minutes that is
**51.58**, and 54.75 at mean plus two standard errors. **The bar and the figure are in different units, so (c) is graded `unmeasured`, not `pass`.**
The bar, 19.96, is 20% of the 99.8 baseline, which is billed job-minutes per PULL-REQUEST run; 51.58 is suite-minutes per full-battery main
commit (every commit runs every suite). The performance review's one-day sample of PR runs (45 runs) found only about 24% (11) executing the
`test-scripts` group the skippable suites sit in, and a mean PR run of about 50 raw job-minutes, so a per-PR-run reading is on the order of 0.24 x
51.58 = 12.6 gross and about 11.6 net of the 1.29 dark selector minutes, below 19.96; the active-state selector cost (1.29 is the DARK-state figure)
depends on the cache hit rate and was not measured per shard (a cold pass is 3 billed minutes, per shard fourteen times that). Both readings are
recorded here; neither is a measurement of the billed per-PR-run saving. Units: suite-minutes from
`scripts/suite-durations{,-heavy}.tsv`; a suite missing from those files counts 1.18 s, which UNDER-counts the web-platform unit registration
(about 15 job-minutes, not in the files), so the figure is a lower bound on that axis; suite-minutes are not billed job-minutes (shards bill a
rounded-up minute each), and the billed saving was not measured. The cheap pre-check on a 30-commit sample read 48.05 (se 5.22), see
`cheap-kill-sample.tsv`; it did not fire.

## Limits (read before trusting the rate)

1. **Survivorship.** Every one of the 300 commits landed, so a commit that broke a skippable suite was refused by the queue's full battery and is
   NOT in that population: its zero is near-vacuous by construction (all 300 carry a green full-battery run on the identical tree). The ejection
   population is the one that can hold an escape; it shows none that is deterministic and uncleared.
2. **A zero escape rate is not a complete index.** The replay can only see failures that happened. The index audit (`index-audit.md`) shows 190 of 630
   suites that name tracked paths the index does not declare for them, a structural way for the rule to skip a suite that reads a changed file.
3. Today's index applied to older diffs; ejection files come from the commits API; a suite flake class is detected by 3 failing units from 3 distinct PRs with at
   least 2 distinct changed-file sets, which is a heuristic, not proof; a clearance is a claim about a LATER run of the same PR with the identical
   (name, blob sha) changed-file set, never an earlier run and never a run on a branch that names no PR.

## Review re-run (what changed after the 11-seat review)

The review found that the first classifier let "could not measure" land in a reassuring class (a cancelled or unfinished job, a truncated jobs list,
an empty diff, an unread attempt 1 and a name-only file match all reached `rule-irrelevant`, `flake-cleared` or `escape`), that the index audit never
read 189 suites, and that `[KILLED]` lines were ignored. All were fixed in the class (see `decision-challenges.md`), every non-clean unit was
re-collected with `--reclassify`, and the window was re-bounded. The classes did not move (29 / 21 / 3 of 53, 0 unverified, 0 escape); the audit
count did (145 to 190 of 630).
