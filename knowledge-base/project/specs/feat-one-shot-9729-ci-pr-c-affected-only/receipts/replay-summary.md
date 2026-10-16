# Escape-rate replay (S4 PR C, activation prerequisite 2, Ref #9729)

Tool: `scripts/ci-pr-affected-replay.py` (read-only; suite `plugins/soleur/test/ci-pr-affected-replay.test.sh`). Run 2026-10-16 against a
pinned `origin/main` tree (`ee8644bded`), so the selector and index are TODAY's, applied to older diffs (a recorded limit).
Window: the last 300 first-parent commits of `main`, 2026-10-06T10:11Z to 2026-10-15T19:12Z
(oldest `2cfef66506`), plus every failed `merge_group` run of `ci.yml` since the oldest commit's date (53 of 394 runs, the queue ejections).
Per-unit rows: `replay-commits.tsv` (353 rows). Raw run records were read live; the oldest listed run is recorded in `dark-cost.md`.

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
(attributable + unverified + not-evaluable). The literal (all failures), queue-and-push-only and retry-cleared counts: of the 53 ejections,
29 failed in jobs or suites the rule would have RUN anyway (e2e, lint, build, selected suites), 21 were would-skip suites that failed and were
cleared (one same-tree green run, or the multi-unit flake class: `scripts/test-all-orphan-log-retention` failed in more than 20 queue runs across many
distinct diffs), and 3 are not evaluable (a failed shard with no `[FAIL]` line, and one failure with no failed job).

Saving (criterion c): over the 300 commits the selector skips a mean of **52.87 suite-minutes** per commit (standard error 1.59; 245 commits
evaluated, 49 runner-changed full runs and 6 non-evaluable diffs count as 0); net of the 1.29 billed selector minutes that is
**51.58**, and 54.75 at mean plus two standard errors, against the bar of **19.96** (20% of the 99.8 baseline). Units: suite-minutes from
`scripts/suite-durations{,-heavy}.tsv`; a suite missing from those files counts 1.18 s, which UNDER-counts the web-platform unit registration
(about 15 job-minutes, not in the files), so the figure is a lower bound on that axis; suite-minutes are not billed job-minutes (shards bill a
rounded-up minute each), and the billed saving was not measured. The cheap pre-check on a 30-commit sample read 48.05 (se 5.22), see
`cheap-kill-sample.tsv`; it did not fire.

## Limits (read before trusting the rate)

1. **Survivorship.** Every one of the 300 commits landed, so a commit that broke a skippable suite was refused by the queue's full battery and is
   NOT in that population: its zero is near-vacuous by construction (all 300 carry a green full-battery run on the identical tree). The ejection
   population is the one that can hold an escape; it shows none that is deterministic and uncleared.
2. **A zero escape rate is not a complete index.** The replay can only see failures that happened. The index audit (`index-audit.md`) shows 145
   suites that name tracked paths the index does not declare for them, a structural way for the rule to skip a suite that reads a changed file.
3. Today's index applied to older diffs; ejection files come from the commits API; a suite flake class is detected by 3 failing units with at
   least 2 distinct changed-file sets, which is a heuristic, not proof.
